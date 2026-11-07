import AppKit
import Carbon
import ItdaEngine
import Sparkle

public func runItda() {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    private let tap: KeyTap
    private let panel = GhostPanel()
    private lazy var watcher = Watcher(tap: tap, panel: panel)
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// The menu bar's glyph, plain and with a problem's dot. Nil until launch, so tests make no status item.
    private var glyphs: (plain: NSImage, marked: NSImage)?
    private var shownIcon: Icon?
    let store = ModelStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Itda"))
    /// A model is loaded and answering. Stays true if a later download or switch fails, as this one still works.
    var ready: Bool { activePath != nil }
    /// What just went wrong with a download or a switch.
    @Published var notice: String? { didSet { retryable = false; updateIcon() } }
    /// The notice is a failed download, which Retry starts again.
    @Published private(set) var retryable = false
    /// Whether the system lets the tap run, which is what the permission comes to.
    @Published var trusted = false { didSet { updateIcon() } }
    /// The model being fetched, by file name, and how far along.
    @Published var downloading: String? { didSet { updateIcon() } }
    @Published var downloadFraction = 0.0 { didSet { updateIcon() } }
    /// Why there's no ghost in the front app's field, as the watcher last settled it.
    @Published var why = Watcher.Why.unreadable
    /// A suggestion was taken since the window opened.
    @Published var accepted = false
    /// This launch began without a model or the permission, so the field gets a sentence once, and the first ghost needs no typing.
    var fresh = false
    @Published var verifying = false
    @Published private var waiting = false
    /// The model being opened, while it's the first.
    @Published private var loadingPath: String?
    /// What happens when a fetch ends: the default at first run loads, your choice loads and is remembered, and
    /// choosing another model in the meantime leaves just the file.
    private enum AfterFetch { case load, loadAndRemember, nothing }
    private var afterFetch = AfterFetch.load
    /// The model that loaded last, which is the one answering. Nil again if it can't load after an idle unload.
    @Published var activePath: String? { didSet { updateIcon() } }
    var window: NSWindow?
    /// Started only in a released build, whose Info.plist names the feed.
    let updates = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    /// The model's line, for the menu and under the field.
    var modelLine: String {
        if ready { return activeName }
        if verifying { return "Checking the download…" }
        if waiting { return "Waiting for a connection…" }
        if downloading != nil { return "Downloading \(store.current.name): \(Int(downloadFraction * 100))% of \(store.current.sizeText)" }
        if let loadingPath { return "Loading \(name(loadingPath))…" }
        return "No model loaded"
    }
    var isRelease: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }
    var askedForAccessibility = false
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
    /// One in use stays, even if its file has since moved.
    var ownModels: [String] { ownPaths.filter { $0 == activePath || FileManager.default.fileExists(atPath: $0) } }
    func forgetOwnModel(_ path: String) { ownPaths.removeAll { $0 == path } }
    func isActive(path: String) -> Bool { activePath == path }
    /// Takes one of your GGUFs, from the lists.
    func use(path: String) { open(path, remember: true) }

    func isActive(_ model: ModelStore.Model) -> Bool { activePath == store.path(model).path }

    /// The tap is a fake in tests.
    init(tap: KeyTap = KeyTap()) {
        self.tap = tap
    }

    static func fileName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private func name(_ path: String) -> String { ModelStore.models.first { store.path($0).path == path }?.name ?? App.fileName(path) }
    /// What the window calls the loaded model: its name if it's one of ours, or else its file.
    var activeName: String { activePath.map(name) ?? "No Model" }

    func applicationDidFinishLaunching(_ note: Notification) {
        // The symbol is for a binary run outside the bundle, as the e2e checks do.
        let glyph = Bundle.main.image(forResource: "MenuBarTemplate") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Itda")!
        glyph.isTemplate = true
        glyph.accessibilityDescription = "Itda"
        glyphs = (glyph, App.marked(glyph))
        status.button?.imagePosition = .imageLeading
        updateIcon()
        installMainMenu()
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu

        readInputSource()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(readInputSource),
                                                            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(rebind), name: name, object: nil)
        }
        watcher.hideOnSessionChange()

        if isRelease { updates.startUpdater() }
        store.removeLeftovers()
        store.onChange = { [weak self] state in self?.modelChanged(state) }
        loadModel()
        // Accessibility is the one permission, and the window asks for it. Nothing runs until the grant.
        watcher.onWhy = { [weak self] why in
            DispatchQueue.main.async {
                self?.why = why
                self?.updateIcon()  // Secure Input comes and goes with no word to us; the watcher sees it.
            }
        }
        tap.onAccept = { [weak self] in DispatchQueue.main.async { if self?.accepted == false { self?.accepted = true } } }
        tap.onUp = { [weak self] up in DispatchQueue.main.async { self?.tapChanged(up: up) } }
        trusted = tap.hold()
        if !trusted { fresh = true }
        // Started by the system at login, it stays out of the way. Started by you, it answers. Without the permission it has to ask.
        let launch = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = launch?.eventID == kAEOpenApplication && launch?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !atLogin || !trusted { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    /// A download stops at quit so the next launch resumes it. At most a second, as a quit from a main-queue block holds back the reply.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.isBusy else { return .terminateNow }
        var replied = false
        let reply = {
            if !replied { NSApp.reply(toApplicationShouldTerminate: true) }
            replied = true
        }
        store.cancel(then: reply)
        RunLoop.main.add(Timer(timeInterval: 1, repeats: false) { _ in reply() }, forMode: .common)
        return .terminateLater
    }

    /// ggml's Metal device asserts at exit if a model is still loaded.
    func applicationWillTerminate(_ note: Notification) {
        watcher.queue.sync { watcher.completer }?.unload()
        watcher.unprime()  // After, as it may give up on hung hosts.
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

    private func tapChanged(up: Bool) {
        let granted = up && !trusted
        trusted = up
        rebind()
        // Back in front of System Settings, where the grant was given.
        if granted, let window {
            showWindow()
            window.orderFrontRegardless()
        }
    }

    /// On, and not paused for the front app.
    private var activeHere: Bool { on && !pausedApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") }

    @objc private func rebind() {
        watcher.hideNow()
        tap.reenable()
        updateIcon()
        guard trusted, activeHere, let front = NSWorkspace.shared.frontmostApplication else {
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
        fresh = true
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

    /// The fetch that failed, from where it stopped.
    @objc func retry() { store.fetch(store.current) }

    func modelChanged(_ state: ModelStore.State) {
        waiting = state == .waiting
        switch state {
        case .waiting:
            break
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
            retryable = true
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
            let engine = try? Engine(modelPath: path) { [weak self] in DispatchQueue.main.async { self?.lost(path) } }
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
                watcher.install(engine)
            }
        }
    }

    /// The model answering couldn't load again after an idle unload: its file moved or broke. Nothing answers until another is chosen.
    func lost(_ path: String) {
        guard activePath == path else { return }
        activePath = nil
        notice = "Could not load " + URL(fileURLWithPath: path).lastPathComponent
        watcher.install(nil)
    }

    /// Not answering, opening or downloading.
    func canDelete(_ model: ModelStore.Model) -> Bool {
        let path = store.path(model).path
        return activePath != path && loadingPath != path && downloading != model.id
    }

    /// A fetched model, off the disk. Getting it again downloads it again.
    func delete(_ model: ModelStore.Model) {
        guard canDelete(model) else { return }
        store.delete(model)
        objectWillChange.send()
    }

    /// The sentence for the empty field, once a launch that began without a model or the permission has both. From the e2e demo, where
    /// the default model suggests, so the first ghost needs no typing.
    static func prefill(fresh: Bool, ready: Bool, draft: String, korean: Bool) -> String? {
        guard fresh, ready, draft.isEmpty else { return nil }
        return korean ? "안녕하세요. 만나서 반갑" : "Please let me know if you have any"
    }

    /// The prefill, taken once. The field is asked again, as a model installed in the same moment may have read it still empty.
    func takePrefill(draft: String) -> String? {
        guard let sentence = App.prefill(fresh: fresh, ready: ready, draft: draft, korean: watcher.koreanInput.load(ordering: .relaxed)) else { return nil }
        fresh = false
        DispatchQueue.main.async { [self] in watcher.redraw() }
        return sentence
    }

    // MARK: Why, and the icon

    /// The one line saying why there's no suggestion here, for the menu and under the field. Nil when off or paused, which the menu's
    /// own items show. Not sure is a normal state, and reads as working.
    static func line(trusted: Bool, active: Bool, obstacle: KeyTap.Obstacle?, ready: Bool, why: Watcher.Why, app: String?) -> String? {
        guard trusted else { return "Itda needs Accessibility permission." }
        guard active else { return nil }
        if let obstacle { return obstacle.rawValue }
        guard ready else { return "The model isn't ready yet." }
        switch why {
        case .shown, .empty, .blocked: return "Working."  // Blocked with no obstacle now: it has just ended.
        case .unsure: return "Working. Not sure enough to suggest yet."
        case .unreadable: return "No field here that Itda can read."
        case .textAfter: return "Text after the cursor, so no suggestion here."
        case .notTwoSet: return "Korean suggestions need Apple's 2-Set Korean layout."
        case .noModel: return "The model isn't ready yet."
        case .noCaret: return "This app doesn't say where the cursor is."
        case .noFont: return "\(app ?? "This app") doesn't report its font, so no suggestion here."
        case .rightToLeft: return "No suggestions in right-to-left text."
        case .noRoom: return "No room to show a suggestion here."
        }
    }

    func line(for why: Watcher.Why) -> String? {
        App.line(trusted: trusted, active: activeHere, obstacle: tap.obstacle, ready: ready, why: why, app: NSWorkspace.shared.frontmostApplication?.localizedName)
    }

    /// macOS's own grey inline predictions, which would show beside ours. Read, never written.
    var predictions: Bool { readPredictions() }
    var readPredictions = { NSSpellChecker.isAutomaticInlinePredictionEnabled }
    @objc func openKeyboardSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }

    struct Icon: Equatable {
        var dimmed = false, mark = false, title = ""
    }

    /// Dimmed when off or paused here, a dot when something needs you, and how far a download has got.
    static func icon(active: Bool, problem: Bool, downloading: Double?) -> Icon {
        Icon(dimmed: !active, mark: problem, title: downloading.map { "\(Int($0 * 100))%" } ?? "")
    }

    /// From each place the state it shows changes: rebind (on, pause, front app, permission), the model's state, and the watcher.
    func updateIcon() {
        guard let glyphs, let button = status.button else { return }
        let icon = App.icon(active: activeHere, problem: !trusted || tap.obstacle != nil || (!ready && notice != nil),
                            downloading: downloading.map { _ in downloadFraction })
        guard icon != shownIcon else { return }
        shownIcon = icon
        button.image = icon.mark ? glyphs.marked : glyphs.plain
        button.appearsDisabled = icon.dimmed
        button.title = icon.title
    }

    /// The glyph with a dot at its top right, cut clear around it so it reads at menu-bar size.
    static func marked(_ glyph: NSImage) -> NSImage {
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            let dot = CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Itda, needs attention"
        return image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Itda", action: #selector(openWindow), keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: "Suggestions", action: #selector(toggleOn), keyEquivalent: "")
        toggle.state = on ? .on : .off
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(), let id = front.bundleIdentifier {
            let pause = menu.addItem(withTitle: "Pause in \(front.localizedName ?? id)", action: #selector(togglePause), keyEquivalent: "")
            pause.state = pausedApps.contains(id) ? .on : .off
            pause.representedObject = id
        }
        menu.addItem(.separator())
        if let line = line(for: why) { menu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false }
        menu.addItem(withTitle: modelLine, action: nil, keyEquivalent: "").isEnabled = false
        if let notice { menu.addItem(withTitle: notice, action: nil, keyEquivalent: "").isEnabled = false }
        if retryable { menu.addItem(withTitle: "Retry Download", action: #selector(retry), keyEquivalent: "") }
        if predictions { menu.addItem(withTitle: "Turn Off macOS Predictions…", action: #selector(openKeyboardSettings), keyEquivalent: "") }
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
