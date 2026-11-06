import AppKit
import ItdaCore

/// Attribute reads. Every call may stall on a hung app for up to the messaging timeout, so all of this runs off the main thread.
enum AX {
    /// Short: the default of 6 s would hold the suggestion queue on a hung app. A failed read just means no ghost.
    static let timeout: Float = 0.25

    static func get(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success ? v : nil
    }
    static func get(_ e: AXUIElement, _ key: String, _ arg: CFTypeRef) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(e, key as CFString, arg, &v) == .success ? v : nil
    }
    static func element(_ v: CFTypeRef?) -> AXUIElement? {
        guard let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    static func rect(_ v: CFTypeRef?) -> CGRect? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        return AXValueGetValue(v as! AXValue, .cgRect, &r) ? r : nil
    }
    static func range(_ v: CFTypeRef?) -> CFRange? {
        guard let v, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        return AXValueGetValue(v as! AXValue, .cfRange, &r) ? r : nil
    }
    static func startMarker(_ range: CFTypeRef?) -> AXTextMarker? {
        guard let range, CFGetTypeID(range) == AXTextMarkerRangeGetTypeID() else { return nil }
        return AXTextMarkerRangeCopyStartMarker((range as! AXTextMarkerRange))
    }
    static func bounds(_ e: AXUIElement, location: Int, length: Int) -> CGRect? {
        var r = CFRange(location: location, length: length)
        return rect(get(e, "AXBoundsForRange", AXValueCreate(.cfRange, &r)!))
    }
}

/// What is true of a field for as long as it has focus.
struct FieldTraits {
    var fontSize: CGFloat
    var fontName: String?
    var color: CGColor?
    var lineLeft: CGFloat?
}

/// One read of the focused field: the text around the caret and where the caret is on screen, in AX coordinates.
struct Reading: Equatable {
    var field: Field
    var caret: CGRect?
    var frame: CGRect
    var previousCharacter: String { field.before.last.map(String.init) ?? "" }
}

enum Reader {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// Secure fields and anything that isn't text entry are never read further. A settable value tells a composer from
    /// a terminal or a read-only text area, both of which also report `AXTextArea`.
    static func isEditableText(_ e: AXUIElement) -> Bool {
        guard let role = AX.get(e, "AXRole") as? String, textRoles.contains(role),
              AX.get(e, "AXSubrole") as? String != "AXSecureTextField" else { return false }
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(e, "AXValue" as CFString, &settable) == .success && settable.boolValue
    }

    /// Nil when there is no text to continue from here: no value, or a non-empty selection.
    /// shortcut: reads the whole value on each change (1-3 ms in the fields tested); use AXStringForRange if huge documents lag.
    static func read(_ e: AXUIElement, koreanInput: Bool) -> Reading? {
        guard let value = AX.get(e, "AXValue") as? String, let selection = AX.range(AX.get(e, "AXSelectedTextRange")),
              let (before, after) = slice(value, selection) else { return nil }
        let frame = AX.rect(AX.get(e, "AXFrame")) ?? .zero
        return Reading(field: Field(before: before, after: after, koreanInput: koreanInput),
                       caret: caret(e, before: before, frame: frame), frame: frame)
    }

    /// By the selection, never the value's length: T3 reports a trailing newline, and length 1 when empty.
    static func slice(_ value: String, _ selection: CFRange) -> (before: String, after: String)? {
        let ns = value as NSString
        guard selection.length == 0, selection.location >= 0, selection.location <= ns.length else { return nil }
        return (ns.substring(to: selection.location), ns.substring(from: selection.location))
    }

