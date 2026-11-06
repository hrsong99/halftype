/// What to show now. `remainder` is drawn after the caret and inserted there. `composing` is what the possibly composing
/// character becomes under this suggestion. `needsReplace` says that differs from what is in the field: 하 has to
/// become 한, or 달 다라, so inserting `remainder` alone would be wrong.
public struct Ghost: Equatable, Sendable {
    public var composing: String
    public var remainder: String
    public var needsReplace: Bool

    public init(composing: String = "", remainder: String, needsReplace: Bool = false) {
        self.composing = composing
        self.remainder = remainder
        self.needsReplace = needsReplace
    }
}

public enum Follow {
    /// Compares field text, not key events, so typing through, backspacing, a smart quote or a suggestion that
    /// arrives late all take this one path. `anchor` is `Field.committed` when the request was made; `suggestion` is
    /// `Stop.cut`'s text. Nil means drop: the field left the suggestion, or nothing is left to show.
    public static func check(anchor: String, suggestion: String, field: Field) -> Ghost? {
        // The prompt never ends in a space, so a suggestion carries its own: `do ` + ` you` is `do you`.
        let base = Word.withoutTrailingSpaces(anchor)
        let full = base + suggestion
        let committed = field.committed, typed = field.composing
        // The last character is out of the comparison while it may be composing, and only `fits` judges it.
        guard !field.secure, committed.count >= base.count - typed.count, full.hasPrefix(committed) else { return nil }
        let rest = String(full.dropFirst(committed.count))
        guard Hangul.fits(composing: typed, suggestion: rest) else { return nil }
        let reach = Hangul.reach(composing: typed, suggestion: rest)
        let composing = String(rest.prefix(reach)), remainder = String(rest.dropFirst(reach))
        return remainder.isEmpty ? nil : Ghost(composing: composing, remainder: remainder, needsReplace: composing != typed)
    }
}

/// Nil while `needsReplace`: how to replace a character that may be composing is not decided, and inserting would be wrong.
public enum Accept {
    /// What is left equals what `Follow` reports once `insert` is in the field.
    public static func nextWord(_ ghost: Ghost) -> (insert: String, remainder: String)? {
        guard !ghost.needsReplace else { return nil }
        let end = Word.firstEnd(ghost.remainder)
        return (String(ghost.remainder[..<end]), String(ghost.remainder[end...]))
    }

    public static func all(_ ghost: Ghost) -> (insert: String, remainder: String)? {
        ghost.needsReplace ? nil : (ghost.remainder, "")
    }
}
