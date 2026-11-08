import AppKit
import HalftypeCore
import HalftypeEngine
import class SwiftUI.NSHostingView
import class SwiftUI.ImageRenderer
import struct SwiftUI.ProposedViewSize
import Synchronization
import Testing
@testable import HalftypeApp

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
    /// Blink reports the font size before page zoom, while the caret is on screen.
    @Test func pageZoomScalesTheFontOnlyFromAWebCaret() {
        let line = NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: 14))
        func size(caretHeight: CGFloat, web: Bool) -> CGFloat {
            var s = spec(" x", caretX: 150, frame: tall)
            s.caret.size.height = caretHeight
            s.webCaret = web
            return GhostLayout.font(s).pointSize
        }
        #expect(abs(size(caretHeight: line * 1.5, web: true) - 21) < 0.01)
        #expect(abs(size(caretHeight: line * 1.25, web: true) - 17.5) < 0.01)  // Cmd-= twice in a browser.
        #expect(size(caretHeight: line, web: true) == 14)
        #expect(size(caretHeight: line * 1.1, web: true) == 14)  // Another font's glyph box at 100%.
        #expect(size(caretHeight: line * 1.5, web: false) == 14)  // A native rect, or a line box.
        #expect(abs(size(caretHeight: line * 0.86, web: true) - 14 * 0.86) < 0.01)  // The band is 1/1.15, about 0.87, below.
        // A page font whose line is 0.9 of ours: at 125% the ratio is 1.125, inside the band, so no change. At 150% the ghost
        // follows the caret, 1.35, not the zoom. Both are the estimate's known limits, for live step 20 to judge.
        #expect(size(caretHeight: line * 0.9 * 1.25, web: true) == 14)
        #expect(abs(size(caretHeight: line * 0.9 * 1.5, web: true) - 14 * 1.35) < 0.01)
    }
    @Test func aWebCaretIsASliverMidLine() {
        #expect(Reader.isWebCaret(marker: CGRect(x: 746, y: 969, width: 0, height: 16), before: "ab"))
        #expect(!Reader.isWebCaret(marker: CGRect(x: 738, y: 966, width: 702, height: 23), before: "ab"))  // T3's line box.
        #expect(!Reader.isWebCaret(marker: CGRect(x: 738, y: 966, width: 0, height: 23), before: "ab\n"))
        #expect(!Reader.isWebCaret(marker: CGRect(x: 738, y: 966, width: 0, height: 23), before: ""))
    }
}

@Suite struct ParagraphTests {
    @Test func theCaretIsMovedPastTheNewlinesTheRangesLeaveOut() {
        #expect(Reader.valueIndex(of: "abcdef", in: "abc\ndef") == 7)
        #expect(Reader.valueIndex(of: "abc", in: "a\nb\nc") == 5)
        #expect(Reader.valueIndex(of: "😀ab", in: "😀a\nb") == 5)
        #expect(Reader.valueIndex(of: "a\nbc", in: "a\nb\nc") == 5)  // A soft break is in both; a paragraph only in the value.
        #expect(Reader.valueIndex(of: "abX", in: "abc\ndef") == nil)
        #expect(Reader.valueIndex(of: "abcdefg", in: "abc\ndef") == nil)
    }
    /// `web`: the field has text markers, as Chromium's and WebKit's do and a native view's don't.
    func read(_ value: String, caret: Int, ranged: String?, web: Bool = true) -> Reading? {
        var range = CFRange(location: caret, length: 0)
        var attributes: [String: CFTypeRef] = ["AXRole": "AXTextArea" as CFString, "AXValue": value as CFString,
                                               "AXSelectedTextRange": AXValueCreate(.cfRange, &range)!]
        if web { attributes["AXSelectedTextMarkerRange"] = "marker" as CFString }
        return Reader.read(AXUIElementCreateSystemWide(), get: { attributes[$1] }, settable: { _ in true }, upTo: { _, _ in ranged })
    }
    @Test func secondParagraphReadsToTheCaret() {
        #expect(read("abc\ndef", caret: 6, ranged: "abcdef")?.field == Field(before: "abc\ndef", after: ""))
        #expect(read("a\nb\nc", caret: 3, ranged: "abc")?.field == Field(before: "a\nb\nc", after: ""))
        #expect(read("a\nb\nc", caret: 3, ranged: "abc")?.skipped == 2)
    }
    @Test func softBreaksAreLeftAlone() {
        #expect(read("ab\ncd", caret: 5, ranged: "ab\ncd")?.field == Field(before: "ab\ncd", after: ""))
        #expect(read("ab\ncd", caret: 5, ranged: "ab\ncd")?.skipped == 0)
    }
    @Test func aWebOffsetThatCantBeCheckedIsNotRead() {
        #expect(read("a\nb\nc", caret: 3, ranged: nil) == nil)  // Failed or timed out: would continue `b` with the caret after `c`.
        #expect(read("a\nb\nc", caret: 3, ranged: "a") == nil)  // Cut short, though it starts the value.
        #expect(read("abc\ndef", caret: 6, ranged: "abcxyz") == nil)  // Doesn't line up.
    }
    @Test func aFailedMarkerQueryIsNoProofOfNativeOffsets() {
        // Range read and marker query both fail, as a timed-out web view's do: still no reading.
        #expect(read("a\nb\nc", caret: 3, ranged: nil, web: false) == nil)
        #expect(read("a\nb\nc", caret: 3, ranged: "a", web: false) == nil)
        // A native view answers the range read, with the same text.
        #expect(read("ab\ncd", caret: 2, ranged: "ab", web: false)?.field == Field(before: "ab", after: "\ncd"))
    }
    @Test func rangeReadsAfterAlignmentAreAskedInTheHostsOwnOffsets() throws {
        let reading = try #require(read("abc\ndef", caret: 6, ranged: "abcdef"))
        let previous = try #require(Reader.previousRange(reading.field.before, skipped: reading.skipped))
        #expect(previous.location == 5 && previous.length == 1)  // `f`, at 5 of the host's 6, not 6.
        #expect(Reader.lineStart(reading.field.before, skipped: reading.skipped) == 3)  // `d`.
        let emoji = try #require(Reader.previousRange("a\nb😀", skipped: 1))
        #expect(emoji.location == 2 && emoji.length == 2)
        #expect(Reader.lineStart("abc", skipped: 0) == 0)
    }
}

@Suite struct PrimingTests {
    let enhanced = Priming.enhanced, manual = Priming.manual
    let start = Date(timeIntervalSince1970: 0)
    func process(_ pid: pid_t, launched: Double = 0) -> Priming.Process { .init(pid: pid, launched: Date(timeIntervalSince1970: launched)) }
    func ours(_ priming: Priming) -> Set<pid_t> { Set(priming.ours(launched: { _ in Date(timeIntervalSince1970: 0) })) }

