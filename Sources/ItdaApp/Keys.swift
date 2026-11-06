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

    /// Needs Accessibility, so call only once trusted. Nil if the system refused.
    func start() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            let decision = KeyTap.decide(type: type, keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                                         own: event.getIntegerValueField(.eventSourceUserData) == KeyTap.ownEvent,
                                         armed: tap.armed.load(ordering: .relaxed), acceptKey: tap.acceptKey)
            switch decision {
            case .pass: return Unmanaged.passUnretained(event)
            case .passAndDismiss: tap.onDismiss?(); return Unmanaged.passUnretained(event)
            case .accept(let all): tap.onAccept?(all); return nil
            case .reenable:
                if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: callback,
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

enum Inserter {
    /// `keyboardSetUnicodeString` silently truncates long strings. Under Korean input, tested in a native field: a syllable still
    /// composing commits first and this text follows in order, with no pause (`scripts/e2e.sh --ime`). So no special case here.
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
        let source = CGEventSource(stateID: .privateState)
        for chunk in chunks(text) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: KeyTap.ownEvent)
                post(event)
            }
        }
    }
}
