import AppKit
import ItdaCore
import Synchronization

/// The active tap, on its own thread. An accept is one transaction here: no AX, no queue, so nothing can come between the Tab
/// and its text, and any other key or click disarms first, which leaves Tab the app's. Input means any event not marked as ours:
/// another program's synthetic key counts too, which errs towards disarming.
final class KeyTap: @unchecked Sendable {
    enum Decision: Equatable { case pass, passAndDismiss, accept(all: Bool), reenable }

    /// What Tab inserts, and where. Set only by a drawn ghost.
    struct Armed {
        var pid: pid_t
        var ghost: Ghost
        /// 2-set presses real keys; every other source inserts text.
        var typesKeys: Bool
        var committed: String
        var before: String
    }

    struct State {
        /// Moves on every input event, and on what moves a field under a snapshot: focus, window, scroll. A snapshot keeps the value from
        /// before its read, through every later step, and may arm only under that value. A hide alone doesn't move it: see `hideOnMain`.
        var generation = 0
        var armed: Armed?
        /// A syllable may be open, for hosts that don't report marked text: the last physical key was a letter, or a Backspace with one
        /// open. A click, an arrow, Return or a shortcut commits it. Wrong towards true would type a stray jamo after a committed syllable.
        var composing = false
        /// What the field will hold once our last accept lands; Tab-Tab can beat the host's update. Any other input ends it, as the
        /// field then holds something else: Tab, Backspace, and `hello ther` would otherwise read as on its way to `hello there`.
        var pending: (from: String, to: String)?

        mutating func accept(_ armed: Armed, all: Bool) -> (strokes: [TwoSetLayout.Stroke]?, text: String)? {
            let next = all ? Accept.all(armed.ghost) : Accept.nextWord(armed.ghost)
            let strokes = armed.typesKeys ? TwoSetLayout.strokes(next.keys + Hangul.keys(next.text)) : nil
            if armed.typesKeys && strokes == nil { return nil }
            let to = armed.committed + armed.ghost.composing + next.text
            let rest = String(armed.ghost.remainder.dropFirst(next.text.count))
            pending = (pending?.from ?? armed.before, to)
            self.armed = rest.isEmpty ? nil : Armed(pid: armed.pid, ghost: Ghost(remainder: rest), typesKeys: armed.typesKeys, committed: to, before: to)
            composing = strokes?.last.map { TwoSetLayout.letterCodes.contains(Int64($0.code)) } ?? false  // As if the user typed it.
            return (strokes, next.text)
        }
    }

    static let tabKey: Int64 = 48, escapeKey: Int64 = 53, backspaceKey: Int64 = 51
    /// Marks our own events, which are no input. They don't come back to a session tap (`tapPostEvent`), and any that do pass untouched.
    static let ownEvent: Int64 = 0x49544441

    let state = Mutex(State())
    /// Off this thread at once. Given the generation this input moved to.
    var onInput: (@Sendable (Int) -> Void)?
    var onDismiss: (@Sendable () -> Void)?
    private var port: CFMachPort?
    /// Private-window checks tap one process. A proxy doesn't reach an app from such a tap, so they post to it instead.
    private let pid: pid_t?
    init(pid: pid_t? = nil) { self.pid = pid }

    var generation: Int { state.withLock { $0.generation } }

    func invalidate() {
        state.withLock {
            $0.generation += 1
            $0.armed = nil
            $0.pending = nil
        }
    }

    func disarm() { state.withLock { $0.armed = nil } }

    /// False if anything has happened since `generation`.
    func arm(_ armed: Armed, generation: Int) -> Bool {
        state.withLock {
            guard $0.generation == generation else { return false }
            $0.armed = armed
            return true
        }
    }

    static func decide(type: CGEventType, keyCode: Int64, flags: CGEventFlags, armed: Bool) -> Decision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .reenable }
        guard type == .keyDown else { return .pass }
        if keyCode == escapeKey { return .passAndDismiss }  // Without it a ghost keeps Tab from moving between fields.
        guard armed, keyCode == tabKey, flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return .pass }
        return .accept(all: flags.contains(.maskShift))
    }

    static func composes(after was: Bool, type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .keyDown, flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return false }
        return keyCode == backspaceKey ? was : TwoSetLayout.letterCodes.contains(keyCode)
    }

    /// True swallows the event.
    func handle(_ type: CGEventType, _ event: CGEvent, post: (CGEvent) -> Void) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEvent else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode), flags = event.flags
        let target = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        var plan: (strokes: [TwoSetLayout.Stroke]?, text: String)?
        var generation = 0
        let decision = state.withLock { s -> Decision in
            let armed = s.armed
            let decision = Self.decide(type: type, keyCode: keyCode, flags: flags, armed: armed != nil)
            s.generation += 1
            generation = s.generation
            s.armed = nil
            s.composing = Self.composes(after: s.composing, type: type, keyCode: keyCode, flags: flags)
            if case .accept(let all) = decision, let armed, armed.pid == target { plan = s.accept(armed, all: all) }
            if plan == nil { s.pending = nil }
            return decision
        }
        if let plan {
            if let strokes = plan.strokes { Inserter.press(strokes, post: post) } else { Inserter.insert(plan.text, post: post) }
        }
        if decision == .reenable, let port { CGEvent.tapEnable(tap: port, enable: true) }
        if decision == .passAndDismiss { onDismiss?() }
        onInput?(generation)
        return plan != nil
    }

    /// Needs Accessibility, so call only once trusted. Nil if the system refused.
    func start() -> Bool {
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            // The proxy puts our events right here in the stream, ahead of any key already queued behind this one.
            let swallow = tap.handle(type, event) { if let pid = tap.pid { $0.postToPid(pid) } else { $0.tapPostEvent(proxy) } }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = events.reduce(0) { $0 | CGEventMask(1 << $1.rawValue) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        let created = pid.map { CGEvent.tapCreateForPid(pid: $0, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: me) }
            ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: me)
        guard let port = created else { return false }
        self.port = port
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.name = "itda.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
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
