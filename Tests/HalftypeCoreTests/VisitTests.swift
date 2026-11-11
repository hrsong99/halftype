import Testing
@testable import HalftypeCore

@Suite struct VisitTests {
    @Test func keepsWhatTheVisitAddedWithTheTextBeforeIt() throws {
        let reply = try #require(Visit.added(from: "> are we still on?", to: "> are we still on?\nyes, see you at noon"))
        #expect(reply.before == "> are we still on?" && reply.text == "\nyes, see you at noon")
        let middle = try #require(Visit.added(from: "Hi Sam,\n\nThanks", to: "Hi Sam,\n\nsorry for the wait. Thanks"))
        #expect(middle.before == "Hi Sam,\n\n" && middle.text == "sorry for the wait. ")
        #expect(Visit.added(from: "same text", to: "same text") == nil)
        #expect(Visit.added(from: "typed then erased", to: "typed") == nil)
        #expect(Visit.added(from: "aaa", to: "aaaa")?.text == "a")  // head and tail don't overlap
    }

    @Test func keepsTwoWordsTypedByHandNotPastesOrCodes() {
        #expect(Visit.keeps("sounds good to me", keys: 17))
        #expect(Visit.keeps("sounds good to me", keys: 9))       // Tabs' words count as keys too
        #expect(!Visit.keeps("sounds good to me", keys: 1))      // one ⌘V
        #expect(!Visit.keeps("hunter2", keys: 7))                // one word
        #expect(!Visit.keeps("482913", keys: 6))                 // a code
    }

    @Test func aReadThatAddsMoreThanItsKeysIsAPaste() {
        #expect(!Visit.pasted("o", keys: 1))
        #expect(!Visit.pasted("there", keys: 2))          // a host's autocorrect, or reads a few keys apart
        #expect(Visit.pasted("private pasted message", keys: 0))  // ⌘V over a selection
    }

    @Test func koreanTypedOnTwoSetPasses() {
        // 2-set: 안녕하세요 반가워요 is 22 keys for 10 syllables and a space.
        let text = "안녕하세요 반가워요"
        #expect(Visit.added(from: "", to: text)?.text == text)
        #expect(Visit.keeps(text, keys: 22))
    }

    @Test func theContextIsLaidOutAsThePromptIs() {
        #expect(Visit.context(screen: "", before: "Hi") == "Hi")
        #expect(Visit.context(screen: "Mina: lunch?", before: "") == "Mina: lunch?\n\n")
        #expect(Visit.context(screen: String(repeating: "x", count: 2000), before: "ok").count == Prompt.windowChars)
    }
}
