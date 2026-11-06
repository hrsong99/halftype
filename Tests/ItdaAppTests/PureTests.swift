import AppKit
import ItdaCore
import Testing
@testable import ItdaApp

@Suite struct SlicingTests {
    @Test func slicesBySelectionNotLength() throws {
        let t3Empty = try #require(Reader.slice("\n", CFRange(location: 0, length: 0)))
        #expect(t3Empty.before == "" && t3Empty.after == "\n")
        let trailing = try #require(Reader.slice("hello\n", CFRange(location: 5, length: 0)))
        #expect(trailing.before == "hello" && trailing.after == "\n")
    }
    @Test func utf16Offsets() throws {
        let s = try #require(Reader.slice("a😀한b", CFRange(location: 4, length: 0)))
        #expect(s.before == "a😀한" && s.after == "b")
    }
    @Test func selectionOrBadRangeGivesNothing() {
        #expect(Reader.slice("abc", CFRange(location: 1, length: 1)) == nil)
        #expect(Reader.slice("abc", CFRange(location: 9, length: 0)) == nil)
    }
}

@Suite struct CaretTests {
    let frame = CGRect(x: 100, y: 100, width: 500, height: 100)
    @Test func markerThenPreviousEachOnlyWithHeight() {
        let marker = CGRect(x: 120, y: 110, width: 0, height: 16)
        #expect(Reader.caretRect(marker: marker, previous: nil, frame: frame) == marker)
        // The height-0 sentinel from the spike falls through to the previous character's right edge.
        let sentinel = CGRect(x: 0, y: 1080, width: 0, height: 0)
        let previous = CGRect(x: 130, y: 110, width: 8, height: 17)
        #expect(Reader.caretRect(marker: sentinel, previous: previous, frame: frame) == CGRect(x: 138, y: 110, width: 0, height: 17))
        #expect(Reader.caretRect(marker: sentinel, previous: sentinel, frame: frame) == nil)
        #expect(Reader.caretRect(marker: nil, previous: nil, frame: frame) == nil)
    }
    @Test func lineBoxUsesItsOrigin() {
        let box = CGRect(x: 120, y: 110, width: 300, height: 23)
        #expect(Reader.caretRect(marker: box, previous: nil, frame: frame)?.minX == 120)
    }
    @Test func outsideTheFieldIsNoCaret() {
        #expect(Reader.caretRect(marker: CGRect(x: 120, y: 400, width: 0, height: 16), previous: nil, frame: frame) == nil)
    }
}

@Suite struct CoordinateTests {
    @Test func flipsAroundPrimaryOnly() {
        // Primary 1000 high. A display above it has negative AX y, one below goes past 1000, and x carries through.
        let primary = GhostLayout.appKitRect(CGRect(x: 10, y: 20, width: 30, height: 40), primaryHeight: 1000)
        #expect(primary == CGRect(x: 10, y: 940, width: 30, height: 40))
        let above = GhostLayout.appKitRect(CGRect(x: 10, y: -500, width: 30, height: 40), primaryHeight: 1000)
        #expect(above == CGRect(x: 10, y: 1460, width: 30, height: 40))
        let belowLeft = GhostLayout.appKitRect(CGRect(x: -1920, y: 1200, width: 30, height: 40), primaryHeight: 1000)
        #expect(belowLeft == CGRect(x: -1920, y: -240, width: 30, height: 40))
    }
}

@Suite struct WrapTests {
    func spec(_ text: String, caretX: CGFloat, frame: CGRect, lineLeft: CGFloat? = 110, mayWrap: Bool = true) -> GhostSpec {
        GhostSpec(text: text, caret: CGRect(x: caretX, y: frame.minY + 4, width: 0, height: 17), frame: frame, fontSize: 14, fontName: nil, color: nil,
                  lineLeft: lineLeft, previousCharacter: "a", mayWrap: mayWrap)
    }
    let single = CGRect(x: 100, y: 100, width: 300, height: 26)
    let tall = CGRect(x: 100, y: 100, width: 300, height: 200)

