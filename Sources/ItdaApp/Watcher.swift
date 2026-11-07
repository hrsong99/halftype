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
    private static let oneFrame: TimeInterval = 1.0 / 60

    let queue = DispatchQueue(label: "itda.watcher", qos: .userInteractive)
    let tap: KeyTap
    private let panel: GhostPanel
    private let updatePending = Atomic<Bool>(false)

    private var app: AXUIElement?
    private var observer: AXObserver?
    var focused: AXUIElement?
    private var pid: pid_t = 0
    private var context: String?
    private var suggestion: (anchor: String, text: String)?
    private var last: Reading?
    /// The tap's generation when `last` was read: a later key means it may no longer be what the field holds.
    private var lastGeneration = 0
    private var request = 0
    private var unloadWork: DispatchWorkItem?

    var completer: Completer?
    /// The host, as this layer reads it: `Reader`, or a fake.
    var read: (AXUIElement) -> Reading? = { Reader.read($0) }
    var traits: (AXUIElement, String) -> FieldTraits? = { Reader.traits($0, before: $1) }
    /// Read on the main thread, as TIS requires, and kept here.
    let koreanInput = Atomic<Bool>(false)
    let twoSet = Atomic<Bool>(false)

    init(tap: KeyTap, panel: GhostPanel) {
        self.tap = tap
        self.panel = panel
        // On the system-wide element this is the default for every element read later, children included.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX.timeout)
        tap.onDismiss = { [weak self] in self?.queue.async { self?.clearSuggestion() } }
        // A key that changes nothing brings no update, and only time can tell, so a ghost Tab no longer accepts stays one frame: no hand
        // presses Tab within it, and hiding at once blanks the ghost on half the keys of typing through it. See docs/measuring.md.
        // A later key has its own frame, which this one's timer must not cut short.
        tap.onInput = { [weak self] generation in
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.oneFrame) {
                if self?.tap.generation == generation { self?.hideDisarmed() }
            }
        }
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
            self.pid = pid
            for name in Self.appNotifications { AXObserverAddNotification(observer, app, name as CFString, refcon) }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            refocus()
            update()
        }
    }

    func unbind() { queue.async { [self] in detach() } }

    /// Each of these can leave a ghost over a field that has moved, with no key or activation to clear it. Main thread.
    func hideOnSessionChange() {
        let workspace = NSWorkspace.shared.notificationCenter
        let hiding: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification), (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification), (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (.default, NSApplication.didChangeScreenParametersNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),  // Undocumented, and the only word of a lock.
        ]
        for (center, name) in hiding {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.hideNow() }
        }
    }

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
            hideNow()  // Before the read, which may stall: from here Tab belongs to whatever has focus.
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

    /// The field may read the same, and the ghost should still change: the input source moved.
    func redraw() {
        queue.async { [self] in
            last = nil
            update()
        }
    }

    private func refocus() {
        guard let app, let observer else { return }
        let now = AX.element(AX.get(app, "AXFocusedUIElement"))
        if let now, let focused, CFEqual(now, focused) {
            last = nil  // Hidden for this notification, with nothing else to bring it back.
            return
        }
        if let focused { for name in Self.fieldNotifications { AXObserverRemoveNotification(observer, focused, name as CFString) } }
        forget()
        focused = now
        guard let now else { return }
        let editable = Reader.isEditableText(now)
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
        (context, suggestion, last) = (nil, nil, nil)
        tap.state.withLock { ($0.composing, $0.pending) = (false, nil) }
        hideOnMain()
    }

    // MARK: The path

    private func update() {
        let generation = tap.generation  // Before the read: whatever comes after it is a change this read may not have seen.
        // A ghost Tab can't take would hand Tab to the host, which moves focus out of the field.
        guard tap.canTake, let focused, var reading = read(focused) else {
            last = nil
            clearSuggestion()
            return
        }
        reading.field.mayCompose = mayCompose(reading)
        // One key brings several notifications; only the first of them finds anything new.
        if reading == last { return }
        // A key during the read may be in it, and its notification must not then find nothing new.
        last = tap.generation == generation ? reading : nil
        lastGeneration = generation
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
        // Any other Korean layout: a composition could swallow text we insert, and there's no telling, so no ghost.
        if koreanInput.load(ordering: .relaxed), !twoSet.load(ordering: .relaxed), let end = field.before.last, Hangul.isHangul(end) {
            clearSuggestion()
            return
        }
        if let suggestion, let ghost = Follow.check(anchor: suggestion.anchor, suggestion: suggestion.text, field: field) {
            display(ghost, field, reading, generation)
            return
        }
        clearSuggestion()
        ask(field)
    }

    /// Anything but a line end right after the caret means the ghost would sit on top of it.
    private func hasTextAfterCaret(_ field: Field) -> Bool {
        field.after.first.map { !$0.isNewline } ?? false
    }

    /// A marked range is exact when there is one. Without one the key history decides.
    private func mayCompose(_ reading: Reading) -> Bool {
        guard twoSet.load(ordering: .relaxed) else { return false }
        if reading.marked { return true }
        return tap.state.withLock {
            // Backspace past a composition's first jamo takes a character away, and what's left was committed.
            if let last, reading.field.before.count < last.field.before.count { $0.composing = false }
            return $0.composing
        }
    }

    /// On the way from `from` to `to`, 갑 is neither where 가 was nor where 값이 will be; only moving forward between them counts,
    /// so a field cleared or edited meanwhile lets it go. A late read can't bring back text already accepted.
    private func settled(_ field: Field) -> Field {
        tap.state.withLock {
            guard let pending = $0.pending else { return field }
            let keys = Hangul.keys(field.before)
            if field.before != pending.to, keys.hasPrefix(Hangul.keys(pending.from)), Hangul.keys(pending.to).hasPrefix(keys) {
                return Field(before: pending.to, after: field.after, mayCompose: field.mayCompose)
            }
            $0.pending = nil
            return field
        }
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
        guard id == request, tap.canTake, let gate, gate >= Gate.threshold, let last else { return }
        suggestion = (anchor, text)
        // A field that has already moved on brings its own update.
        let field = settled(last.field)
        if let ghost = Follow.check(anchor: anchor, suggestion: text, field: field) { display(ghost, field, last, lastGeneration) }
    }

    private func display(_ ghost: Ghost, _ field: Field, _ reading: Reading, _ generation: Int) {
        let twoSet = twoSet.load(ordering: .relaxed)
        var ghost = ghost
        if twoSet { ghost.remainder = TwoSetLayout.typable(ghost.remainder) }
        // Only as offered: typing through a word has to see it out, or the ghost would blink off for its last letters.
        let typedThrough = suggestion.map { Word.withoutTrailingSpaces($0.anchor) != Word.withoutTrailingSpaces(field.committed) } ?? false
        guard !ghost.remainder.isEmpty, typedThrough || Gate.worthShowing(ghost), let focused, let caret = reading.caret, !Reader.isRightToLeft(field.before, ghost.remainder) else { return hideOnMain() }
        guard let traits = traits(focused, reading.field.before) else {
            last = nil  // A good read isn't a good draw: the next notification may find the same field, and must try again.
            return hideOnMain()
        }
        let spec = GhostSpec(text: ghost.remainder, caret: caret, frame: reading.frame, fontSize: traits.fontSize, fontName: traits.fontName,
                             color: traits.color, lineLeft: traits.lineLeft, previousCharacter: reading.previousCharacter,
                             mayWrap: reading.field.after.allSatisfy(\.isWhitespace))
        let armed = KeyTap.Armed(pid: pid, ghost: ghost, typesKeys: twoSet, committed: field.committed, before: field.before)
        DispatchQueue.main.async { [self] in
            guard tap.generation == generation else { return }
            guard let drawn = panel.show(spec) else { return hidePanel() }
            var offer = armed
            offer.ghost.remainder = drawn  // `suggestion` keeps the rest, to draw as the field reaches it.
            if tap.arm(offer, generation: generation) { showScrollWatch() } else { hideDisarmed() }
        }
    }

    private func clearSuggestion() {
        suggestion = nil
        completer?.cancel()
        request += 1
        hideOnMain()
    }

    // MARK: Hiding

    private var scrollMonitor: Any?

    /// Scrolling moves text with no AX notification. A passive monitor, up only while a ghost shows, needs no permission.
    private func showScrollWatch() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in self?.hideNow() }
    }

    /// Queue. Moves no generation, as the read this hide came from may still ask: its answer is good unless input came since. A display
    /// already queued for the main thread runs before this hide, so it can arm for that moment but ends hidden and disarmed.
    private func hideOnMain() {
        tap.disarm()
        DispatchQueue.main.async { [self] in hidePanel() }
    }

    /// Main thread.
    func hideNow() {
        tap.invalidate()
        hidePanel()
    }

    /// Main thread. Armed here is the rest of a suggestion after Tab, which stays up.
    private func hideDisarmed() {
        if tap.state.withLock({ $0.armed == nil }) { hidePanel() }
    }

    /// Main thread. Nothing hidden can be accepted.
    private func hidePanel() {
        tap.disarm()
        panel.hideGhost()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }
}
