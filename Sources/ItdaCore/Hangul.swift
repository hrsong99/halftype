import Foundation

public enum Hangul {
    private static let onsets = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    /// Letters typed as two keys on a 2-set layout.
    private static let twoKeys: [Character: String] = [
        "ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ", "ㅞ": "ㅜㅔ", "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ",
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ", "ㄽ": "ㄹㅅ", "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ",
    ]

    /// A syllable or a jamo, compatibility or conjoining.
    static func isHangul(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0xAC00...0xD7A3).contains(v) || (0x3131...0x3163).contains(v) || (0x1100...0x11FF).contains(v)
    }

    /// 2-set keystrokes behind a text: 값 -> ㄱㅏㅂㅅ, ㅘ -> ㅗㅏ. Other characters stand for themselves.
    public static func keys(_ text: String) -> String {
        var out = ""
        for c in text.precomposedStringWithCanonicalMapping {
            let letters: [Character]
            if let v = c.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(v), c.unicodeScalars.count == 1 {
                let i = Int(v) - 0xAC00, final = i % 28
                letters = [onsets[i / 588], vowels[i % 588 / 28]] + (final > 0 ? [finals[final - 1]] : [])
            } else {
                letters = [c]
            }
            for letter in letters { out += twoKeys[letter] ?? String(letter) }
        }
        return out
    }

    /// Could typing on from `composing` still produce `suggestion`? 달 fits 다라, as the ㄹ can still move on.
    public static func fits(composing: String, suggestion: String) -> Bool {
        keys(suggestion).hasPrefix(keys(composing))
    }

    /// How many leading characters of `suggestion` the composing keystrokes reach into: 하 -> 1 of 한글, 달 -> 2 of 다라가.
    static func reach(composing: String, suggestion: String) -> Int {
        var left = keys(composing).count, reached = 0
        for c in suggestion where left > 0 {
            left -= keys(String(c)).count
            reached += 1
        }
        return reached
    }
}
