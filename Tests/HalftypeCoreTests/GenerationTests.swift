import Testing
@testable import HalftypeCore

private func token(_ text: String, _ logprob: Double = 0) -> Token { Token(bytes: Array(text.utf8), logprob: logprob) }

struct GateCase: CustomTestStringConvertible, Sendable {
    let name: String, fragment: String, tokens: [Token], expected: Double?
    var testDescription: String { name }
}

private let cases = [
    GateCase(name: "word finished inside the crossing token, next starts with a space", fragment: " yo",
             tokens: [token(" you", -0.5), token(" are", -3)], expected: -0.5),
    GateCase(name: "crossing token holds the end of one word and the start of the next", fragment: " yo",
             tokens: [token(" you ar", -0.5), token("e", -3), token(" we", -2)], expected: -0.5),
    GateCase(name: "fragment-exhausting token adds zero bytes and does not count", fragment: " you",
             tokens: [token(" you", -9), token(" are", -0.4), token(" we", -2)], expected: -0.4),
    GateCase(name: "several forced tokens before the crossing one", fragment: " underst",
             tokens: [token(" under", -8), token("st", -7), token("and", -0.3), token(" it", -2)], expected: -0.3),
    GateCase(name: "word continues over tokens", fragment: " mo",
             tokens: [token(" mor", -0.1), token("ning", -0.2), token(".", -4)], expected: -0.1 + -0.2),
    GateCase(name: "punctuation after the word does not count", fragment: "",
             tokens: [token(" done", -0.3), token(".", -5)], expected: -0.3),
    GateCase(name: "apostrophe stays in the word", fragment: " don",
             tokens: [token(" don", -9), token("'t", -0.2), token(" go", -3)], expected: -0.2),
    GateCase(name: "leading punctuation joins the word after it", fragment: "",
             tokens: [token(",", -0.2), token(" then", -0.3), token(" go", -3)], expected: -0.2 + -0.3),
    GateCase(name: "a token splits a Hangul character", fragment: " 오",
             tokens: [Token(bytes: Array(" 오".utf8) + [0xEB, 0x8A], logprob: -0.1), Token(bytes: [0x98], logprob: -0.2), token(" 맑", -3)], expected: -0.1 + -0.2),
    GateCase(name: "fragment ends inside a token that splits a character", fragment: "한",
             tokens: [Token(bytes: Array("한".utf8) + [0xEA], logprob: -0.1), Token(bytes: [0xB8, 0x80], logprob: -0.2), token(",", -5)], expected: -0.1 + -0.2),
    GateCase(name: "word not known yet: partial character only", fragment: "", tokens: [Token(bytes: [0xED, 0x95], logprob: -0.1)], expected: nil),
    GateCase(name: "fragment not finished", fragment: " yo", tokens: [token(" y", -1)], expected: nil),
    GateCase(name: "only the fragment", fragment: " yo", tokens: [token(" yo", -1)], expected: nil),
    GateCase(name: "token contradicts the fragment: abstain, never invent", fragment: " yo", tokens: [token(" xy", -0.1)], expected: nil),
    GateCase(name: "invalid bytes: abstain", fragment: "", tokens: [Token(bytes: [0xFF, 0x41, 0x42, 0x43, 0x44], logprob: -0.1)], expected: nil),
    GateCase(name: "nothing generated", fragment: "", tokens: [], expected: nil),
    GateCase(name: "stops at a special token", fragment: "",
             tokens: [token(" ok", -0.1), Token(bytes: [], logprob: -7, special: true), token("x", -9)], expected: -0.1),
]

@Test(arguments: cases)
func gate(c: GateCase) {
    #expect(Gate.firstWord(c.tokens, fragment: c.fragment) == c.expected)
}

