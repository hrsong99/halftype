import Testing
@testable import HalftypeCore

private func token(_ text: String, _ logprob: Double = 0) -> Token { Token(bytes: Array(text.utf8), logprob: logprob) }

@Test func peekShowsTheKeptWordsThenTheOneItStoppedBefore() throws {
    let prompt = Prompt.make(context: "are we still on?", before: "Sounds good, see you tomo")
    let tokens = [token(" tomorrow", -0.12), token(" at", -0.41), token(" the", -0.22), token(" station", -0.3)]
    let shown = Stop.cut(tokens, fragment: prompt.fragment).text
    #expect(shown == "rrow at the")
    let peek = try #require(Peek.make(tokens, prompt: prompt, context: 16, shown: shown, tuning: Tuning()))
    #expect(peek.held == " tomo")
    #expect(peek.screen == "are we still on?")
    #expect(peek.field == "Sounds good, see you")
    #expect(peek.steps.map(\.text) == [" tomorrow", " at", " the", " station"])
    #expect(peek.steps.map(\.kept) == [true, true, true, false])
    #expect(peek.steps.map(\.end) == [4, 7, 11, 19])
    // Typed through "tomorrow": the ghost follows without asking again, and the card marks the word taken, as the app does.
    var later = peek
    let ghost = try #require(Follow.check(anchor: "Sounds good, see you tomo", suggestion: shown, field: Field(before: "Sounds good, see you tomorrow")))
    later.taken = later.shown - ghost.composing.count - ghost.remainder.count
    #expect(later.steps.map(later.isTaken) == [true, false, false, false])
    #expect(abs(peek.steps[1].logprob - -0.41) < 1e-9)
    #expect(abs(peek.steps[3].running - -1.05) < 1e-9)
    // The first word's number is the gate's.
    #expect(peek.steps[0].running == Gate.firstWord(tokens, fragment: prompt.fragment))
    #expect(peek.end == .floor)
}

@Test func peekStopsAtPunctuationAsTheGhostDoes() throws {
    let prompt = Prompt.make(context: "", before: "well, I said hel")
    let tokens = [token(" hello", -0.1), token(". world", -1.1)]
    let shown = Stop.cut(tokens, fragment: prompt.fragment).text
    #expect(shown == "lo.")
    let peek = try #require(Peek.make(tokens, prompt: prompt, context: 0, shown: shown, tuning: Tuning()))
    #expect(peek.steps.map(\.text) == [" hello"])
    #expect(peek.end == .punctuation)
}

@Test func peekKeepsHangulSplitAcrossTokensAndStopsAtANewline() throws {
    let prompt = Prompt.make(context: "", before: "오늘 날씨 좋")
    let 네 = Array("네".utf8)
    let tokens = [token(" 좋", -5), Token(bytes: Array("아".utf8) + 네.prefix(2), logprob: -0.2), Token(bytes: Array(네.dropFirst(2)), logprob: -0.1),
                  token("\n다음", -0.1)]
    let shown = Stop.cut(tokens, fragment: prompt.fragment).text
    let peek = try #require(Peek.make(tokens, prompt: prompt, context: 0, shown: shown, tuning: Tuning()))
    #expect(peek.steps.map(\.text) == [" 좋아네"])
    #expect(peek.steps.allSatisfy { $0.kept })
    #expect(abs(peek.steps[0].logprob - -0.3) < 1e-9)
    #expect(peek.end == .line)
}

@Test func peekIsNilWithNoWord() {
    let prompt = Prompt.make(context: "", before: "hello th")
    #expect(Peek.make([token(" th", -1), token("\n", -0.1)], prompt: prompt, context: 0, shown: "", tuning: Tuning()) == nil)
}

@Test func promptKnowsWhereTheScreenEndsEvenWithABlankLineInTheField() {
    let prompt = Prompt.make(context: "the plan", before: "Hi,\n\nsee you tomo")
    #expect(prompt.prefix == "the plan\n\nHi,\n\nsee you")
    #expect(prompt.screenChars == 10)
    // Trimmed to the window, the screen text loses its start and keeps its count right.
    let long = Prompt.make(context: String(repeating: "x", count: 1500), before: "see you tomo")
    #expect(long.prefix.dropFirst(long.screenChars) == "see you")
    #expect(long.prefix.prefix(long.screenChars).hasSuffix("x\n\n"))
    let none = Prompt.make(context: "", before: "see you tomo")
    #expect(none.screenChars == 0)
}

@Test func aNewWordAfterAWholeOneStandsAlone() throws {
    let prompt = Prompt.make(context: "", before: "see you tomorrow")
    let tokens = [token(" tomorrow", -0.1), token(" at", -0.2), token(" six", -0.2)]
    let peek = try #require(Peek.make(tokens, prompt: prompt, context: 0, shown: " at six", tuning: Tuning()))
    #expect(peek.steps.map(\.text) == [" at", " six"])
}
