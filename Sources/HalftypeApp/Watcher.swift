import AppKit
import HalftypeCore
import HalftypeEngine
import Synchronization

/// The model, as this layer needs it: `Engine`, or a fake in the private-window checks.
protocol Completer: AnyObject, Sendable {
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void)
    func cancel()
    func unload()
    /// Unloads for good: no later request may load it again.
    func close()
}

extension Completer {
    func close() { unload() }
}

extension Engine: Completer {}

/// One path from "the field changed" to "the ghost is right". All state belongs to `queue`, as AX reads may stall;
/// observer callbacks on the main run loop hand over at once, and only the panel lives on the main thread.
final class Watcher: @unchecked Sendable {
    private static let appNotifications = ["AXFocusedUIElementChanged", "AXFocusedWindowChanged", "AXMainWindowChanged", "AXWindowMoved", "AXWindowResized",
                                           "AXSelectedTextChanged"]
    // On the field only: app-wide AXValueChanged storms while a reply streams.
    private static let fieldNotifications = ["AXValueChanged", "AXSelectedTextChanged"]
    private static let oneFrame: TimeInterval = 1.0 / 60
    /// A host that hasn't shown a typed letter by now never will: Chromium answers in 12-29 ms (docs/measuring.md), so this is over 15 times that.
    private static let unanswered: TimeInterval = 0.5
    /// The input whose letter the drawing lost in place, which the frame's hide leaves to the host's update. Main thread.
    private var trimmed = -1

    let queue = DispatchQueue(label: "halftype.watcher", qos: .userInteractive)
    let tap: KeyTap
    private let panel: GhostPanel
    private let updatePending = Atomic<Bool>(false)

    private var app: AXUIElement?
    private var observer: AXObserver?
    var focused: AXUIElement?
    private var pid: pid_t = 0
    private var process = Priming.Process(pid: 0, launched: nil)
    private var context: String?
    private var suggestion: (anchor: String, text: String)?
    /// The ⌃⌥ card for `suggestion`, made only while `peeking`. Typed text, so in memory only.
    private var peek: Peek?
    let peeking = Atomic<Bool>(false)
    private var last: Reading?
    /// The tap's generation when `last` was read: a later key means it may no longer be what the field holds.
    private var lastGeneration = 0
    private var request = 0
    private var unloadWork: DispatchWorkItem?
    /// Numbers the model's suggestions by their request, for the counts: streaming or following one as you type keeps its number.
    private var suggestionNumber = 0
    /// Main thread only: the last suggestion counted as shown.
    private var counted = 0
    /// On the main thread, once per suggestion drawn.
    var onShown: (() -> Void)?
    /// How long a model stays loaded with nothing asked of it.
    var idleUnload: TimeInterval = 300
    /// No field could be read at the last try. A host building its tree lazily may say nothing once it's done, so keys then ask again.
    private var lost = false
    var priming = Priming()
    private let healing = OneAtATime()
    /// Turns Chromium's flag off at quit. Watcher queue.
    var restore: (pid_t) -> Void = { AXUIElementSetAttributeValue(AXUIElementCreateApplication($0), Priming.enhanced as CFString, kCFBooleanFalse) }
    /// A process's launch time, which tells it from a later one given the same pid. Watcher queue.
    var launchDate: (pid_t) -> Date? = { NSRunningApplication(processIdentifier: $0)?.launchDate }

    var completer: Completer?
    /// The host, as this layer reads it: `Reader`, or a fake.
    var read: (AXUIElement) -> Reading? = { Reader.read($0) }
    var traits: (AXUIElement, Reading) -> FieldTraits? = { Reader.traits($0, before: $1.field.before, skipped: $1.skipped) }
    /// How Often's gate, read per answer. Tests fix it, as any App() in another suite retunes the shared one.
    var threshold: () -> Double = { Tuning.current.withLock { $0.threshold } }
    /// Read on the main thread, as TIS requires, and kept here.
    let koreanInput = Atomic<Bool>(false)
    let twoSet = Atomic<Bool>(false)

