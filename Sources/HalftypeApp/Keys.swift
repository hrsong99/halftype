import AppKit
import Carbon
import HalftypeCore
import Synchronization
import notify

/// The active tap, on its own thread. An accept is one transaction here: no AX, no queue, so nothing can come between the Tab
/// and its text, and any other key or click disarms first, which leaves Tab the app's. Input means any event not marked as ours:
/// another program's synthetic key counts too, which errs towards disarming.
class KeyTap: @unchecked Sendable {
    enum Decision: Equatable {
        case pass, dismiss(swallow: Bool), accept(all: Bool), reenable
        /// The lesson this key would answer, on a ghost.
        var taught: Taught? {
            switch self {
            case .accept(let all): all ? .shiftTab : .tab
            case .dismiss(swallow: true): .esc
            default: nil
            }
        }
    }

    /// Why Tab wouldn't reach us, in the menu's words.
    enum Obstacle: String {
        case tapOff = "Tab isn't reaching Halftype right now."
        case secureInput = "Secure Input is on in another app, so no suggestions until it ends."
    }

    /// What Tab inserts, and where. Set only by a drawn ghost.
    struct Armed {
        var pid: pid_t
        var ghost: Ghost
        /// 2-set presses real keys; every other source inserts text.
        var typesKeys: Bool
        var committed: String
        var before: String
        /// Which of the model's suggestions this is, for the counts: redraws and the rest after a Tab keep it.
        var suggestion = 0
        /// Which of the panel's drawings it was armed on, so a Tab's glint goes only where its words were drawn. The rest after a Tab keeps it.
        var drawing = 0
    }

    struct State {
        /// Moves on every input event, and on what moves a field under a snapshot: focus, window, scroll. A snapshot keeps the value from
        /// before its read, through every later step, and may arm only under that value. A hide alone doesn't move it: see `hideOnMain`.
        var generation = 0
        var armed: Armed?
        /// A syllable may be open, for hosts that don't report marked text: the last physical key was a letter, or a Backspace with one
        /// open. A click, an arrow, Return or a shortcut commits it. Wrong towards true would type a stray jamo after a committed syllable.
        var composing = false
        /// Onboarding's lesson: in our own window, a ghost answers only this key, and the others do nothing at all.
        var only: Taught?
        /// What the field will hold once our last accept lands; Tab-Tab can beat the host's update. Any other input ends it, as the
        /// field then holds something else: Tab, Backspace, and `hello ther` would otherwise read as on its way to `hello there`.
        var pending: (from: String, to: String)?
        /// Tab just took the last of a ghost, and the next (its clipped rest, or a new suggestion) isn't drawn yet. Until then a Tab
        /// for that app types nothing, rather than reach the app as a tab: tapping through a long ghost outruns the redraw and the model.
        /// Any other input, a new ghost or the deadline ends it, so a host that refuses the insert keeps Tab for 0.3 s at most.
        var held: (pid: pid_t, until: Date)?
        var holdFor: TimeInterval = 0.3
        /// The live tap, and the run loop of its thread once that has started.
        var port: CFMachPort?
        var loop: CFRunLoop?

        mutating func accept(_ armed: Armed, all: Bool) -> (strokes: [TwoSetLayout.Stroke]?, text: String, added: Int, words: Int)? {
            let next = all ? Accept.all(armed.ghost) : Accept.nextWord(armed.ghost)
            let strokes = armed.typesKeys ? TwoSetLayout.strokes(next.keys + Hangul.keys(next.text)) : nil
            if armed.typesKeys && strokes == nil { return nil }
            let to = armed.committed + armed.ghost.composing + next.text
            let rest = String(armed.ghost.remainder.dropFirst(next.text.count))
            pending = (pending?.from ?? armed.before, to)
            self.armed = rest.isEmpty ? nil : Armed(pid: armed.pid, ghost: Ghost(remainder: rest), typesKeys: armed.typesKeys, committed: to, before: to,
                                                         suggestion: armed.suggestion, drawing: armed.drawing)
            if rest.isEmpty { held = (armed.pid, Date() + holdFor) }
            composing = strokes?.last.map { TwoSetLayout.letterCodes.contains(Int64($0.code)) } ?? false  // As if the user typed it.
            // Finishing a syllable can add more than the text typed: `그 달` to `그 다라가` is two characters, from `가` alone.
            // Words with the syllable it finishes: `하` to `한 다음` is two.
            return (strokes, next.text, max(0, to.count - armed.before.count), Tally.words(in: armed.ghost.composing + next.text))
        }
    }

