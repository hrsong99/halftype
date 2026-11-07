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
        #expect(decide(53, armed: false) == .passAndDismiss)
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
        #expect(!press(tap, key(48)).swallowed)  // Nothing left: Tab is the app's.
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
