import ItdaCore
import Testing
@testable import itda_replay

@Test func nextWordOnlyVersusWordsVersusEverything() {
    let s = score(Ghost(remainder: "u are going now"), typed: "", rest: "u are going home")
    #expect(s.useful)
    #expect(s.tabChars == 1)
    #expect(s.wordsChars == " are going".count + 1)
    #expect(s.allChars == 0)
}

@Test func allRightScoresEverything() {
    let s = score(Ghost(remainder: "u are"), typed: "", rest: "u are going")
    #expect(s.allChars == 5)
    #expect(s.wordsChars == 5)
}

@Test func aWordCutShortIsNotUseful() {
    let s = score(Ghost(remainder: " the"), typed: "", rest: " there it is")
    #expect(!s.useful)
    #expect(s.tabChars == 0)
    #expect(s.wordsChars == 0)
}

@Test func theSuggestionsWordMustEndToo() {
    #expect(!score(Ghost(remainder: " there"), typed: "", rest: " the end").useful)
}

@Test func composingSyllableCountsInKeysNotAsTyped() {
    // 하 typed, 한글 next: keys left are ㄴ ㄱ ㅡ ㄹ, characters saved are the one 글.
    let s = score(Ghost(composing: "한", remainder: "글", needsReplace: true), typed: "하", rest: "한글 입력")
    #expect(s.useful)
    #expect(s.tabKeys == 4)
    #expect(s.tabChars == 1)
}

@Test func committedSyllableSavesOnlyWhatFollows() {
    let s = score(Ghost(composing: "한", remainder: "글"), typed: "한", rest: "한글.")
    #expect(s.tabKeys == 3)
    #expect(s.tabChars == 1)
}
