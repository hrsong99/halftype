// End-to-end checks against a private window, run by scripts/e2e.sh. The test runner can't host this: it needs a
// real NSApplication run loop to serve AX and events, as the shipped app has.
import AppKit
import Carbon
@testable import ItdaApp
import ItdaCore
@testable import ItdaEngine
import Metal
import Synchronization

final class FakeCompleter: Completer, @unchecked Sendable {
    let text: String
    private let log = Mutex<[(prefix: String, fragment: String)]>([])
    var prompts: [(prefix: String, fragment: String)] { log.withLock { $0 } }
    init(_ text: String) { self.text = text }
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void) {
        log.withLock { $0.append((prefix, fragment)) }
        onResult(Suggestion(text: text, gate: 0))
    }
    func cancel() {}
    func unload() {}
}

/// A real text view in a window of this process, reached the way the app reaches any other: through AX, with the real
/// observer and panel. Key events go to this process only, so nothing else on the Mac sees them. It never activates.
final class Harness {
    var window: NSPanel!
    var view: NSTextView!
    var panel: GhostPanel!
    let tap = KeyTap()
    var watcher: Watcher!

    init(completer: Completer) {
        DispatchQueue.main.sync {
            window = NSPanel(contentRect: CGRect(x: 80, y: 80, width: 420, height: 160), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .floating
            let label = NSTextField(labelWithString: "Earlier message from the other person")
            label.frame = CGRect(x: 10, y: 130, width: 400, height: 20)
            view = NSTextView(frame: CGRect(x: 10, y: 10, width: 400, height: 110))
            view.font = .systemFont(ofSize: 15)
            view.isAutomaticQuoteSubstitutionEnabled = false
            window.contentView!.addSubview(label)
            window.contentView!.addSubview(view)
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            panel = GhostPanel()
            watcher = Watcher(tap: tap, panel: panel)
            watcher.completer = completer
            watcher.post = { $0.postToPid(getpid()) }
        }
    }

    func close() {
        watcher.unbind()
        onMain { self.watcher.hideNow(); self.window.orderOut(nil) }
    }

    var caretX: CGFloat { onMain { self.view.firstRect(forCharacterRange: NSRange(location: self.view.selectedRange().location, length: 0), actualRange: nil).minX } }
    var ghostX: CGFloat? {
        onMain {
            guard let layout = self.panel.view.layout else { return nil }
            return self.panel.frame.minX + layout.drawOrigin.x + layout.manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minX + layout.manager.location(forGlyphAt: 0).x
        }
    }
    var text: String { onMain { self.view.string } }
    var visible: Bool { onMain { self.panel.isVisible } }
    var ghostText: String? { onMain { self.panel.view.layout?.visibleText } }
}

func onMain<T>(_ work: () -> T) -> T { DispatchQueue.main.sync(execute: work) }

func eventually(_ seconds: Double = 3, _ done: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if done() { return true }
        usleep(5000)
    }
    return false
}

func typeToSelf(_ text: String) { Inserter.insert(text) { $0.postToPid(getpid()) } }

