import Testing
@testable import HalftypeCore

@Test(arguments: [
    // before, prefix, fragment: the outputs of the bench's split_fragment plus its trim path
    ("do yo", "do", " yo"), ("do yo ", "do yo", ""), ("do yo  ", "do yo", ""),
    ("foo.ba", "foo.", "ba"), ("foo. ba", "foo.", " ba"), ("foo,", "foo,", ""), ("foo, ", "foo,", ""),
    ("한국어 주민등", "한국어", " 주민등"), ("한국어 ", "한국어", ""), ("a\nba", "a", "\nba"), ("a  b", "a", "  b"),
    ("x don't", "x", " don't"), ("x it’s", "x", " it’s"), ("x snake_ca", "x", " snake_ca"), ("price 12", "price", " 12"),
    ("mixed 한글wor", "mixed", " 한글wor"), ("line\n", "line\n", ""),
])
func splitsLikeTheBench(before: String, prefix: String, fragment: String) {
    #expect(Prompt.make(context: "", before: before) == Prompt(prefix: prefix, fragment: fragment))
}

@Test func contextComesFirstAndAWholeFieldWordHoldsOut() {
    #expect(Prompt.make(context: "Note.", before: "go ho") == Prompt(prefix: "Note.\n\ngo", fragment: " ho", screenChars: 7))
    #expect(Prompt.make(context: "Note.", before: "hel") == Prompt(prefix: "Note.\n\n", fragment: "hel", screenChars: 7))
    #expect(Prompt.make(context: "Note.", before: "") == Prompt(prefix: "Note.\n\n", fragment: "", screenChars: 7))
}

@Test func withNothingElseTheFragmentIsThePrompt() {
    #expect(Prompt.make(context: "", before: "hel") == Prompt(prefix: "hel", fragment: ""))
    #expect(Prompt.make(context: "", before: "  hel") == Prompt(prefix: "  hel", fragment: ""))
    #expect(Prompt.make(context: "", before: "  ") == Prompt(prefix: "", fragment: ""))
}

@Test(arguments: [
    ("그 달", true, "그", ""), ("기분이 좋으시게", true, "기분이", " 좋으시"), ("기분이 좋으시게", false, "기분이", " 좋으시게"),
    ("그 달 ", true, "그 달", ""), ("do yo", true, "do", " yo"), ("달", true, "", ""),
])
func aPossiblyComposingCharacterIsWithheld(before: String, korean: Bool, prefix: String, fragment: String) {
    let prompt = Prompt.make(context: "", field: Field(before: before, mayCompose: korean))
    #expect(prompt.prefix == prefix)
    #expect(prompt.fragment == fragment)
}

@Test func headStaysStableThroughContinuousComposition() {
    var previous = ""
    for state in TwoSet.trace("오늘 다라가 값이 괜찮아 없어요") {
        let prompt = Prompt.make(context: "", field: state.field)
        #expect(prompt.prefix.hasPrefix(previous), "\(state)")
        previous = prompt.prefix
    }
}

@Test func windowJumpsByStepAndKeepsTheEnd() {
    let at = { (n: Int) in Prompt.make(context: "", before: String(repeating: "x", count: n)) }
    #expect(at(Prompt.windowChars).prefix.count == Prompt.windowChars)
    #expect(at(Prompt.windowChars + 1).prefix.count == Prompt.windowChars + 1 - Prompt.stepChars)
    #expect(at(5000).prefix.count <= Prompt.windowChars)
}

/// The property the cache depends on: typing only ever appends to the prompt, except at a jump of whole steps.
@Test func headStaysByteIdenticalWhileTyping() {
    let words = ["the", "quiet", "river", "don't", "오늘은", "날씨가", "맑아서", "값이", "well,", "다라"]
    var draft = ""
    var i = 7
    while draft.count < 4000 {
        i = (i * 31 + 11) % 97
        draft += words[i % words.count] + (i % 13 == 0 ? ".\n" : " ")
    }
    let context = String(repeating: "Earlier text on the screen, frozen. ", count: 20)

    var previous = Prompt.make(context: context, before: "").prefix
    var jumps = 0
    for count in 1...draft.count {
        let prompt = Prompt.make(context: context, before: String(draft.prefix(count)))
        #expect(prompt.prefix.count <= Prompt.windowChars)
        #expect(!prompt.prefix.hasSuffix(" "))
        // A newline ends the prompt until a word follows it, then moves to the fragment, as in the bench.
        let head = previous[..<(previous.lastIndex { !$0.isWhitespace }.map(previous.index(after:)) ?? previous.endIndex)]
        if !prompt.prefix.utf8.starts(with: head.utf8) {
            jumps += 1
            #expect(prompt.prefix.utf8.starts(with: head.dropFirst(Prompt.stepChars).utf8), "at \(count) the head changed without a jump")
        }
        previous = prompt.prefix
    }
    let total = context.count + 2 + draft.count
    #expect(jumps == (total - Prompt.windowChars) / Prompt.stepChars + 1 || jumps == (total - Prompt.windowChars) / Prompt.stepChars)
}

@Test func composingCarriesTheSpacesThePromptDropped() {
    let startOfWord = Prompt.make(context: "", field: Field(before: "오늘 날", mayCompose: true))
    #expect(startOfWord.prefix == "오늘")
    #expect(startOfWord.fragment == "")
    #expect(startOfWord.composing == " 날")
    let midWord = Prompt.make(context: "", field: Field(before: "오늘 날씨", mayCompose: true))
    #expect(midWord.fragment == " 날")
    #expect(midWord.composing == "씨")
    #expect(Prompt.make(context: "", field: Field(before: "the wor")).composing == "")
    #expect(Prompt.make(context: "", field: Field(before: "the word ")).composing == " ")
}
