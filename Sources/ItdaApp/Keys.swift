import AppKit
import Synchronization

/// The active keyDown tap. It runs on its own thread, so nothing on the main thread can delay typing. Its callback only
/// reads one flag and hands off: no AX, no model.
final class KeyTap: @unchecked Sendable {
    enum Decision: Equatable { case pass, passAndDismiss, accept(all: Bool), reenable }

    static let tabKey: Int64 = 48, escapeKey: Int64 = 53
    /// Marks our own events, so a Tab handed back to the app passes this tap.
    static let ownEvent: Int64 = 0x49544441

    /// True exactly while a ghost is on screen.
    let armed = Atomic<Bool>(false)
    /// The user's last act was a letter key, so under Korean input a syllable may be open. A click, an arrow, Return or a
    /// shortcut commits it. Getting this wrong towards false only costs a ghost, as inserting text commits in order anyway.
    let composing = Atomic<Bool>(false)
    var onAccept: (@Sendable (_ all: Bool) -> Void)?
    var onDismiss: (@Sendable () -> Void)?
    private var port: CFMachPort?

    private let acceptKey: Int64
    /// Another key only for testing this tap on a key that does nothing if it leaks.
    init(acceptKey: Int64 = tabKey) { self.acceptKey = acceptKey }

    static func decide(type: CGEventType, keyCode: Int64, flags: CGEventFlags, own: Bool, armed: Bool, acceptKey: Int64 = tabKey) -> Decision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .reenable }
        guard type == .keyDown, !own, armed else { return .pass }
        if keyCode == escapeKey { return .passAndDismiss }  // Without it a ghost keeps Tab from moving between fields.
        guard keyCode == acceptKey, flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { return .pass }
        return .accept(all: flags.contains(.maskShift))
    }

    static func composes(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        type == .keyDown && TwoSetLayout.letterCodes.contains(keyCode) && flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
    }

    /// Needs Accessibility, so call only once trusted. Nil if the system refused.
    func start() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let own = event.getIntegerValueField(.eventSourceUserData) == KeyTap.ownEvent
            let decision = KeyTap.decide(type: type, keyCode: keyCode, flags: event.flags, own: own,
                                         armed: tap.armed.load(ordering: .relaxed), acceptKey: tap.acceptKey)
            switch decision {
            case .pass, .passAndDismiss:
                if decision == .passAndDismiss { tap.onDismiss?() }
                if !own { tap.composing.store(KeyTap.composes(type: type, keyCode: keyCode, flags: event.flags), ordering: .relaxed) }
                return Unmanaged.passUnretained(event)
            case .accept(let all): tap.onAccept?(all); return nil
            case .reenable:
                tap.composing.store(false, ordering: .relaxed)  // Keys went by unseen.
                if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
        }
        let events: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: events.reduce(0) { $0 | CGEventMask(1 << $1.rawValue) }, callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
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

    /// A Tab swallowed for a ghost that turned out to be stale goes on to the app after all.
    static func repostTab(shift: Bool, post: (CGEvent) -> Void) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(tabKey), keyDown: true) else { return }
        event.flags = shift ? .maskShift : []
        event.setIntegerValueField(.eventSourceUserData, value: ownEvent)
        post(event)
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

    static let letterCodes = Set(plain.values.map(Int64.init))
    static let jamo = Array(plain.keys) + Array(shifted.keys)

    /// Nil if any of these isn't a key on the layout.
    static func strokes(_ keys: String) -> [Stroke]? {
        var out: [Stroke] = []
        for key in keys {
            if let code = plain[key] { out.append((code, false)) }
            else if let base = shifted[key], let code = plain[base] { out.append((code, true)) }
            else { return nil }
        }
        return out
    }
}

enum Inserter {
    /// F18 ends a live composition with no text and no caret move. Without it the input method swallows a text event while there is
    /// marked text, or lets it replace the syllable (`scripts/e2e.sh --ime`). Modifiers and JIS keys don't commit; Esc and arrows do, with
    /// effects; F20 leaves a U+0010 in a text view; F14 and F15 can be brightness; F19 is a favourite for remapping.
    static let commitKey: TwoSetLayout.Stroke = (79, false)
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