    /// The marker's rect, else the previous character's right edge, each only if height > 0: failure is a height-0
    /// sentinel with a success code. Nil means no ghost, and a line box on an empty line counts through its origin.
    static func caretRect(marker: CGRect?, previous: CGRect?, frame: CGRect) -> CGRect? {
        var rect: CGRect?
        if let marker, marker.height > 0 {
            rect = CGRect(x: marker.minX, y: marker.minY, width: 0, height: marker.height)
        } else if let previous, previous.height > 0 {
            rect = CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
        }
        // A caret outside its own field is scrolled out of sight, or a stale answer.
        guard let rect, frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: rect.minX, y: rect.midY)) else { return nil }
        return rect
    }

    private static func caret(_ e: AXUIElement, before: String, frame: CGRect) -> CGRect? {
        let marker = AX.get(e, "AXSelectedTextMarkerRange").flatMap { AX.rect(AX.get(e, "AXBoundsForTextMarkerRange", $0)) }
        if let marker, marker.height > 0 { return caretRect(marker: marker, previous: nil, frame: frame) }
        // The previous character is one composed sequence, and a newline has no useful right edge.
        guard let last = before.last, !last.isNewline else { return nil }
        let length = last.utf16.count
        return caretRect(marker: nil, previous: AX.bounds(e, location: before.utf16.count - length, length: length), frame: frame)
    }

    /// Font, colour and left text edge, read once per focused field from the character before the caret.
    static func traits(_ e: AXUIElement, before: String) -> FieldTraits? {
        guard let attributes = previousCharacterAttributes(e, before: before),
              let font = attributes[NSAttributedString.Key("AXFont")] as? [String: Any],
              let size = font["AXFontSize"] as? CGFloat, size > 0 else { return nil }
        let color = attributes[NSAttributedString.Key("AXForegroundColor")].flatMap { value -> CGColor? in
            CFGetTypeID(value as CFTypeRef) == CGColor.typeID ? (value as! CGColor) : nil
        }
        return FieldTraits(fontSize: size, fontName: font["AXFontName"] as? String, color: color, lineLeft: lineLeft(e, before: before))
    }

    private static func previousCharacterAttributes(_ e: AXUIElement, before: String) -> [NSAttributedString.Key: Any]? {
        var text: NSAttributedString?
        if let start = AX.startMarker(AX.get(e, "AXSelectedTextMarkerRange")),
           let previous = AX.get(e, "AXPreviousTextMarkerForTextMarker", start),
           let pair = AX.get(e, "AXTextMarkerRangeForUnorderedTextMarkers", [previous, start] as CFArray) {
            text = AX.get(e, "AXAttributedStringForTextMarkerRange", pair) as? NSAttributedString
        }
        if text == nil, let last = before.last {
            var r = CFRange(location: before.utf16.count - last.utf16.count, length: last.utf16.count)
            text = AX.get(e, "AXAttributedStringForRange", AXValueCreate(.cfRange, &r)!) as? NSAttributedString
        }
        guard let text, text.length > 0 else { return nil }
        return text.attributes(at: 0, effectiveRange: nil)
    }

    /// The field's text edge, from its current line (markers) or its paragraph's first character (ranges). Nil: not wrapping.
    private static func lineLeft(_ e: AXUIElement, before: String) -> CGFloat? {
        if let start = AX.startMarker(AX.get(e, "AXSelectedTextMarkerRange")),
           let line = AX.get(e, "AXLeftLineTextMarkerRangeForTextMarker", start), let r = AX.rect(AX.get(e, "AXBoundsForTextMarkerRange", line)), r.height > 0 {
            return r.minX
        }
        let start = (before as NSString).range(of: "\n", options: .backwards).upperBound
        guard start < before.utf16.count, let r = AX.bounds(e, location: start, length: 1), r.height > 0 else { return nil }
        return r.minX
    }

    /// The text before the field in reading order, its tail up to the prompt's budget. This never includes the field's own
    /// text, and in a chat what comes right before the composer is the conversation, so no ancestor has to be chosen.
    static func context(of e: AXUIElement) -> String {
        // U+FFFC stands in for images and buttons, and is noise to a model.
        String((markerContext(e) ?? walkContext(e)).replacingOccurrences(of: "\u{FFFC}", with: "").suffix(Prompt.windowChars))
    }

    /// Chromium and WebKit: 1 ms for 10k characters in T3.
    private static func markerContext(_ e: AXUIElement) -> String? {
        guard let start = AX.get(e, "AXStartTextMarker"),
              let fieldStart = AX.startMarker(AX.get(e, "AXTextMarkerRangeForUIElement", e)),
              let range = AX.get(e, "AXTextMarkerRangeForUnorderedTextMarkers", [start, fieldStart] as CFArray) else { return nil }
        return AX.get(e, "AXStringForTextMarkerRange", range) as? String
    }

    /// Native apps: the same text from the window's tree. 1000 nodes reached all 11k characters in T3's tree.
    private static func walkContext(_ field: AXUIElement) -> String {
        guard let window = AX.element(AX.get(field, "AXWindow")) else { return "" }
        var out: [String] = [], budget = 1000
        let deadline = Date().addingTimeInterval(0.15)
        // True once the field is reached or the budget is gone, which ends the walk: only what comes before the field counts.
        func walk(_ e: AXUIElement) -> Bool {
            if CFEqual(e, field) { return true }
            budget -= 1
            if budget <= 0 || Date() > deadline { return true }
            guard let role = AX.get(e, "AXRole") as? String else { return false }
            if role == "AXStaticText" || role == "AXTextArea", AX.get(e, "AXSubrole") as? String != "AXSecureTextField",
               let text = AX.get(e, "AXValue") as? String, !text.isEmpty {
                out.append(text)
            }
            for child in AX.get(e, "AXChildren") as? [AXUIElement] ?? [] where walk(child) { return true }
            return false
        }
        _ = walk(window)
        return out.joined(separator: "\n")
    }
}

extension NSRange {
    fileprivate var upperBound: Int { location == NSNotFound ? 0 : location + length }
}
