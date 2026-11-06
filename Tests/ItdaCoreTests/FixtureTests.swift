import Testing
@testable import ItdaCore

/// Same shapes as the replay bench's before/after tables, in invented sentences. Each "before" is what a model did
/// without the rule and each "after" what it did with it. No model runs here: the core must carry each of them.
private func firstWord(_ text: String) -> String { String(text[..<Word.firstEnd(text)]) }

private func tokens(_ fragment: String, _ text: String) -> [Token] {
    var out = fragment.isEmpty ? [] : [Token(bytes: Array(fragment.utf8), logprob: -9)]
    var word = ""
    for c in text {
        if c == " ", !word.isEmpty {
            out.append(Token(bytes: Array(word.utf8), logprob: -0.5))
            word = ""
        }
        word.append(c)
    }
    if !word.isEmpty { out.append(Token(bytes: Array(word.utf8), logprob: -0.5)) }
    return out
}

@Test(arguments: [
    // typed, prefix, fragment, trimmed (before), held out (after), real
    ("Please check the garden gat", "Please check the garden", " gat", "?", "e tomorrow.", "e tonight?"),
    ("Then paint the fence your", "Then paint the fence", " your", " own.", "self.", "self. Maybe later"),
    ("Will they be leaving t", "Will they be leaving", " t", " soon?", "oday?", "oday?"),
    ("sure pack everyt", "sure pack", " everyt", ".", "hing.", "hing"),
    ("should I keep any of th", "should I keep any of", " th", "**h**h**h**h", "ese.", "ese or not."),
    ("the third step is the simpl", "the third step is the", " simpl", " method for bread", "est one for now", "est for us?"),
    ("mix flour with salt an", "mix flour with salt", " an", " pepper.", "d see how it tastes", "d then stir"),
    ("Could we read and rem", "Could we read and", " rem", "ind it?", "ember the list for me?", "ember that recipe?"),
    ("make sure tha", "make sure", " tha", " front door is", "t the front door", "t everything is"),
    ("a blue coat, s", "a blue coat,", " s", " maybe a warm", "omething.", "omething. Try"),
])
func heldOutFragment(typed: String, prefix: String, fragment: String, trimmed: String, heldOut: String, real: String) {
    let prompt = Prompt.make(context: "", before: typed)
    #expect(prompt == Prompt(prefix: prefix, fragment: fragment))
    #expect(Grammar.forcing(fragment: fragment).contains(fragment))

    let generated = tokens(fragment, heldOut)
    #expect(Stop.cut(generated, fragment: fragment).text == heldOut)
    #expect(Gate.firstWord(generated, fragment: fragment) == -0.5)

    let ghost = Follow.check(anchor: typed, suggestion: heldOut, field: Field(before: typed))
    #expect(ghost?.remainder == heldOut)
    #expect(firstWord(real) == Accept.nextWord(ghost!)?.insert)   // after: Tab gives the real next word
    #expect(firstWord(real) != firstWord(trimmed))               // before: it did not
}

@Test(arguments: [
    // typed, as is (before), trimmed (after), real
    ("the soup was good the first ", "40 days of spring", " time but now", "time; either"),
    ("let me see if there's ", "200% of the sugar", " anything that needs", "anything that's salty"),
    ("also the city's ", "2.0.0 is the same", " new bus route", "new bus route:"),
    ("well if you trust ", "5K is the answer", " them I would", "them then"),
    ("tell me what ", "100% of the time", " you're planning to", "you're planning to"),
    ("use a ladder instead ", "50 rungs?", " of a chair?", "of a stool?"),
    ("return the old ", "7 chairs if you", " ones if you want", "ones and then"),
    ("what should we do now? What ", "9-digit codes", " are the choices?", "are those for"),
    ("I made sure ", "", " to lock the door", "to lock behind"),
    ("sorry I missed that, can ", "", " you tell me more", "you say it again?"),
])
func trailingSpace(typed: String, asIs: String, trimmed: String, real: String) {
    let prompt = Prompt.make(context: "Earlier.", before: typed)
    #expect(!prompt.prefix.hasSuffix(" "))
    #expect(prompt.fragment.isEmpty)

    #expect(Stop.cut(tokens("", trimmed), fragment: "").text == trimmed)
    let ghost = Follow.check(anchor: typed, suggestion: trimmed, field: Field(before: typed))
    #expect(ghost?.remainder == String(trimmed.dropFirst()))     // the space is already in the field
    #expect(firstWord(real) == Accept.nextWord(ghost!)?.insert)
    #expect(firstWord(real) != firstWord(asIs))
    #expect(Follow.check(anchor: typed, suggestion: asIs, field: Field(before: typed)) == nil)
}

@Test(arguments: [
    // typed, composing, sent as text (before), withheld (after), real next syllable state, real
    ("오늘 일정 변", "겨", "겨울 준비를 위해", "경이 생겼어요", "경", "경이 있어요"),
    ("그나저나 사과", "르", "르는 건 단지 맛있어서", "를 먹는 건 좋은 거지.", "를", "를 잘 씻어 줘."),
    ("기분이 좋으시", "게", "게요?", "겠어요.", "겠", "겠어요."),
])
func withheldComposition(typed: String, composing: String, sent: String, withheld: String, next: String, real: String) {
    // The composing syllable never reaches the model.
    let field = Field(before: typed + composing, koreanInput: true)
    let prompt = Prompt.make(context: "", field: field)
    #expect(prompt.prefix + prompt.fragment == typed)

    // Withheld: it fits now and when the syllable changes, and it holds the real next word.
    #expect(Follow.check(anchor: field.committed, suggestion: withheld, field: field) != nil)
    let changed = Field(before: typed + next, koreanInput: true)
    let later = Follow.check(anchor: field.committed, suggestion: withheld, field: changed)
    #expect(later?.needsReplace == false)
    #expect(later.map { firstWord($0.composing + $0.remainder) } == firstWord(real))

    // Sent as text: its next word is wrong, whatever survives of it.
    let sentGhost = Follow.check(anchor: typed + composing, suggestion: sent, field: changed)
    #expect(sentGhost.map { firstWord($0.composing + $0.remainder) } != firstWord(real))
    #expect(firstWord(sent) != firstWord(real))
}
