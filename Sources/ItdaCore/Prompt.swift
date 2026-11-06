/// One snapshot of the focused text field. Apps may report no marked text, leaving a composing character in `before`
/// looking committed, so under Korean input a Hangul last character is treated as possibly composing. A wrongly
/// suspected committed syllable costs nothing: it fits the suggestion too.
public struct Field: Equatable, Sendable {
    public var before: String
    public var after: String
    public var secure: Bool
    /// Whether the active input source is Korean.
    public var koreanInput: Bool

    public init(before: String, after: String = "", secure: Bool = false, koreanInput: Bool = false) {
        self.before = before
        self.after = after
        self.secure = secure
        self.koreanInput = koreanInput
    }

    /// The character that may still change, or empty.
    public var composing: String {
        guard koreanInput, let last = before.last, Hangul.isHangul(last) else { return "" }
        return String(last)
    }

    /// `before` without it. This is the anchor to keep with a request: 달 becoming 다라 changes the character before
    /// the caret, but not this text's start.
    public var committed: String { String(before.dropLast(composing.count)) }
}

/// The one word-boundary rule, for prompts, the gate, stopping and accepting, in Hangul and Latin alike.
package enum Word {
    package static func isPart(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || "'’_".contains(c)
    }

    /// Just past the first word: anything leading it, then its run of word characters.
    /// `u are` -> `u`, ` are we` -> ` are`, `?` -> `?`.
    package static func firstEnd<S: StringProtocol>(_ text: S) -> S.Index {
        guard let start = text.firstIndex(where: isPart) else { return text.endIndex }
        return text[start...].firstIndex { !isPart($0) } ?? text.endIndex
    }

    package static func withoutTrailingSpaces<S: StringProtocol>(_ text: S) -> S.SubSequence {
        text[..<(text.lastIndex { $0 != " " }.map(text.index(after:)) ?? text.startIndex)]
    }
}

/// What the model sees. `prefix` ends at the last whole word with no trailing space. `fragment` is the half-typed
/// word, with the whitespace before it, to be forced back by `Grammar` so the model picks its natural token.
public struct Prompt: Equatable, Sendable {
    public static let windowChars = 1200
    /// The start moves only in jumps of this size, so the head, and the model's cache of it, survives each key.
    public static let stepChars = 512

    public let prefix: String
    public let fragment: String
    /// What the output must next agree with in 2-set keystrokes, not bytes: spaces the prompt dropped, then the withheld syllable.
    public var composing = ""

    /// A composing syllable is withheld, because `하` on its way to `한` cannot be continued into `한`.
    public static func make(context: String, field: Field) -> Prompt {
        var prompt = make(context: context, before: field.committed)
        if !field.composing.isEmpty {
            let spaces = field.committed.count - Word.withoutTrailingSpaces(field.committed).count
            prompt.composing = String(repeating: " ", count: prompt.fragment.isEmpty ? spaces : 0) + field.composing
        }
        return prompt
    }

    /// With nothing else to send, the half-typed word is the prompt. Empty `prefix`: don't ask.
    public static func make(context: String, before: String) -> Prompt {
        let wordStart = before.lastIndex { !Word.isPart($0) }.map(before.index(after:)) ?? before.startIndex
        let beforeWord = before[..<wordStart]
        var head = beforeWord[..<(beforeWord.lastIndex { !$0.isWhitespace }.map(before.index(after:)) ?? before.startIndex)]
        var fragment = String(before[head.endIndex...])
        if wordStart == before.endIndex || (head.isEmpty && context.isEmpty) {
            head = Word.withoutTrailingSpaces(before)
            fragment = ""
        }
        let text = context.isEmpty ? String(head) : context + "\n\n" + head
        let over = text.count - windowChars
        return Prompt(prefix: over > 0 ? String(text.dropFirst((over / stepChars + 1) * stepChars)) : text, fragment: fragment)
    }
}

public enum Grammar {
    /// The fragment, then anything. The tail allows line breaks, so the model can still choose to stop there.
    public static func forcing(fragment: String) -> String {
        var literal = String.UnicodeScalarView()
        for scalar in fragment.unicodeScalars {
            switch scalar {
            case "\"", "\\": literal.append("\\"); literal.append(scalar)
            case "\n": literal.append(contentsOf: #"\n"#.unicodeScalars)
            case "\r": literal.append(contentsOf: #"\r"#.unicodeScalars)
            case "\t": literal.append(contentsOf: #"\t"#.unicodeScalars)
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                let hex = String(scalar.value, radix: 16)
                literal.append(contentsOf: (#"\x"# + (hex.count == 1 ? "0" : "") + hex).unicodeScalars)
            default: literal.append(scalar)
            }
        }
        return #"root ::= "\#(String(literal))" [^\x01]*"#
    }
}