/// The defect in the bench's feature: the following token moved the gate. Only that token changes here.
@Test(arguments: [-9.0, -0.1, 0.0])
func followingTokenDoesNotMoveTheGate(next: Double) {
    #expect(Gate.firstWord([token(" xy", -0.1), token(" next", next)], fragment: " x") == -0.1)
    #expect(Gate.firstWord([token(" x", -6), token(" next", next), token(" more", next)], fragment: " x") == next)
    #expect(Gate.firstWord([token(" x", -6), token(" next", -0.5), token(" more", next)], fragment: " x") == -0.5)
    #expect(Gate.firstWord([token("한", -0.1), token("글", -0.2), token(" 다음", next)], fragment: "") == -0.1 + -0.2)
}

struct StopCase: CustomTestStringConvertible, Sendable {
    let name: String, fragment: String, tokens: [Token], text: String, done: Bool
    var testDescription: String { name }
}

private let eight = (1...8).map { token(" w\($0)") }

private let stops = [
    StopCase(name: "still going", fragment: "", tokens: [token(" and"), token(" then")], text: " and then", done: false),
    StopCase(name: "newline, not kept", fragment: "", tokens: [token(" and\nmore")], text: " and", done: true),
    StopCase(name: "newline first is no suggestion", fragment: "", tokens: [token("\nmore")], text: "", done: true),
    StopCase(name: "full stop kept", fragment: "", tokens: [token(" it."), token(" Then")], text: " it.", done: true),
    StopCase(name: "comma, as in the bench", fragment: "", tokens: [token("ly, and")], text: "ly,", done: true),
    StopCase(name: "question mark", fragment: "", tokens: [token("s?")], text: "s?", done: true),
    StopCase(name: "CJK full stop", fragment: "", tokens: [token("今天好。明")], text: "今天好。", done: true),
    StopCase(name: "fullwidth question mark", fragment: "", tokens: [token("かな？次")], text: "かな？", done: true),
    StopCase(name: "ideographic comma", fragment: "", tokens: [token("赤、青")], text: "赤、", done: true),
    StopCase(name: "Korean sentence end", fragment: "", tokens: [token("좋아요. 다음")], text: "좋아요.", done: true),
    StopCase(name: "Korean question", fragment: "", tokens: [token("갈까요? 네")], text: "갈까요?", done: true),
    StopCase(name: "Korean casual tilde", fragment: "", tokens: [token("고마워요~ 또")], text: "고마워요~", done: true),
    StopCase(name: "ellipsis", fragment: "", tokens: [token("글쎄요… 음")], text: "글쎄요…", done: true),
    StopCase(name: "punctuation alone is no suggestion", fragment: "", tokens: [token("?")], text: "", done: true),
    StopCase(name: "eight tokens", fragment: "", tokens: eight, text: " w1 w2 w3 w4 w5 w6 w7 w8", done: true),
    StopCase(name: "never past eight", fragment: "", tokens: eight + [token(" w9")], text: " w1 w2 w3 w4 w5 w6 w7 w8", done: true),
    StopCase(name: "forced tokens do not count", fragment: " 가나다라마",
             tokens: [" 가", "나", "다", "라", "마"].map { token($0) } + (1...7).map { token(" w\($0)") },
             text: " w1 w2 w3 w4 w5 w6 w7", done: false),
    StopCase(name: "crossing token counts once", fragment: " yo", tokens: [token(" you")] + (1...7).map { token(" w\($0)") },
             text: "u w1 w2 w3 w4 w5 w6 w7", done: true),
    StopCase(name: "fragment's newline does not stop", fragment: "\nba", tokens: [token("\nbas"), token("ic")], text: "sic", done: false),
    StopCase(name: "special token stops without a string list", fragment: "",
             tokens: [token(" ok"), Token(bytes: Array("<think>".utf8), special: true), token("hidden")], text: " ok", done: true),
    StopCase(name: "special first", fragment: "", tokens: [Token(bytes: [], special: true)], text: "", done: true),
    StopCase(name: "split Hangul is held until whole", fragment: "",
             tokens: [token(" 좋"), Token(bytes: [0xEC, 0x95])], text: " 좋", done: false),
    StopCase(name: "trailing space dropped", fragment: "", tokens: [token(" so ")], text: " so", done: false),
    StopCase(name: "contradicts the fragment", fragment: " yo", tokens: [token(" xy")], text: "", done: true),
]