    @Test func electronIsSetOnceAndKeptAtQuit() {
        var priming = Priming(), kinds = 0
        #expect(priming.next(process(1), now: start, kind: { kinds += 1; return manual }, voiceOver: { true }, isOn: { false }) == manual)
        #expect(priming.next(process(1), now: start + 60, kind: { kinds += 1; return manual }, voiceOver: { false }, isOn: { false }) == nil)
        #expect(kinds == 1 && ours(priming).isEmpty)
    }
    @Test func chromiumIsSetOnlyIfOffAndClearedOnlyIfOurs() {
        var priming = Priming()
        #expect(priming.next(process(1), now: start, kind: { enhanced }, voiceOver: { false }, isOn: { true }) == nil)
        #expect(priming.next(process(2), now: start, kind: { enhanced }, voiceOver: { false }, isOn: { false }) == enhanced)
        #expect(priming.next(process(3), now: start, kind: { enhanced }, voiceOver: { false }, isOn: { nil }) == enhanced)
        #expect(ours(priming) == [2, 3])
    }
    @Test func chromiumIsSetAgainOnlyPastItsWaitAndOnlyIfItReadsOff() {
        var priming = Priming(), reads = 0
        func next(_ pid: pid_t, _ t: Double, _ on: Bool?) -> String? {
            priming.next(process(pid), now: start + t, kind: { enhanced }, voiceOver: { false }, isOn: { reads += 1; return on })
        }
        #expect(next(1, 0, false) == enhanced)
        reads = 0
        #expect(next(1, 2, false) == nil && reads == 0)  // Within the wait a set would restart it, so the flag isn't even read.
        #expect(next(1, 4, nil) == nil)  // A failed read isn't "off".
        #expect(next(1, 8, false) == enhanced)
        #expect(next(1, 12, true) == nil)
        // Someone else's flag, cleared later and set by us, is then ours to clear.
        #expect(next(2, 0, true) == nil)
        #expect(next(2, 4, false) == enhanced)
        #expect(ours(priming).contains(2))
    }
    @Test func voiceOverIsAskedAtEachSetNotRemembered() {
        var priming = Priming(), voiceOver = true, kinds = 0
        func next(_ pid: pid_t, _ t: Double) -> String? {
            priming.next(process(pid), now: start + t, kind: { kinds += 1; return enhanced }, voiceOver: { voiceOver }, isOn: { false })
        }
        #expect(next(1, 0) == nil)  // On: VoiceOver holds the flag.
        voiceOver = false
        #expect(next(1, 1) == enhanced)  // Off: never set, so no wait to restart.
        #expect(next(2, 0) == enhanced)
        voiceOver = true
        #expect(next(2, 10) == nil)  // On again: not set again.
        #expect(kinds == 2)
    }
    @Test func aReusedPidIsANewProcessAndTheOldOneIsNotRestored() {
        var priming = Priming(), kinds = 0
        #expect(priming.next(process(7, launched: 100), now: start, kind: { kinds += 1; return enhanced }, voiceOver: { false }, isOn: { false }) == enhanced)
        // The browser quit and pid 7 went to a native app.
        #expect(priming.next(process(7, launched: 200), now: start + 1, kind: { kinds += 1; return nil }, voiceOver: { false }, isOn: { false }) == nil)
        #expect(kinds == 2)
        #expect(priming.ours(launched: { _ in Date(timeIntervalSince1970: 200) }).isEmpty)
        #expect(priming.ours(launched: { _ in Date(timeIntervalSince1970: 100) }) == [7])
        #expect(priming.ours(launched: { _ in nil }).isEmpty)  // Gone.
    }
    @Test func anUnknownLaunchTimeIsNeverTheSameProcess() {
        var priming = Priming(), kinds = 0
        func next(_ p: Priming.Process, _ t: Double) -> String? {
            priming.next(p, now: start + t, kind: { kinds += 1; return enhanced }, voiceOver: { false }, isOn: { false })
        }
        let unknown = Priming.Process(pid: 7, launched: nil)
        #expect(next(unknown, 0) == enhanced)
        #expect(next(unknown, 1) == nil)  // One binding still sets it once.
        #expect(priming.ours(launched: { _ in nil }).isEmpty)  // Never restored: pid 7 may be another app's by quit.
        priming.bound(unknown)
        #expect(next(unknown, 2) == enhanced && kinds == 2)  // Bound again, it's primed again.
        let known = process(8, launched: 5)
        #expect(next(known, 0) == enhanced)
        priming.bound(known)
        #expect(next(known, 1) == nil && kinds == 3)  // A known process keeps what was learnt.
    }
    @Test func nativeAppsAreAskedOnceAndGetNothing() {
        var priming = Priming(), kinds = 0
        for t in [0.0, 5, 10] {
            #expect(priming.next(process(1), now: start + t, kind: { kinds += 1; return nil }, voiceOver: { false }, isOn: { false }) == nil)
        }
        #expect(kinds == 1 && ours(priming).isEmpty)
    }
    @Test func aBurstOfInputAgainstABlockedHostRunsOneRecoveryAndThenAgain() {
        let queue = DispatchQueue(label: "test.heal"), gate = DispatchSemaphore(value: 0), job = OneAtATime()
        let runs = Atomic<Int>(0), seenByBind = Atomic<Int>(-1)
        job.run(on: queue) { gate.wait(); runs.add(1, ordering: .relaxed) }  // A host that doesn't answer.
        for _ in 0..<100 { job.run(on: queue) { runs.add(1, ordering: .relaxed) } }
        queue.async { seenByBind.store(runs.load(ordering: .relaxed), ordering: .relaxed) }  // A bind after the burst.
        gate.signal()
        queue.sync {}
        #expect(runs.load(ordering: .relaxed) == 1 && seenByBind.load(ordering: .relaxed) == 1)
        job.run(on: queue) { runs.add(1, ordering: .relaxed) }
        queue.sync {}
        #expect(runs.load(ordering: .relaxed) == 2)
    }
    @Test func chromiumIsKnownByItsRendererHelper() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("halftype-bundles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        func make(_ path: String) throws { try FileManager.default.createDirectory(at: dir.appendingPathComponent(path), withIntermediateDirectories: true) }
        try make("Chat.app/Contents/Frameworks/Chat Helper (Renderer).app")  // Electron.
        try make("Browser.app/Contents/Frameworks/Browser Framework.framework/Versions/1.2.3/Helpers/Browser Helper (Renderer).app")
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("Browser.app/Contents/Frameworks/Browser Framework.framework/Versions/Current").path,
                                                   withDestinationPath: "1.2.3")
        try make("Notes.app/Contents/Frameworks/Sparkle.framework/Versions/B/Helpers/Updater.app")
        try make("Bare.app/Contents/MacOS")
        #expect(Priming.shipsChromium(dir.appendingPathComponent("Chat.app")))
        #expect(Priming.shipsChromium(dir.appendingPathComponent("Browser.app")))
        #expect(!Priming.shipsChromium(dir.appendingPathComponent("Notes.app")))
        #expect(!Priming.shipsChromium(dir.appendingPathComponent("Bare.app")))
        #expect(!Priming.shipsChromium(dir.appendingPathComponent("Missing.app")))
    }
}

@Suite struct KeyTests {
    func decide(_ code: Int64, _ flags: CGEventFlags = [], armed: Bool = true, type: CGEventType = .keyDown) -> KeyTap.Decision {
        KeyTap.decide(type: type, keyCode: code, flags: flags, armed: armed)
    }
    @Test func tabOnlyWhenArmed() {
        #expect(decide(48) == .accept(all: false))
        #expect(decide(48, .maskShift) == .accept(all: true))
        #expect(decide(48, armed: false) == .pass)
        #expect(decide(48, .maskCommand) == .pass)
        #expect(decide(48, [.maskShift, .maskAlternate]) == .pass)
        #expect(decide(0) == .pass)
    }
    @Test func escStopsAtAnArmedGhostAndForceQuitNeverDoes() {
        #expect(decide(53) == .dismiss(swallow: true))
        #expect(decide(53, armed: false) == .dismiss(swallow: false))
        #expect(decide(53, .maskShift) == .dismiss(swallow: true))
        #expect(decide(53, [.maskCommand, .maskAlternate]) == .dismiss(swallow: false))
    }
    @Test func anAcceptIsReportedAndNothingElseIs() {
        let accepts = Atomic<Int>(0)
        let tap = KeyTap()
        tap.onAccept = { _, _, _ in accepts.add(1, ordering: .relaxed) }
        #expect(!press(tap, key(48)).swallowed && accepts.load(ordering: .relaxed) == 0)  // No ghost: the app's Tab.
        armed(tap, Ghost(remainder: " there"))
        _ = press(tap, key(53))
        #expect(accepts.load(ordering: .relaxed) == 0)
        armed(tap, Ghost(remainder: " there"))
        #expect(press(tap, key(48)).swallowed && accepts.load(ordering: .relaxed) == 1)
    }
    @Test func escHidesTheGhostOnceThenIsTheApps() {
        let dismissed = Atomic<Int>(0)
        let tap = KeyTap()
        tap.onDismiss = { dismissed.add(1, ordering: .relaxed) }
        armed(tap, Ghost(remainder: " there"))
        #expect(press(tap, key(53)).swallowed)
        #expect(tap.state.withLock { $0.armed == nil } && dismissed.load(ordering: .relaxed) == 1)
        #expect(!press(tap, key(53)).swallowed)
    }
    @Test func escAimedAtAnotherAppIsThatApps() {
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there"))
        #expect(!press(tap, key(53, pid: 99)).swallowed)
        #expect(tap.state.withLock { $0.armed == nil })
    }
    @Test func reenables() {
        #expect(decide(0, type: .tapDisabledByTimeout, ) == .reenable)
        #expect(decide(0, armed: false, type: .tapDisabledByUserInput) == .reenable)
    }
    @Test func onlyALetterOrABackspaceFromOneKeepsASyllableOpen() {
        func composes(after was: Bool = false, _ code: Int64, _ flags: CGEventFlags = [], type: CGEventType = .keyDown) -> Bool {
            KeyTap.composes(after: was, type: type, keyCode: code, flags: flags)
        }
        #expect(composes(5))
        #expect(composes(5, .maskShift))
        #expect(!composes(5, .maskCommand))
        #expect(!composes(after: true, 49))  // space
        #expect(composes(after: true, 51))  // delete, from a live syllable
        #expect(!composes(after: false, 51))
        #expect(!composes(after: true, 123))  // left arrow
        #expect(!composes(after: true, 5, type: .leftMouseDown))
    }

