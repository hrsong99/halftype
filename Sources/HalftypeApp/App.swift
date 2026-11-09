import AppKit
import Carbon
import HalftypeCore
import HalftypeEngine
import Sparkle
import Synchronization

public func runHalftype() {
    moveFromItda(UserDefaults.standard)
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}

/// The app was Itda until 2026-11-08. Once, before anything reads them, its folder (models, stats, adapters) and
/// settings move to Halftype's, with paths into the old folder pointed at the new one.
func moveFromItda(_ defaults: UserDefaults, oldDomain: String = "app.itda.Itda", support: URL = App.support) {
    let old = support.deletingLastPathComponent().appendingPathComponent("Itda")
    let files = FileManager.default
    // Item by item and folder into folder, so a Halftype folder made first strands nothing; a name in both stays put.
    func merge(_ from: URL, into to: URL) {
        try? files.createDirectory(at: to, withIntermediateDirectories: true)
        for name in (try? files.contentsOfDirectory(atPath: from.path)) ?? [] {
            let a = from.appendingPathComponent(name), b = to.appendingPathComponent(name)
            if !files.fileExists(atPath: b.path) { try? files.moveItem(at: a, to: b) }
            else if a.hasDirectoryPath || (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { merge(a, into: b) }
        }
        if (try? files.contentsOfDirectory(atPath: from.path))?.isEmpty == true { try? files.removeItem(at: from) }
    }
    if files.fileExists(atPath: old.path) { merge(old, into: support) }
    if defaults.object(forKey: "movedFromItda") == nil {
        for (key, value) in defaults.persistentDomain(forName: oldDomain) ?? [:] where defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: "movedFromItda")
    }
    // Every launch, so a file that only moves on a retry still gets its path fixed.
    let moved = { (path: String) -> String in
        let new = path.replacingOccurrences(of: old.path + "/", with: support.path + "/")
        return files.fileExists(atPath: new) && !files.fileExists(atPath: path) ? new : path  // only where the file really moved
    }
    if let path = defaults.string(forKey: "modelPath"), moved(path) != path { defaults.set(moved(path), forKey: "modelPath") }
    if let paths = defaults.stringArray(forKey: "ownModels"), paths.map(moved) != paths { defaults.set(paths.map(moved), forKey: "ownModels") }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    private let tap: KeyTap
    private let panel = GhostPanel()
    private lazy var watcher = Watcher(tap: tap, panel: panel)
    private lazy var status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    /// The menu bar's glyph, plain and with a problem's dot. Nil until launch, so tests make no status item.
    private var glyphs: (plain: NSImage, marked: NSImage)?
    private var shownIcon: Icon?
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Halftype")
    let store = ModelStore(directory: App.support)
    /// Counts only, for the Stats page. Each typed key counts, so it's written at most every 10 s, and at quit.
    @Published var tally = App.tallyFile.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Tally.self, from: $0) } ?? Tally() {
        didSet {
            guard !saving else { return }
            saving = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.save() }
        }
    }
    private var saving = false
    private func save() {
        saving = false
        guard let file = App.tallyFile, let data = try? JSONEncoder().encode(tally) else { return }
        // A model chosen from elsewhere means no download has made the folder yet.
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
    /// Nil in the window pictures, whose made-up counts must not reach the real file. Set before any App exists.
    /// Main thread only: the suggestion the last Tab took from.
    private var lastTaken = -1
    /// Only in the app itself: unit tests and the e2e runner make an App too, and once wrote their counts into the real file.
    nonisolated(unsafe) static var tallyFile: URL? = Bundle.main.bundleIdentifier == "app.halftype.Halftype" ? support.appendingPathComponent("stats.json") : nil

    /// Personal LoRAs trained on the user's own text for this model (lab/dogfood on the `learn` branch), in `adapters/<model file>/`,
    /// by name, which train.sh dates. An adapter fits only the model it was trained on, so each model has its own folder.
    static func adapters(for model: String) -> [String] {
        let folder = support.appendingPathComponent("adapters").appendingPathComponent(URL(fileURLWithPath: model).lastPathComponent).path
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".gguf") }.sorted().map { folder + "/" + $0 }
    }
    /// The one chosen in General (by name, kept per name so it holds across models' folders), else the newest.
    static func adapterFile(for model: String) -> String? {
        let all = adapters(for: model), chosen = UserDefaults.standard.string(forKey: "adapter") ?? ""
        return all.first { name(ofAdapter: $0) == chosen } ?? all.last
    }
    static func name(ofAdapter path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    /// Read on each request, so a new setting or midnight takes effect at once.
    /// Compare puts it on odd dates only, so the Stats page can set days with it against days without.
    @Sendable static func adapterToday(model: String) -> String? {
        switch Personal(rawValue: UserDefaults.standard.string(forKey: "personal") ?? "") ?? .compare {
        case .off: return nil
        case .compare where Calendar.current.component(.day, from: Date()) % 2 == 0: return nil
        default: return adapterFile(for: model)
        }
    }
    @Published var personal = Personal(rawValue: UserDefaults.standard.string(forKey: "personal") ?? "") ?? .compare {
        didSet {
            UserDefaults.standard.set(personal.rawValue, forKey: "personal")
            count { $0.mark(personal: nil) }  // A day the setting changed on is mixed, whatever was sampled.
        }
    }
    /// Empty: the newest. Read by `adapterFile` on each request, so the engine reloads with it on the next suggestion.
    @Published var adapterChoice = UserDefaults.standard.string(forKey: "adapter") ?? "" {
        didSet {
            UserDefaults.standard.set(adapterChoice, forKey: "adapter")
            count { $0.mark(personal: nil) }
        }
    }
    private var engine: Engine?
    /// Counts the event, and marks today with the model's state as it is now, in one change.
    private func count(_ event: (inout Tally) -> Void) {
        var next = tally
        event(&next)
        if let activePath {
            let file = App.adapterFile(for: activePath)
            App.markPersonal(&next, adapter: file.map(App.name(ofAdapter:)), applied: engine?.applied.withLock { $0 },
                             wanted: App.adapterToday(model: activePath) != nil)
        }
        tally = next
    }
    /// A model with no adapter compares nothing, so its day is mixed. Otherwise only once the engine has caught up with today:
    /// unloaded (nil), just past midnight, or an adapter that won't load says nothing.
    /// shortcut: a broken adapter's hours, then a working one's the same day, count as a personal day; track failed loads if adapters ship.
    static func markPersonal(_ tally: inout Tally, adapter: String?, applied: Bool?, wanted: @autoclosure () -> Bool) {
        if adapter == nil { tally.mark(personal: nil) }
        else if let applied, applied == wanted() { tally.mark(personal: applied, adapter: adapter) }
    }
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
    /// A suggestion was taken since the window opened, and nothing has stood in the way since.
    @Published var accepted = false
    /// Counts each bind and unbind, so a reason from an earlier one is dropped.
    var binding = 0
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
    /// Started only in a released build, whose Info.plist names the feed. Lazy, to be its own delegate.
    lazy var updates = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    /// An update Sparkle has downloaded, which would wait for a quit that a menu-bar app rarely sees: the dot and a menu item offer it now.
    var readyUpdate: (version: String, install: () -> Void)? { didSet { updateIcon() } }
    /// A newer version the daily check found while Update Automatically is off: the dot and a menu item, instead of Sparkle's window.
    var availableUpdate: String? { didSet { updateIcon() } }
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
    @Published var askedForAccessibility = false
    /// First launch's steps show instead of the home window, until Start Writing (Onboarding.swift).
    @Published var onboarding = false
    /// No model yet, so `Practice` answers Try It's own sentences in the meantime.
    @Published var practicing = false
    /// The last key that took or hid a suggestion, which onboarding's lessons wait for. Onboarding sets it back to nil.
    @Published var taught: KeyTap.Taught?
    /// A key the lesson didn't ask for, so it can say which one it wants. Onboarding sets it back to nil.
    @Published var refused: KeyTap.Taught?
    /// The key onboarding's lesson teaches, the only one our window's ghost answers meanwhile. Nil outside the lessons.
    var lessonKey: KeyTap.Taught? {
        get { tap.state.withLock { $0.only } }
        set { tap.state.withLock { $0.only = newValue } }
    }
    let guide = SettingsGuide()
    private let loading = DispatchQueue(label: "halftype.load", qos: .userInitiated)
    private var latestOpen = 0
    /// The open whose model is installed, so a failure from one it replaced, even at the same path, is ignored. Main thread.
    private var installed = 0
    /// Opens a model, on the loading queue: `Engine`, or a fake in tests.
    var makeEngine: (String, @escaping @Sendable () -> Void) -> Completer? = { path, lost in try? Engine(modelPath: path, onLoadFailure: lost, adapter: App.adapterToday(model:)) }

    @Published var on = UserDefaults.standard.object(forKey: "on") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(on, forKey: "on")
            rebind()
        }
    }
    @Published var length = Length(rawValue: UserDefaults.standard.string(forKey: "length") ?? "") ?? .short {
        didSet { UserDefaults.standard.set(length.rawValue, forKey: "length"); tune() }
    }
    @Published var motion = AcceptMotion(rawValue: UserDefaults.standard.string(forKey: "motion") ?? "") ?? .trail {
        didSet { UserDefaults.standard.set(motion.rawValue, forKey: "motion"); panel.motion = motion }
    }
    /// Lets a tap of ⌃⌥ show what the model was given over each suggestion. Off by default.
    @Published var peeking = UserDefaults.standard.bool(forKey: "peeking") {
        didSet { UserDefaults.standard.set(peeking, forKey: "peeking"); peek() }
    }
    func peek() {
        panel.peekWatch.on = peeking
        watcher.peeking.store(peeking, ordering: .relaxed)
        watcher.retune()  // A ghost already up has no card yet, or keeps one it no longer should.
    }
    @Published var often = Often(rawValue: UserDefaults.standard.string(forKey: "often") ?? "") ?? .normal {
        didSet { UserDefaults.standard.set(often.rawValue, forKey: "often"); tune() }
    }
    /// Try It is where people judge Halftype first, so there it shows a suggestion whenever it can, as long as it can, whatever the settings say.
    func tune() {
        let tryIt = NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()
        let tuning = tryIt ? Tuning(floor: -.infinity, threshold: Often.always.threshold) :Tuning(floor: length.floor, threshold: often.threshold)
        guard Tuning.current.withLock({ $0 }) != tuning else { return }
        Tuning.current.withLock { $0 = tuning }
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
    func isActive(path: String) -> Bool { activePath == path }
    /// Takes one of your GGUFs, from the lists.
    func use(path: String) { open(path, remember: true) }

    func isActive(_ model: ModelStore.Model) -> Bool { ready && activePath == store.path(model).path }

    /// The tap is a fake in tests.
    init(tap: KeyTap = KeyTap()) {
        self.tap = tap
    }

    static func fileName(_ path: String) -> String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private func name(_ path: String) -> String { ModelStore.models.first { store.path($0).path == path }?.name ?? App.fileName(path) }
    /// What the window calls the loaded model: its name if it's one of ours, or else its file.
    var activeName: String { activePath.map(name) ?? "No Model" }
    /// The model being switched to, which can take seconds for a large one: the window shows it at once, so a click is never met with nothing.
    var loadingName: String? { loadingPath.map(name) }
    func isLoading(_ model: ModelStore.Model) -> Bool { loadingPath == store.path(model).path }
    func isLoading(path: String) -> Bool { loadingPath == path }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Before anything makes the folder. Every install before onboarding has it (a model, or the move from Itda), or chose its own model.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "onboarded") == nil {
            defaults.set(FileManager.default.fileExists(atPath: App.support.path) || defaults.string(forKey: "modelPath") != nil, forKey: "onboarded")
        }
        onboarding = !defaults.bool(forKey: "onboarded")
        tune()
        panel.motion = motion
        peek()
        watcher.onShown = { [weak self] in self?.count { $0.shown() } }
        // Keys typed while off had no chance at a suggestion.
        // Only a key in our own window teaches: a Tab in another app while onboarding is open isn't the lesson.
        tap.onTaught = { [weak self] key in
            DispatchQueue.main.async { if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() { self?.taught = key } }
        }
        tap.onRefused = { [weak self] key in DispatchQueue.main.async { self?.refused = key } }
        tap.onTyped = { [weak self] in DispatchQueue.main.async { if self?.on == true { self?.count { $0.typed(1) } } } }
        tap.onAccept = { [weak self] added, keys, suggestion, text, drawing in
            DispatchQueue.main.async {
                guard let self else { return }
                self.panel.took(text, drawing: drawing)
                self.count { $0.took(added, keys: keys, first: suggestion != self.lastTaken) }
                self.lastTaken = suggestion
                if !self.accepted { self.accepted = true }
            }
        }
        // The symbol is for a binary run outside the bundle, as the e2e checks do.
        let glyph = Bundle.main.image(forResource: "MenuBarTemplate") ?? NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "Halftype")!
        glyph.isTemplate = true
        glyph.accessibilityDescription = "Halftype"
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

        if isRelease {
            // The check runs daily whatever General says; Update Automatically only decides whether it downloads.
            updates.updater.automaticallyChecksForUpdates = true
            updates.startUpdater()
        }
        store.removeLeftovers()
        store.onChange = { [weak self] state in self?.modelChanged(state) }
        loadModel()
        // Accessibility is the one permission, and the window asks for it. Nothing runs until the grant.
        watcher.onWhy = { [weak self] why, binding in DispatchQueue.main.async { self?.whyChanged(why, binding: binding) } }
        tap.onUp = { [weak self] up in DispatchQueue.main.async { self?.tapChanged(up: up) } }
        trusted = tap.hold()
        if !trusted { fresh = true }
        // A model opening now installs after this, and replaces it.
        if onboarding, !ready {
            practicing = true
            watcher.install(Practice())
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

    /// A download stops at quit, and what it got is saved first, so the next launch resumes it. Best effort: the save comes on the main
    /// queue, which a quit from a main-queue block holds, so after a second it quits without.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var replied = false
        let reply = {
            if !replied { NSApp.reply(toApplicationShouldTerminate: true) }
            replied = true
        }
        guard store.stop(then: reply) else { return .terminateNow }
        RunLoop.main.add(Timer(timeInterval: 1, repeats: false) { _ in reply() }, forMode: .common)
        return .terminateLater
    }

    /// ggml's Metal device asserts at exit if a model is still loaded. A load under way finishes first, as it can't be stopped, and none
    /// starts after; then every model opened closes, installed or not.
    func applicationWillTerminate(_ note: Notification) {
        save()
        quitting.store(true, ordering: .sequentiallyConsistent)  // Before the drain, so opens queued behind it skip their load.
        watcher.quit(closing: loading.sync { engines.allObjects.compactMap { $0 as? Completer } })
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
        if granted { guide.close() }
        rebind()
        // Back in front of System Settings, where the grant was given.
        if granted, let window {
            showWindow()
            window.orderFrontRegardless()
            // `activate()` is only a request since macOS 14, and Settings, active, keeps the front: the window showed but stayed
            // inactive, so the watcher kept watching Settings and the first lesson's suggestion waited for a click (John: "takes a few
            // seconds"). The deprecated form still takes the front (tried on macOS 27), and here the user has just asked to come back.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// On, and not paused for the front app.
    private var activeHere: Bool { on && !pausedApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") }

    @objc private func rebind() {
        tune()  // Try It and every other app are tuned apart.
        watcher.hideNow()
        tap.reenable()
        updateIcon()
        guard trusted, activeHere, let front = NSWorkspace.shared.frontmostApplication else {
            binding += 1
            watcher.unbind(binding: binding)
            return
        }
        binding += 1
        watcher.bind(pid: front.processIdentifier, binding: binding)
    }

    // MARK: Model

    private func loadModel() {
        if let path = customModel, FileManager.default.fileExists(atPath: path) { return open(path) }
        let first = ModelStore.models[0]
        if store.has(first) { return open(store.path(first).path) }
        // An install from before Gemma was the default keeps the model it has, rather than fetching 3.4 GB unasked.
        if let had = ModelStore.models.first(where: store.has) { return open(store.path(had).path) }
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
    /// Every model opened that something still holds, so quit can close each without waiting on the watcher. Loading queue: an engine
    /// is in here before anything else can hold it.
    private let engines = NSHashTable<AnyObject>.weakObjects()
    /// The model installed last, which onboarding's practice wraps until it ends. Main thread.
    private var answering: Completer?
    private let quitting = Atomic<Bool>(false)

    private func open(_ path: String, remember: Bool = false) {
        if remember { afterFetch = .nothing }
        loadingPath = path
        notice = nil
        latestOpen += 1
        let id = latestOpen
        loading.async { [self] in
            guard !quitting.load(ordering: .sequentiallyConsistent) else { return }
            let engine = makeEngine(path) { [weak self] in DispatchQueue.main.async { self?.lost(id) } }
            if let engine { engines.add(engine) }
            DispatchQueue.main.async { [self] in
                guard id == latestOpen else { return }
                loadingPath = nil
                guard let engine else {
                    notice = "Could not load " + URL(fileURLWithPath: path).lastPathComponent
                    return
                }
                activePath = path
                practicing = false
                self.engine = engine as? Engine
                if !ModelStore.models.contains(where: { store.path($0).path == path }), !ownPaths.contains(path) { ownPaths.append(path) }
                if remember { customModel = path == store.path(ModelStore.models[0]).path ? nil : path }
                installed = id
                answering = engine
                watcher.install(onboarding ? Practice(over: engine) : engine)
            }
        }
    }

    /// The model answering couldn't load again after an idle unload: its file moved or broke. Nothing answers until another is chosen.
    private func lost(_ id: Int) {
        guard id == installed, let path = activePath else { return }
        (installed, activePath, answering) = (0, nil, nil)
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
        // Practice knows English only.
        // Practice finishes only its own sentence, so a field opened again (the window closed mid-step) needs it again too.
        guard let sentence = App.prefill(fresh: fresh || practicing, ready: ready || practicing, draft: draft, korean: ready && watcher.koreanInput.load(ordering: .relaxed)) else { return nil }
        fresh = false
        DispatchQueue.main.async { [self] in watcher.redraw() }
        return sentence
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        onboarding = false
        lessonKey = nil
        if let answering { watcher.install(answering) }
        guide.close()
    }

    // MARK: Why, and the icon

    /// The one line saying why there's no suggestion here, for the menu and under the field. Nil when off or paused, which the menu's
    /// own items show. Not sure is a normal state, and reads as working.
    static func line(trusted: Bool, active: Bool, obstacle: KeyTap.Obstacle?, ready: Bool, why: Watcher.Why) -> String? {
        guard trusted else { return "Halftype needs Accessibility permission." }
        guard active else { return nil }
        if let obstacle { return obstacle.rawValue }
        guard ready else { return "The model isn't ready yet." }
        switch why {
        case .shown, .idle, .blocked: return "Working."  // Blocked with no obstacle now: it has just ended.
        case .unsure: return "Working. Not sure enough to suggest yet."
        case .unreadable: return "No field here that Halftype can read."
        case .textAfter: return "Text after the cursor, so no suggestion here."
        case .notTwoSet: return "Korean suggestions need Apple's 2-Set Korean layout."
        case .noModel: return "The model isn't ready yet."
        case .noCaret: return "This app doesn't say where the cursor is."
        case .noFont: return "This field doesn't report its font, so no suggestion here."
        case .rightToLeft: return "No suggestions in right-to-left text."
        case .noRoom: return "No room to show a suggestion here."
        }
    }

    /// Main. A reason about an app no longer watched is stale. One that stands in the way ends the first accept's line.
    func whyChanged(_ new: Watcher.Why, binding: Int) {
        guard binding == self.binding else { return }
        why = new
        if !new.working { accepted = false }
        updateIcon()  // Secure Input comes and goes with no word to us; the watcher sees it.
    }

    func line(for why: Watcher.Why) -> String? {
        App.line(trusted: trusted, active: activeHere, obstacle: tap.obstacle, ready: ready || practicing, why: why)
    }

    static let lesson = "Tab takes a word. Shift-Tab takes it all. Esc hides it."
    static let success = "That's it. Halftype works like this in almost any app."

    /// Under the field: the menu's line, or while nothing is in the way, that the first accept worked or how to take the ghost showing.
    /// Nothing while off, paused or without the permission.
    func fieldLine(_ why: Watcher.Why) -> String? {
        guard let line = line(for: why) else { return nil }
        guard why.working, ready || practicing, tap.obstacle == nil else { return line }
        return accepted ? App.success : why == .shown ? App.lesson : line
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
        let icon = App.icon(active: activeHere, problem: !trusted || tap.obstacle != nil || (!ready && notice != nil) || readyUpdate != nil || availableUpdate != nil,
                            downloading: downloading.map { _ in downloadFraction })
        guard icon != shownIcon else { return }
        shownIcon = icon
        button.image = icon.mark ? glyphs.marked : glyphs.plain
        button.appearsDisabled = icon.dimmed
        button.title = icon.title
    }

    /// The glyph with a dot at its top right, cut clear around it so it reads at menu-bar size.
    /// Not a template, as macOS paints a template in one colour and the dot should be red, macOS's badge colour for something new; the glyph is coloured for the menu bar's
    /// appearance at each draw instead, so it still follows light and dark.
    static func marked(_ glyph: NSImage) -> NSImage {
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            // Solid black or white, as macOS draws a template (labelColor is a shade lighter).
            (NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor.white : NSColor.black).set()
            rect.fill(using: .sourceAtop)
            let dot = CGRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.accessibilityDescription = "Halftype, needs attention"
        return image
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open Halftype", action: #selector(openWindow), keyEquivalent: "")
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
        if let readyUpdate { menu.addItem(withTitle: "Halftype \(readyUpdate.version) is ready: Restart to Update", action: #selector(installUpdate), keyEquivalent: "") }
        else if let availableUpdate { menu.addItem(withTitle: "Halftype \(availableUpdate) is available: Update…", action: #selector(checkForUpdates), keyEquivalent: "") }
        else if isRelease { menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "") }
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
    @objc private func installUpdate() { readyUpdate?.install() }

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
enum Personal: String, CaseIterable { case off, compare, on }

enum Often: String, CaseIterable {
    case less, normal, more, always
    /// Always has no check at all, unmeasured: what Try It shows.
    var threshold: Double { switch self { case .less: -0.3; case .normal: Gate.threshold; case .more: -1.2; case .always: -.infinity } }
}

extension App: SPUUpdaterDelegate {
    /// Downloaded and set to install on quit. Taking it here keeps Sparkle's own alert away; the menu's item runs the install and relaunch.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        readyUpdate = (item.displayVersionString, immediateInstallHandler)
        return true
    }
    /// The cycle holds while an update waits, so its end means the install ran or failed: either way there's nothing left to offer.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        readyUpdate = nil
    }
}

/// With Update Automatically off, a scheduled check that finds a new version shows the dot rather than Sparkle's window, which in a
/// menu-bar app would open over whatever you're typing. The menu's item asks Sparkle to show it then.
extension App: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { availableUpdate = update.displayVersionString }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { availableUpdate = nil }
    func standardUserDriverWillFinishUpdateSession() { availableUpdate = nil }
}
