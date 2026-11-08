import HalftypeCore

/// What one Tab takes of a ghost: Halftype, Cotypist, Cotabby and KeyType take a word by default, macOS the whole prediction.
public enum TabUnit: String, Codable, Sendable { case word, all }

/// One sentence to type, counted in keys: 2-set keystrokes for Hangul (값 is four), the character itself otherwise.
/// Every judgement is against the field's real text, so a misread ghost can only make the oracle press Tab less well, never miscount.
public struct Plan: Sendable {
    public let target: String
    public let keys: [Character]

    public init(_ target: String) {
        self.target = target.precomposedStringWithCanonicalMapping
        keys = Array(Hangul.keys(self.target))
    }

    /// Keys of the target the field already stands for, or nil once it has gone off the target. `composing` is the input
    /// method's live syllable at the field's end, which can still become the target's syllable (온 on the way to 오늘).
    public func done(field: String, composing: String = "") -> Int? {
        let field = field.precomposedStringWithCanonicalMapping
        guard composing.count <= field.count, target.hasPrefix(String(field.dropLast(composing.count))) else { return nil }
        let typed = Array(Hangul.keys(field))
        guard typed.count <= keys.count, keys.starts(with: typed) else { return nil }
        return typed.count
    }

    /// The next key to press, nil when the sentence is finished or the field is off the target.
    public func next(field: String, composing: String = "") -> Character? {
        guard let d = done(field: field, composing: composing), d < keys.count else { return nil }
        return keys[d]
    }

    /// The ghost's first word, with any space before it: ` world is` -> ` world`, `lo world` -> `lo`.
    public static func firstWord(_ ghost: String) -> String {
        let lead = ghost.prefix(while: { $0 == " " })
        return String(lead + ghost.dropFirst(lead.count).prefix(while: { $0 != " " }))
    }

    /// The field a Tab taking `take` would leave, if it stays on the target. While a syllable composes, a ghost may
    /// start after it or replace it (Halftype finishes the syllable): it replaces it when it can grow from it.
    func after(field: String, composing: String, take: String) -> (text: String, done: Int)? {
        guard !take.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let replaces = !composing.isEmpty && Hangul.fits(composing: composing, suggestion: String(take.prefix(composing.count)))
        let text = (replaces ? String(field.dropLast(composing.count)) : field) + take
        // The last syllable may still be composing after a Tab that types keys through the input method.
        guard let d = done(field: text, composing: text.last.map { Hangul.isHangul($0) ? String($0) : "" } ?? "") else { return nil }
        return (text, d)
    }

    /// The oracle: press Tab only when what it takes is the true text and saves more than the Tab costs.
    /// Returns the text the field should hold after the Tab, to check the app and the OCR against.
    public func tab(field: String, composing: String = "", ghost: String, unit: TabUnit) -> String? {
        guard let now = done(field: field, composing: composing),
              let a = after(field: field, composing: composing, take: unit == .all ? ghost : Plan.firstWord(ghost)),
              a.done - now >= 2 else { return nil }
        return a.text
    }

    /// The first shown word is the true next word, ending where the target's word ends (`lo` is not right for `lot`).
    public func firstWordRight(field: String, composing: String = "", ghost: String) -> Bool {
        guard let a = after(field: field, composing: composing, take: Plan.firstWord(ghost)),
              a.done > (done(field: field, composing: composing) ?? Int.max) else { return false }
        return a.done == keys.count || !Plan.continuesWord(keys[a.done])
    }

    /// A key that carries a word on: a letter, a digit or a jamo.
    static func continuesWord(_ key: Character) -> Bool { key.isLetter || key.isNumber || key == "'" }
}