func shell(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    try? p.run()
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

extension NSAppearance {
    func performAsCurrentDrawingAppearance2<T>(_ work: () -> T) -> T {
        var out: T!
        performAsCurrentDrawingAppearance { out = work() }
        return out
    }
}

final class AtomicBox { let count = Atomic<Int>(0) }
let listened = AtomicBox()

/// As the system sees it, not this process's own view of itself.
func frontmost() -> String { shell(CommandLine.arguments[0], ["--front-id"]) }

enum EndToEnd {
    nonisolated(unsafe) static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        if !ok { failures += 1 }
    }

    static func main() {
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--front-id") {
            print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--set-source") {
            let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: CommandLine.arguments[i + 1]] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
            exit(list.first.map(TISSelectInputSource) ?? 1)
        }
        if CommandLine.arguments.contains("--source-id") {
            print(TISGetInputSourceProperty(TISCopyCurrentKeyboardInputSource().takeRetainedValue(), kTISPropertyInputSourceID).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?")
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)  // Never active, so the user's own keys can't land in the test window.
        if ProcessInfo.processInfo.environment["ITDA_E2E_HOST"] != nil { return app.run() }
        Thread.detachNewThread {
            usleep(200_000)
            run()
            print(failures == 0 ? "all passed" : "\(failures) failed")
            exit(failures == 0 ? 0 : 1)
        }
        app.run()
    }

    struct Shot {
        var name: String, typed: String, ghost: String, font: CGFloat, size: CGSize, dark: Bool
    }

    /// `--shots <dir>`: a real text view with the real ghost view over it, placed by the real layout from what AX would report.
    static func shots(to dir: String) {
        let shots = [
            Shot(name: "small-field", typed: "Thanks, I'll send it over", ghost: " by the end of the day", font: 11, size: CGSize(width: 340, height: 30), dark: false),
            Shot(name: "large-field", typed: "The quick brown", ghost: " fox jumps over", font: 28, size: CGSize(width: 620, height: 64), dark: false),
            Shot(name: "dark", typed: "Can you take a look at", ghost: " the latest build?", font: 14, size: CGSize(width: 460, height: 40), dark: true),
            Shot(name: "light", typed: "Can you take a look at", ghost: " the latest build?", font: 14, size: CGSize(width: 460, height: 40), dark: false),
            Shot(name: "single-line-right-edge", typed: "This line is already quite close to the edge of", ghost: " the field and so the rest gets cut at a word", font: 14, size: CGSize(width: 400, height: 34), dark: false),
            Shot(name: "multi-line-wrap", typed: "This line is already quite close to the edge of", ghost: " the field, so the rest of the suggestion wraps", font: 14, size: CGSize(width: 400, height: 90), dark: true),
            Shot(name: "korean-light", typed: "오늘 회의는 세 시에", ghost: " 시작할 예정입니다", font: 15, size: CGSize(width: 420, height: 40), dark: false),
            Shot(name: "korean-dark-wrap", typed: "내일 오전에 다시 한번 확인해 보고 결과를 정리해서", ghost: " 공유드리겠습니다 감사합니다", font: 15, size: CGSize(width: 380, height: 90), dark: true),
        ]
        for shot in shots { render(shot, to: dir) }
    }

    static func render(_ shot: Shot, to dir: String) {
        let appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)!
        final class Flipped: NSView { override var isFlipped: Bool { true } }
        let scene = Flipped(frame: CGRect(x: 0, y: 0, width: shot.size.width + 40, height: shot.size.height + 40))
        scene.appearance = appearance
        scene.wantsLayer = true
        scene.layer?.backgroundColor = appearance.performAsCurrentDrawingAppearance2 { NSColor.windowBackgroundColor.cgColor }
        let frame = CGRect(x: 20, y: 20, width: shot.size.width, height: shot.size.height)
        let text = NSTextView(frame: frame)
        text.appearance = appearance
        text.font = .systemFont(ofSize: shot.font)
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = CGSize(width: 8, height: 6)
        text.string = shot.typed
        text.setSelectedRange(NSRange(location: (shot.typed as NSString).length, length: 0))
        scene.addSubview(text)

        // What AX reports for the previous character: its rect, in global points. Here the scene stands in for the screen.
        let manager = text.layoutManager!, container = text.textContainer!
        manager.ensureLayout(for: container)
        let lastGlyph = manager.glyphRange(forCharacterRange: NSRange(location: (shot.typed as NSString).length - 1, length: 1), actualCharacterRange: nil)
        let glyphRect = manager.boundingRect(forGlyphRange: lastGlyph, in: container)
        let line = manager.lineFragmentRect(forGlyphAt: lastGlyph.location, effectiveRange: nil)
        let origin = text.textContainerOrigin
        let caret = CGRect(x: frame.minX + origin.x + glyphRect.maxX, y: frame.minY + origin.y + line.minY, width: 0, height: line.height)
        let spec = GhostSpec(text: shot.ghost, caret: caret, frame: frame, fontSize: shot.font, fontName: nil,
                             color: appearance.performAsCurrentDrawingAppearance2 { NSColor.textColor.usingColorSpace(.sRGB)!.cgColor },
                             lineLeft: frame.minX + origin.x + container.lineFragmentPadding, previousCharacter: String(shot.typed.last!), mayWrap: true)
        guard let layout = GhostLayout.make(spec) else { return check(false, "\(shot.name): no ghost") }
        let ghost = GhostView(frame: layout.window)
        ghost.layout = layout
        scene.addSubview(ghost)
        print("      \(shot.name): visible '\(layout.visibleText)'")

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(scene.bounds.width * 2), pixelsHigh: Int(scene.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = scene.bounds.size
        appearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.windowBackgroundColor.setFill()
            scene.bounds.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        scene.cacheDisplay(in: scene.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent(shot.name + ".png"))
    }

    static func run() {
        if let i = CommandLine.arguments.firstIndex(of: "--engine") { return engine(path: CommandLine.arguments[i + 1]) }
        if let i = CommandLine.arguments.firstIndex(of: "--measure") { return measure(path: CommandLine.arguments[i + 1]) }
        if let i = CommandLine.arguments.firstIndex(of: "--shots") {
            return onMain { shots(to: CommandLine.arguments[i + 1]) }
        }
        if CommandLine.arguments.contains("--ime") { return ime() }
        frontAtStart = frontmost()
        ghostAtCaret()
        hides()
        secure()
        insertion()
        hung()
        tap()
        latency()
        check(frontmost() == frontAtStart && !frontAtStart.isEmpty, "frontmost app unchanged by the whole run: \(frontAtStart.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    nonisolated(unsafe) static var frontAtStart = ""

    static func ghostAtCaret() {
        let model = FakeCompleter(" there friend, how are you")
        let h = Harness(completer: model)
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        check(eventually { h.text == "hello" }, "key events reach the field: '\(h.text)'")
        check(eventually { h.visible }, "ghost appears")
        check(abs((h.ghostX ?? -99) - h.caretX) < 1, "ghost starts on the real caret: \(h.ghostX ?? -1) vs \(h.caretX)")
        onMain { check(h.panel.ignoresMouseEvents && !h.panel.canBecomeKey && !h.panel.isKeyWindow, "panel is click-through and never key") }
        let frontNow = frontmost()
        print("      front:", frontNow.trimmingCharacters(in: .whitespacesAndNewlines), "me:", getpid(), "isActive", onMain({ NSApp.isActive }), "text:", h.text)
        check(frontNow == frontAtStart, "the system never sees this process frontmost")

        let prompt = model.prompts.last
        check(prompt?.prefix.contains("Earlier message") == true, "context comes from the window")
        check(prompt?.fragment == "hello" || prompt?.fragment.hasSuffix("hello") == true, "the field's text goes in as the fragment")
        check(prompt?.prefix.contains("hello") == false, "the field's text isn't in the context")

        h.watcher.queue.async { h.watcher.accept(all: false) }
        check(eventually { h.text == "hello there" }, "Tab accepts the next word")
        check(eventually { h.ghostText?.hasPrefix(" friend") == true }, "ghost shrinks to what's left without asking the model again: \(h.ghostText ?? "nil")")
        check(abs((h.ghostX ?? -99) - h.caretX) < 1, "ghost moved with the caret")
        // Tab-Tab with no time for the host to report the first: each word goes in once.
        h.watcher.queue.async { h.watcher.accept(all: false); h.watcher.accept(all: false) }
        check(eventually { h.text == "hello there friend, how" }, "two fast Tabs accept two words: \(h.text)")
        h.watcher.queue.async { h.watcher.accept(all: true) }
        check(eventually { h.text == "hello there friend, how are you" }, "Shift-Tab accepts the rest")
        let asked = model.prompts.count
        typeToSelf("x")
        check(eventually { model.prompts.count > asked }, "typing off the suggestion asks again")
        _ = eventually { h.text.hasSuffix("x") }  // Or it lands in the next test's window.
        usleep(100_000)
    }

    static func hides() {
        let h = Harness(completer: FakeCompleter(" world"))
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        check(eventually { h.visible }, "ghost appears")
        check(h.tap.armed.load(ordering: .relaxed), "tap armed while it shows")
        usleep(150_000)  // The insert's last event would set the caret back.
        // AX to this same process runs on the calling thread and can read before a change lands, so each gets a second look. Another app is IPC.
        func select(_ location: Int, _ length: Int) {
            onMain { h.view.setSelectedRange(NSRange(location: location, length: length)) }
            usleep(30_000)
            h.watcher.scheduleUpdate()
        }
        select(0, 3)
        check(eventually { !h.visible }, "selection hides it")
        select(2, 0)
        usleep(300_000)
        check(!h.visible, "text after the caret hides it")
        check(!h.tap.armed.load(ordering: .relaxed), "tap disarmed when hidden")
        select(5, 0)
        check(eventually { h.visible }, "back at the end it shows again")
        onMain { h.window.setFrameOrigin(CGPoint(x: 100, y: 100)) }
        check(eventually { !h.visible }, "window move hides it")
    }

    static func secure() {
        let h = Harness(completer: FakeCompleter(" world"))
        defer { h.close() }
        onMain {
            let secure = NSSecureTextField(frame: CGRect(x: 10, y: 10, width: 200, height: 24))
            h.window.contentView!.addSubview(secure)
            h.window.makeFirstResponder(secure)
        }
        usleep(100_000)
        let ax = AXUIElementCreateApplication(getpid())
        let focused = AX.element(AX.get(ax, "AXFocusedUIElement"))
        check(focused.map(Reader.isEditableText) == false, "a secure field isn't text entry")
    }

    static func insertion() {
        let h = Harness(completer: FakeCompleter(""))
        defer { h.close() }
        let text = "한글이 잘 들어가는지 확인합니다 and English 😀👨‍👩‍👧‍👦 mixed, longer than one chunk."
        typeToSelf(text)
        check(eventually { h.text == text }, "Hangul, emoji and long text arrive whole and in order")
    }

    /// A private host, frozen with SIGSTOP, is a hung app.
    static func hung() {
        let host = Process()
        host.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        host.environment = ["ITDA_E2E_HOST": "1"]
        guard (try? host.run()) != nil else { return check(false, "host starts") }
        defer { host.terminate(); kill(host.processIdentifier, SIGCONT) }
        usleep(1_000_000)
        let ax = AXUIElementCreateApplication(host.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, AX.timeout)
        check(AX.get(ax, "AXRole") != nil, "host answers before it hangs")
        kill(host.processIdentifier, SIGSTOP)
        let start = Date()
        _ = AX.get(ax, "AXFocusedUIElement")
        let elapsed = Date().timeIntervalSince(start)
        check(elapsed < 0.5, "a hung app costs one timeout: \(Int(elapsed * 1000)) ms")
    }

    /// The real tap on a harmless key, F20, with a listener behind it to see what gets through.
    static func tap() {
        let tap = KeyTap(acceptKey: 90)
        let accepted = Atomic<Int>(0)
        tap.onAccept = { _ in accepted.add(1, ordering: .relaxed) }
        guard tap.start() else { return check(false, "tap starts") }
        let listener = Thread {
            let callback: CGEventTapCallBack = { _, _, event, refcon in
                if event.getIntegerValueField(.keyboardEventKeycode) == 90 { Unmanaged<AtomicBox>.fromOpaque(refcon!).takeUnretainedValue().count.add(1, ordering: .relaxed) }
                return Unmanaged.passUnretained(event)
            }
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                               callback: callback, userInfo: Unmanaged.passRetained(listened).toOpaque()) else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CFRunLoopRun()
        }
        listener.start()
        usleep(200_000)
        func press() {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 90, keyDown: true)!
            e.post(tap: .cgSessionEventTap)
            usleep(150_000)
        }
        press()
        check(accepted.load(ordering: .relaxed) == 0 && listened.count.load(ordering: .relaxed) == 1, "disarmed: the key passes, nothing accepted")
        tap.armed.store(true, ordering: .relaxed)
        press()
        check(accepted.load(ordering: .relaxed) == 1 && listened.count.load(ordering: .relaxed) == 1, "armed: the key is swallowed and accepted")
        tap.armed.store(false, ordering: .relaxed)
    }

    /// Value change to ghost on screen. The host and the panel share a main thread here, which only makes it slower.
    static func latency() {
        let h = Harness(completer: FakeCompleter(String(repeating: " abcde", count: 8)))
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        _ = eventually { h.visible }
        var times: [Double] = []
        for c in String(repeating: " abcde", count: 5).map(String.init) {
            let before = h.ghostText
            let start = Date()
            typeToSelf(c)
            _ = eventually { h.ghostText != before }
            times.append(Date().timeIntervalSince(start) * 1000)
            usleep(10_000)
        }
        times.sort()
        print("      key to ghost moved, ms: p50 \(Int(times[times.count / 2])) max \(Int(times.last!))")
        check(times[times.count / 2] < 30, "ghost follows typing within a frame or two")
    }
}

