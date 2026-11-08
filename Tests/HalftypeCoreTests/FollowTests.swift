import Testing
@testable import HalftypeCore

@Test(arguments: [
    // anchor, suggestion, before, expected remainder (nil: drop)
    ("do yo", "u are", "do yo", "u are"),
    ("do yo", "u are", "do you", " are"),
    ("do yo", "u are", "do you a", "re"),
    ("do yo", "u are", "do you are", nil),      // nothing left
    ("do yo", "u are", "do yod", nil),          // typed something else
    ("do ", " you", "do ", "you"),              // trailing space: the suggestion carries its own
    ("do ", "you", "do ", nil),                 // no space of its own, so it does not join
    ("do ", ", yes", "do ", nil),
    ("do you a", "re we", "do you", nil),       // backspaced past the anchor
    ("do yo", "u are", "do you ", "are"),
    ("say do yo", "u are", "say so yo", nil),   // an earlier edit
    ("I do", "n't know", "I don't", " know"),
    ("I do", "n't know", "I don’t", nil),       // smart quote substitution
    ("I lo", "ok \"up\"", "I look “", nil),
    ("teh ca", "t sat", "the ca", nil),         // autocorrect of the anchor
    ("그 ", " 다라", "그 달", nil),              // Hangul compares literally without Korean input
])
func followLiteral(anchor: String, suggestion: String, before: String, remainder: String?) {
    #expect(Follow.check(anchor: anchor, suggestion: suggestion, field: Field(before: before))?.remainder == remainder)
}

@Test(arguments: [
    // anchor, suggestion, before, expected remainder (nil: drop), what the last character becomes, jamo still to type
    ("오늘 ", " 하늘은", "오늘 ㅎ", "늘은", "하", "ㅏ"),
    ("오늘 ", " 하늘은", "오늘 하", "늘은", "하", ""),
    ("오늘 ", " 한글은", "오늘 하", "글은", "한", "ㄴ"),
    ("오늘 ", " 호수", "오늘 하", nil, "", ""),
    ("그 ", " 다라가", "그 달", "가", "다라", "ㅏ"),      // a final that may yet move
    ("그 ", " 다라가", "그 다라", "가", "라", ""),     // and has
    ("그 ", " 다라", "그 달", nil, "", ""),           // covered, nothing further to draw
    ("값", "이 싸", "값ㅇ", " 싸", "이", "ㅣ"),
    ("기분이 좋으시", "겠어요.", "기분이 좋으시게", "어요.", "겠", "ㅆ"),
    ("그 달", " 이것", "그 달", " 이것", "달", ""),    // a committed 달, wrongly suspected: costs nothing
    ("그 달", " 이것", "그 달 ", "이것", "", ""),      // and no longer suspected
    ("그 달", " 이것", "그 다라", nil, "", ""),        // it was composing after all, and moved
    ("그 달", " 이것", "그 ", nil, "", ""),           // backspaced past the anchor
    ("그 ", " 값이 싸", "그 가", "이 싸", "값", "ㅂㅅ"),    // double final
    ("그 ", " 갑시다", "그 값", "다", "갑시", "ㅣ"),       // whose second key moves on
    ("그 ", " 과자 맛", "그 고", "자 맛", "과", "ㅏ"),      // compound vowel
    ("그 ", " 한 다음", "그 ㅎ", " 다음", "한", "ㅏㄴ"),    // from a lone jamo
])
func followWhileComposing(anchor: String, suggestion: String, before: String, remainder: String?, composing: String, keys: String) {
    let ghost = Follow.check(anchor: anchor, suggestion: suggestion, field: Field(before: before, mayCompose: true))
    #expect(ghost == remainder.map { Ghost(keys: keys, composing: composing, remainder: $0) })
}

/// 달 becomes 다라: the character before the caret changes under the suggestion, so the anchor must exclude it.
@Test func committedTextChangesWhenAFinalMoves() {
    let asked = Field(before: "그 달", mayCompose: true)
    #expect(asked.committed == "그 ")
    let moved = Field(before: "그 다라", mayCompose: true)
    #expect(!moved.before.hasPrefix(asked.before))
    #expect(Follow.check(anchor: asked.committed, suggestion: " 다라가 왔어", field: asked)?.remainder == "가 왔어")
    #expect(Follow.check(anchor: asked.committed, suggestion: " 다라가 왔어", field: moved)?.remainder == "가 왔어")
    // Keeping the whole of `before` as the anchor would have lost it, as this other suggestion is lost.
    #expect(Follow.check(anchor: asked.before, suggestion: " 이것", field: moved) == nil)
}

@Test func backspaceWithinASuggestionStillShowsIt() {
    let shown = { (before: String) in Follow.check(anchor: "go ho", suggestion: "me now", field: Field(before: before))?.remainder }
    #expect(shown("go home n") == "ow")
    #expect(shown("go home") == " now")   // back one word
    #expect(shown("go hom") == "e now")
    #expect(shown("go h") == nil)         // past where it started
}

private let sentences = ["오늘 다라가 값이 괜찮아", "없어요 닭고기 과일", "의사 선생님 앉아 있어", "까치 뷁 왜요 mixed 말"]

