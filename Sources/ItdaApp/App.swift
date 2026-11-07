import AppKit
import Carbon
import ItdaEngine

public func runItda() {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    private let tap = KeyTap()
    private let panel = GhostPanel()
    private lazy var watcher = Watcher(tap: tap, panel: panel)
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let store = ModelStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Itda"))
    @Published var modelLine = "Model: not loaded"
    /// A model is loaded and answering. Stays true if a later download or switch fails, as this one still works.
    @Published var ready = false
    /// What just went wrong with a download or a switch.
    @Published var notice: String?
    @Published var trusted = AXIsProcessTrusted()
    /// The model being fetched, by file name, and how far along.
    @Published var downloading: String?
    @Published var downloadFraction = 0.0
    @Published var verifying = false
    /// Whether what's being fetched loads when it arrives: a later choice of another model cancels that, and the file just stays.
    private var fetchLoads = true
    /// Whether what's being fetched was your choice, to remember once it loads, or just the default at first run.
    private var fetchIsChoice = false
    /// The model that loaded last, which is the one answering.
    @Published private var activePath: String?
    var window: NSWindow?
    var askedForAccessibility = false
    private var tapFailed = false
    private var permissionTimer: Timer?
    private let loading = DispatchQueue(label: "itda.load", qos: .userInitiated)
    private var latestOpen = 0

    @Published var on = UserDefaults.standard.object(forKey: "on") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(on, forKey: "on")
            rebind()
        }
    }
    @Published var pausedApps = Set(UserDefaults.standard.stringArray(forKey: "pausedApps") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(pausedApps), forKey: "pausedApps")
            rebind()
        }
    }
    @Published private var customModel = UserDefaults.standard.string(forKey: "modelPath") {
        didSet { UserDefaults.standard.set(customModel, forKey: "modelPath") }
    }

    /// GGUFs of yours that have loaded, so one stays in the list after you switch away. Paths only.
    @Published private var ownPaths = UserDefaults.standard.stringArray(forKey: "ownModels") ?? [] {
        didSet { UserDefaults.standard.set(ownPaths, forKey: "ownModels") }
    }
    var ownModels: [String] { ownPaths.filter(FileManager.default.fileExists) }
    func forgetOwnModel(_ path: String) { ownPaths.removeAll { $0 == path } }
    func isActive(path: String) -> Bool { ready && activePath == path }
    /// Takes one of your GGUFs, from the lists.
    func use(path: String) { open(path, remember: true) }

    func isActive(_ model: ModelStore.Model) -> Bool { ready && activePath == store.path(model).path }

    static func fileName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private func name(_ path: String) -> String { ModelStore.models.first { store.path($0).path == path }?.name ?? App.fileName(path) }
    /// What the window calls the loaded model: its name if it's one of ours, or else its file.
    var activeName: String { activePath.map(name) ?? "No Model" }

    func applicationDidFinishLaunching(_ note: Notification) {
        // The symbol is for a binary run outside the bundle, as the e2e checks do.
        let glyph = Bundle.main.image(forResource: "MenuBarTemplate") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Itda")
        glyph?.isTemplate = true
        glyph?.accessibilityDescription = "Itda"
        status.button?.image = glyph
        installMainMenu()
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        readInputSource()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(readInputSource),
                                                            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(rebind), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        store.removeLeftovers()
        store.onChange = { [weak self] state in self?.modelChanged(state) }
        loadModel()
        // Accessibility is the one permission, and the window asks for it. Nothing runs until the grant.
        if AXIsProcessTrusted() {
            startWatching()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.trusted = true
                self?.startWatching()
            }
        }
        // Started by the system at login, it stays out of the way. Started by you, it answers. Without the permission it has to ask.
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launch?.eventID == kAEOpenApplication && launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !atLogin || !trusted { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    /// ggml's Metal device asserts at exit if a model is still loaded.
    func applicationWillTerminate(_ note: Notification) {
        watcher.queue.sync { watcher.completer }?.unload()
    }

    private func startWatching() {
        guard tap.start() else {
            tapFailed = true
            return
        }
        rebind()
    }

    /// TIS must be read on the main thread. Going by the source's language covers third-party Korean input methods too.
    @objc private func readInputSource() {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        func property<T>(_ key: CFString, as: T.Type) -> T? {
            TISGetInputSourceProperty(source, key).flatMap { Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as? T }
        }
        watcher.koreanInput.store(property(kTISPropertyInputSourceLanguages, as: [String].self)?.first == "ko", ordering: .relaxed)
        watcher.twoSet.store(property(kTISPropertyInputSourceID, as: String.self) == TwoSetLayout.source, ordering: .relaxed)
        tap.state.withLock { $0.composing = false }  // Switching source commits.
        watcher.hideNow()
        watcher.redraw()
    }

    @objc private func spaceChanged() {
        watcher.hideNow()
    }

    @objc private func rebind() {
        watcher.hideNow()
        guard AXIsProcessTrusted() else { return }
        guard on, let front = NSWorkspace.shared.frontmostApplication,
              !pausedApps.contains(front.bundleIdentifier ?? "") else {
            watcher.unbind()
            return
        }
        watcher.bind(pid: front.processIdentifier)
    }

    // MARK: Model

    private func modelName(_ path: String) -> String { "Model: " + URL(fileURLWithPath: path).lastPathComponent }

    private func loadModel() {
        if let path = customModel, FileManager.default.fileExists(atPath: path) { return open(path) }
        let first = ModelStore.models[0]
        if store.has(first) { return open(store.path(first).path) }
        fetchLoads = true
        fetchIsChoice = false
        store.fetch(first)
    }

    /// Takes a model we know, fetching it first if need be.
    func use(_ model: ModelStore.Model) {
        guard store.has(model) else {
            if store.isBusy { return }
            fetchLoads = true
            fetchIsChoice = true
            return store.fetch(model)
        }
        open(store.path(model).path, remember: true)
    }

    private func modelChanged(_ state: ModelStore.State) {
        switch state {
        case .downloading(let done):
            downloading = store.current.id
            downloadFraction = done
            notice = nil
            verifying = false
            if !ready { modelLine = "Downloading model: \(Int(done * 100))%" }
        case .verifying:
            verifying = true
            if !ready { modelLine = "Verifying model…" }
        case .ready:
            downloading = nil
            verifying = false
            if fetchLoads { open(store.path(store.current).path, remember: fetchIsChoice) }
        case .cancelled:
            downloading = nil
            verifying = false
            if !ready { modelLine = "Model: not loaded" }
        case .failed(let why):
            downloading = nil
            verifying = false
            notice = "Model download failed: \(why)"
            if !ready { modelLine = "Model: not loaded" }
        }
    }

    /// Loading takes a moment and compiles Metal pipelines, so it stays off the main thread. One at a time, and the last choice wins.
    /// The model answering now keeps answering until another has loaded, and it stays if that one can't.
    /// The launch's own load only reads the preference: a choice is what writes it, and only once it has worked.
    private func open(_ path: String, remember: Bool = false) {
        if remember { fetchLoads = false }
        if !ready { modelLine = "Loading " + URL(fileURLWithPath: path).lastPathComponent + "…" }
        notice = nil
        latestOpen += 1
        let id = latestOpen
        loading.async { [self] in
            let engine = try? Engine(modelPath: path)
            DispatchQueue.main.async { [self] in
                guard id == latestOpen else { return }
                guard let engine else {
                    notice = "Could not load " + URL(fileURLWithPath: path).lastPathComponent
                    if !ready { modelLine = "Model: not loaded" }
                    return
                }
                activePath = path
                if !ModelStore.models.contains(where: { store.path($0).path == path }), !ownPaths.contains(path) { ownPaths.append(path) }
                if remember { customModel = path == store.path(ModelStore.models[0]).path ? nil : path }
                modelLine = modelName(path)
                ready = true
                watcher.queue.async { [self] in
                    watcher.completer?.cancel()
                    watcher.completer = engine
                    watcher.unloadWhenIdle()
                }
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Itda", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Itda", action: #selector(toggleOn), keyEquivalent: "")
        toggle.state = on ? .on : .off
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(), let id = front.bundleIdentifier {
            let pause = menu.addItem(withTitle: "Pause in \(front.localizedName ?? id)", action: #selector(togglePause), keyEquivalent: "")
            pause.state = pausedApps.contains(id) ? .on : .off
            pause.representedObject = id
        }
        menu.addItem(.separator())
        if !AXIsProcessTrusted() { menu.addItem(withTitle: "Waiting for Accessibility permission", action: nil, keyEquivalent: "").isEnabled = false }
        if tapFailed { menu.addItem(withTitle: "Could not watch for Tab", action: nil, keyEquivalent: "").isEnabled = false }
        menu.addItem(withTitle: modelLine, action: nil, keyEquivalent: "").isEnabled = false
        if let notice { menu.addItem(withTitle: notice, action: nil, keyEquivalent: "").isEnabled = false }
        if notice?.hasPrefix("Model download failed") == true { menu.addItem(withTitle: "Try Download Again", action: #selector(retryDownload), keyEquivalent: "") }
        menu.addItem(withTitle: "Choose GGUF…", action: #selector(chooseModel), keyEquivalent: "")
        if customModel != nil { menu.addItem(withTitle: "Use Default Model", action: #selector(useDefaultModel), keyEquivalent: "") }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != nil { item.target = self }
    }

    @objc private func toggleOn() {
        on.toggle()
    }

    @objc private func togglePause(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        if pausedApps.contains(id) { pausedApps.remove(id) } else { pausedApps.insert(id) }
    }

    @objc private func openWindow() { showWindow() }

    @objc private func retryDownload() { store.fetch(store.current) }

    @objc func chooseModel() {
        let open = NSOpenPanel()
        open.allowedContentTypes = []
        open.allowsOtherFileTypes = true
        open.message = "Choose a GGUF model"
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return }
        self.open(url.path, remember: true)
    }

    @objc private func useDefaultModel() {
        use(ModelStore.models[0])
    }
}
