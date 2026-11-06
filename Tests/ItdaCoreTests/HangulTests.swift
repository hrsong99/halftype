import Foundation
import Testing
import TwoSet
@testable import ItdaCore

@Test(arguments: [
    ("값", "ㄱㅏㅂㅅ"), ("과", "ㄱㅗㅏ"), ("한", "ㅎㅏㄴ"), ("의", "ㅇㅡㅣ"), ("없", "ㅇㅓㅂㅅ"), ("까", "ㄲㅏ"), ("닭", "ㄷㅏㄹㄱ"), ("뷁", "ㅂㅜㅔㄹㄱ"),
    ("ㅎ", "ㅎ"), ("ㅘ", "ㅗㅏ"), ("ㅢ", "ㅡㅣ"), ("ㄳ", "ㄱㅅ"), ("ㅀ", "ㄹㅎ"), ("ㅄ", "ㅂㅅ"),
    ("a한 b", "aㅎㅏㄴ b"), ("", ""), ("한".decomposedStringWithCanonicalMapping, "ㅎㅏㄴ"),
])
func keys(text: String, expected: String) {
    #expect(Hangul.keys(text) == expected)
}

@Test(arguments: [
    ("ㅎ", "한글", true), ("하", "한글", true), ("한", "한글", true), ("한", "하나", true), ("달", "다라", true), ("달", "달라", true),
    ("갑", "값", true), ("값", "값이", true), ("갑", "갑시다", true), ("값", "갑시다", true), ("고", "과일", true), ("ㅇ", "의사", true), ("으", "의사", true), ("", "아무", true),
    ("hel", "hello", true),
    ("하", "호", false), ("한", "하", false), ("달", "다나", false), ("과", "고아", false), ("값", "갑", false), ("ㄱ", "나", false), ("hel", "he", false),
])
func fits(composing: String, suggestion: String, expected: Bool) {
    #expect(Hangul.fits(composing: composing, suggestion: suggestion) == expected)
}

/// Written from Unicode's formula, not the code under test.
private func parts(_ syllable: Int) -> (onset: Int, vowel: Int) {
    ((syllable - 0xAC00) / 588, (syllable - 0xAC00) % 588 / 28)
}

private func text(_ syllable: Int) -> String { String(Unicode.Scalar(UInt32(syllable))!) }

/// Vowels that start with another key: ㅘ after ㅗ, and so on. Those index pairs alone may share a first key.
private let vowelExtends = [(8, 9), (8, 10), (8, 11), (13, 14), (13, 15), (13, 16), (18, 19)]

@Test func fitsIsNeverTrueOnAMismatchedSyllable() {
    var mismatched = 0
    for a in stride(from: 0xAC00, through: 0xD7A3, by: 149) {
        for b in stride(from: 0xAC00, through: 0xD7A3, by: 137) {
            let (pa, pb) = (parts(a), parts(b))
            let extends = vowelExtends.contains { $0 == (pa.vowel, pb.vowel) }
            guard pa.onset != pb.onset || (pa.vowel != pb.vowel && !extends) else { continue }
            mismatched += 1
            #expect(!Hangul.fits(composing: text(a), suggestion: text(b) + "요"), "\(text(a)) must not fit \(text(b))")
        }
    }
    #expect(mismatched > 3000)
}

@Test(arguments: [
    ("다라", ["ㄷ", "다", "달", "라"], ["", "", "", "다"]),
    ("값", ["ㄱ", "가", "갑", "값"], ["", "", "", ""]),
    ("과", ["ㄱ", "고", "과"], ["", "", ""]),
    ("갑시", ["ㄱ", "가", "갑", "값", "시"], ["", "", "", "", "갑"]),
    ("달가", ["ㄷ", "다", "달", "닭", "가"], ["", "", "", "", "달"]),
    ("없어", ["ㅇ", "어", "업", "없", "ㅇ", "어"], ["", "", "", "", "없", "없"]),
])
func traceIsContinuousComposition(text: String, marked: [String], before: [String]) {
    let states = TwoSet.trace(text).dropLast()
    #expect(states.map(\.marked) == marked)
    #expect(states.map(\.before) == before)
}

private let sentences = ["오늘 다라가 값이 괜찮아", "없어요 닭고기 과일", "의사 선생님 앉아 있어", "뛰어 놀았다 갑시다", "까치 뷁 왜요 mixed 말"]

@Test(arguments: sentences)
func traceEndsAtTheTextAndCommittedOnlyGrows(sentence: String) {
    let states = TwoSet.trace(sentence)
    #expect(states.last == TwoSet.State(before: sentence, marked: ""))
    for (a, b) in zip(states, states.dropFirst()) {
        #expect(b.before.hasPrefix(a.before))
    }
}

@Test(arguments: sentences)
func everyContinuousStateFitsItsOwnText(sentence: String) {
    for state in TwoSet.trace(sentence) {
        #expect(sentence.hasPrefix(state.before), "\(state)")
        let rest = String(sentence.dropFirst(state.before.count))
        #expect(Hangul.fits(composing: state.marked, suggestion: rest), "\(state)")
    }
}

/// The core's rule must recover exactly what the IME was composing, with no marked text to read.
@Test(arguments: sentences)
func fieldFindsTheComposingCharacter(sentence: String) {
    for state in TwoSet.trace(sentence) where !state.marked.isEmpty {
        #expect(state.field.composing == state.marked)
        #expect(state.field.committed == state.before)
    }
}

@Test(arguments: [("그 달", true, "달", "그 "), ("그 ㄷ", true, "ㄷ", "그 "), ("그 ㅘ", true, "ㅘ", "그 "), ("그 달", false, "", "그 달"), ("그 ", true, "", "그 "), ("go", true, "", "go"), ("", true, "", "")])
func composingRule(before: String, korean: Bool, composing: String, committed: String) {
    let field = Field(before: before, koreanInput: korean)
    #expect(field.composing == composing)
    #expect(field.committed == committed)
}

@Test func aMovingFinalChangesTheMarkedSyllableButNotEarlierText() {
    let states = TwoSet.trace("다라", start: "그래 ")
    #expect(states[2] == .init(before: "그래 ", marked: "달"))
    #expect(states[3] == .init(before: "그래 다", marked: "라"))
    #expect(states[2].field.before == "그래 달" && states[3].field.before == "그래 다라")  // 달 is gone from the field
}
