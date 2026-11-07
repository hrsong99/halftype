import AppKit
import Carbon
import ItdaCore
import ItdaEngine
import Sparkle

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
    /// A model is loaded and answering. Stays true if a later download or switch fails, as this one still works.
    @Published var ready = false
    /// What just went wrong with a download or a switch.
    @Published var notice: String?
    @Published var trusted = AXIsProcessTrusted()
    /// The model being fetched, by file name, and how far along.
    @Published var downloading: String?
    @Published var downloadFraction = 0.0
    @Published var verifying = false
    /// The model being opened, while it's the first.
    @Published private var loadingPath: String?
    /// What happens when a fetch ends: the default at first run loads, your choice loads and is remembered, and
    /// choosing another model in the meantime leaves just the file.
    private enum AfterFetch { case load, loadAndRemember, nothing }
    private var afterFetch = AfterFetch.load
    /// The model that loaded last, which is the one answering.
    @Published var activePath: String?
    var window: NSWindow?
    /// Started only in a released build, whose Info.plist names the feed.
    let updates = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    /// The one line of status, for the menu and under the field.
    var modelLine: String {
        if ready, let activePath { return "Model: " + URL(fileURLWithPath: activePath).lastPathComponent }
        if verifying { return "Verifying model…" }
        if downloading != nil { return "Downloading model: \(Int(downloadFraction * 100))%" }
        if let loadingPath { return "Loading " + URL(fileURLWithPath: loadingPath).lastPathComponent + "…" }
        return "Model: not loaded"
    }
    var isRelease: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }
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
    @Published var length = Length(rawValue: UserDefaults.standard.string(forKey: "length") ?? "") ?? .short {
        didSet { UserDefaults.standard.set(length.rawValue, forKey: "length"); tune() }
    }
    @Published var often = Often(rawValue: UserDefaults.standard.string(forKey: "often") ?? "") ?? .normal {
        didSet { UserDefaults.standard.set(often.rawValue, forKey: "often"); tune() }
    }
    func tune() {
        Tuning.current.withLock { $0 = Tuning(floor: length.floor, threshold: often.threshold) }
        watcher.retune()
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
    /// One in use stays, even if its file has since moved.
    var ownModels: [String] { ownPaths.filter { $0 == activePath || FileManager.default.fileExists(atPath: $0) } }
    func forgetOwnModel(_ path: String) { ownPaths.removeAll { $0 == path } }
    func isActive(path: String) -> Bool { ready && activePath == path }
    /// Takes one of your GGUFs, from the lists.
    func use(path: String) { open(path, remember: true) }

    func isActive(_ model: ModelStore.Model) -> Bool { ready && activePath == store.path(model).path }
    /// Downloaded, and neither loaded nor loading, so its file can go.
    func canDelete(_ model: ModelStore.Model) -> Bool {
        let path = store.path(model).path
        return store.has(model) && path != activePath && path != loadingPath
    }
    func delete(_ model: ModelStore.Model) {
        guard canDelete(model) else { return }
        try? FileManager.default.removeItem(at: store.path(model))
        objectWillChange.send()
    }

    static func fileName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private func name(_ path: String) -> String { ModelStore.models.first { store.path($0).path == path }?.name ?? App.fileName(path) }
    /// What the window calls the loaded model: its name if it's one of ours, or else its file.
    var activeName: String { activePath.map(name) ?? "No Model" }

    func applicationDidFinishLaunching(_ note: Notification) {
        tune()
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

        if isRelease { updates.startUpdater() }
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

    private func loadModel() {
        if let path = customModel, FileManager.default.fileExists(atPath: path) { return open(path) }
        let first = ModelStore.models[0]
        if store.has(first) { return open(store.path(first).path) }
        afterFetch = .load
        store.fetch(first)
    }

    /// Takes a model we know, fetching it first if need be.
    func use(_ model: ModelStore.Model) {
        guard store.has(model) else {
            if store.isBusy { return }
            afterFetch = .loadAndRemember
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
        case .verifying:
            verifying = true
        case .ready:
            downloading = nil
            verifying = false
            if afterFetch != .nothing { open(store.path(store.current).path, remember: afterFetch == .loadAndRemember) }
        case .cancelled:
            downloading = nil
            verifying = false
        case .failed(let why):
            downloading = nil
            verifying = false
            notice = "Model download failed: \(why)"
        }
    }

    /// Loading takes a moment and compiles Metal pipelines, so it stays off the main thread. One at a time, and the last choice wins.
    /// The model answering now keeps answering until another has loaded, and it stays if that one can't.
    /// The launch's own load only reads the preference: a choice is what writes it, and only once it has worked.
    private func open(_ path: String, remember: Bool = false) {
        if remember { afterFetch = .nothing }
        loadingPath = path
        notice = nil
        latestOpen += 1
        let id = latestOpen
        loading.async { [self] in
            let engine = try? Engine(modelPath: path)
            DispatchQueue.main.async { [self] in
                guard id == latestOpen else { return }
                loadingPath = nil
                guard let engine else {
                    notice = "Could not load " + URL(fileURLWithPath: path).lastPathComponent
                    return
                }
                activePath = path
                if !ModelStore.models.contains(where: { store.path($0).path == path }), !ownPaths.contains(path) { ownPaths.append(path) }
                if remember { customModel = path == store.path(ModelStore.models[0]).path ? nil : path }
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
        menu.addItem(.separator())
        if isRelease { menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "") }
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
    @objc func checkForUpdates() { updates.checkForUpdates(nil) }

    func chooseModel() {
        let open = NSOpenPanel()
        open.allowedContentTypes = []
        open.allowsOtherFileTypes = true
        open.message = "Choose a GGUF model"
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return }
        self.open(url.path, remember: true)
    }

}

/// Replayed on English test threads with Qwen 3.5 0.8B (docs/measuring.md): grey characters right 77%, 61%, 50%.
enum Length: String, CaseIterable {
    case short, medium, long
    var floor: Double { switch self { case .short: Stop.floor; case .medium: -2; case .long: -3 } }
}

/// The same replay: suggestions shown on 12%, 20% and 31% of requests, with the first word right 89%, 75% and 58% of the time.
enum Often: String, CaseIterable {
    case less, normal, more
    var threshold: Double { switch self { case .less: -0.3; case .normal: Gate.threshold; case .more: -1.2 } }
}