    // The transaction, through the callback's own code, with events no one receives.
    let pid: pid_t = 4242
    func key(_ code: CGKeyCode, pid target: pid_t = 4242, flags: CGEventFlags = []) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        event.flags = flags
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(target))
        return event
    }
    func armed(_ tap: KeyTap, _ ghost: Ghost, typesKeys: Bool = false, committed: String = "hello") {
        #expect(tap.arm(.init(pid: pid, ghost: ghost, typesKeys: typesKeys, committed: committed, before: committed), generation: tap.generation))
    }
    /// Text of Unicode events, jamo by key code.
    func press(_ tap: KeyTap, _ event: CGEvent, type: CGEventType = .keyDown) -> (swallowed: Bool, posted: [CGEvent]) {
        var posted: [CGEvent] = []
        let swallowed = tap.handle(type, event) { posted.append($0) }
        return (swallowed, posted)
    }
    func unicode(_ events: [CGEvent]) -> String {
        events.filter { $0.getIntegerValueField(.keyboardEventKeycode) == 0 && $0.type == .keyDown }.map {
            var length = 0, units = [UniChar](repeating: 0, count: 32)
            $0.keyboardGetUnicodeString(maxStringLength: 32, actualStringLength: &length, unicodeString: &units)
            return String(utf16CodeUnits: units, count: length)
        }.joined()
    }

    @Test func tabPostsAndSwallowsWithNoQueueAndDoubleTabNeedsNoRead() {
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there friend"))
        let first = press(tap, key(48))
        #expect(first.swallowed && unicode(first.posted) == " there")
        let second = press(tap, key(48))
        #expect(second.swallowed && unicode(second.posted) == " friend")
        #expect(tap.state.withLock { $0.armed == nil && $0.pending?.to == "hello there friend" && $0.pending?.from == "hello" })
        #expect(press(tap, key(48)).posted.isEmpty)  // Nothing left: held a moment for the next ghost, typing nothing.
    }
    @Test func aFastTabAfterTheLastWordIsHeldForTheNextGhost() {
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there"))
        #expect(unicode(press(tap, key(48)).posted) == " there")
        let generation = tap.generation
        let held = press(tap, key(48))  // Before the next ghost: ours, typing nothing, and no input.
        #expect(held.swallowed && held.posted.isEmpty && tap.generation == generation)
        #expect(!press(tap, key(48, pid: 99)).swallowed)  // Another app's Tab is its own.
        #expect(!press(tap, key(48, flags: .maskShift)).swallowed)  // Shift-Tab back a field is the app's, and ends the hold.
        #expect(!press(tap, key(48)).swallowed)
        armed(tap, Ghost(remainder: " there"))
        _ = press(tap, key(48))
        armed(tap, Ghost(remainder: " friend"))
        #expect(unicode(press(tap, key(48)).posted) == " friend")
        _ = press(tap, key(0))  // Any other key ends the hold.
        #expect(!press(tap, key(48)).swallowed)
    }
    @Test func theHoldEndsByItself() {
        let tap = KeyTap()
        tap.state.withLock { $0.holdFor = 0 }  // A host that refused the insert: no next ghost comes.
        armed(tap, Ghost(remainder: " there"))
        _ = press(tap, key(48))
        #expect(!press(tap, key(48)).swallowed)
    }
    @Test func tabThenReturnKeepsItsOrderAndDisarms() {
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there friend"))
        #expect(press(tap, key(48)).swallowed)
        let enter = press(tap, key(36))
        #expect(!enter.swallowed && enter.posted.isEmpty)
        #expect(!press(tap, key(48)).swallowed)
    }
    @Test func anyOtherKeyOrClickLeavesTabToTheApp() {
        for (type, event) in [(CGEventType.keyDown, key(0)), (.leftMouseDown, key(0)), (.rightMouseDown, key(0)), (.tapDisabledByTimeout, key(0))] {
            let tap = KeyTap()
            armed(tap, Ghost(remainder: " there"))
            _ = press(tap, event, type: type)
            let tab = press(tap, key(48))
            #expect(!tab.swallowed && tab.posted.isEmpty)
        }
    }
    @Test func onlyAnAcceptKeepsWhatTheLastAcceptPredicted() {
        func pending(_ tap: KeyTap) -> Bool { tap.state.withLock { $0.pending != nil } }
        for (type, event, code) in [(CGEventType.keyDown, key(51), "backspace"), (.keyDown, key(0), "letter"), (.leftMouseDown, key(0), "click"),
                                    (.keyDown, key(48, pid: 99), "another app's Tab"), (.keyDown, key(48, flags: .maskCommand), "cmd-Tab")] {
            let tap = KeyTap()
            armed(tap, Ghost(remainder: " there friend"))
            _ = press(tap, key(48))
            #expect(pending(tap), "\(code)")
            _ = press(tap, event, type: type)
            #expect(!pending(tap), "\(code)")
        }
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there friend"))
        _ = press(tap, key(48))
        _ = press(tap, key(48))  // Still the same run of inserts.
        #expect(pending(tap))
        tap.invalidate()  // Focus moved.
        #expect(!pending(tap))
    }
    @Test func optionAndControlTabPassAndDisarmShiftAloneAcceptsAll() {
        for flags in [CGEventFlags.maskAlternate, .maskControl, .maskCommand, [.maskShift, .maskAlternate], [.maskShift, .maskControl]] {
            let tap = KeyTap()
            armed(tap, Ghost(remainder: " there friend"))
            let tab = press(tap, key(48, flags: flags))
            #expect(!tab.swallowed && tab.posted.isEmpty)
            #expect(tap.state.withLock { $0.armed == nil })
        }
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there friend"))
        #expect(unicode(press(tap, key(48, flags: .maskShift)).posted) == " there friend")
    }
    @Test func shiftTabSharesTheHangulPlanAndCarriesExactlyTheFlagsOfEachKey() {
        let tap = KeyTap()
        armed(tap, Ghost(keys: "ㄴ", composing: "한", remainder: " 있어 값"), typesKeys: true, committed: "그 ")
        // Caps Lock on and Shift held, as in the event that reaches the tap: neither may reach what it posts.
        let posted = press(tap, key(48, flags: [.maskShift, .maskAlphaShift])).posted
        #expect(posted.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [1, 49, 2, 37, 17, 2, 38, 49, 15, 40, 12, 17])
        #expect(tap.state.withLock { $0.pending?.to == "그 한 있어 값" })
        #expect(posted.count == 24)  // Down and up, both carrying the flags.
        for (index, event) in posted.enumerated() {
            // ㅆ is the only shifted key: strokes 5 of 12.
            #expect(event.flags == (index / 2 == 4 ? .maskShift : []), "\(index)")
            #expect(event.getIntegerValueField(.eventSourceUserData) == KeyTap.ownEvent)
        }
        let tap2 = KeyTap()
        armed(tap2, Ghost(remainder: " there"))
        #expect(press(tap2, key(48, flags: [.maskShift, .maskAlphaShift])).posted.allSatisfy { $0.flags == [] })
    }
    @Test func ourOwnEventsReplayedMoveNothing() {
        let tap = KeyTap()
        armed(tap, Ghost(keys: "ㄴ", composing: "한", remainder: " 다음 날"), typesKeys: true, committed: "그 ")
        let posted = press(tap, key(48)).posted
        let before = tap.state.withLock { ($0.generation, $0.armed?.ghost.remainder, $0.composing, $0.pending?.to) }
        for event in posted {
            let replay = press(tap, event, type: event.type)
            #expect(!replay.swallowed && replay.posted.isEmpty)
        }
        let after = tap.state.withLock { ($0.generation, $0.armed?.ghost.remainder, $0.composing, $0.pending?.to) }
        #expect(before == after)
    }
    @Test func aHideAloneLeavesASnapshotGoodAndInputDoesnt() {
        let tap = KeyTap()
        let read = tap.generation
        tap.disarm()
        #expect(tap.arm(.init(pid: pid, ghost: Ghost(remainder: "x"), typesKeys: false, committed: "", before: ""), generation: read))
        _ = press(tap, key(0))
        #expect(!tap.arm(.init(pid: pid, ghost: Ghost(remainder: "x"), typesKeys: false, committed: "", before: ""), generation: read))
    }
    @Test func anotherAppsTabPasses() {
        let tap = KeyTap()
        armed(tap, Ghost(remainder: " there"))
        let tab = press(tap, key(48, pid: 99))
        #expect(!tab.swallowed && tab.posted.isEmpty)
    }
    @Test func aStaleDrawCantArm() {
        let tap = KeyTap()
        let before = tap.generation
        tap.invalidate()
        #expect(!tap.arm(.init(pid: pid, ghost: Ghost(remainder: "x"), typesKeys: false, committed: "", before: ""), generation: before))
        let keyed = tap.generation
        _ = press(tap, key(0))
        #expect(!tap.arm(.init(pid: pid, ghost: Ghost(remainder: "x"), typesKeys: false, committed: "", before: ""), generation: keyed))
    }
    @Test func hangulIsTypedAndLeavesTheLastSyllableOpen() {
        let tap = KeyTap()
        armed(tap, Ghost(keys: "ㄴ", composing: "한", remainder: " 다음, 3"), typesKeys: true, committed: "그 ")
        let posted = press(tap, key(48)).posted.filter { $0.type == .keyDown }
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [1, 49, 14, 40, 2, 46, 0])  // ㄴ space ㄷㅏㅇㅡㅁ
        #expect(tap.state.withLock { $0.composing && $0.pending?.to == "그 한 다음" })
        _ = press(tap, key(48))  // Ends in a digit: nothing open.
        #expect(tap.state.withLock { !$0.composing })
    }
    @Test func typableStopsAtWhatTheLayoutCantType() {
        #expect(TwoSetLayout.typable("전거 file") == "전거")
        #expect(TwoSetLayout.typable(" 다음, 3시에!") == " 다음, 3시에!")
        #expect(TwoSetLayout.typable(" file") == "")
        #expect(TwoSetLayout.typable(", file") == "")
        #expect(TwoSetLayout.typable("끝 😀") == "끝")
    }
    @Test func rightToLeftOnTheCaretsLineIsNoGhost() {
        #expect(Reader.isRightToLeft("hello שלום", " x"))
        #expect(Reader.isRightToLeft("hello", " مرحبا"))
        #expect(!Reader.isRightToLeft("שלום\nhello", " 안녕"))
    }
    @Test func twoSetCoversEveryJamoTheCoreCanAskFor() throws {
        // All the keys of every syllable, by Hangul's own tables.
        for scalar in stride(from: 0xAC00, through: 0xD7A3, by: 1) {
            let keys = Hangul.keys(String(Unicode.Scalar(UInt32(scalar))!))
            #expect(TwoSetLayout.strokes(keys) != nil, "\(keys)")
        }
        #expect(TwoSetLayout.strokes("ㅃ")?.first?.shift == true && TwoSetLayout.strokes("ㅂ")?.first?.shift == false)
        #expect(TwoSetLayout.strokes("a") == nil)
        #expect(TwoSetLayout.strokes("?")?.first?.shift == true && TwoSetLayout.strokes(" ")?.first?.code == 49)
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

/// A tap with a port no event reaches, whose system can refuse it, and whose obstacle is the test's to set.
final class FakeTap: KeyTap, @unchecked Sendable {
    let refusals = Atomic<Int>(0), attempts = Atomic<Int>(0)
    let blocked = Mutex<Obstacle?>(nil)
    override var obstacle: Obstacle? { blocked.withLock { $0 } }
    override func createPort() -> CFMachPort? {
        attempts.add(1, ordering: .relaxed)
        if refusals.load(ordering: .relaxed) > 0 {
            refusals.subtract(1, ordering: .relaxed)
            return nil
        }
        return CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
    }
}

/// The real `show`, never ordered onto the screen.
final class QuietPanel: GhostPanel {
    var stranded = false
    /// Runs inside a draw, as input arriving mid-draw does; `refuses` makes the draw find no room.
    var onShow: (() -> Void)?
    var refuses = false
    /// Draws only this many characters, as a narrow field does.
    var fits: Int?
    override var isOnActiveSpace: Bool { !stranded }
    override func show(_ spec: GhostSpec) -> String? {
        onShow?()
        guard !refuses, let drawn = super.show(spec) else { return nil }
        return fits.map { String(drawn.prefix($0)) } ?? drawn
    }
    override func orderFrontRegardless() {}
}

final class CountingCompleter: Completer, @unchecked Sendable {
    let text: String
    let asks = Atomic<Int>(0), unloads = Atomic<Int>(0)
    var onAsk: (@Sendable () -> Void)?
    var gate: Double? = 0
    /// False answers nil, the model's "nothing to suggest".
    var answers = true
    /// True answers, then stops short with nil, as a decode failure after streaming does.
    var stopsShort = false
    init(_ text: String) { self.text = text }
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void) {
        asks.add(1, ordering: .relaxed)
        onAsk?()
        onResult(answers ? Suggestion(text: text, gate: gate) : nil)
        if stopsShort { onResult(nil) }
    }
    func cancel() {}
    func unload() { unloads.add(1, ordering: .relaxed) }
}