    static let tabKey: Int64 = 48, escapeKey: Int64 = 53, backspaceKey: Int64 = 51
    /// Marks our own events, which are no input. They don't come back to a session tap (`tapPostEvent`), and any that do pass untouched.
    static let ownEvent: Int64 = 0x49544441

    let state = Mutex(State())
    /// Off this thread at once. Given the generation this input moved to.
    var onInput: (@Sendable (Int) -> Void)?
    var onDismiss: (@Sendable () -> Void)?
    /// Which key just took or hid a suggestion, for onboarding's lessons. Off this thread at once.
    enum Taught: Sendable { case tab, shiftTab, esc }
    var onTaught: (@Sendable (Taught) -> Void)?
    /// A key the lesson didn't ask for, swallowed with the ghost left up. Off this thread at once.
    var onRefused: (@Sendable (Taught) -> Void)?
    /// Given the characters a Tab added, which suggestion it took from, the text (nil when typed as strokes: an input method may recompose
    /// the letter before it, moving the text from where the ghost was), and the drawing it was taken from. Off this thread at once.
    var onAccept: (@Sendable (_ added: Int, _ keys: Int, _ words: Int, _ suggestion: Int, _ text: String?, _ drawing: Int) -> Void)?
    /// A key typed the ghost's next letter, so the drawing can lose it in place while the host catches up. Tab is disarmed as after any
    /// key, until the host's update arms it again. Given the drawing, the letter, and the generation it moved to. Off this thread at once.
    var onTypedThrough: (@Sendable (_ drawing: Int, _ text: String, _ generation: Int) -> Void)?
    /// When the tap comes up or the system refuses it, on `keeper`. Not for a tap back up within the retry.
    var onUp: (@Sendable (Bool) -> Void)?
    /// Private-window checks tap one process. A proxy doesn't reach an app from such a tap, so they post to it instead.
    private let pid: pid_t?
    /// Owns `up` and `attempt`. Not the main thread: a tap has to come down even if that's busy.
    let keeper = DispatchQueue(label: "halftype.tap.keeper", qos: .userInteractive)
    private var up = false
    private var attempt: DispatchWorkItem?
    private var token: Int32?
    private let retryEvery: TimeInterval

    init(pid: pid_t? = nil, retryEvery: TimeInterval = 1) {
        self.pid = pid
        self.retryEvery = retryEvery
    }

    var generation: Int { state.withLock { $0.generation } }
    /// A key typed a character by hand, for the Stats page's share typed by Tab.
    var onTyped: (@Sendable () -> Void)?

    func invalidate() {
        state.withLock {
            $0.generation += 1
            $0.armed = nil
            $0.pending = nil
            $0.held = nil
        }
    }

    func disarm() { state.withLock { $0.armed = nil } }

    /// Nil if Tab would reach us now, so a ghost could be taken. Secure Input keeps keys from a tap that stays present and enabled.
    var obstacle: Obstacle? {
        guard let port = state.withLock({ $0.port }), CGEvent.tapIsEnabled(tap: port) else { return .tapOff }
        return IsSecureEventInputEnabled() ? .secureInput : nil
    }

    var canTake: Bool { obstacle == nil }

