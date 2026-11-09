import ImageIO
import AppKit
@testable import CompareKit
import Testing

// Invented sentences only (AGENTS.md: no private text).

@Test func plansCountKeysAsTyped() {
    #expect(Plan("Hi there").keys.count == 8)
    #expect(Plan("값 오늘").keys.count == 4 + 1 + 5)
    let p = Plan("오늘 날씨")
    #expect(p.done(field: "오느", composing: "느") == 4)
    #expect(p.next(field: "오느", composing: "느") == "ㄹ")
    #expect(p.done(field: "온", composing: "온") == 3)  // ㄴ is still free to move on.
    #expect(p.done(field: "온", composing: "") == nil)  // Committed, it can't.
    #expect(p.done(field: "오늘 날씨") == p.keys.count)
    #expect(Plan("gone").done(field: "go!") == nil)
}

@Test func oracleTakesOnlyTrueText() {
    let p = Plan("Hello world is round")
    #expect(p.tab(field: "Hel", ghost: "lo world", unit: .word).first == "Hello")
    #expect(p.tab(field: "Hello", ghost: " world is flat", unit: .word).first == "Hello world")
    #expect(p.tab(field: "Hello", ghost: " world is flat", unit: .all).isEmpty)  // macOS would take the wrong tail too.
    #expect(p.tab(field: "Hello", ghost: " world is", unit: .all).first == "Hello world is")
    #expect(p.tab(field: "Hello", ghost: "world", unit: .word).isEmpty)  // No space: helloworld.
    #expect(p.tab(field: "Hello worl", ghost: "d", unit: .word).isEmpty)  // Saves nothing over the key itself.
    #expect(p.tab(field: "Hello", ghost: " ", unit: .word).isEmpty)
}

@Test func firstWordMustEndWhereTheTargetsDoes() {
    let p = Plan("a lot of time")
    #expect(p.firstWordRight(field: "a l", ghost: "ot of"))
    #expect(!p.firstWordRight(field: "a l", ghost: "o"))
    #expect(p.firstWordRight(field: "a lot", ghost: " of course"))
    #expect(!p.firstWordRight(field: "a lot", ghost: " off"))
    #expect(Plan("Sure, why not").firstWordRight(field: "Su", ghost: "re, I can"))
}

@Test func koreanGhostsReplaceOrFollowTheSyllable() {
    let p = Plan("오늘 날씨가 좋다")
    // A ghost that finishes the composing syllable, as Halftype shows it.
    #expect(p.tab(field: "오", composing: "오", ghost: "오늘 날씨", unit: .word).first == "오늘")
    #expect(p.tab(field: "오느", composing: "느", ghost: "늘 날씨", unit: .word).isEmpty)  // One key saved, one Tab spent.
    #expect(p.firstWordRight(field: "오느", composing: "느", ghost: "늘 날씨"))
    // One that starts after it.
    #expect(p.tab(field: "오늘", composing: "늘", ghost: " 날씨가 좋네", unit: .word).first == "오늘 날씨가")
    #expect(p.firstWordRight(field: "오늘", composing: "늘", ghost: " 날씨가 좋네"))
    #expect(!p.firstWordRight(field: "오늘", composing: "늘", ghost: " 날씨 좋네"))  // 날씨 is not 날씨가.
    #expect(p.tab(field: "오느", composing: "느", ghost: "는 아침", unit: .word).isEmpty)
    // Halftype draws only what follows the syllable its Tab will finish: 가 on screen, then 다면 in grey, for 간다면.
    #expect(Plan("간다면 좋지").tab(field: "가", composing: "가", ghost: "다면 좋지", unit: .word).first == "간다면")
}

@Test func aWordStopsBeforeItsPunctuationToo() {
    let p = Plan("Hello world")
    #expect(p.tab(field: "Hel", ghost: "lo, everyone", unit: .word).first == "Hello")  // Halftype takes `lo`, not `lo,`.
    #expect(p.firstWordRight(field: "Hel", ghost: "lo, everyone"))
    #expect(Plan("Hello, world").tab(field: "Hel", ghost: "lo, there", unit: .word) == ["Hello,", "Hello"])  // Either is right.
    #expect(Plan("다라가 보자").tab(field: "달", composing: "달", ghost: "가 보자", unit: .word).first == "다라가")  // 달 reaches into 다라.
    #expect(Set(Plan("하하하").tab(field: "하", composing: "하", ghost: "하하", unit: .word)) == ["하하", "하하하"])
}

@Test func delaysAreSeededAndHuman() {
    var a = Delays(seed: Delays.seed("x")), b = Delays(seed: Delays.seed("x"))
    let xs = (0..<4000).map { _ in a.next() }
    #expect(xs.prefix(50).elementsEqual((0..<50).map { _ in b.next() }))
    let median = Score.percentile(xs, 0.5)!
    #expect(abs(median - 264) < 15)
    #expect(xs.allSatisfy { (90...1200).contains($0) })
}

