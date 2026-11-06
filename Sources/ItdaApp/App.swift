import AppKit
import Carbon
import ItdaEngine

public func runItda() {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tap = KeyTap()
    private let panel = GhostPanel()
    private lazy var watcher = Watcher(tap: tap, panel: panel)
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store = ModelStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Itda"))
    private var modelLine = "Model: not loaded"
    private var tapFailed = false
    private var permissionTimer: Timer?
    private let loading = DispatchQueue(label: "itda.load", qos: .userInitiated)
    private var latestOpen = 0

    private var on: Bool {
        get { UserDefaults.standard.object(forKey: "on") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "on") }
    }
    private var pausedApps: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "pausedApps") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "pausedApps") }
    }
    private var customModel: String? {
        get { UserDefaults.standard.string(forKey: "modelPath") }
        set { UserDefaults.standard.set(newValue, forKey: "modelPath") }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // The symbol is for a binary run outside the bundle, as the e2e checks do.
        let glyph = Bundle.main.image(forResource: "MenuBarTemplate") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Itda")
        glyph?.isTemplate = true
        glyph?.accessibilityDescription = "Itda"
        status.button?.image = glyph
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        readInputSource()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(readInputSource),
                                                            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(rebind), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        loadModel()
        // Accessibility is the one permission. The system's prompt shows once; nothing runs until the grant.
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary) {
            startWatching()
        } else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.startWatching()
            }
        }
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
        guard on, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
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
        if store.hasModel { return open(store.destination.path) }
        store.onChange = { [weak self] state in
            DispatchQueue.main.async { self?.modelChanged(state) }
        }
        store.fetch()
    }

    private func modelChanged(_ state: ModelStore.State) {
        switch state {
        case .downloading(let done): modelLine = "Downloading model: \(Int(done * 100))%"
        case .verifying: modelLine = "Verifying model…"
        case .ready(let path): open(path)
        case .failed(let why): modelLine = "Model download failed: \(why)"
        }
    }

    /// Loading takes a moment and compiles Metal pipelines, so it stays off the main thread. One at a time, and the last choice wins.
    private func open(_ path: String) {
        modelLine = "Loading " + URL(fileURLWithPath: path).lastPathComponent + "…"
        latestOpen += 1
        let id = latestOpen
        loading.async { [self] in
            let engine = try? Engine(modelPath: path)
            DispatchQueue.main.async { [self] in
                guard id == latestOpen else { return }
                modelLine = engine == nil ? "Could not load that model" : modelName(path)
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
        if modelLine.hasPrefix("Model download failed") { menu.addItem(withTitle: "Try Download Again", action: #selector(retryDownload), keyEquivalent: "") }
        menu.addItem(withTitle: "Choose GGUF…", action: #selector(chooseModel), keyEquivalent: "")
        if customModel != nil { menu.addItem(withTitle: "Use Default Model", action: #selector(useDefaultModel), keyEquivalent: "") }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) && item.action != nil { item.target = self }
    }

    @objc private func toggleOn() {
        on.toggle()
        rebind()
    }

    @objc private func togglePause(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        if pausedApps.contains(id) { pausedApps.remove(id) } else { pausedApps.insert(id) }
        rebind()
    }

    @objc private func retryDownload() { store.fetch() }

    @objc private func chooseModel() {
        let open = NSOpenPanel()
        open.allowedContentTypes = []
        open.allowsOtherFileTypes = true
        open.message = "Choose a GGUF model"
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return }
        customModel = url.path
        self.open(url.path)
    }

    @objc private func useDefaultModel() {
        customModel = nil
        loadModel()
    }
}
