import AppKit
import ItdaCore
import ItdaEngine
import Synchronization

/// The model, as this layer needs it: `Engine`, or a fake in the private-window checks.
protocol Completer: AnyObject, Sendable {
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void)
    func cancel()
    func unload()
}

extension Engine: Completer {}

/// One path from "the field changed" to "the ghost is right". All state belongs to `queue`, as AX reads may stall;
/// observer callbacks on the main run loop hand over at once, and only the panel lives on the main thread.
final class Watcher: @unchecked Sendable {
    private static let appNotifications = ["AXFocusedUIElementChanged", "AXFocusedWindowChanged", "AXMainWindowChanged", "AXWindowMoved", "AXWindowResized",
                                           "AXSelectedTextChanged"]
    // On the field only: app-wide AXValueChanged storms while a reply streams.
    private static let fieldNotifications = ["AXValueChanged", "AXSelectedTextChanged"]
    private static let idleUnload: TimeInterval = 300

    let queue = DispatchQueue(label: "itda.watcher", qos: .userInteractive)
    let tap: KeyTap
    private let panel: GhostPanel
    private let updatePending = Atomic<Bool>(false)

    private var app: AXUIElement?
    private var observer: AXObserver?
    private var focused: AXUIElement?
    private var editable = false
    private var context: String?
    private var traits: FieldTraits?
    private var suggestion: (anchor: String, text: String)?
    private var last: Reading?
    private var request = 0
    private var unloadWork: DispatchWorkItem?
    private var pending: (from: String, to: String)?
    /// Where our key events go. Tests send them to a private window.
    var post: (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }

    var completer: Completer?
    /// Read on the main thread, as TIS requires, and kept here.
    let koreanInput = Atomic<Bool>(false)
    let twoSet = Atomic<Bool>(false)
    private var mayCompose: Bool { koreanInput.load(ordering: .relaxed) && tap.composing.load(ordering: .relaxed) }

    init(tap: KeyTap, panel: GhostPanel) {
        self.tap = tap
        self.panel = panel
        // On the system-wide element this is the default for every element read later, children included.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX.timeout)
        tap.onAccept = { [weak self] all in self?.queue.async { self?.accept(all: all) } }
        tap.onDismiss = { [weak self] in self?.queue.async { self?.dismiss() } }
    }

    // MARK: Binding

    /// Which app to watch: the frontmost, or in tests a private window's own process.
    func bind(pid: pid_t) {
        queue.async { [self] in
            detach()
            let app = AXUIElementCreateApplication(pid)
            // Electron's documented switch; a no-op elsewhere. Chromium's own switch follows in `refocus` if needed.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, name, refcon in
                Unmanaged<Watcher>.fromOpaque(refcon!).takeUnretainedValue().notified(name as String)
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
            self.app = app
            self.observer = observer
            for name in Self.appNotifications { AXObserverAddNotification(observer, app, name as CFString, refcon) }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            refocus()
            update()
        }
    }

    func unbind() { queue.async { [self] in detach() } }