@Test func savedCountsTabsAndCarriesAnInterval() {
    let rows = (0..<10).map { SentenceRecord(app: "a", lang: "en", sentence: "\($0)", total: 40, pressed: $0 < 5 ? 30 : 40, tabs: 2, wrongTabs: 0, tabsAsRead: 2) }
    let s = Score.saved(rows)!
    #expect(abs(s.value - 0.125) < 1e-9)
    #expect(s.low < s.value && s.value < s.high)
    let keys = [
        KeyRecord(app: "a", lang: "en", sentence: "0", tab: false, probe: true, fresh: true, latencyMs: 80, shown: true, firstRight: true, composing: false),
        KeyRecord(app: "a", lang: "en", sentence: "0", tab: false, probe: true, fresh: true, latencyMs: nil, shown: false, firstRight: false, composing: false),
        KeyRecord(app: "a", lang: "en", sentence: "0", tab: false, probe: false, fresh: false, latencyMs: 16, shown: true, firstRight: false, composing: false),
    ]
    let row = Score.rows(keys: keys, sentences: rows, resources: [])[0]
    #expect(row.shownShare == 2.0 / 3 && row.firstRight == 0.5)
    #expect(row.freshP50 == 80 && row.probeNone == 0.5 && row.freshN == 1)
    #expect(Score.markdown([row]).contains("12.5%"))
}

// MARK: OCR on frames drawn the way an app draws a ghost: typed ink, then grey text from the caret.

/// A BGRA frame of a white field at 2x: `typed` in black, then `ghost` in `grey` from the caret. Returns the caret's x in pixels.
func frame(typed: String, ghost: String, grey: NSColor = NSColor(white: 0.6, alpha: 1), size: CGFloat = 17,
           _ body: (Frame, Int) -> Void) {
    let scale: CGFloat = 2, w = 1400, h = Int(size * 2.4 * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let font = NSFont.systemFont(ofSize: size)
    let ink = NSAttributedString(string: typed, attributes: [.font: font, .foregroundColor: NSColor.black])
    let origin = CGPoint(x: 8, y: size * 0.7)
    ink.draw(at: origin)
    let caret = origin.x + ink.size().width
    NSAttributedString(string: ghost, attributes: [.font: font, .foregroundColor: grey]).draw(at: CGPoint(x: caret, y: origin.y))
    NSGraphicsContext.restoreGraphicsState()
    body(Frame(base: UnsafeRawPointer(ctx.data!), width: w, height: h, bytesPerRow: ctx.bytesPerRow), Int((caret * scale).rounded()))
}

@Test func inkRightOfTheCaretIsOnlyTheGhost() {
    frame(typed: "Could you send", ghost: "") { f, caret in #expect(Ghost.ink(in: f, fromX: caret + 1) == nil) }
    frame(typed: "Could you send", ghost: " me the file") { f, caret in
        let ink = Ghost.ink(in: f, fromX: caret + 1)!
        #expect(Ghost.leadingSpace(caretX: caret, ink: ink, emPixels: 34))
    }
    frame(typed: "Could you se", ghost: "nd me") { f, caret in
        #expect(!Ghost.leadingSpace(caretX: caret, ink: Ghost.ink(in: f, fromX: caret + 1)!, emPixels: 34))
    }
}

/// Vision waits on threads from the pool these tests block, so OCR tests at once starve it and hang (2026-11-09): one at a time.
@Suite(.serialized) struct OCR {
@Test(arguments: [
    ("Could you send", " me the file", false), ("I would like", " to book a table", false), ("Is it wor", "th the trip", false),
    ("Let's meet at", " noon tomorrow", false), ("오늘", " 저녁에 만나요", true), ("주말에 같이", " 영화 볼래?", true),
    ("We are look", "ing", false), ("Thanks for y", "our help.", false),
])
func ocrReadsAGreyGhost(typed: String, ghost: String, korean: Bool) {
    for grey in [NSColor(white: 0.55, alpha: 1), NSColor(white: 0.72, alpha: 1)] {
        frame(typed: typed, ghost: ghost, grey: grey) { f, caret in
            let image = Ghost.binarized(f, fromX: caret + 1)!
            #expect(Ghost.read(image, korean: korean) == ghost.trimmingCharacters(in: .whitespaces), "grey \(grey.whiteComponent)")
        }
    }
}

/// A real capture of Halftype's ghost, a word's end at the left of the field-wide strip: Vision read it as nothing until the
/// crop was cut to the ink. A drawn frame didn't show the miss, so this is the screen's own pixels (public text).
@Test func ocrReadsAWordEndOnTheWholeStrip() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/word-end-ing.png")
    let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let f = Frame(base: UnsafeRawPointer(ctx.data!), width: image.width, height: image.height, bytesPerRow: ctx.bytesPerRow)
    #expect(Ghost.read(try #require(Ghost.binarized(f, fromX: 0)), korean: false) == "ing")
}

/// The oracle waits for OCR before each key (up to 500 ms), so a warm read must be well inside a typing delay.
@Test func ocrIsQuickOnceWarm() {
    for korean in [false, true] {
        frame(typed: korean ? "오늘" : "Could you send", ghost: korean ? " 저녁에 만나요" : " me the file") { f, caret in
            let image = Ghost.binarized(f, fromX: caret + 1)!
            _ = Ghost.read(image, korean: korean)
            let times = (0..<5).map { _ in
                let t = Date()
                _ = Ghost.read(image, korean: korean)
                return Date().timeIntervalSince(t) * 1000
            }
            print("OCR \(korean ? "ko" : "en") warm ms:", times.map { Int($0) })
            #expect(Score.percentile(times, 0.5)! < 250)
        }
    }
}
}