// MARK: The live input method

extension EndToEnd {
    private static var idleSeconds: Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) }

    /// `--ime`: Tab against Apple's real 2-set input method in the private window, with the real watcher. Selecting the source reaches
    /// the whole system, so it only runs with the user idle and stops the moment they aren't; scripts/e2e.sh puts the source back.
    static func ime() {
        guard idleSeconds > 15 else { return check(false, "needs the user idle for 15 s, was \(Int(idleSeconds)) s: run again") }
        let h = Harness(completer: FakeCompleter(""))
        defer { h.close() }
        let before: String? = onMain {
            let context = h.view.inputContext!
            let was = context.selectedKeyboardInputSource
            context.selectedKeyboardInputSource = TwoSetLayout.source
            context.activate()
            return was
        }
        defer { onMain { h.view.inputContext!.selectedKeyboardInputSource = before; h.view.inputContext!.deactivate() } }
        print("      source here:", onMain { h.view.inputContext!.selectedKeyboardInputSource ?? "nil" }, "| system-wide:", shell(CommandLine.arguments[0], ["--source-id"]).trimmingCharacters(in: .whitespacesAndNewlines))
        h.watcher.koreanInput.store(true, ordering: .relaxed)
        h.watcher.twoSet.store(true, ordering: .relaxed)
        h.watcher.bind(pid: getpid())
        usleep(200_000)

        func clear() {
            // AX to this same process runs on the calling thread, and deadlocks with TextKit on main, so the watcher holds still. Another app is IPC.
            h.watcher.queue.sync { onMain { h.view.inputContext!.discardMarkedText(); h.view.string = "" } }
            h.tap.composing.store(false, ordering: .relaxed)
            usleep(50_000)
        }
        func press(_ jamo: String) {
            if idleSeconds < 1 {
                print("the user is back: stopping")
                exit(3)
            }
            h.tap.composing.store(true, ordering: .relaxed)  // What the tap does for a real key: these go past it, to this process only.
            Inserter.press(TwoSetLayout.strokes(jamo)!) { $0.postToPid(getpid()) }
        }
        func tab(all: Bool = false) { h.watcher.queue.async { h.watcher.accept(all: all) } }

        // The table against the live input method: each jamo alone, shift included.
        var wrong: [String] = []
        for jamo in "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ" {
            clear()
            press(String(jamo))
            if !eventually(1, { h.text == String(jamo) }) { wrong.append("\(jamo) gave '\(h.text)'") }
        }
        check(wrong.isEmpty, "all 33 jamo type themselves on the live input method \(wrong)")

        func accepts(_ name: String, start: String = "그 ", typed: String, suggestion: String, ghost: String, first: String, rest: String) {
            clear()
            h.watcher.completer = FakeCompleter(suggestion)
            Inserter.insert(start) { $0.postToPid(getpid()) }
            check(eventually { h.text == start }, "\(name): start")
            press(typed)
            check(eventually { h.ghostText == ghost }, "\(name): shows '\(ghost)', field '\(h.text)', ghost '\(h.ghostText ?? "nil")'")
            tab()
            check(eventually { h.text == start + first }, "\(name): Tab gives '\(first)': '\(h.text)'")
            tab(all: true)
            check(eventually { h.text == start + first + rest }, "\(name): Shift-Tab gives the rest: '\(h.text)'")
        }
        accepts("하 to 한 다음", typed: "ㅎㅏ", suggestion: " 한 다음 날", ghost: " 다음 날", first: "한 다음", rest: " 날")
        accepts("달 to 다라", typed: "ㄷㅏㄹ", suggestion: " 다라가 왔어", ghost: "가 왔어", first: "다라가", rest: " 왔어")
        accepts("값, double final, two keys", typed: "ㄱㅏ", suggestion: " 값이 싸", ghost: "이 싸", first: "값이", rest: " 싸")
        accepts("값, second key moves on", typed: "ㄱㅏㅂㅅ", suggestion: " 갑시다 정말", ghost: "다 정말", first: "갑시다", rest: " 정말")
        accepts("과, compound vowel", typed: "ㄱㅗ", suggestion: " 과자 맛", ghost: "자 맛", first: "과자", rest: " 맛")
        accepts("갔, shifted final", typed: "ㄱㅏ", suggestion: " 갔어 어제", ghost: "어 어제", first: "갔어", rest: " 어제")
        accepts("얘, shifted vowel", typed: "ㅇ", suggestion: " 얘기 해봐", ghost: "기 해봐", first: "얘기", rest: " 해봐")
        accepts("from a lone jamo", typed: "ㅎ", suggestion: " 한 다음 날", ghost: " 다음 날", first: "한 다음", rest: " 날")

        // Every composition state of harder words: type a prefix of the keys, Tab for all of it, expect the word.
        var bad: [String] = []
        for word in ["괜찮아요", "닭고기", "없어요", "앉아서", "많이", "의사", "뷁", "왜요", "떡볶이", "빨리", "까치", "짜장", "쌀밥", "예의", "외워", "됐어", "읽어"] {
            let keys = Array(Hangul.keys(word))
            h.watcher.completer = FakeCompleter(" " + word + " 끝")
            for count in 1..<keys.count {
                clear()
                Inserter.insert("그 ") { $0.postToPid(getpid()) }
                guard eventually(3, { h.text == "그 " }) else { continue }
                press(String(keys[..<count]))
                _ = eventually(1) { Hangul.keys(h.text) == "그 " + String(keys[..<count]) }
                usleep(40_000)  // And the watcher's turn. The ghost from before the key is up too, so `visible` can't say.
                guard h.visible else { continue }  // Nothing to draw once the keys reach the word's end.
                tab(all: true)
                if !eventually(1, { h.text == "그 \(word) 끝" }) { bad.append("\(word)@\(count): '\(h.text)'") }
            }
        }
        check(bad.isEmpty, "every composing state of 17 hard words finishes right \(bad)")

        // Tab-Tab with no time between them, through a two-key syllable.
        clear()
        h.watcher.completer = FakeCompleter(" 값이 싸 정말")
        Inserter.insert("그 ") { $0.postToPid(getpid()) }
        _ = eventually { h.text == "그 " }
        press("ㄱㅏ")
        _ = eventually { h.ghostText == "이 싸 정말" }
        h.watcher.queue.async { h.watcher.accept(all: false); h.watcher.accept(all: false) }
        check(eventually { h.text == "그 값이 싸" }, "two fast Tabs, each word once: '\(h.text)'")

        // A click or an arrow commits the syllable with no change in the field. The signal says so: the ghost that needed 한 goes.
        clear()
        h.watcher.completer = FakeCompleter(" 한 다음")
        Inserter.insert("그 ") { $0.postToPid(getpid()) }
        _ = eventually { h.text == "그 " }
        press("ㅎㅏ")
        check(eventually { h.ghostText == " 다음" }, "composing 하: ghost up")
        Inserter.press([Inserter.commitKey]) { $0.postToPid(getpid()) }
        h.tap.composing.store(false, ordering: .relaxed)
        h.watcher.completer = FakeCompleter("")
        h.watcher.scheduleUpdate()
        check(eventually { !h.visible }, "committed 하, suggestion needs 한: ghost gone")
        check(!h.tap.armed.load(ordering: .relaxed) && h.text == "그 하", "and Tab stays the host's: '\(h.text)'")

        // The worst case, if the signal were wrong: a jamo typed after a committed syllable stands alone, one backspace to fix.
        Inserter.press(TwoSetLayout.strokes("ㄴ")! + [Inserter.commitKey]) { $0.postToPid(getpid()) }
        Inserter.insert(" 다음") { $0.postToPid(getpid()) }
        _ = eventually { h.text.hasSuffix("다음") }
        print("      worst case, signal wrong on a committed 하:", "'\(h.text)'")

        // Any other Korean layout: no ghost in the state that would need keys, and a ghost in the state that doesn't.
        clear()
        h.watcher.twoSet.store(false, ordering: .relaxed)
        h.watcher.completer = FakeCompleter(" 한 다음")
        Inserter.insert("그 ") { $0.postToPid(getpid()) }
        _ = eventually { h.text == "그 " }
        press("ㅎㅏ")
        usleep(400_000)
        check(!h.visible, "not 2-set, 하 needing 한: no ghost")
        clear()
        h.watcher.completer = FakeCompleter(" 하늘은 맑아")
        Inserter.insert("그 ") { $0.postToPid(getpid()) }
        _ = eventually { h.text == "그 " }
        press("ㅎㅏ")
        check(eventually { h.ghostText == "늘은 맑아" }, "not 2-set, 하 fits as it is: ghost")
        clear()
    }

    /// `--engine <gguf>`: the real model behind the real path, with the real composing argument, on the live input method.
    static func engine(path: String) {
        guard let engine = try? Engine(modelPath: path) else { return check(false, "engine loads") }
        defer { engine.unload() }
        let h = Harness(completer: engine)
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("Thanks, see you to")
        check(eventually(6) { h.ghostText?.hasPrefix("morrow") == true }, "real engine, English: '\(h.ghostText ?? "nil")'")
        h.watcher.queue.sync { onMain { h.view.string = "" } }
        h.watcher.koreanInput.store(true, ordering: .relaxed)
        h.watcher.twoSet.store(true, ordering: .relaxed)
        h.tap.composing.store(true, ordering: .relaxed)
        // The composing argument reaches the model: 하 is withheld, and what comes back must fit its keys.
        typeToSelf("오늘 날씨가 정말 좋아서 공원에 산책하")
        let before = h.ghostText
        check(eventually(6) { h.visible && h.ghostText != before }, "real engine, composing 하: '\(h.ghostText ?? "nil")'")
    }

    private static func stats(_ what: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let wired = shell("/usr/bin/vm_stat", []).split(separator: "\n").first { $0.contains("wired down") }?.split(separator: " ").last.flatMap { Int($0.dropLast()) } ?? 0
        let mb = { (bytes: UInt64) in Int(bytes / 1_048_576) }
        print("[\(what)] footprint \(mb(info.phys_footprint)) MB, RSS \(mb(UInt64(info.resident_size))) MB, compressed \(mb(info.compressed)) MB, Metal allocated \(mb(UInt64(metal?.currentAllocatedSize ?? 0))) MB, system wired \(wired * Int(vm_page_size) / 1_048_576) MB")
    }
    nonisolated(unsafe) private static var metal = MTLCreateSystemDefaultDevice()

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func tool(_ path: String, _ args: [String], keeping lines: (Substring) -> Bool) {
        for line in shell(path, args).split(separator: "\n") where lines(line) { print("   ", line) }
    }

    /// `--measure <gguf>`: memory and CPU of the real path under typing in the private window, then idle, then 20 reloads.
    static func measure(path: String) {
        let me = "\(getpid())"
        func report(_ what: String) {
            stats(what)
            tool("/usr/bin/footprint", [me], keeping: { $0.contains("phys_footprint") || $0.contains("IOAccelerator") || $0.contains("Footprint:") || $0.contains("graphics") || $0.contains("VM_ALLOCATE") || $0.contains("mapped file") })
            tool("/usr/bin/vmmap", ["--summary", me], keeping: { $0.contains("REGION TYPE") || $0.contains("IOAccelerator") || $0.contains("mapped file") || $0.contains("Physical footprint") || $0.hasPrefix("TOTAL") })
        }
        report("before load")
        guard let engine = try? Engine(modelPath: path) else { return check(false, "engine loads") }
        report("loaded, nothing asked")
        // A long prompt from nothing, then one key on, then a reload: what a smaller wired set might cost.
        do {
            let filler = String(repeating: "The quick brown fox jumps over the lazy dog near the river bank at dawn. ", count: 14)
            func timed(_ label: String, _ prefix: String, _ fragment: String) {
                let start = Date()
                engine.suggest(prefix: prefix, fragment: fragment, composing: "", onResult: { _ in })
                engine.finish()
                print("\(label): \(Int(Date().timeIntervalSince(start) * 1000)) ms")
            }
            for _ in 0..<2 { timed("long prompt, cold memory", filler + "We", " sh"); timed("next key", filler + "We", " sho"); engine.unload(); usleep(200_000) }
            timed("after reload, short", "Hello my", " fr")
            Thread.sleep(forTimeInterval: 30)
            timed("after 30 s idle, short", "Hello my friend", " is")
            stats("after 30 s idle")
        }
        let h = Harness(completer: engine)
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        let typing = "Thanks for the update, I will take a look at the build this afternoon and get back to you with notes. 오늘 회의는 세 시에 시작하고 끝나면 다시 정리해서 공유드리겠습니다. "
        let cpu0 = cpuSeconds(), start = Date()
        var keys = 0, shown = 0
        for _ in 0..<2 {
            for c in typing {
                typeToSelf(String(c))
                keys += 1
                usleep(UInt32(120_000 + Int.random(in: 0..<120_000)))
                if h.visible { shown += 1 }
            }
        }
        let seconds = Date().timeIntervalSince(start)
        print("typed \(keys) keys in \(Int(seconds)) s, ghost up on \(shown); CPU \(Int((cpuSeconds() - cpu0) / seconds * 100))% of a core while typing")
        report("after typing, model loaded")
        h.close()
        engine.cancel()
        for label in ["1", "2"] {
            let cpu = cpuSeconds()
            Thread.sleep(forTimeInterval: 20)
            print("idle \(label), model loaded: \((cpuSeconds() - cpu) / 20 * 100)% CPU")
        }
        report("idle, model loaded")
        engine.unload()
        usleep(500_000)
        report("unloaded")
        let cpu = cpuSeconds()
        Thread.sleep(forTimeInterval: 10)
        print("idle, unloaded: \((cpuSeconds() - cpu) / 10 * 100)% CPU")
        for cycle in 1...20 {
            engine.suggest(prefix: "Hello my", fragment: " fr", composing: "", onResult: { _ in })
            engine.finish()
            if cycle % 10 == 0 { stats("loaded, reload \(cycle)") }
            engine.unload()
            usleep(200_000)
            if cycle % 5 == 0 { stats("unloaded, reload \(cycle)") }
        }
        report("end")
    }
}