    private var refcon: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        (app, observer, focused) = (nil, nil, nil)
        forget()
    }

    /// Main run loop, no IPC here.
    private func notified(_ name: String) {
        switch name {
        case "AXWindowMoved", "AXWindowResized":
            hideNow()
        case "AXFocusedUIElementChanged", "AXFocusedWindowChanged", "AXMainWindowChanged":
            queue.async { [self] in
                refocus()
                update()
            }
        default:
            scheduleUpdate()
        }
    }

    /// Reads coalesce, so a hung app can't build a backlog.
    func scheduleUpdate() {
        guard !updatePending.exchange(true, ordering: .acquiringAndReleasing) else { return }
        queue.async { [self] in
            updatePending.store(false, ordering: .releasing)
            update()
        }
    }

    private func refocus() {
        guard let app, let observer else { return }
        let now = AX.element(AX.get(app, "AXFocusedUIElement"))
        if let now, let focused, CFEqual(now, focused) { return }
        if let focused { for name in Self.fieldNotifications { AXObserverRemoveNotification(observer, focused, name as CFString) } }
        forget()
        focused = now
        guard let now else { return }
        editable = Reader.isEditableText(now)
        if !editable, let role = AX.get(now, "AXRole") as? String, role == "AXWebArea" || role == "AXGroup" {
            // shortcut: Chromium builds its web tree only when asked, and a web view holding focus with no field is its sign. Not
            // tested with the attribute off (Cotypist had it on); see docs/live-test.md.
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        guard editable else { return }
        for name in Self.fieldNotifications { AXObserverAddNotification(observer, now, name as CFString, refcon) }
    }

    /// Everything tied to the focused field.
    private func forget() {
        completer?.cancel()
        request += 1
        (editable, context, traits, suggestion, last, pending) = (false, nil, nil, nil, nil, nil)
        tap.composing.store(false, ordering: .relaxed)
        hideOnMain()
    }

    // MARK: The path

    private func update() {
        guard editable, let focused, let reading = Reader.read(focused, mayCompose: mayCompose) else {
            last = nil
            clearSuggestion()
            return
        }
        // One key brings several notifications; only the first of them finds anything new.
        if reading == last { return }
        last = reading
        let field = settled(reading.field)
        if field.before.isEmpty {
            // A message was sent, so what's above has changed. It is read again with the first character typed, not now: the
            // reply isn't there yet. An empty field also shows its placeholder, which a ghost would overlap.
            context = nil
            clearSuggestion()
            return
        }
        guard !hasTextAfterCaret(field) else {
            clearSuggestion()
            return
        }
        if let suggestion, let ghost = Follow.check(anchor: suggestion.anchor, suggestion: suggestion.text, field: field) {
            display(ghost, reading)
            return
        }
        clearSuggestion()
        ask(field)
    }

    /// Anything but a line end right after the caret means the ghost would sit on top of it.
    private func hasTextAfterCaret(_ field: Field) -> Bool {
        field.after.first.map { !$0.isNewline } ?? false
    }

    /// `pending` is what the field will hold once our last accept lands. Tab-Tab can beat the host's update, and accepting from the
    /// old text would insert the same word twice. On the way, 갑 is neither where 가 was nor where 값이 will be; only moving
    /// forward between them counts, so a field cleared or edited meanwhile lets it go.
    private func settled(_ field: Field) -> Field {
        guard let pending else { return field }
        let keys = Hangul.keys(field.before)
        if field.before != pending.to, keys.hasPrefix(Hangul.keys(pending.from)), Hangul.keys(pending.to).hasPrefix(keys) {
            return Field(before: pending.to, after: field.after)
        }
        self.pending = nil
        return field
    }

    /// What Tab would type before inserting. Nil if that can't be done here, which means no ghost: any Korean layout but 2-set.
    private func strokes(_ ghost: Ghost) -> [TwoSetLayout.Stroke]? {
        if ghost.keys.isEmpty { return [] }
        return twoSet.load(ordering: .relaxed) ? TwoSetLayout.strokes(ghost.keys) : nil
    }

    private func ask(_ field: Field) {
        guard let completer, let focused else { return }
        if context == nil { context = Reader.context(of: focused) }
        let prompt = Prompt.make(context: context ?? "", field: field)
        guard !prompt.prefix.isEmpty else { return }
        let anchor = field.committed
        request += 1
        let id = request
        completer.suggest(prefix: prompt.prefix, fragment: prompt.fragment, composing: prompt.composing) { [weak self] result in
            guard let result else { return }
            self?.queue.async { self?.received(id: id, anchor: anchor, text: result.text, gate: result.gate) }
        }
        unloadWhenIdle()
    }

    /// Queue. Runs from the load too, or a model never asked anything would stay.
    func unloadWhenIdle() {
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak completer] in completer?.unload() }
        unloadWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.idleUnload, execute: work)
    }

    private func received(id: Int, anchor: String, text: String, gate: Double?) {
        guard id == request, let gate, gate >= Gate.threshold, let last else { return }
        suggestion = (anchor, text)
        // A field that has already moved on brings its own update.
        if let ghost = Follow.check(anchor: anchor, suggestion: text, field: settled(last.field)) { display(ghost, last) }
    }

    private func display(_ ghost: Ghost, _ reading: Reading) {
        guard strokes(ghost) != nil, let focused, let caret = reading.caret else { return hideOnMain() }
        if traits == nil { traits = Reader.traits(focused, before: reading.field.before) }
        guard let traits else { return hideOnMain() }
        let spec = GhostSpec(text: ghost.remainder, caret: caret, frame: reading.frame, fontSize: traits.fontSize, fontName: traits.fontName,
                             color: traits.color, lineLeft: traits.lineLeft, previousCharacter: reading.previousCharacter,
                             mayWrap: reading.field.after.allSatisfy(\.isWhitespace))
        DispatchQueue.main.async { [self] in
            tap.armed.store(panel.show(spec), ordering: .relaxed)
            showScrollWatch()
        }
    }

    private func clearSuggestion() {
        suggestion = nil
        completer?.cancel()
        request += 1
        hideOnMain()
    }

    private func dismiss() {
        suggestion = nil
        hideOnMain()
    }

    // MARK: Accepting

    /// Read again, as the ghost may be a keystroke behind. If nothing is left to accept the Tab goes on to the app.
    func accept(all: Bool) {
        if let focused, let suggestion, let read = Reader.read(focused, mayCompose: mayCompose)?.field {
            let field = settled(read)
            if let ghost = Follow.check(anchor: suggestion.anchor, suggestion: suggestion.text, field: field), let strokes = strokes(ghost) {
                let accepted = all ? Accept.all(ghost) : Accept.nextWord(ghost)
                pending = (pending?.from ?? read.before, field.committed + ghost.composing + accepted.text)
                Inserter.press(field.composing.isEmpty ? strokes : strokes + [Inserter.commitKey], post: post)
                Inserter.insert(accepted.text, post: post)
                tap.composing.store(false, ordering: .relaxed)  // Inserting commits.
                return
            }
        }
        KeyTap.repostTab(shift: all, post: post)
    }

    // MARK: Hiding

    private var scrollMonitor: Any?

    /// Scrolling moves text with no AX notification. A passive monitor, up only while a ghost shows, needs no permission.
    private func showScrollWatch() {
        guard tap.armed.load(ordering: .relaxed), scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] _ in self?.hideNow() }
    }

    private func hideOnMain() {
        DispatchQueue.main.async { [self] in hideNow() }
    }

    /// Main thread.
    func hideNow() {
        tap.armed.store(false, ordering: .relaxed)
        panel.hideGhost()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}