@Test(arguments: stops)
func stop(c: StopCase) {
    let cut = Stop.cut(c.tokens, fragment: c.fragment)
    #expect(cut.text == c.text)
    #expect(cut.done == c.done)
}


@Test func aSuggestionStopsBeforeTheWordItIsUnsureOf() {
    let sure = [token(" take", -0.2), token(" a", -0.1), token(" look", -0.3)]
    #expect(Stop.cut(sure, fragment: "").text == " take a look")
    let cut = Stop.cut(sure + [token(" around", -0.5), token(" here", -0.1)], fragment: "")
    #expect(cut.text == " take a look")
    #expect(cut.done)
}

@Test func aClosingBracketStaysWithItsWordWhenTheNextWordIsCut() {
    let tokens = [token(" this", -0.2), token(")", -0.1), token(" and", -2)]
    #expect(Stop.cut(tokens, fragment: "").text == " this)")
    #expect(Stop.cut([token(" \"this", -0.2), token("\"", -0.1), token(" and", -2)], fragment: "").text == " \"this\"")
    #expect(Stop.cut([token(" this", -0.2), token(")", -2), token(" and", -0.1)], fragment: "").text == " this")
    #expect(Stop.cut([token(" this", -0.2), token("-", -0.1), token("and", -2)], fragment: "").text == " this")
}

@Test func aLowerFloorKeepsLessLikelyWords() {
    let tokens = [token(" take", -0.2), token(" a", -0.1), token(" look", -0.3), token(" around", -0.5), token(" here", -0.1)]
    #expect(Stop.cut(tokens, fragment: "", floor: -2).text == " take a look around here")
    #expect(Stop.cut(tokens, fragment: "", floor: -1.15).text == " take a look around")
    #expect(Tuning() == Tuning(floor: Stop.floor, threshold: Gate.threshold))
}

@Test func theFirstWordIsTheGatesToJudge() {
    #expect(Stop.cut([token(" maybe", -3)], fragment: "").text == " maybe")
    #expect(Stop.cut([token(" maybe", -3), token(" so", -0.1)], fragment: "").text == " maybe")
}

@Test func theForcedFragmentCostsNothing() {
    #expect(Stop.cut([Token(bytes: Array(" lo".utf8), logprob: -9), token("ok", -0.1), token(" at", -0.2)], fragment: " lo").text == "ok at")
}

@Test func aSplitCharacterIsHeldUntilItDecodes() {
    let bytes = Array(" 시작".utf8)
    let tokens = [Token(bytes: Array(bytes.prefix(2)), logprob: -0.1), Token(bytes: Array(bytes.dropFirst(2)), logprob: -0.1), token("합니다", -0.2)]
    #expect(Stop.cut(tokens, fragment: "").text == " 시작합니다")
}

@Test func heldBytesCountAgainstTheWordTheyWillFinish() {
    let start = Array("각".utf8)
    let tokens = [token(" first", -0.2), token(" 가", -0.7), Token(bytes: Array(start.prefix(1)), logprob: -0.3)]
    #expect(Stop.cut(tokens, fragment: "").text == " first")
}

@Test(arguments: [(Ghost(remainder: " a"), true), (Ghost(remainder: "g"), false), (Ghost(remainder: "ng"), true), (Ghost(remainder: " an"), true), (Ghost(remainder: " the rest"), true),
                  (Ghost(remainder: "ing"), true), (Ghost(remainder: "음"), true), (Ghost(remainder: " 네"), true), (Ghost(remainder: "네"), true), (Ghost(remainder: " a lot"), true),
                  (Ghost(remainder: "o the"), true), (Ghost(remainder: "g a"), true), (Ghost(remainder: "s."), true), (Ghost(remainder: "."), false),
                  (Ghost(keys: "s", composing: "한", remainder: " a"), true), (Ghost(keys: "s", composing: "한", remainder: "g"), true), (Ghost(remainder: "e"), false)])
func onlyAGhostThatSavesAKeyIsWorthShowing(ghost: Ghost, worth: Bool) {
    #expect(Gate.worthShowing(ghost) == worth)
}