    /// Why there's no ghost in the focused field, or that one shows: set at each place the path stops, and only when it settles, not
    /// while a request is out. No typed text in it.
    enum Why: Equatable {
        case shown, idle, unsure, unreadable, blocked, textAfter, notTwoSet, noModel, noCaret, noFont, rightToLeft, noRoom
        /// Nothing in the way: a ghost, none asked for yet, or the model not sure.
        var working: Bool { self == .shown || self == .idle || self == .unsure }
    }
    /// Told of each change with the binding it's about, in order, on this queue.
    var onWhy: ((Why, Int) -> Void)?
    /// Which `bind` or `unbind` this queue is serving, as numbered by the caller. Queue.
    private var binding = 0
    private var reported: (why: Why, binding: Int) = (.unreadable, 0)
    /// Queue, so reports go out in the order they're made. A draw comes back from the main thread only for its own input and binding,
    /// and every hide comes back the same way, after it: see `display` and `hidePanel`.
    private func record(_ now: Why) {
        guard (now, binding) != reported else { return }
        reported = (now, binding)
        onWhy?(now, binding)
    }

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
            if let self { healing.run(on: queue) { [weak self] in self?.heal() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.oneFrame) {
                if self?.tap.generation == generation, self?.trimmed != generation { self?.hideDisarmed() }
            }
        }
        // Typed through: the drawing loses the letter in place and waits for the host, disarmed, rather than hide after a frame. A host that
        // never shows the letter can't keep it up: with no new drawing and no other input, it goes after the time any host takes to answer.
        // Not with a Korean source, which may recompose the letter before. Queued before `onInput`'s frame, so it runs first.
        tap.onTypedThrough = { [weak self] drawing, text, generation in
            guard let self, !koreanInput.load(ordering: .relaxed) else { return }
            DispatchQueue.main.async {
                guard self.panel.trim(text, drawing: drawing) != nil else { return }
                self.trimmed = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.unanswered) {
                    if self.tap.generation == generation, self.panel.drawing == drawing { self.hidePanel() }
                }
            }
        }
    }

    // MARK: Binding

    /// Which app to watch: the frontmost, or in tests a private window's own process.
    func bind(pid: pid_t, binding: Int = 0) {
        queue.async { [self] in attach(pid: pid, binding: binding) }
    }

    /// Queue.
    private func attach(pid: pid_t, binding: Int) {
        self.binding = binding
        detach()
        let app = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            Unmanaged<Watcher>.fromOpaque(refcon!).takeUnretainedValue().notified(name as String, element)
        }
        // Just after the grant the tap is up but AX still refuses for a moment (apiDisabled): an observer made then hears nothing,
        // ever, and the first lesson's field sat without its suggestion until a click rebound (seen live, 2026-11-09). Again shortly.
        // Checked in the same block that attaches: a newer bind queued meanwhile has moved `binding`, and wins.
        let again = { [self] in queue.asyncAfter(deadline: .now() + 0.5) { [self] in if self.binding == binding { attach(pid: pid, binding: binding) } } }
        let made = AXObserverCreate(pid, callback, &created)
        guard made == .success, let observer = created else { return made == .apiDisabled ? again() : () }
        self.app = app
        self.observer = observer
        self.pid = pid
        process = Priming.Process(pid: pid, launched: launchDate(pid))
        priming.bound(process)
        let added = AX.own(app) { Self.appNotifications.map { AXObserverAddNotification(observer, app, $0 as CFString, refcon) } }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        refocus()
        update()
        if added.contains(.apiDisabled) { again() }
    }

    func unbind(binding: Int = 0) {
        queue.async { [self] in
            self.binding = binding
            detach()
        }
    }

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
        record(.unreadable)
    }

    /// Main run loop, no IPC here.
    private func notified(_ name: String, _ element: AXUIElement) {
        switch name {
        case "AXWindowMoved", "AXWindowResized":
            // In Try It our own panel's moves come here too, and drawing a ghost moves it: that hide disarmed every ghost there.
            guard !Self.isGhostPanel(element) else { return }
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

    /// Only asks our own process, which answers in-process: the main thread does no IPC here.
    static func isGhostPanel(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == getpid() else { return false }
        return AX.get(element, "AXIdentifier") as? String == GhostPanel.accessibilityID
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

    /// True if an editable field has focus.
    @discardableResult private func refocus() -> Bool {
        guard let app, let observer else { return false }
        prime(app)
        let now = AX.element(AX.get(app, "AXFocusedUIElement"))
        if let now, let focused, CFEqual(now, focused) {
            last = nil  // Hidden for this notification, with nothing else to bring it back.
        } else {
            if let focused { AX.own(focused) { for name in Self.fieldNotifications { AXObserverRemoveNotification(observer, focused, name as CFString) } } }
            forget()
            focused = now
        }
        // Asked again of the same element, as a field can become editable in place. Adding twice is refused, harmlessly.
        guard let now, Reader.isEditableText(now) else { return false }
        AX.own(now) { for name in Self.fieldNotifications { AXObserverAddNotification(observer, now, name as CFString, refcon) } }
        return true
    }

    /// Queue, from the tap's input: nothing unless the last read failed, then a look for the field and a read only if there is one.
    private func heal() {
        if lost, refocus() { scheduleUpdate() }
    }

    /// Chromium and Electron build their accessibility tree only when asked, once per process.
    private func prime(_ app: AXUIElement) {
        let pid = pid
        guard let attribute = priming.next(process, now: Date(), kind: { Priming.kind(of: app, pid: pid) },
                                           voiceOver: { NSWorkspace.shared.isVoiceOverEnabled }, isOn: { AX.get(app, Priming.enhanced) as? Bool })
        else { return }
        // Its result says nothing: Chromium answers "not implemented" while it works.
        _ = AX.own(app) { AXUIElementSetAttributeValue(app, attribute as CFString, kCFBooleanTrue) }
    }

    /// Quit, main thread. The models close first, without waiting on this queue, which a hung host can hold: ggml asserts at exit with
    /// one loaded, and a request still on its way must not load it again. Only then the restore, which may give up.
    func quit(closing models: [Completer], within deadline: TimeInterval = 2 * Double(AX.timeout)) {
        for model in models { model.close() }
        unprime(within: deadline)
    }

    /// Chromium's flag slows window managers, so it goes back off where we turned it on, as best we can: hung hosts
    /// can't hold the quit past one deadline, the wait for the queue included. VoiceOver's own use stays. Electron's switch is left, as
    /// its read-back can't tell it was ours.
    func unprime(within deadline: TimeInterval = 2 * Double(AX.timeout)) {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in
            if !NSWorkspace.shared.isVoiceOverEnabled {
                for pid in priming.ours(launched: launchDate) { restore(pid) }
            }
            done.signal()
        }
        _ = done.wait(timeout: .now() + deadline)
    }

    /// Everything tied to the focused field.
    private func forget() {
        completer?.cancel()
        request += 1
        (context, suggestion, peek, last) = (nil, nil, nil, nil)
        tap.state.withLock { ($0.composing, $0.pending) = (false, nil) }
        hideOnMain()
    }

    // MARK: The path

    private func update() {
        let generation = tap.generation  // Before the read: whatever comes after it is a change this read may not have seen.
        // A ghost Tab can't take would hand Tab to the host, which moves focus out of the field. Asked again after the read, which
        // may have stalled while Secure Input began.
        guard tap.canTake, let focused, var reading = read(focused), tap.canTake else {
            (last, lost) = (nil, true)
            clearSuggestion()
            return record(tap.canTake ? .unreadable : .blocked)
        }
        lost = false
        reading.field.mayCompose = mayCompose(reading)
        // One key brings several notifications; only the first of them finds anything new.
        if reading == last { return }
        // A key during the read may be in it, and its notification must not then find nothing new.
        last = tap.generation == generation ? reading : nil
        lastGeneration = generation
        // The read where our last accept has fully landed, which `settled` then lets go: its caret is where a Tab's motion ends.
        if tap.state.withLock({ $0.pending?.to == reading.field.before }), let caret = reading.caret {
            DispatchQueue.main.async { [panel] in panel.landed(at: caret) }
        }
        let field = settled(reading.field)
        if field.before.isEmpty {
            // A message was sent, so what's above has changed. It is read again with the first character typed, not now: the
            // reply isn't there yet. An empty field also shows its placeholder, which a ghost would overlap.
            context = nil
            clearSuggestion()
            return record(.idle)
        }
        guard !hasTextAfterCaret(field) else {
            clearSuggestion()
            return record(.textAfter)
        }
        // Any other Korean layout: a composition could swallow text we insert, and there's no telling, so no ghost.
        if koreanInput.load(ordering: .relaxed), !twoSet.load(ordering: .relaxed), let end = field.before.last, Hangul.isHangul(end) {
            clearSuggestion()
            return record(.notTwoSet)
        }
        if let suggestion, let ghost = Follow.check(anchor: suggestion.anchor, suggestion: suggestion.text, field: field) {
            display(ghost, field, reading, generation)
            return
        }
        clearSuggestion()
        // No ghost could be drawn: Teams, LibreOffice, or a native line start. A suggestion already held still follows above.
        guard reading.caret != nil else { return record(.noCaret) }
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
        guard let completer, let focused else { return record(.noModel) }
        if context == nil { context = Reader.context(of: focused) }
        let prompt = Prompt.make(context: context ?? "", field: field)
        guard !prompt.prefix.isEmpty else { return record(.unsure) }  // Not a whole word yet.
        // The context read may have stalled too. Forgetting the read lets the same field ask again once Tab can be taken.
        guard tap.canTake else {
            last = nil
            return record(.blocked)
        }
        let anchor = field.committed
        request += 1
        let id = request
        let context = context?.count ?? 0
        completer.suggest(prefix: prompt.prefix, fragment: prompt.fragment, composing: prompt.composing) { [weak self] result in
            self?.queue.async { self?.received(id: id, anchor: anchor, prompt: prompt, context: context, result) }
        }
        unloadWhenIdle()
    }

    /// Queue. Runs from the install too, or a model never asked anything would stay. On this queue, so a request and an unload whose
    /// time has come can't interleave: the request cancels it first, or it unloads first and the request loads again.
    private func unloadWhenIdle() {
        unloadWork?.cancel()
        let work = DispatchWorkItem { [weak completer] in completer?.unload() }
        unloadWork = work
        queue.asyncAfter(deadline: .now() + idleUnload, execute: work)
    }

    /// A new model, or none: the old one's request and suggestion go, and the field is asked again, as it may not change by itself.
    func install(_ new: Completer?) {
        queue.async { [self] in
            clearSuggestion()  // Cancels the old model's request.
            completer = new
            last = nil
            unloadWhenIdle()
            update()
        }
    }

    /// Nil is the model's last word: nothing to suggest. A gate of nil is a first word still being written, not an answer yet.
    private func received(id: Int, anchor: String, prompt: Prompt, context: Int, _ result: Suggestion?) {
        guard id == request else { return }
        guard tap.canTake else {
            last = nil  // Never shown, so the same field must ask again once Tab can be taken.
            clearSuggestion()
            return record(.blocked)
        }
        guard let result else {
            clearSuggestion()  // The model stopped short: what it streamed goes too.
            return record(.idle)
        }
        guard let gate = result.gate else { return }
        guard gate >= threshold() else { return record(.unsure) }
        guard let last else { return }
        let text = result.text
        suggestion = (anchor, text)
        peek = peeking.load(ordering: .relaxed)
            ? Peek.make(result.tokens, prompt: prompt, context: context, shown: text, tuning: Tuning.current.withLock { $0 }) : nil
        suggestionNumber = id  // One request is one suggestion, however many times it streams.
        // A field that has already moved on brings its own update.
        let field = settled(last.field)
        if let ghost = Follow.check(anchor: anchor, suggestion: text, field: field) { display(ghost, field, last, lastGeneration) }
    }

    private func display(_ ghost: Ghost, _ field: Field, _ reading: Reading, _ generation: Int) {
        let twoSet = twoSet.load(ordering: .relaxed)
        let left = ghost.composing.count + ghost.remainder.count  // of the suggestion, before 2-set trims what it can't type
        var ghost = ghost
        if twoSet { ghost.remainder = TwoSetLayout.typable(ghost.remainder) }
        // Only as offered: typing through a word has to see it out, or the ghost would blink off for its last letters.
        let typedThrough = suggestion.map { Word.withoutTrailingSpaces($0.anchor) != Word.withoutTrailingSpaces(field.committed) } ?? false
        guard !ghost.remainder.isEmpty, typedThrough || Gate.worthShowing(ghost), let focused else {
            hideOnMain()
            return record(.unsure)
        }
        guard let caret = reading.caret else {
            hideOnMain()
            return record(.noCaret)
        }
        guard !Reader.isRightToLeft(field.before, ghost.remainder) else {
            hideOnMain()
            return record(.rightToLeft)
        }
        guard let traits = traits(focused, reading) else {
            last = nil  // A good read isn't a good draw: the next notification may find the same field, and must try again.
            hideOnMain()
            return record(.noFont)
        }
        let spec = GhostSpec(text: ghost.remainder, caret: caret, frame: reading.frame, fontSize: traits.fontSize, fontName: traits.fontName,
                             color: traits.color, lineLeft: traits.lineLeft, previousCharacter: reading.previousCharacter,
                             mayWrap: reading.field.after.allSatisfy(\.isWhitespace), webCaret: reading.webCaret, glass: pid == getpid(),
                             peek: peek.map { var peek = $0; peek.taken = peek.shown - left; return peek })
        let armed = KeyTap.Armed(pid: pid, ghost: ghost, typesKeys: twoSet, committed: field.committed, before: field.before, suggestion: suggestionNumber)
        let binding = binding
        /// Back on the queue, and only for the binding and input this draw was made under: input during the draw has queued a newer report.
        func report(_ why: Why) { queue.async { [self] in if self.binding == binding, tap.generation == generation { record(why) } } }
        DispatchQueue.main.async { [self] in
            guard tap.generation == generation else { return }
            // The last moment before Tab is promised, as Secure Input moves no generation.
            guard tap.canTake else {
                queue.async { [self] in last = nil }
                report(.blocked)
                return hidePanel()
            }
            guard let drawn = panel.show(spec) else {
                report(.noRoom)
                return hidePanel()
            }
            var offer = armed
            offer.ghost.remainder = drawn  // `suggestion` keeps the rest, to draw as the field reaches it.
            offer.drawing = panel.drawing
            guard typedThrough || Gate.worthShowing(offer.ghost) else {  // What fits must still be worth a Tab.
                report(.noRoom)
                return hidePanel()
            }
            if tap.arm(offer, generation: generation) {
                showScrollWatch()
                report(.shown)
                if counted != offer.suggestion {
                    counted = offer.suggestion
                    onShown?()
                }
            } else { hideDisarmed() }
        }
    }

    /// A setting changed: nothing asked for or kept under the old one may show.
    func retune() { queue.async { [self] in clearSuggestion() } }

    private func clearSuggestion() {
        (suggestion, peek) = (nil, nil)
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

    /// Main thread. Every hide ends here: nothing hidden can be accepted, and a ghost no longer shows.
    private func hidePanel() {
        tap.disarm()
        panel.hideGhost()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        queue.async { [self] in if reported.why == .shown { record(.idle) } }
    }
}

/// Which accessibility switch an app needs, and when to flip it. Chromium waits 2 s after its flag is set, and each set restarts the wait,
/// so each process gets one set, and another only if the flag reads off again later. Watcher queue.
struct Priming {
    static let manual = "AXManualAccessibility", enhanced = "AXEnhancedUserInterface"
    /// Past Chromium's 2 s wait, so a second set can't restart it.
    static let recheck: TimeInterval = 3
    /// A process, as a pid alone can be given to another app later.
    struct Process: Hashable {
        var pid: pid_t
        var launched: Date?
    }
    private var apps: [Process: (attribute: String?, touched: Date, ours: Bool)] = [:]

    /// The attribute to set now, if any. `kind` is asked once per process, `voiceOver` at each Chromium set, as it comes and goes, and
    /// `isOn` reads Chromium's flag at most once per `recheck`.
    mutating func next(_ process: Process, now: Date, kind: () -> String?, voiceOver: () -> Bool, isOn: () -> Bool?) -> String? {
        let first = apps[process] == nil
        var app = apps[process] ?? (kind(), .distantPast, false)
        defer { apps[process] = app }
        // Electron's read-back is unreliable, so its one set stands.
        if first, app.attribute == Self.manual { return Self.manual }
        guard app.attribute == Self.enhanced, now.timeIntervalSince(app.touched) > Self.recheck, !voiceOver() else { return nil }
        app.touched = now
        // Chromium can clear it. A failed read is no reason to set it again, but at first there is nothing else to go on.
        let on = isOn(), set = first ? on != true : on == false
        app.ours = app.ours || set
        return set ? Self.enhanced : nil
    }

    /// Where we turned Chromium's flag on and the same process still runs, by a known launch time, to turn it off at quit. Without one,
    /// the pid may be another app's by now, so it's left alone.
    func ours(launched: (pid_t) -> Date?) -> [pid_t] {
        apps.filter { $0.value.ours && $0.key.launched != nil && launched($0.key.pid) == $0.key.launched }.map(\.key.pid)
    }

    /// A process bound again with no launch time may not be the one seen before, so what was learnt of it goes, and it is primed again.
    mutating func bound(_ process: Process) {
        if process.launched == nil { apps[process] = nil }
    }

    /// Electron answers its documented switch as settable. Else a Chromium bundle gets Chromium's. Native apps get nothing: the flag only
    /// slows their windows.
    static func kind(of app: AXUIElement, pid: pid_t) -> String? {
        var settable = DarwinBoolean(false)
        if AX.own(app, { AXUIElementIsAttributeSettable(app, manual as CFString, &settable) == .success }), settable.boolValue { return manual }
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL, shipsChromium(bundle) else { return nil }
        return enhanced
    }

    /// Chromium's process model names a renderer helper `<Name> Helper (Renderer).app`, beside the app's frameworks (Electron)
    /// or inside its framework's helpers (ego lite, Helium and Dia, as installed here).
    static func shipsChromium(_ bundle: URL) -> Bool {
        let files = FileManager.default, frameworks = bundle.appendingPathComponent("Contents/Frameworks")
        func renderer(_ dir: URL) -> Bool { ((try? files.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0.hasSuffix(" Helper (Renderer).app") } }
        return renderer(frameworks) || ((try? files.contentsOfDirectory(atPath: frameworks.path)) ?? []).contains {
            renderer(frameworks.appendingPathComponent($0).appendingPathComponent("Versions/Current/Helpers"))
        }
    }
}

/// At most one run of a job queued or running, so a hung host can't build a backlog. A call after it ends runs it again.
final class OneAtATime: Sendable {
    private let pending = Atomic<Bool>(false)
    func run(on queue: DispatchQueue, _ work: @escaping @Sendable () -> Void) {
        guard !pending.exchange(true, ordering: .acquiringAndReleasing) else { return }
        queue.async { [self] in
            work()
            pending.store(false, ordering: .releasing)
        }
    }
}