/// A result is not instantly available: it may land any number of keys after the request. Requested at state `i`,
/// arriving at any later state `j`, the right text must still show, through every real composition state.
@Test(arguments: sentences)
func aSuggestionArrivingLateFollowsContinuousStates(sentence: String) {
    let states = TwoSet.trace(sentence)
    for (i, requested) in states.enumerated() {
        let anchor = requested.field.committed
        let suggestion = String(sentence.dropFirst(Word.withoutTrailingSpaces(anchor).count))
        for state in states[i...] {
            let rest = String(sentence.dropFirst(state.field.committed.count))
            if let ghost = Follow.check(anchor: anchor, suggestion: suggestion, field: state.field) {
                #expect(ghost.composing + ghost.remainder == rest, "\(state)")
            } else {
                // Only the last syllables can leave nothing to draw.
                #expect(Hangul.reach(composing: state.field.composing, suggestion: rest) == rest.count, "\(state)")
            }
        }
    }
}

/// The user types `typed`; the suggestion on hand was for something else. It stays while they agree, and goes for good
/// at the first state that leaves it, however late it arrived.
@Test(arguments: [
    ("다나", "다라가", ["ㄷ": true, "다": true, "단": false, "나": false]),
    ("과자", "고아원", ["ㄱ": true, "고": true, "과": false, "ㅈ": false, "자": false]),
    ("갑자", "값이다", ["ㄱ": true, "가": true, "갑": true, "ㅈ": false, "자": false]),
])
func aMismatchDrops(typed: String, suggestion: String, expected: [String: Bool]) {
    var left = false
    for state in TwoSet.trace(typed, start: "그 ").dropLast() {
        let ghost = Follow.check(anchor: "그 ", suggestion: " " + suggestion, field: state.field)
        if let want = expected[state.marked] { #expect((ghost != nil) == want, "\(state)") }
        if ghost == nil { left = true }
        if left { #expect(ghost == nil, "came back at \(state)") }
    }
    #expect(left)
}

@Test(arguments: [
    (" are we", " are", " we"), ("u are", "u", " are"), ("tes, please", "tes", ", please"), (", then go", ", then", " go"),
    ("?", "?", ""), ("하세요 저는", "하세요", " 저는"), (" 좋아요. 다음", " 좋아요", ". 다음"), ("n't know", "n't", " know"), ("mixed한글 next", "mixed한글", " next"),
])
func nextWord(remainder: String, insert: String, left: String) {
    let accepted = Accept.nextWord(Ghost(remainder: remainder))
    #expect(accepted.text == insert)
    #expect(remainder == accepted.text + left)
}

@Test func acceptAllTakesEverything() {
    let accepted = Accept.all(Ghost(remainder: "글은 좋아"))
    #expect(accepted.text == "글은 좋아")
}

@Test(arguments: ["do yo", "그 달"])
func acceptAgreesWithFollowOnceInTheField(start: String) {
    let suggestion = start == "do yo" ? "u know what" : " 이것 저것 그것"
    var field = Field(before: start, mayCompose: start != "do yo")
    var inserted: [String] = []
    while let ghost = Follow.check(anchor: start, suggestion: suggestion, field: field) {
        let accepted = Accept.nextWord(ghost)
        inserted.append(accepted.text)
        field.before += accepted.text
        let left = String(ghost.remainder.dropFirst(accepted.text.count))
        #expect(Follow.check(anchor: start, suggestion: suggestion, field: field)?.remainder == (left.isEmpty ? nil : left))
    }
    #expect(inserted == (start == "do yo" ? ["u", " know", " what"] : [" 이것", " 저것", " 그것"]))
}

@Test func acceptTypesWhatTheSyllableNeedsThenInserts() {
    let field = { (before: String) in Field(before: before, mayCompose: true) }
    let matched = Follow.check(anchor: "오늘 ", suggestion: " 하늘은 맑아", field: field("오늘 하"))!
    #expect(Accept.nextWord(matched) == ("", "늘은"))
    #expect(Accept.all(matched) == ("", "늘은 맑아"))

    let changing = Follow.check(anchor: "오늘 ", suggestion: " 한 다음 날", field: field("오늘 하"))!
    #expect(changing.composing == "한")
    #expect(Accept.nextWord(changing) == ("ㄴ", " 다음"))
    #expect(Accept.all(changing) == ("ㄴ", " 다음 날"))
}

/// Once the key says the syllable is committed, Hangul compares literally: nothing asks to change it, so no stray ㄴ is possible.
@Test func aCommittedSyllableIsNeverTypedOnto() {
    let committed = Field(before: "오늘 하")
    #expect(Follow.check(anchor: "오늘 ", suggestion: " 한 다음", field: committed) == nil)
    #expect(Follow.check(anchor: "오늘 ", suggestion: " 하늘은", field: committed) == Ghost(remainder: "늘은"))
    #expect(Follow.check(anchor: "오늘 하", suggestion: "늘은", field: committed) == Ghost(remainder: "늘은"))
}