final class ClosingCompleter: Completer, @unchecked Sendable {
    let onClose: @Sendable () -> Void
    init(_ onClose: @escaping @Sendable () -> Void) { self.onClose = onClose }
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void) {}
    func cancel() {}
    func unload() {}
    func close() { onClose() }
}

/// Polled, as hiding and drawing go through the main queue.
@MainActor func soon(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@Suite struct TapLifetimeTests {
    func until(_ condition: () -> Bool) -> Bool {
        for _ in 0..<300 {
            if condition() { return true }
            usleep(10_000)
        }
        return condition()
    }

    @Test func downLeavesNothingToAcceptAndNoPort() throws {
        let tap = FakeTap()
        defer { tap.close() }
        #expect(tap.start())
        let port = try #require(tap.state.withLock { $0.port })
        let generation = tap.generation
        #expect(tap.arm(.init(pid: 1, ghost: Ghost(remainder: " there"), typesKeys: false, committed: "", before: ""), generation: generation))
        tap.state.withLock { $0.pending = ("a", "b") }
        tap.stop()
        #expect(tap.state.withLock { $0.armed == nil && $0.pending == nil && $0.port == nil })
        #expect(!CFMachPortIsValid(port))
        // A draw already on its way can't arm over the tap's going.
        #expect(!tap.arm(.init(pid: 1, ghost: Ghost(remainder: "x"), typesKeys: false, committed: "", before: ""), generation: generation))
        tap.stop()  // Twice is nothing.
    }
    @Test func aRefusedTapIsRetriedUntilItComesUpAndThenNothingPolls() {
        let tap = FakeTap(retryEvery: 0.01)
        defer { tap.close() }
        let ups = Mutex<[Bool]>([])
        tap.onUp = { up in ups.withLock { $0.append(up) } }
        tap.refusals.store(3, ordering: .relaxed)
        #expect(!tap.hold())
        #expect(until { ups.withLock { $0 } == [true] })
        let attempts = tap.attempts.load(ordering: .relaxed)
        #expect(attempts == 4)
        usleep(100_000)
        #expect(tap.attempts.load(ordering: .relaxed) == attempts)
    }
    @Test func aRevokeTakesItDownAndTellsAndAGrantBringsItBack() {
        let tap = FakeTap(retryEvery: 0.01)
        defer { tap.close() }
        let ups = Mutex<[Bool]>([])
        tap.onUp = { up in ups.withLock { $0.append(up) } }
        #expect(tap.hold())
        #expect(ups.withLock { $0 } == [true])
        tap.refusals.store(2, ordering: .relaxed)
        tap.keeper.sync { tap.permissionChanged() }
        #expect(tap.state.withLock { $0.port == nil })
        #expect(until { ups.withLock { $0 } == [true, false, true] })
        #expect(tap.state.withLock { $0.port != nil })
    }
    @Test func anotherAppsPermissionLeavesTrustAlone() {
        let tap = FakeTap(retryEvery: 0.01)
        defer { tap.close() }
        let ups = Mutex<[Bool]>([])
        tap.onUp = { up in ups.withLock { $0.append(up) } }
        #expect(tap.hold())
        tap.keeper.sync { tap.permissionChanged() }
        #expect(until { tap.state.withLock { $0.port != nil } })
        #expect(ups.withLock { $0 } == [true])
    }
    @Test func aLateThreadOfAStoppedTapCantTakeTheNewOnesPlace() throws {
        let tap = FakeTap()
        defer { tap.close() }
        let old = try #require(tap.createPort()), current = try #require(tap.createPort())
        let mine = CFRunLoopGetCurrent()!, stale = CFRunLoopGetMain()!
        tap.state.withLock { ($0.port, $0.loop) = (current, mine) }
        #expect(!tap.claim(old, loop: stale))
        #expect(tap.state.withLock { $0.loop === mine })
        #expect(tap.claim(current, loop: mine))
    }
    @Test func closeEndsTheThreadTheRetryAndTheNews() {
        weak var gone: FakeTap?
        // The pool: the test thread's own keeps anything a `keeper.sync` closure captured until the test ends.
        autoreleasepool {
            let tap = FakeTap(retryEvery: 0.01)
            gone = tap
            #expect(tap.hold())
            tap.keeper.sync { tap.permissionChanged() }  // A retry now pending.
            tap.close()
            let attempts = tap.attempts.load(ordering: .relaxed)
            tap.keeper.sync {}
            usleep(50_000)
            #expect(tap.attempts.load(ordering: .relaxed) == attempts && tap.state.withLock { $0.port == nil })
        }
        // The tap thread holds the tap until its run loop ends.
        #expect(until { gone == nil })
    }
    @Test func noPortIsAnObstacle() {
        #expect(KeyTap().obstacle == .tapOff && !KeyTap().canTake)
    }
}

@Suite struct ReadTests {
    /// A host, with what it's asked written down.
    final class Host {
        var attributes: [String: CFTypeRef] = ["AXRole": "AXTextArea" as CFString, "AXValue": "hello" as CFString]
        var settable = true
        var asked: [String] = []
        init() {
            var caret = CFRange(location: 5, length: 0)
            attributes["AXSelectedTextRange"] = AXValueCreate(.cfRange, &caret)!
        }
        func read() -> Reading? {
            Reader.read(AXUIElementCreateSystemWide(), get: { _, key in self.asked.append(key); return self.attributes[key] }, settable: { _ in self.settable })
        }
    }
    @Test func aFieldThatTurnsSecureInPlaceIsNeverAskedItsValue() {
        let host = Host()
        #expect(host.read()?.field.before == "hello")
        #expect(host.asked.prefix(3) == ["AXRole", "AXSubrole", "AXValue"])
        host.asked = []
        host.attributes["AXSubrole"] = "AXSecureTextField" as CFString
        #expect(host.read() == nil)
        #expect(!host.asked.contains("AXValue"))
    }
    @Test func aFieldThatGoesReadOnlyOrChangesRoleIsNeverAskedItsValue() {
        let host = Host()
        host.settable = false
        #expect(host.read() == nil && !host.asked.contains("AXValue"))
        host.settable = true
        host.asked = []
        host.attributes["AXRole"] = "AXStaticText" as CFString
        #expect(host.read() == nil && !host.asked.contains("AXValue"))
    }
}

/// `update` to the armed ghost, with a fake host, model and tap, and the real layout.
@Suite @MainActor struct GhostPathTests {
    let single = CGRect(x: 100, y: 100, width: 300, height: 26)
    let tap = FakeTap()
    let panel = QuietPanel()
    let keys = KeyTests()
    let host = FakeField()

    /// What the field holds now, and how often it was read.
    final class FakeField: @unchecked Sendable {
        let now = Mutex<(field: Field, caretX: CGFloat)>((Field(before: ""), 300))
        let reads = Atomic<Int>(0)
        let caretless = Atomic<Bool>(false)
    }

    func watcher(_ field: Field, marked: Bool = false, completer: Completer?) -> Watcher {
        let watcher = Watcher(tap: tap, panel: panel)
        let frame = single, host = host
        host.now.withLock { $0.field = field }
        watcher.focused = AXUIElementCreateSystemWide()
        watcher.completer = completer
        watcher.read = { _ in
            host.reads.add(1, ordering: .relaxed)
            let (field, caretX) = host.now.withLock { $0 }
            let caret = host.caretless.load(ordering: .relaxed) ? nil : CGRect(x: caretX, y: frame.minY + 4, width: 0, height: 17)
            return Reading(field: field, caret: caret, frame: frame, marked: marked)
        }
        watcher.traits = { _, _ in FieldTraits(fontSize: 14, fontName: nil, color: nil, lineLeft: 110) }
        return watcher
    }
    func armed() -> KeyTap.Armed? { tap.state.withLock { $0.armed } }

    /// The reason the watcher settled on for one field, and how many changes it reported.
    func why(_ field: Field, completer: Completer? = CountingCompleter(" there friend"), _ setup: (Watcher) -> Void = { _ in }) async -> (Watcher.Why, Int) {
        let seen = Mutex<(Watcher.Why, Int)>((.unreadable, 0))
        let watcher = watcher(field, completer: completer)
        watcher.onWhy = { why, _ in seen.withLock { $0 = (why, $0.1 + 1) } }
        setup(watcher)
        watcher.scheduleUpdate()
        await watcher.settle()
        watcher.redraw()  // The same again, which is no change.
        await watcher.settle()
        let result = seen.withLock { $0 }
        watcher.hideNow()
        return result
    }
    @Test func eachPlaceThePathStopsSaysWhyOnce() async {
        #expect(await why(Field(before: "hello")) == (.shown, 1))
        #expect(await why(Field(before: "")) == (.idle, 1))
        #expect(await why(Field(before: "hello", after: "x")) == (.textAfter, 1))
        #expect(await why(Field(before: "hello"), completer: nil) == (.noModel, 1))
        let unsure = CountingCompleter(" there friend")
        unsure.gate = -5
        #expect(await why(Field(before: "hello"), completer: unsure) == (.unsure, 1))
        #expect(await why(Field(before: "hello"), completer: CountingCompleter(" a")) == (.unsure, 1), "too short to be worth it")
        #expect(await why(Field(before: "hello")) { $0.traits = { _, _ in nil } } == (.noFont, 1))
        #expect(await why(Field(before: "안녕")) { $0.koreanInput.store(true, ordering: .relaxed) } == (.notTwoSet, 1))
        host.caretless.store(true, ordering: .relaxed)
        #expect(await why(Field(before: "hello")) == (.noCaret, 1))
        host.caretless.store(false, ordering: .relaxed)
        tap.blocked.withLock { $0 = .secureInput }
        #expect(await why(Field(before: "hello")) == (.blocked, 1))
        tap.blocked.withLock { $0 = nil }
        #expect(await why(Field(before: "hello")) { $0.read = { _ in nil } }.1 == 0, "the start, unreadable, is no change")
    }
    @Test func aFieldThatStopsBeingReadableSaysSo() async {
        let seen = Mutex<Watcher.Why?>(nil)
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        watcher.onWhy = { why, _ in seen.withLock { $0 = why } }
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .shown })
        await watcher.settle()  // The fake belongs to the watcher's queue.
        watcher.read = { _ in nil }
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .unreadable })
    }
    final class Reasons: Sendable {
        let last = Mutex<Watcher.Why?>(nil)
        func withLock<T>(_ body: (inout Watcher.Why?) -> T) -> T { last.withLock(body) }
    }
    func reasons(_ watcher: Watcher) -> Reasons {
        let seen = Reasons()
        watcher.onWhy = { why, _ in seen.withLock { $0 = why } }
        return seen
    }
    @Test func aGhostHiddenWithTheFieldUnchangedIsNoLongerShown() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        let seen = reasons(watcher)
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .shown })
        #expect(keys.press(tap, keys.key(53, pid: 0)).swallowed)  // Esc.
        #expect(await soon { seen.withLock { $0 } == .idle })
        watcher.redraw()
        #expect(await soon { seen.withLock { $0 } == .shown })
        watcher.hideNow()  // Scroll, sleep, lock.
        #expect(await soon { seen.withLock { $0 } == .idle })
    }
    @Test func nothingToSuggestReplacesAnOlderReasonAndAnUnfinishedWordIsNoAnswer() async {
        let model = CountingCompleter(" there friend")
        let watcher = watcher(Field(before: "hello"), completer: model)
        let seen = reasons(watcher)
        watcher.traits = { _, _ in nil }
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .noFont })
        await watcher.settle()
        watcher.traits = { _, _ in FieldTraits(fontSize: 14, fontName: nil, color: nil, lineLeft: 110) }
        model.answers = false
        host.now.withLock { $0.field = Field(before: "hello w") }
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .idle })
        // Shown, then a first word still being written: neither shown nor "not sure".
        model.answers = true
        watcher.redraw()
        #expect(await soon { seen.withLock { $0 } == .shown })
        await watcher.settle()
        model.gate = nil
        host.now.withLock { $0.field = Field(before: "hello wo") }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(seen.withLock { $0 } == .idle)
    }
    @Test func aDrawFromBeforeARebindIsNotReportedForTheNewBinding() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        let seen = Mutex<[String]>([])
        watcher.onWhy = { why, binding in seen.withLock { $0.append("\(why) \(binding)") } }
        watcher.scheduleUpdate()
        // The main thread is held here, so the draw for binding 0 waits for it: the read, then the answer, queue it.
        watcher.queue.sync {}
        watcher.queue.sync {}
        watcher.unbind(binding: 1)
        watcher.queue.sync {}
        await watcher.settle()  // The draw runs now, after the rebind.
        #expect(seen.withLock { $0 } == ["unreadable 1"])
    }
    @Test func aDrawOvertakenByInputDoesntReportOverTheNewerReason() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        let seen = reasons(watcher)
        panel.refuses = true
        panel.onShow = { [self] in
            panel.onShow = nil
            host.now.withLock { $0.field = Field(before: "hello", after: " world") }
            _ = keys.press(tap, keys.key(0, pid: 0))
            watcher.scheduleUpdate()  // Queued before the draw's own report.
        }
        watcher.scheduleUpdate()
        await watcher.settle()
        await watcher.settle()
        #expect(seen.withLock { $0 } == .textAfter)
    }
    @Test func whatFitsMustStillBeWorthATab() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        panel.fits = 2  // " t": two keys.
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(armed() == nil && !panel.isVisibleGhost)
        panel.fits = 3
        watcher.redraw()
        await watcher.settle()
        #expect(armed()?.ghost.remainder == " th")
    }
    @Test func anyKeyThatHidesTheGhostEndsShown() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        let seen = reasons(watcher)
        watcher.scheduleUpdate()
        #expect(await soon { seen.withLock { $0 } == .shown })
        #expect(!keys.press(tap, keys.key(8, pid: 0, flags: .maskCommand)).swallowed)  // Cmd-C: the field doesn't change.
        #expect(await soon { seen.withLock { $0 } == .idle && !panel.isVisibleGhost })
    }
    @Test func aModelThatStopsShortTakesBackWhatItStreamed() async {
        let model = CountingCompleter(" there friend")
        model.stopsShort = true
        let watcher = watcher(Field(before: "hello"), completer: model)
        let seen = reasons(watcher)
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(await soon { seen.withLock { $0 } == .idle })
        #expect(armed() == nil && !panel.isVisibleGhost)
    }
    @Test func noTakerMeansNoReadNoModelAndNoGhost() async {
        for blocked in [KeyTap.Obstacle.secureInput, .tapOff] {
            tap.blocked.withLock { $0 = blocked }
            let model = CountingCompleter(" there friend")
            let watcher = watcher(Field(before: "hello"), completer: model)
            watcher.scheduleUpdate()
            await watcher.settle()
            #expect(host.reads.load(ordering: .relaxed) == 0 && model.asks.load(ordering: .relaxed) == 0)
            #expect(armed() == nil && !panel.isVisibleGhost)
            // The same field with a taker gets all three, or the above proves nothing.
            tap.blocked.withLock { $0 = nil }
            watcher.scheduleUpdate()
            #expect(await soon { armed() != nil })
            #expect(host.reads.load(ordering: .relaxed) > 0 && model.asks.load(ordering: .relaxed) > 0 && panel.isVisibleGhost)
            watcher.hideNow()
            host.reads.store(0, ordering: .relaxed)
        }
    }
    @Test func secureInputArrivingWithTheAnswerDrawsNothing() async {
        let model = CountingCompleter(" there friend")
        let watcher = watcher(Field(before: "hello"), completer: model)
        tap.blocked.withLock { $0 = nil }
        model.onAsk = { [tap] in tap.blocked.withLock { $0 = .secureInput } }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(model.asks.load(ordering: .relaxed) == 1)
        #expect(armed() == nil && !panel.isVisibleGhost)
        // Secure Input ends with the field unchanged: the same field asks again and shows.
        model.onAsk = nil
        tap.blocked.withLock { $0 = nil }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(model.asks.load(ordering: .relaxed) == 2)
        #expect(armed() != nil && panel.isVisibleGhost)
    }
    @Test func secureInputDuringTheReadMeansNoModelAndComesBack() async {
        let model = CountingCompleter(" there friend")
        let watcher = watcher(Field(before: "hello"), completer: model)
        let read = watcher.read
        watcher.read = { [tap] element in
            defer { tap.blocked.withLock { $0 = .secureInput } }
            return read(element)
        }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(host.reads.load(ordering: .relaxed) == 1 && model.asks.load(ordering: .relaxed) == 0 && armed() == nil)
        watcher.read = read
        tap.blocked.withLock { $0 = nil }
        watcher.scheduleUpdate()  // The same field: it must still ask.
        #expect(await soon { armed() != nil })
    }
    @Test func secureInputBeforeTheDrawMeansNoGhostAndComesBack() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        let traits = watcher.traits
        watcher.traits = { [tap] element, before in
            defer { tap.blocked.withLock { $0 = .secureInput } }
            return traits(element, before)
        }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(armed() == nil && !panel.isVisibleGhost)
        watcher.traits = traits
        tap.blocked.withLock { $0 = nil }
        watcher.scheduleUpdate()  // The same field, with the suggestion still held: it draws now.
        #expect(await soon { armed() != nil })
    }
    @Test func tabCanReachOnlyWhatADrawnClippedGhostShows() async throws {
        let text = " one two three four five six seven"
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(text))
        watcher.scheduleUpdate()
        #expect(await soon { armed() != nil })
        let offer = try #require(armed()?.ghost.remainder)
        #expect(offer == panel.view.layout.map { String(Word.withoutTrailingSpaces($0.visibleText)) })
        #expect(offer.count < text.count && text.hasPrefix(offer))
        let all = keys.press(tap, keys.key(48, pid: 0, flags: .maskShift))
        #expect(all.swallowed && keys.unicode(all.posted) == offer)
        #expect(keys.press(tap, keys.key(48, pid: 0)).posted.isEmpty)  // The unseen tail is out of reach: Tab waits for the redraw.
    }
    @Test func nextWordTabsStopAtTheDrawnEdge() async throws {
        let text = " one two three four five six seven"
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(text))
        watcher.scheduleUpdate()
        #expect(await soon { armed() != nil })
        let offer = try #require(armed()?.ghost.remainder)
        var taken = ""
        while true {
            let tab = keys.press(tap, keys.key(48, pid: 0))
            guard tab.swallowed, !tab.posted.isEmpty else { break }  // Held for the redraw, which this test never makes.
            taken += keys.unicode(tab.posted)
        }
        #expect(taken == offer)
    }
    @Test func aClippedKoreanGhostKeepsItsSyllableAndTypesOnlyWhatShows() async throws {
        let text = " 한 다음 날에 다시 만나서 이야기를 나누면 좋겠습니다"  // Carries its own space, as the prompt ends at 그.
        let watcher = watcher(Field(before: "그 하", mayCompose: true), marked: true, completer: CountingCompleter(text))
        watcher.twoSet.store(true, ordering: .relaxed)
        watcher.scheduleUpdate()
        #expect(await soon { armed() != nil })
        let ghost = try #require(armed()?.ghost)
        #expect(ghost.keys == "ㄴ" && ghost.composing == "한")
        let rest = String(text.dropFirst(2))
        #expect(ghost.remainder.count < rest.count && rest.hasPrefix(ghost.remainder))
        let posted = keys.press(tap, keys.key(48, pid: 0, flags: .maskShift)).posted.filter { $0.type == .keyDown }
        let expected = try #require(TwoSetLayout.strokes("ㄴ" + Hangul.keys(ghost.remainder)))
        #expect(posted.map { $0.getIntegerValueField(.keyboardEventKeycode) } == expected.map { Int64($0.code) })
        #expect(tap.state.withLock { $0.pending?.to == "그 한" + ghost.remainder })
        #expect(keys.press(tap, keys.key(48, pid: 0)).posted.isEmpty)
    }
    @Test func theSuggestionKeepsItsTailForTheNextDraw() async throws {
        let text = " one two three four five six seven", model = CountingCompleter(text)
        let watcher = watcher(Field(before: "hello"), completer: model)
        watcher.scheduleUpdate()
        #expect(await soon { armed() != nil })
        let offer = try #require(armed()?.ghost.remainder)
        _ = keys.press(tap, keys.key(48, pid: 0, flags: .maskShift))
        host.now.withLock { $0 = (Field(before: "hello" + offer), 120) }  // The insert landed, and the rest now fits.
        await watcher.settle()
        watcher.redraw()
        #expect(await soon { armed() != nil })
        #expect(armed()?.ghost.remainder == String(text.dropFirst(offer.count)))
        #expect(model.asks.load(ordering: .relaxed) == 1)
    }
    @Test func quitClosesTheModelFirstAndAHungHostCantHoldItPastOneDeadline() async {
        let watcher = Watcher(tap: tap, panel: panel)
        let events = Mutex<[String]>([])
        let model = ClosingCompleter { events.withLock { $0.append("close") } }
        let browser = Priming.Process(pid: 42, launched: Date(timeIntervalSince1970: 1))
        watcher.queue.sync {
            watcher.launchDate = { _ in browser.launched }
            _ = watcher.priming.next(browser, now: Date(), kind: { Priming.enhanced }, voiceOver: { false }, isOn: { false })
            watcher.restore = { _ in events.withLock { $0.append("restore") } }
        }
        watcher.queue.async { sleep(2) }  // A read stuck on a hung host when the quit comes.
        let start = Date()
        // Off the main actor, which the suite's other tests share and this wait would hold.
        await Task.detached { watcher.quit(closing: [model], within: 0.5) }.value
        #expect(Date().timeIntervalSince(start) < 0.9)
        #expect(events.withLock { $0 } == ["close"])  // Closed without waiting on the queue.
        await Task.detached { watcher.queue.sync {} }.value
        events.withLock { $0 = [] }
        await Task.detached { watcher.quit(closing: [model], within: 0.5) }.value  // Nothing in the way now.
        let expected = NSWorkspace.shared.isVoiceOverEnabled ? ["close"] : ["close", "restore"]
        #expect(events.withLock { $0 } == expected)
    }
    @Test func noCaretMeansNoModelCall() async {
        let model = CountingCompleter(" there friend")
        host.caretless.store(true, ordering: .relaxed)
        let watcher = watcher(Field(before: "hello"), completer: model)
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(model.asks.load(ordering: .relaxed) == 0 && armed() == nil)
        host.caretless.store(false, ordering: .relaxed)
        watcher.redraw()
        #expect(await soon { armed() != nil })
        #expect(model.asks.load(ordering: .relaxed) == 1)
    }
    @Test func aSuggestionHeldThroughACaretlessReadIsDrawnAgainWithNoModelCall() async {
        let model = CountingCompleter(" there friend")
        let watcher = watcher(Field(before: "hello"), completer: model)
        watcher.scheduleUpdate()
        #expect(await soon { armed() != nil })
        host.caretless.store(true, ordering: .relaxed)
        host.now.withLock { $0.field = Field(before: "hello t") }
        watcher.scheduleUpdate()
        #expect(await soon { armed() == nil && !panel.isVisibleGhost })
        host.caretless.store(false, ordering: .relaxed)
        host.now.withLock { $0.field = Field(before: "hello th") }
        watcher.scheduleUpdate()
        #expect(await soon { armed()?.ghost.remainder == "ere friend" })
        #expect(model.asks.load(ordering: .relaxed) == 1)
    }
    @Test func aPanelStrandedOnAnotherSpaceDrawsNothingAndArmsNothing() async {
        panel.stranded = true
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(armed() == nil && !panel.isVisibleGhost)
    }
    @Test func aFieldTypedIntoBeforeTheModelLoadedIsAskedOnceItDoes() async {
        let watcher = watcher(Field(before: "hello"), completer: nil)
        watcher.scheduleUpdate()
        await watcher.settle()
        let model = CountingCompleter(" there friend")
        watcher.install(model)  // No edit, so no notification: the install itself must ask.
        #expect(await soon { armed() != nil })
        #expect(model.asks.load(ordering: .relaxed) == 1)
    }
    @Test func aNewModelDoesntReuseTheOldOnesSuggestion() async {
        let old = CountingCompleter(" there friend"), new = CountingCompleter(" the end")
        let watcher = watcher(Field(before: "hello"), completer: old)
        watcher.scheduleUpdate()
        #expect(await soon { armed()?.ghost.remainder == " there friend" })
        watcher.install(new)
        await watcher.settle()
        host.now.withLock { $0.field = Field(before: "hello t") }  // Fits either; only the new one may answer.
        watcher.scheduleUpdate()
        #expect(await soon { armed()?.ghost.remainder == "he end" })
        #expect(old.asks.load(ordering: .relaxed) == 1 && new.asks.load(ordering: .relaxed) >= 1)
    }
    @Test func aRequestQueuedBeforeTheIdleDeadlineCancelsTheUnload() async {
        let model = CountingCompleter(" there friend")
        let watcher = watcher(Field(before: "hello"), completer: nil)
        watcher.idleUnload = 0.4  // The margin for settle() below, under load.
        // The install asks and starts the wait. Its deadline passes while the watcher is busy, with a request queued behind it: the
        // request comes first, and starts the wait again.
        watcher.install(model)
        watcher.queue.async { [host] in
            usleep(1_000_000)
            host.now.withLock { $0.field = Field(before: "hello w") }
        }
        watcher.scheduleUpdate()
        await watcher.settle()
        #expect(model.asks.load(ordering: .relaxed) == 2)
        #expect(model.unloads.load(ordering: .relaxed) == 0)
        #expect(await soon { model.unloads.load(ordering: .relaxed) == 1 }, "and once idle, it does unload")
    }
    @Test func sleepLockAndDisplayChangesHideAndDisarm() async {
        let watcher = watcher(Field(before: "hello"), completer: CountingCompleter(" there friend"))
        watcher.hideOnSessionChange()
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, name) in [(workspace, NSWorkspace.willSleepNotification), (workspace, NSWorkspace.screensDidSleepNotification),
                               (workspace, NSWorkspace.sessionDidResignActiveNotification), (workspace, NSWorkspace.activeSpaceDidChangeNotification),
                               (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)] {
            watcher.redraw()
            #expect(await soon { armed() != nil })
            center.post(name: name, object: nil)
            #expect(await soon { armed() == nil && !panel.isVisibleGhost }, "\(name.rawValue)")
        }
    }
}

