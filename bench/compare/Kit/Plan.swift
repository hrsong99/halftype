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

    /// What one Tab may take of a ghost: up to the next space, or up to where the word's letters end, as Halftype stops
    /// before punctuation (`Word.firstEnd`). Both are tried; the field shows afterwards which one the app took.
    static func words(_ ghost: String) -> [String] {
        let spaced = firstWord(ghost), letters = String(ghost[..<Word.firstEnd(ghost)])
        return spaced == letters ? [spaced] : [spaced, letters]
    }

    /// The field a Tab taking `take` would leave, if it stays on the target. While a syllable composes, a ghost may follow
    /// it, replace it, or (Halftype's way) show only what comes after the syllable it will finish: 가 + 다면 for 간다면.
    /// That last reading takes the target's own syllable, which the screen can't tell apart; the field check after Tab can.
    func after(field: String, composing: String, take: String) -> (text: String, done: Int)? {
        guard !take.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let committed = String(field.dropLast(composing.count))
        var candidates = [field + take]
        if !composing.isEmpty {
            candidates.append(committed + take)
            if target.count > committed.count, target.hasPrefix(committed) {
                let own = String(target[target.index(target.startIndex, offsetBy: committed.count)])
                if Hangul.fits(composing: composing, suggestion: own) { candidates.append(committed + own + take) }
            }
        }
        // The last syllable may still be composing after a Tab that types keys through the input method.
        return candidates.compactMap { text in
            done(field: text, composing: text.last.map { Hangul.isHangul($0) ? String($0) : "" } ?? "").map { (text, $0) }
        }.max { $0.1 < $1.1 }
    }

    /// The oracle: press Tab only when what it takes is the true text and saves more than the Tab costs.
    /// Returns the text the field should hold after the Tab, to check the app and the OCR against.
    public func tab(field: String, composing: String = "", ghost: String, unit: TabUnit) -> String? {
        guard let now = done(field: field, composing: composing),
              let a = (unit == .all ? [ghost] : Plan.words(ghost)).compactMap({ after(field: field, composing: composing, take: $0) }).max(by: { $0.done < $1.done }),
              a.done - now >= 2 else { return nil }
        return a.text
    }

    /// The first shown word is the true next word, ending where the target's word ends (`lo` is not right for `lot`).
    public func firstWordRight(field: String, composing: String = "", ghost: String) -> Bool {
        Plan.words(ghost).contains { take in
            guard let a = after(field: field, composing: composing, take: take),
                  a.done > (done(field: field, composing: composing) ?? Int.max) else { return false }
            return a.done == keys.count || !Plan.continuesWord(keys[a.done])
        }
    }

    /// A key that carries a word on: a letter, a digit or a jamo.
    static func continuesWord(_ key: Character) -> Bool { key.isLetter || key.isNumber || key == "'" }
}
