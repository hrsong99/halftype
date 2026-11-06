import ItdaCore

/// A continuous 2-set composer for tests and replay: the field states a real IME goes through for a string. Typing 다라 passes
/// through ㄷ, 다, 달, then 다 committed with 라 marked. Keys come from `Hangul.keys`; the composition is written here.
public enum TwoSet {
    public struct State: Equatable, Sendable {
        public var before: String
        public var marked: String
        public init(before: String, marked: String) { (self.before, self.marked) = (before, marked) }
        /// What the core gets: apps report no marked text, so the composing character is just in the field.
        public var field: Field { Field(before: before + marked, koreanInput: true) }
    }

    private static let onsets = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let vowelPairs: [String: Character] = ["ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ", "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ", "ㅡㅣ": "ㅢ"]
    private static let finalPairs: [String: Character] = ["ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ", "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ", "ㅂㅅ": "ㅄ"]

    private static func syllable(_ onset: Character, _ vowel: Character, _ final: Character?) -> String {
        let f = final.map { finals.firstIndex(of: $0)! + 1 } ?? 0
        let v = 0xAC00 + (onsets.firstIndex(of: onset)! * 21 + vowels.firstIndex(of: vowel)!) * 28 + f
        return String(Unicode.Scalar(UInt32(v))!)
    }

    /// Every state after every key of `text`, starting from committed `start`, ending with the last syllable committed.
    public static func trace(_ text: String, start: String = "") -> [State] {
        var before = start
        var onset: Character?, vowel: Character?, final: Character?
        var states: [State] = []

        func marked() -> String {
            guard let onset else { return vowel.map(String.init) ?? "" }
            guard let vowel else { return String(onset) }
            return syllable(onset, vowel, final)
        }
        func commit() {
            before += marked()
            (onset, vowel, final) = (nil, nil, nil)
        }
        func press(_ key: Character) {
            if vowels.contains(key) {
                if let f = final {  // the final, or the last key of a double final, moves to the next syllable
                    let pair = finalPairs.first { $0.value == f }?.key
                    final = pair.flatMap { $0.first }
                    let moved = pair?.last ?? f
                    commit()
                    (onset, vowel) = (moved, key)
                } else if let v = vowel, onset != nil, let compound = vowelPairs[String([v, key])] {
                    vowel = compound
                } else if onset != nil, vowel == nil {
                    vowel = key
                } else {
                    commit()
                    vowel = key
                }
            } else if onset != nil, vowel != nil {
                if let f = final {
                    if let double = finalPairs[String([f, key])] {
                        final = double
                    } else {
                        commit()
                        onset = key
                    }
                } else if finals.contains(key) {
                    final = key
                } else {
                    commit()
                    onset = key
                }
            } else {
                commit()
                onset = key
            }
            states.append(State(before: before, marked: marked()))
        }

        for c in text {
            let keys = Hangul.keys(String(c))
            if keys != String(c) || onsets.contains(c) || vowels.contains(c) {
                keys.forEach(press)
            } else {
                commit()
                before.append(c)
                states.append(State(before: before, marked: ""))
            }
        }
        commit()
        states.append(State(before: before, marked: ""))
        return states
    }
}