extension Watcher {
    /// Everything queued for the watcher and the main thread has run.
    @MainActor func settle() async {
        for _ in 0..<3 {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in queue.async { DispatchQueue.main.async { done.resume() } } }
        }
    }
}

extension GhostPanel {
    var isVisibleGhost: Bool { view.layout != nil }
}

/// Hugging Face, faked: answers with the status in the model's repo name, `fake/503`, and the body "abd".
final class FakeServer: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url!.pathComponents[2] == "stall" {  // Part of a file that can resume, and then nothing.
            let headers = ["Content-Length": "100000", "Accept-Ranges": "bytes", "ETag": "\"e\""]
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            return client!.urlProtocol(self, didLoad: Data(repeating: 1, count: 5000))
        }
        let status = Int(request.url!.pathComponents[2]) ?? 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("abd".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite @MainActor struct DownloadTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    func model(status: Int, size: Int64 = 3, repo: String? = nil) -> ModelStore.Model {
        ModelStore.Model(name: "Test", note: "", file: "test.gguf", sha256: abc, repo: "fake/" + (repo ?? "\(status)"), size: size)
    }
    /// What the store said, on the main thread.
    final class States: @unchecked Sendable { var all: [ModelStore.State] = [] }
    func store() -> (ModelStore, States) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeServer.self]
        let store = ModelStore(directory: directory, configuration: configuration), states = States()
        store.onChange = { state in states.all.append(state) }
        return (store, states)
    }

    @Test func offlineAtLaunchWaitsForAConnection() {
        #expect(ModelStore(directory: directory).configuration.waitsForConnectivity)
    }
    @Test func aServerErrorSaysSoNotChecksum() async {
        let (store, states) = store()
        store.fetch(model(status: 503))
        #expect(await soon { states.all.last == .failed("Hugging Face answered 503. Try again later.") })
    }
    @Test func aBadDownloadLeavesNothingToResumeFrom() async throws {
        let (store, states) = store()
        store.fetch(model(status: 200))  // "abd", not "abc".
        #expect(await soon { states.all.last == .failed("The download didn't match its checksum.") })
        store.resumeData = Data("stale".utf8)  // Damaged too, so it must start over rather than raise.
        store.fetch(model(status: 200))
        #expect(await soon { states.all.last == .failed("The download didn't match its checksum.") && states.all.count > 3 })
        #expect(store.resumeData == nil)
    }
    @Test func noRoomFailsBeforeStartingAndSaysHowMuch() throws {
        let (store, states) = store()
        store.fetch(model(status: 200, size: Int64(1) << 60))
        let failure = try #require(states.all.last)
        guard case .failed(let why) = failure else { Issue.record("\(failure)"); return }
        #expect(why.hasPrefix("It needs 1152921504.6 GB free, and this Mac has "))
        #expect(!store.isBusy)
    }
    @Test func whereItStoppedSurvivesAQuit() {
        ModelStore(directory: directory).resumeData = Data("here".utf8)
        #expect(ModelStore(directory: directory).resumeData == Data("here".utf8))
    }
    @Test func aFailedDownloadOffersRetryAndNothingElseDoes() {
        let app = App()
        app.modelChanged(.failed("Hugging Face answered 503. Try again later."))
        #expect(app.retryable && app.notice == "Model download failed: Hugging Face answered 503. Try again later.")
        app.modelChanged(.downloading(0))
        #expect(!app.retryable && app.notice == nil)
        app.modelChanged(.waiting)
        #expect(app.modelLine == "Waiting for a connection…")
        app.modelChanged(.failed("x"))
        app.notice = "Could not load a.gguf"
        #expect(!app.retryable)
    }
    @Test func onlyTheInstalledModelsFailureCountsEvenAtTheSamePath() async {
        let app = App(), path = app.store.path(ModelStore.models[0]).path  // Ours, so choosing it writes no path to the settings.
        let failures = Mutex<[@Sendable () -> Void]>([])
        app.makeEngine = { _, lost in
            failures.withLock { $0.append(lost) }
            return CountingCompleter("")
        }
        app.use(path: path)
        #expect(await soon { app.isActive(path: path) })
        app.use(path: path)  // The same file again: a second engine.
        #expect(await soon { failures.withLock { $0.count } == 2 })
        try? await Task.sleep(for: .milliseconds(100))  // Its install, on main.
        failures.withLock { $0[0] }()  // The replaced one, late.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(app.isActive(path: path) && app.notice == nil)
        failures.withLock { $0[1] }()
        #expect(await soon { !app.ready })
        #expect(app.modelLine == "No model loaded" && app.notice == "Could not load " + ModelStore.models[0].file)
    }
    @Test func aLoadUnderWayAtQuitFinishesAndClosesAndOneQueuedBehindItNeverLoads() {
        let app = App(), model = CountingCompleter(""), gate = DispatchSemaphore(value: 0), started = DispatchSemaphore(value: 0)
        let builds = Atomic<Int>(0)
        app.makeEngine = { _, _ in
            builds.add(1, ordering: .relaxed)
            started.signal()
            gate.wait()
            return model
        }
        app.use(path: app.store.path(ModelStore.models[0]).path)
        app.use(path: "/nonexistent/queued.gguf")
        started.wait()  // The first load is under way; the second waits behind it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { gate.signal(); gate.signal() }  // A second so a wrong load fails, not hangs.
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(model.unloads.load(ordering: .relaxed) == 1)
        #expect(builds.load(ordering: .relaxed) == 1)
    }
    @Test func aModelLoadedButNotYetInstalledAtQuitCloses() {
        let app = App(), model = CountingCompleter(""), built = DispatchSemaphore(value: 0)
        app.makeEngine = { _, _ in
            built.signal()
            return model
        }
        app.use(path: app.store.path(ModelStore.models[0]).path)
        built.wait()  // Main is held, so its install can't run before the quit.
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(model.unloads.load(ordering: .relaxed) == 1)
    }
    @Test func nothingToStopWhileVerifyingSoQuitIsNotHeld() async throws {
        let (store, states) = store()
        var stopped = false
        #expect(!store.stop { stopped = true })
        store.fetch(model(status: 0, repo: "stall"))
        #expect(await soon { states.all.contains { if case .downloading(let done) = $0 { done > 0 } else { false } } })
        let file = directory.appendingPathComponent("partial")
        try Data("abd".utf8).write(to: file)
        store.urlSession(URLSession.shared, downloadTask: URLSession.shared.downloadTask(with: URL(fileURLWithPath: "/")), didFinishDownloadingTo: file)
        #expect(store.isBusy && !store.stop { stopped = true })  // Verifying: a session, but no download.
        #expect(!stopped)
    }
    @Test func aStopSavesWhereItGotToBeforeItSaysDone() async {
        let (store, states) = store()
        store.fetch(model(status: 0, repo: "stall"))
        #expect(await soon { states.all.contains { if case .downloading(let done) = $0 { done > 0 } else { false } } })
        var savedFirst: Bool?
        #expect(store.stop { savedFirst = store.resumeData != nil })
        #expect(await soon { savedFirst != nil })
        #expect(savedFirst == true && !store.isBusy)
    }
    @Test func theModelLineNamesTheModelAndTheDownloadsSize() {
        let app = App()
        app.modelChanged(.downloading(0.37))
        #expect(app.modelLine == "Downloading \(ModelStore.models[0].name): 37% of \(ModelStore.models[0].sizeText)")
        app.modelChanged(.cancelled)
        app.activePath = app.store.path(ModelStore.models[0]).path
        #expect(app.modelLine == ModelStore.models[0].name)
    }
    @Test func theLineSaysWhyAndNotSureReadsAsWorking() {
        func line(trusted: Bool = true, active: Bool = true, obstacle: KeyTap.Obstacle? = nil, ready: Bool = true, _ why: Watcher.Why) -> String? {
            App.line(trusted: trusted, active: active, obstacle: obstacle, ready: ready, why: why)
        }
        #expect(line(.unsure) == "Working. Not sure enough to suggest yet.")
        #expect(line(.shown) == "Working." && line(.idle) == "Working.")
        #expect(line(.noFont) == "This field doesn't report its font, so no suggestion here.")
        #expect(line(.textAfter) == "Text after the cursor, so no suggestion here.")
        // What comes first: the permission, then off or paused, then Tab's way to us, then the model.
        #expect(line(trusted: false, active: false, obstacle: .tapOff, .unsure) == "Halftype needs Accessibility permission.")
        #expect(line(active: false, obstacle: .secureInput, .unsure) == nil)
        #expect(line(obstacle: .secureInput, ready: false, .unsure) == KeyTap.Obstacle.secureInput.rawValue)
        #expect(line(ready: false, .shown) == "The model isn't ready yet.")
        #expect(line(.blocked) == "Working.", "an obstacle that has gone")
        let all: [Watcher.Why] = [.shown, .idle, .unsure, .unreadable, .blocked, .textAfter, .notTwoSet, .noModel, .noCaret, .noFont, .rightToLeft, .noRoom]
        #expect(all.allSatisfy { line($0)?.hasSuffix(".") == true })
    }
    @Test func aReasonFromAnEarlierBindingIsDropped() {
        let app = App()
        app.binding = 7
        app.whyChanged(.noFont, binding: 6)
        #expect(app.why == .unreadable)
        app.whyChanged(.noFont, binding: 7)
        #expect(app.why == .noFont)
    }
    @Test func theLessonAndSuccessShowOnlyWhileOnAndNothingIsInTheWay() {
        let app = App(tap: FakeTap())
        app.trusted = true
        app.activePath = app.store.path(ModelStore.models[0]).path
        #expect(app.fieldLine(.shown) == App.lesson)
        #expect(app.fieldLine(.textAfter) == "Text after the cursor, so no suggestion here.")
        app.accepted = true
        #expect(app.fieldLine(.unsure) == App.success && app.fieldLine(.textAfter) != App.success)
        // Untrusted while switching, so the rebind binds nothing real.
        let was = app.on
        app.trusted = false
        app.on = false
        app.trusted = true
        #expect(app.fieldLine(.shown) == nil)
        app.trusted = false
        app.on = was
    }
    @Test func aLaterReasonInTheWayEndsTheFirstAcceptsLine() {
        let app = App()
        app.binding = 7
        for blocking in [Watcher.Why.textAfter, .blocked, .unreadable] {
            app.accepted = true
            app.whyChanged(.unsure, binding: 7)  // Still working: the line stays.
            #expect(app.accepted)
            app.whyChanged(blocking, binding: 7)
            #expect(!app.accepted, "\(blocking)")
        }
    }
    @Test func theIconShowsState() {
        #expect(App.icon(active: true, problem: false, downloading: nil) == App.Icon())
        #expect(App.icon(active: false, problem: false, downloading: nil) == App.Icon(dimmed: true))
        #expect(App.icon(active: true, problem: true, downloading: nil) == App.Icon(mark: true))
        #expect(App.icon(active: true, problem: false, downloading: 0.374) == App.Icon(title: "37%"))
    }
    @Test func theMenuIsPlain() {
        let app = App()
        app.activePath = app.store.path(ModelStore.models[0]).path
        app.readPredictions = { false }
        let menu = NSMenu()
        app.menuNeedsUpdate(menu)
        var titles = menu.items.map(\.title)
        #expect(titles.contains("Suggestions") && titles.contains(ModelStore.models[0].name) && titles.contains("Halftype needs Accessibility permission."))
        #expect(!titles.contains { $0.contains(".gguf") || $0 == "Halftype" })
        #expect(!titles.contains("Turn Off macOS Predictions…"))
        app.readPredictions = { true }
        app.menuNeedsUpdate(menu)
        titles = menu.items.map(\.title)
        #expect(titles.contains("Turn Off macOS Predictions…"))
    }
    @Test func theFieldIsPrefilledOnlyOnAFreshLaunchOnceReady() {
        #expect(App.prefill(fresh: true, ready: true, draft: "", korean: false) == "Please let me know if you have any")
        #expect(App.prefill(fresh: true, ready: true, draft: "", korean: true) == "안녕하세요. 만나서 반갑")
        #expect(App.prefill(fresh: false, ready: true, draft: "", korean: false) == nil)
        #expect(App.prefill(fresh: true, ready: false, draft: "", korean: false) == nil)
        #expect(App.prefill(fresh: true, ready: true, draft: "mine", korean: false) == nil)
        let app = App()
        app.activePath = app.store.path(ModelStore.models[0]).path
        app.fresh = true
        #expect(app.takePrefill(draft: "") != nil)
        #expect(app.takePrefill(draft: "") == nil, "once")
    }
    @Test func onlyAModelNotInUseCanBeDeleted() throws {
        let app = App()
        let (kanana, qwen) = (ModelStore.models[0], ModelStore.models[1])
        app.activePath = app.store.path(kanana).path
        #expect(!app.canDelete(kanana) && app.canDelete(qwen))
        app.downloading = qwen.id
        #expect(!app.canDelete(qwen))
        // The file op itself, on a store of its own: never the real models.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelStore(directory: directory)
        try Data().write(to: store.path(qwen))
        store.delete(qwen)
        #expect(!FileManager.default.fileExists(atPath: store.path(qwen).path))
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
    @Test func onlyUnverifiedFilesAreLeftovers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let left = directory.appendingPathComponent("a.gguf.unverified"), model = directory.appendingPathComponent("a.gguf")
        try Data().write(to: left)
        try Data().write(to: model)
        ModelStore(directory: directory).removeLeftovers()
        #expect(!FileManager.default.fileExists(atPath: left.path))
        #expect(FileManager.default.fileExists(atPath: model.path))
    }

    @Test func aFailureKeepsWhereItStoppedAndARefusalLetsItGo() throws {
        let store = ModelStore(directory: FileManager.default.temporaryDirectory)
        let session = URLSession(configuration: .ephemeral), task = session.dataTask(with: ModelStore.models[0].url)
        store.urlSession(session, task: task, didCompleteWithError: NSError(domain: NSURLErrorDomain, code: -1, userInfo: [NSURLSessionDownloadTaskResumeData: Data("here".utf8)]))
        #expect(store.resumeData == Data("here".utf8))
        store.urlSession(session, task: task, didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        #expect(store.resumeData == Data("here".utf8), "cancel records its own, so a cancellation leaves it alone")
        store.urlSession(session, task: task, didCompleteWithError: NSError(domain: NSURLErrorDomain, code: -3003))
        #expect(store.resumeData == nil)
    }
}

