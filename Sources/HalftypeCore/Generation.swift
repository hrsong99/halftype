import Synchronization

/// One decoded token as the engine reports it.
public struct Token: Equatable, Sendable {
    public var bytes: [UInt8]
    /// Log probability of this token, renormalised over all tokens whose bytes are compatible with what remains of
    /// the fragment. Once the fragment is consumed, the plain log probability. Computed from the full logits.
    public var logprob: Double
    public var special: Bool

    public init(bytes: [UInt8], logprob: Double = 0, special: Bool = false) {
        self.bytes = bytes
        self.logprob = logprob
        self.special = special
    }
}

extension [Token] {
    /// The tokens up to the first special one, without the fragment's bytes. A token wholly inside the fragment is
    /// gone; one crossing its end keeps its new bytes. Nil if a token contradicts the fragment.
    fileprivate func continuation(after fragment: String) -> [Token]? {
        var need = [UInt8](fragment.utf8)[...]
        var free: [Token] = []
        for token in self {
            if token.special { break }
            let forced = Swift.min(need.count, token.bytes.count)
            guard token.bytes.prefix(forced).elementsEqual(need.prefix(forced)) else { return nil }
            need = need.dropFirst(forced)
            if forced < token.bytes.count {
                free.append(Token(bytes: [UInt8](token.bytes.dropFirst(forced)), logprob: token.logprob))
            }
        }
        return free
    }
}

extension Collection<Token> {
    /// Log P of the text up to `end`: every token with a new byte before it, so one crossing `end` counts. Text running to
    /// its end may go on into bytes that don't decode yet, so there all tokens count.
    fileprivate func logprob(through end: String.Index, of text: String) -> Double {
        let bytes = end == text.endIndex ? Int.max : text[..<end].utf8.count
        var start = 0, sum = 0.0
        for token in self where start < bytes {
            sum += token.logprob
            start += token.bytes.count
        }
        return sum
    }
}

/// A token may end inside a character, so the last bytes may not decode yet. Nil if earlier bytes are invalid.
private func decode(_ tokens: [Token]) -> String? {
    let bytes = tokens.flatMap(\.bytes)
    for held in 0...Swift.min(3, bytes.count) {
        if let text = String(validating: bytes.dropLast(held), as: UTF8.self) { return text }
    }
    return nil
}

public enum Stop {
    /// Counts tokens with new bytes, so a long forced fragment cannot use up the budget.
    public static let maxTokens = 8
    /// Words after the first stay only while their running log probability holds above this. Without it four in five grey
    /// characters were wrong; with it, one in four. This alone keeps the measured savings, as Tab takes one word anyway. Fitted on English dev threads, see docs/measuring.md.
    public static let floor = -1.0

    /// The suggestion so far, and whether to stop generating. It ends before a newline, after the first terminal
    /// punctuation, at `maxTokens`, at a special token, or before the word that takes it below `floor`. The first word
    /// is the gate's to judge. Text with no word in it is no suggestion.
    public static func cut(_ tokens: [Token], fragment: String, floor: Double = Stop.floor) -> (text: String, done: Bool) {
        guard let free = tokens.continuation(after: fragment), let text = decode(Array(free.prefix(maxTokens))) else {
            return ("", true)
        }
        var done = tokens.contains(where: \.special) || free.count >= maxTokens
        var end = text.endIndex
        if let i = text.firstIndex(where: { $0.isNewline || endsClause($0) }) {
            end = text[i].isNewline ? i : text.index(after: i)
            done = true
        }
        // Past the first word, and where a word ends the tokens that make it are all in the sum.
        var wordEnd = Word.firstEnd(text[..<end])
        while wordEnd < end {
            let next = Word.firstEnd(text[wordEnd..<end])
            guard next > wordEnd, text[wordEnd..<next].contains(where: Word.isPart) else { break }
            if free.prefix(maxTokens).logprob(through: next, of: text) < floor {
                // A closing bracket or quote right after the last kept word stays if it holds the floor itself: `this)`, not `this`.
                var closed = wordEnd
                while closed < end, closes(text[closed]) { closed = text.index(after: closed) }
                end = closed > wordEnd && free.prefix(maxTokens).logprob(through: closed, of: text) >= floor ? closed : wordEnd
                done = true
                break
            }
            wordEnd = next
        }
        let cut = text[..<end]
        guard cut.contains(where: Word.isPart) else { return ("", done) }
        return (String(cut[...(cut.lastIndex { !$0.isWhitespace } ?? cut.startIndex)]), done)
    }

    /// `)`, `]`, `”`, `’`, and the straight `"`, which Unicode files as neither open nor close; right after a word it closes.
    private static func closes(_ c: Character) -> Bool {
        c == "\"" || [.closePunctuation, .finalPunctuation].contains(c.unicodeScalars.first?.properties.generalCategory)
    }

    /// Unicode's own Terminal_Punctuation covers Latin and CJK. `~` and `…` end casual Korean sentences and have no such property.
    private static func endsClause(_ c: Character) -> Bool {
        c == "~" || c == "…" || c.unicodeScalars.first?.properties.isTerminalPunctuation == true
    }
}

/// The window's Length and How Often: a floor for `Stop.cut` and a threshold for the gate. Read once per request.
/// The defaults are the fitted values; the others trade right grey text for more of it (docs/measuring.md).
public struct Tuning: Sendable, Equatable {
    public var floor: Double
    public var threshold: Double
    public init(floor: Double = Stop.floor, threshold: Double = Gate.threshold) {
        (self.floor, self.threshold) = (floor, threshold)
    }
    public static let current = Mutex(Tuning())
}

public enum Gate {
    /// Fitted on dev threads for 80% precision on English: -0.7, -0.7, -0.6 and -0.6 on Kanana 1.5 2.1B, Qwen 3.5 2B, Qwen 3.5 0.8B and Gemma 4 E2B.
    public static let threshold = -0.7

    /// A ghost that saves one or two keystrokes saves nothing, and showing it only interrupts. Judged on all of it, as Tab
    /// repeated or Shift-Tab takes the lot: `to the` shows although `to` alone is short. By the keys it stands in for, as a
    /// Hangul syllable is two or three, including any that finish the composing syllable. Against the first word alone, replay
    /// saved 18.2% of keystrokes, not 17.1%, for 0.6 more wrong ghosts per 100 requests: docs/measuring.md.
    public static func worthShowing(_ ghost: Ghost) -> Bool {
        let all = Accept.all(ghost)
        return all.keys.count + Hangul.keys(all.text).count >= 3
    }

    /// Log P(first word | it fits the fragment): the sum of `Token.logprob` from the token that first crosses the end
    /// of the fragment through the one that finishes the first word (`Word.firstEnd` on the new bytes). A token
    /// counts once if any new byte of it lies in the word, so one holding the end of this word and the start of the
    /// next counts and is the last. A token adding no new bytes, or starting after the word, does not count.
    /// Nil, so abstain, if there is no word yet or a token contradicts the fragment.
    public static func firstWord(_ tokens: [Token], fragment: String) -> Double? {
        guard let free = tokens.continuation(after: fragment), let text = decode(free),
              text.contains(where: Word.isPart) else { return nil }
        return free.logprob(through: Word.firstEnd(text), of: text)
    }
}
