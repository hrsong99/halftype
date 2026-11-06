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

    /// The suggestion so far, and whether to stop generating. It ends before a newline, after the first terminal
    /// punctuation, at `maxTokens`, or at a special token. Text with no word in it is no suggestion.
    public static func cut(_ tokens: [Token], fragment: String) -> (text: String, done: Bool) {
        guard let free = tokens.continuation(after: fragment), let text = decode(Array(free.prefix(maxTokens))) else {
            return ("", true)
        }
        var done = tokens.contains(where: \.special) || free.count >= maxTokens
        var end = text.endIndex
        if let i = text.firstIndex(where: { $0.isNewline || endsClause($0) }) {
            end = text[i].isNewline ? i : text.index(after: i)
            done = true
        }
        let cut = text[..<end]
        guard cut.contains(where: Word.isPart) else { return ("", done) }
        return (String(cut[...(cut.lastIndex { !$0.isWhitespace } ?? cut.startIndex)]), done)
    }

    /// Unicode's own Terminal_Punctuation covers Latin and CJK. `~` and `…` end casual Korean sentences and have no such property.
    private static func endsClause(_ c: Character) -> Bool {
        c == "~" || c == "…" || c.unicodeScalars.first?.properties.isTerminalPunctuation == true
    }
}

public enum Gate {
    /// Placeholder, to be re-fitted: −1.2 is from the replay bench, whose feature read past the first word and made
    /// up probability mass from truncated candidate lists. No correctly computed value exists yet.
    public static let threshold = -1.2

    /// Log P(first word | it fits the fragment): the sum of `Token.logprob` from the token that first crosses the end
    /// of the fragment through the one that finishes the first word (`Word.firstEnd` on the new bytes). A token
    /// counts once if any new byte of it lies in the word, so one holding the end of this word and the start of the
    /// next counts and is the last. A token adding no new bytes, or starting after the word, does not count.
    /// Nil, so abstain, if there is no word yet or a token contradicts the fragment.
    public static func firstWord(_ tokens: [Token], fragment: String) -> Double? {
        guard let free = tokens.continuation(after: fragment), let text = decode(free),
              text.contains(where: Word.isPart) else { return nil }
        let end = Word.firstEnd(text)
        // A word running to the end may go on into bytes that don't decode yet, so all tokens count.
        let wordBytes = end == text.endIndex ? Int.max : text[..<end].utf8.count
        var start = 0, sum = 0.0
        for token in free where start < wordBytes {
            sum += token.logprob
            start += token.bytes.count
        }
        return sum
    }
}