/// The window's states as PNGs, drawn off screen, so nothing takes focus. `HALFTYPE_SHOTS=<dir> swift test --filter WindowShots`. The sky's shader is blank in these; 13 and 14 draw it alone.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HALFTYPE_SHOTS"] != nil)) @MainActor struct WindowShots {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HALFTYPE_SHOTS"] ?? "")

    func app(_ set: (App) -> Void) -> App {
        let app = App(tap: FakeTap())
        app.readPredictions = { false }
        set(app)
        return app
    }
    func textView(in view: NSView) -> NSTextView? { (view as? NSTextView) ?? view.subviews.lazy.compactMap(textView).first }

    @discardableResult func shoot(_ name: String, _ app: App, page: Root.Page = .field, dark: Bool = false) -> NSView {
        let host = NSHostingView(rootView: Root(app: app, page: page, sidebar: page != .field))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(x: 0, y: 0, width: 720, height: 500)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("\(name).png"))
        return host
    }

    @Test func states() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ready: (App) -> Void = { $0.trusted = true; $0.activePath = $0.store.path(ModelStore.models[0]).path }
        shoot("1-allow-downloading", app { $0.modelChanged(.downloading(0.37)) })
        shoot("2-field-downloading", app { $0.trusted = true; $0.modelChanged(.downloading(0.37)) })
        let host = shoot("3-prefilled-teach", app { ready($0); $0.fresh = true; $0.why = .shown })
        let field = try #require(textView(in: host))
        #expect(field.string == "Please let me know if you have any")
        #expect(field.selectedRange() == NSRange(location: field.string.utf16.count, length: 0), "the caret at the end, where a ghost goes")
        shoot("4-teach-dark", app { ready($0); $0.why = .shown }, dark: true)
        shoot("5-unsure", app { ready($0); $0.why = .unsure })
        shoot("6-accepted", app { ready($0); $0.why = .idle; $0.accepted = true })
        shoot("7-predictions", app { ready($0); $0.why = .unsure; $0.readPredictions = { true } })
        shoot("8-no-font", app { ready($0); $0.why = .noFont })
        shoot("9-failed-download", app { $0.trusted = true; $0.modelChanged(.failed("Hugging Face answered 503. Try again later.")) })
        shoot("10-models-delete", app { $0.trusted = true; $0.activePath = $0.store.directory.appendingPathComponent("Qwen3.5-0.8B-Q4_K_M.gguf").path }, page: .models)
        // The sky mid-typing (fast keys lifting the bars) and 0.35 s into a Tab's swell.
        let now = Date()
        for (name, keys, tabs) in [("13-sky-typing", [0.3, 0.2, 0.12, 0.05], [Double]()), ("14-sky-tab", [0.5], [0.35])] {
            // The sky is a Metal shader, which cacheDisplay leaves blank.
            let renderer = ImageRenderer(content: Sky(rise: 0.6, keys: keys.map { now - $0 }, tabs: tabs.map { now - $0 }))
            renderer.proposedSize = ProposedViewSize(width: 720, height: 500)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("\(name).png"))
        }
        // The whole window through ImageRenderer, which does draw the sky, at the smallest size and a tall one: the inks keep clear of the content.
        for (width, height) in [(640.0, 440.0), (720.0, 500.0), (900.0, 820.0)] {
            let renderer = ImageRenderer(content: Root(app: app { ready($0); $0.why = .idle }).environment(\.colorScheme, .dark).frame(width: width, height: height))
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("15-window-\(Int(width))x\(Int(height)).png"))
        }
        shoot("11-accepted-dark", app { ready($0); $0.why = .idle; $0.accepted = true; $0.readPredictions = { true } }, dark: true)
    }

    @Test func icons() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let glyph = try #require(NSImage(contentsOf: resources.appendingPathComponent("MenuBarTemplate@2x.png")))
        glyph.size = CGSize(width: 18, height: 18)
        let marked = App.marked(glyph)
        for dark in [false, true] {
            let image = NSImage(size: CGSize(width: 240, height: 24), flipped: false) { rect in
                (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                rect.fill()
                let ink = dark ? NSColor.white : NSColor.black
                func draw(_ image: NSImage, x: CGFloat, alpha: CGFloat, title: String = "") {
                    let tinted = NSImage(size: image.size, flipped: false) { r in
                        image.draw(in: r)
                        ink.setFill()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: CGRect(x: x, y: 3, width: 18, height: 18), from: .zero, operation: .sourceOver, fraction: alpha)
                    (title as NSString).draw(at: CGPoint(x: x + 21, y: 4), withAttributes: [.font: NSFont.menuBarFont(ofSize: 0), .foregroundColor: ink.withAlphaComponent(alpha)])
                }
                draw(glyph, x: 8, alpha: 1)
                draw(glyph, x: 48, alpha: 0.4)
                draw(marked, x: 88, alpha: 1)
                draw(glyph, x: 128, alpha: 1, title: "37%")
                return true
            }
            let rep = NSBitmapImageRep(data: image.tiffRepresentation(using: .none, factor: 2)!)!  // Two pixels a point, as on a Retina bar.
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(dark ? "12-icons-dark.png" : "12-icons.png"))
        }
    }
}

