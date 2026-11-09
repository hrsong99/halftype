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
    #expect(peek.tail.hasSuffix("see you"))
    #expect(peek.steps.map(\.text) == ["rrow", " at", " the", " station"])
    #expect(peek.steps.map(\.kept) == [true, true, true, false])
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
    #expect(peek.steps.map(\.text) == ["lo"])
    #expect(peek.end == .punctuation)
}

@Test func peekKeepsHangulSplitAcrossTokensAndStopsAtANewline() throws {
    let prompt = Prompt.make(context: "", before: "오늘 날씨 좋")
    let 네 = Array("네".utf8)
    let tokens = [token(" 좋", -5), Token(bytes: Array("아".utf8) + 네.prefix(2), logprob: -0.2), Token(bytes: Array(네.dropFirst(2)), logprob: -0.1),
                  token("\n다음", -0.1)]
    let shown = Stop.cut(tokens, fragment: prompt.fragment).text
    let peek = try #require(Peek.make(tokens, prompt: prompt, context: 0, shown: shown, tuning: Tuning()))
    #expect(peek.steps.map(\.text) == ["아네"])
    #expect(peek.steps.allSatisfy { $0.kept })
    #expect(abs(peek.steps[0].logprob - -0.3) < 1e-9)
    #expect(peek.end == .line)
}

@Test func peekIsNilWithNoWord() {
    let prompt = Prompt.make(context: "", before: "hello th")
    #expect(Peek.make([token(" th", -1), token("\n", -0.1)], prompt: prompt, context: 0, shown: "", tuning: Tuning()) == nil)
}