    @Test func fitsOnOneLine() throws {
        let l = try #require(GhostLayout.make(spec(" are we there", caretX: 150, frame: single)))
        #expect(l.visibleText == " are we there")
    }
    @Test func singleLineCutsAtAWord() throws {
        let l = try #require(GhostLayout.make(spec(" one two three four five six seven", caretX: 300, frame: single)))
        #expect(l.visibleText != " one two three four five six seven")
        #expect(l.visibleText.hasPrefix(" one"))
        #expect(!l.visibleText.trimmingCharacters(in: .whitespaces).hasSuffix("thr"))
    }
    @Test func tallFieldWraps() throws {
        let text = " one two three four five six seven"
        let l = try #require(GhostLayout.make(spec(text, caretX: 300, frame: tall)))
        #expect(l.visibleText == text)
    }
    @Test func textBelowCaretKeepsItOnOneLine() throws {
        let text = " one two three four five six seven"
        let l = try #require(GhostLayout.make(spec(text, caretX: 300, frame: tall, mayWrap: false)))
        #expect(l.visibleText != text)
    }
    @Test func midWordWithNoRoomIsNoGhost() {
        #expect(GhostLayout.make(spec("continuation", caretX: 370, frame: single)) == nil)
        #expect(GhostLayout.make(spec("continuation", caretX: 370, frame: tall)) == nil)
    }
    @Test func noLineLeftMeansNoWrap() throws {
        let text = " one two three four five six seven"
        let l = try #require(GhostLayout.make(spec(text, caretX: 300, frame: tall, lineLeft: nil)))
        #expect(l.visibleText != text)
    }
    @Test func lineLeftOutsideTheFieldIsIgnored() throws {
        // T3 can report the whole pane as the line. Without a real left edge there's no wrapping.
        let text = " one two three four five six seven"
        let l = try #require(GhostLayout.make(spec(text, caretX: 300, frame: tall, lineLeft: 12)))
        #expect(l.visibleText != text)
    }
    @Test func windowIsWholePoints() throws {
        let l = try #require(GhostLayout.make(spec(" x", caretX: 150.4, frame: single)))
        #expect(l.window.origin.x == l.window.origin.x.rounded() && l.window.origin.y == l.window.origin.y.rounded())
    }
}

@Suite struct KeyTests {
    func decide(_ code: Int64, _ flags: CGEventFlags = [], own: Bool = false, armed: Bool = true, type: CGEventType = .keyDown) -> KeyTap.Decision {
        KeyTap.decide(type: type, keyCode: code, flags: flags, own: own, armed: armed)
    }
    @Test func tabOnlyWhenArmed() {
        #expect(decide(48) == .accept(all: false))
        #expect(decide(48, .maskShift) == .accept(all: true))
        #expect(decide(48, armed: false) == .pass)
        #expect(decide(48, own: true) == .pass)
        #expect(decide(48, .maskCommand) == .pass)
        #expect(decide(48, [.maskShift, .maskAlternate]) == .pass)
        #expect(decide(0) == .pass)
    }
    @Test func reenables() {
        #expect(decide(0, type: .tapDisabledByTimeout, ) == .reenable)
        #expect(decide(0, armed: false, type: .tapDisabledByUserInput) == .reenable)
    }
    @Test func onlyAnUnmodifiedLetterKeepsASyllableOpen() {
        #expect(KeyTap.composes(type: .keyDown, keyCode: 5, flags: []))
        #expect(KeyTap.composes(type: .keyDown, keyCode: 5, flags: .maskShift))
        #expect(!KeyTap.composes(type: .keyDown, keyCode: 5, flags: .maskCommand))
        #expect(!KeyTap.composes(type: .keyDown, keyCode: 49, flags: []))  // space
        #expect(!KeyTap.composes(type: .keyDown, keyCode: 51, flags: []))  // delete
        #expect(!KeyTap.composes(type: .keyDown, keyCode: 123, flags: []))  // left arrow
        #expect(!KeyTap.composes(type: .leftMouseDown, keyCode: 5, flags: []))
    }
    @Test func twoSetCoversEveryJamoTheCoreCanAskFor() throws {
        // All the keys of every syllable, by Hangul's own tables.
        for scalar in stride(from: 0xAC00, through: 0xD7A3, by: 1) {
            let keys = Hangul.keys(String(Unicode.Scalar(UInt32(scalar))!))
            #expect(TwoSetLayout.strokes(keys) != nil, "\(keys)")
        }
        #expect(TwoSetLayout.strokes("ㅃ")?.first?.shift == true && TwoSetLayout.strokes("ㅂ")?.first?.shift == false)
        #expect(TwoSetLayout.strokes("a") == nil)
    }
    @Test func chunksKeepCharactersWhole() {
        let family = "👨‍👩‍👧‍👦"
        let text = String(repeating: "한", count: 15) + family + "abc"
        let chunks = Inserter.chunks(text)
        #expect(chunks.allSatisfy { $0.count <= Inserter.chunkUnits || String(utf16CodeUnits: $0, count: $0.count) == family })
        #expect(chunks.map { String(utf16CodeUnits: $0, count: $0.count) }.joined() == text)
        #expect(!chunks.contains { $0.last.map(UTF16.isLeadSurrogate) ?? false })
    }
}

@Suite struct ModelTests {
    @Test func verifiesSizeAndHash() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(try ModelStore.verify(file, size: 3, sha256: abc))
        #expect(try !ModelStore.verify(file, size: 4, sha256: abc))
        #expect(try !ModelStore.verify(file, size: 3, sha256: String(repeating: "0", count: 64)))
    }
}