@Suite struct SkyBandTests {
    @Test func theBandKeepsAMarginThatShrinksButNeverUnderTheShadersFade() {
        #expect(Root.clear(CGRect(x: 0, y: 150, width: 400, height: 200), in: 500) == 106...394)  // room: 44 each side
        #expect(Root.clear(CGRect(x: 0, y: 60, width: 400, height: 340), in: 440) == 30...424)    // short: half the free space
        #expect(Root.clear(CGRect(x: 0, y: 10, width: 400, height: 425), in: 440) == -14...459)   // cramped: still 24
    }
}

@Suite struct RenameTests {
    @Test func itdasFolderAndSettingsMoveOnceWithTheirPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("halftype-move-\(UUID().uuidString)")
        let old = root.appendingPathComponent("Itda"), new = root.appendingPathComponent("Halftype")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)  // made first, as a launch would
        try Data("m".utf8).write(to: old.appendingPathComponent("m.gguf"))
        for folder in [old, new] { try FileManager.default.createDirectory(at: folder.appendingPathComponent("adapters/k"), withIntermediateDirectories: true) }
        try Data("a".utf8).write(to: old.appendingPathComponent("adapters/k/a.gguf"))
        let name = "halftype-test-\(UUID().uuidString)", oldName = name + ".old"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.setPersistentDomain(["modelPath": old.path + "/m.gguf", "on": false, "pausedApps": ["a"], "ownModels": [old.path + "/gone.gguf"]], forName: oldName)
        defer { defaults.removePersistentDomain(forName: name); defaults.removePersistentDomain(forName: oldName); try? FileManager.default.removeItem(at: root) }
        moveFromItda(defaults, oldDomain: oldName, support: new)
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("m.gguf").path))
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("adapters/k/a.gguf").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(defaults.string(forKey: "modelPath") == new.path + "/m.gguf")
        #expect(defaults.stringArray(forKey: "ownModels") == [old.path + "/gone.gguf"])  // nothing arrived, so untouched
        #expect(defaults.object(forKey: "on") as? Bool == false && defaults.stringArray(forKey: "pausedApps") == ["a"])
        defaults.set(true, forKey: "on")
        moveFromItda(defaults, oldDomain: oldName, support: new)
        #expect(defaults.bool(forKey: "on"))
        // A file that failed to move the first time moves on a later launch, and its path follows.
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("l".utf8).write(to: old.appendingPathComponent("late.gguf"))
        defaults.set(old.path + "/late.gguf", forKey: "modelPath")
        moveFromItda(defaults, oldDomain: oldName, support: new)
        #expect(defaults.string(forKey: "modelPath") == new.path + "/late.gguf")
    }
}