    /// A tap the system turned off stays off if its notice never came, so activation and wake call this.
    func reenable() {
        guard let port = state.withLock({ $0.port }), !CGEvent.tapIsEnabled(tap: port) else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// False if anything has happened since `generation`.
    func arm(_ armed: Armed, generation: Int) -> Bool {
        state.withLock {
            guard $0.generation == generation else { return false }
            $0.armed = armed
            $0.held = nil
            return true
        }
    }

    static func decide(type: CGEventType, keyCode: Int64, flags: CGEventFlags, armed: Bool) -> Decision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .reenable }
        guard type == .keyDown else { return .pass }
        let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
        // On a ghost Esc is ours alone: passed on, it would also clear a search field or close a pane. Force Quit always passes.
        if keyCode == escapeKey { return .dismiss(swallow: armed && plain) }
        guard armed, keyCode == tabKey, plain else { return .pass }
        return .accept(all: flags.contains(.maskShift))
    }

    /// A key typed the ghost's next letter, which only the drawing may act on before the host confirms it (a Chromium app takes longer
    /// than the frame a ghost is kept): not for 2-set, whose letters an input method recomposes, nor the last letter, which leaves nothing.
    static func typesNext(_ armed: Armed, _ typed: String) -> Bool {
        guard !armed.typesKeys, armed.ghost.composing.isEmpty, armed.ghost.keys.isEmpty, armed.ghost.remainder.count > 1,
              let first = armed.ghost.remainder.first else { return false }
        return String(first) == typed
    }

    static func composes(after was: Bool, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .keyDown, flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return false }
        return keyCode == backspaceKey ? was : TwoSetLayout.letterCodes.contains(keyCode)
    }

    /// A key that types a character: not Tab, Return, Backspace, an arrow or a shortcut.
    /// shortcut: counts in every app, paused or not, so the share typed by Tab is a little low; count per watched field if that matters.
    static func types(_ type: CGEventType, _ event: CGEvent, _ flags: CGEventFlags) -> Bool {
        guard type == .keyDown, flags.intersection([.maskCommand, .maskControl]).isEmpty else { return false }
        var length = 0, units = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        return length > 0 && units[0] >= 0x20 && units[0] != 0x7F && !(0xF700...0xF8FF).contains(units[0])  // F7xx: arrows and function keys.
    }

    /// True swallows the event.
    func handle(_ type: CGEventType, _ event: CGEvent, post: (CGEvent) -> Void) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEvent else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode), flags = event.flags
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        var plan: (strokes: [TwoSetLayout.Stroke]?, text: String, added: Int, words: Int)?
        var suggestion = 0, drawing = 0
        var generation = 0
        var held = false
        var refused: Taught?
        var whole = false
        var through: (drawing: Int, text: String)?
        var length = 0, units = [UniChar](repeating: 0, count: 4)
        if Self.types(type, event, flags) { event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units) }
        let typed = String(utf16CodeUnits: units, count: length)
        let decision = state.withLock { s -> Decision in
            let armed = s.armed.flatMap { $0.pid == target ? $0 : nil }  // A key for another app is that app's.
            let decision = Self.decide(type: type, keyCode: keyCode, flags: flags, armed: armed != nil)
            if let only = s.only, armed != nil, target == getpid(), let key = decision.taught, key != only {
                refused = key
                return .pass
            }
            // A held Tab changes nothing, so it is no input: the draw already on its way still arms.
            // Not Shift-Tab, which goes back a field.
            if armed == nil, type == .keyDown, keyCode == Self.tabKey, flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
               let h = s.held, h.pid == target, Date() < h.until {
                held = true
                return decision
            }
            s.held = nil
            s.generation += 1
            generation = s.generation
            s.armed = nil
            if decision == .pass, let armed, Self.typesNext(armed, typed) { through = (armed.drawing, typed) }
            s.composing = Self.composes(after: s.composing, type: type, keyCode: keyCode, flags: flags)
            if case .accept(let all) = decision, let armed {
                plan = s.accept(armed, all: all)
                whole = all
                suggestion = armed.suggestion
                drawing = armed.drawing
            }
            if plan == nil { s.pending = nil }
            return decision
        }
        if let refused {
            onRefused?(refused)
            return true
        }
        if let plan {
            if let strokes = plan.strokes { Inserter.press(strokes, post: post) } else { Inserter.insert(plan.text, post: post) }
            onAccept?(plan.added, plan.strokes?.count ?? plan.added, plan.words, suggestion, plan.strokes == nil ? plan.text : nil, drawing)
            onTaught?(whole ? .shiftTab : .tab)
        }
        if decision == .reenable { reenable() }
        if case .dismiss(let swallow) = decision {
            onDismiss?()
            if swallow { onTaught?(.esc) }  // Swallowed: a ghost was up, so this Esc hid it.
        }
        if held { return true }
        if let through { onTypedThrough?(through.drawing, through.text, generation) }
        if plan == nil, Self.types(type, event, flags) { onTyped?() }
        onInput?(generation)
        return plan != nil || decision == .dismiss(swallow: true)
    }

    /// Takes the tap now if it can, and from then on keeps to the permission: up when it's given, down when it goes, whichever
    /// comes first. True if up already, and `onUp` tells the rest.
    func hold() -> Bool {
        keeper.sync {
            var token: Int32 = 0
            // Undocumented, posted for any app's permission. Were it to stop, a revoke would again go unnoticed until the next launch.
            notify_register_dispatch("com.apple.tcc.access.changed", &token, keeper) { [weak self] _ in self?.permissionChanged() }
            self.token = token
            tryStart()
            return up
        }
    }

    /// For good, unlike a permission change: no more news of it, no retry, no tap. A notice already queued runs before this.
    func close() {
        keeper.sync {
            if let token { notify_cancel(token) }
            token = nil
            attempt?.cancel()
            attempt = nil
        }
        stop()
    }

    /// On `keeper`. Down at once, as a tap left in the stream after a revoke can hold every key and click on the Mac. Up again only
    /// after the retry's delay, so that it asks a system that has settled.
    func permissionChanged() {
        stop()
        onDismiss?()
        retry()
    }

    /// The one loop. It ends on success, so nothing polls once the tap is up.
    private func tryStart() {
        let now = start()
        if now != up {
            up = now
            onUp?(now)
        }
        if !now { retry() }
    }

    private func retry() {
        attempt?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tryStart() }
        attempt = work
        keeper.asyncAfter(deadline: .now() + retryEvery, execute: work)
    }

    /// Any thread, this tap's own too. Nothing can be armed once it's down, and a draw on its way finds a moved generation.
    func stop() {
        let (port, loop) = state.withLock { s in
            let running = (s.port, s.loop)
            (s.port, s.loop, s.armed, s.pending, s.held) = (nil, nil, nil, nil, nil)
            s.generation += 1
            return running
        }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        // Invalidating doesn't wake a sleeping run loop. A thread not there yet adds a dead source and returns from its run at once.
        if let loop { CFRunLoopStop(loop) }
    }

    /// True once the tap is up, false while the system refuses it. What `AXIsProcessTrusted` says doesn't make it true: that can be
    /// a stale cache after a revoke, and tapCreate is what fails then.
    func start() -> Bool {
        if state.withLock({ $0.port != nil }) { return true }
        guard let port = createPort() else { return false }
        state.withLock { $0.port = port }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        let thread = Thread { [self] in
            guard claim(port, loop: CFRunLoopGetCurrent()) else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "halftype.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    /// A thread that starts late, after its tap was stopped and another started, would otherwise give the newer tap a loop `stop`
    /// can't wake.
    func claim(_ port: CFMachPort, loop: CFRunLoop) -> Bool {
        state.withLock { s in
            guard s.port === port else { return false }
            s.loop = loop
            return true
        }
    }

    func createPort() -> CFMachPort? {
        // An untrusted tapCreate is reported to raise the system's own dialog, here ahead of the window that explains it, and every
        // second. This only keeps that from happening: a yes can be stale, and tapCreate then refuses.
        guard AXIsProcessTrusted() else { return nil }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            // The proxy puts our events right here in the stream, ahead of any key already queued behind this one.
            let swallow = tap.handle(type, event) { if let pid = tap.pid { $0.postToPid(pid) } else { $0.tapPostEvent(proxy) } }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(0) { $0 | CGEventMask(1 << $1.rawValue) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        return pid.map { CGEvent.tapCreateForPid(pid: $0, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: me) }
            ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: me)
    }
}

/// Apple's Korean 2-set: which physical key types which jamo. The source has no Unicode layout data to ask, so
/// `scripts/e2e.sh --ime` checks this table against the live input method.
enum TwoSetLayout {
    static let source = "com.apple.inputmethod.Korean.2SetKorean"
    typealias Stroke = (code: CGKeyCode, shift: Bool)

    private static let plain: [Character: CGKeyCode] = [
        "ㅂ": 12, "ㅈ": 13, "ㄷ": 14, "ㄱ": 15, "ㅅ": 17, "ㅛ": 16, "ㅕ": 32, "ㅑ": 34, "ㅐ": 31, "ㅔ": 35,
        "ㅁ": 0, "ㄴ": 1, "ㅇ": 2, "ㄹ": 3, "ㅎ": 5, "ㅗ": 4, "ㅓ": 38, "ㅏ": 40, "ㅣ": 37,
        "ㅋ": 6, "ㅌ": 7, "ㅊ": 8, "ㅍ": 9, "ㅠ": 11, "ㅜ": 45, "ㅡ": 46,
    ]
    private static let shifted: [Character: Character] = ["ㅃ": "ㅂ", "ㅉ": "ㅈ", "ㄸ": "ㄷ", "ㄲ": "ㄱ", "ㅆ": "ㅅ", "ㅒ": "ㅐ", "ㅖ": "ㅔ"]

    /// What isn't jamo types itself. Not `\\`, `|`, `` ` `` or `~`, which the live input method types as something else.
    private static let symbols: [Character: Stroke] = {
        var out: [Character: Stroke] = [" ": (49, false)]
        let keys: [(CGKeyCode, Character, Character)] = [
            (18, "1", "!"), (19, "2", "@"), (20, "3", "#"), (21, "4", "$"), (23, "5", "%"), (22, "6", "^"), (26, "7", "&"), (28, "8", "*"), (25, "9", "("), (29, "0", ")"),
            (27, "-", "_"), (24, "=", "+"), (33, "[", "{"), (30, "]", "}"), (41, ";", ":"), (39, "'", "\""), (43, ",", "<"), (47, ".", ">"), (44, "/", "?"),
        ]
        for (code, unshifted, shift) in keys { (out[unshifted], out[shift]) = ((code, false), (code, true)) }
        return out
    }()

    static let letterCodes = Set(plain.values.map(Int64.init))

    /// Nil if any of these isn't a key on the layout.
    static func strokes(_ keys: String) -> [Stroke]? {
        var out: [Stroke] = []
        for key in keys {
            if let code = plain[key] { out.append((code, false)) }
            else if let base = shifted[key], let code = plain[base] { out.append((code, true)) }
            else if let symbol = symbols[key] { out.append(symbol) }
            else { return nil }
        }
        return out
    }

    /// Up to the first character these keys can't type, as text inserted during a composition is what the input method swallows.
    /// `전거 file` -> `전거`. Empty when no word is left.
    static func typable(_ text: String) -> String {
        guard let stop = text.firstIndex(where: { strokes(Hangul.keys(String($0))) == nil }) else { return text }
        let cut = Word.withoutTrailingSpaces(text[..<stop])
        return cut.contains(where: Word.isPart) ? String(cut) : ""
    }
}

enum Inserter {
    /// `keyboardSetUnicodeString` silently truncates long strings.
    static let chunkUnits = 16

    /// Splits at character boundaries, so a surrogate pair or a joined emoji is never cut.
    static func chunks(_ text: String) -> [[UniChar]] {
        var out: [[UniChar]] = [], current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if current.count + units.count > chunkUnits, !current.isEmpty {
                out.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// No clipboard. Flags are cleared because Shift is still held after Shift-Tab.
    static func insert(_ text: String, post: (CGEvent) -> Void) {
        for chunk in chunks(text) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: KeyTap.ownEvent)
                post(event)
            }
        }
    }

    /// Real key events with no text, for the input method to compose. Our flags, as Shift is still held after Shift-Tab.
    static func press(_ strokes: [TwoSetLayout.Stroke], post: (CGEvent) -> Void) {
        for stroke in strokes {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: stroke.code, keyDown: down) else { continue }
                event.flags = stroke.shift ? .maskShift : []
                event.setIntegerValueField(.eventSourceUserData, value: KeyTap.ownEvent)
                post(event)
            }
        }
    }
}
