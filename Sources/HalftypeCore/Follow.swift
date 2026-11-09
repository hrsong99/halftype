/// What to show now. `remainder` is drawn after the caret and inserted there. `composing` is what the possibly composing
/// character becomes under this suggestion, and `keys` the 2-set jamo still to type for that: 하 -> ㄴ for 한, 달 -> ㅏ for 다라.
public struct Ghost: Equatable, Sendable {
    public var keys: String
    public var composing: String
    public var remainder: String

    public init(keys: String = "", composing: String = "", remainder: String) {
        self.keys = keys
        self.composing = composing
        self.remainder = remainder
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
        guard committed.count >= base.count - typed.count, full.hasPrefix(committed) else { return nil }
        let rest = String(full.dropFirst(committed.count))
        guard Hangul.fits(composing: typed, suggestion: rest) else { return nil }
        let reach = Hangul.reach(composing: typed, suggestion: rest)
        let composing = String(rest.prefix(reach)), remainder = String(rest.dropFirst(reach))
        guard !remainder.isEmpty else { return nil }
        return Ghost(keys: String(Hangul.keys(composing).dropFirst(Hangul.keys(typed).count)), composing: composing, remainder: remainder)
    }
}

/// The input method finishes the syllable from `keys`, and `text` follows. Never delete and retype.
public enum Accept {
    /// The words a Tab types any of, for Stats: with the composing syllable when it changes it (`하` to `한 다음` is two), not when the
    /// user had already typed it right (`달`, then ` 이것`, is one).
    public static func words(_ ghost: Ghost, _ taken: (keys: String, text: String)) -> Int {
        Tally.words(in: (taken.keys.isEmpty ? "" : ghost.composing) + taken.text)
    }
    public static func nextWord(_ ghost: Ghost) -> (keys: String, text: String) {
        (ghost.keys, String(ghost.remainder[..<Word.firstEnd(ghost.remainder)]))
    }

    public static func all(_ ghost: Ghost) -> (keys: String, text: String) { (ghost.keys, ghost.remainder) }
}
