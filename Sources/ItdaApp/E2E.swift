// End-to-end checks against a private window, built only by scripts/e2e.sh. The test runner can't host this: it needs a
// real NSApplication run loop to serve AX and events, as the shipped app has.
#if ITDA_E2E
import AppKit
import ItdaCore
import ItdaEngine
import Synchronization

final class FakeCompleter: Completer, @unchecked Sendable {
    let text: String
    private let log = Mutex<[(prefix: String, fragment: String)]>([])
    var prompts: [(prefix: String, fragment: String)] { log.withLock { $0 } }
    init(_ text: String) { self.text = text }
    func suggest(prefix: String, fragment: String, onResult: @escaping @Sendable (String, Double?) -> Void) {
        log.withLock { $0.append((prefix, fragment)) }
        onResult(text, 0)
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
        main { self.watcher.hideNow(); self.window.orderOut(nil) }
    }

    var caretX: CGFloat { main { self.view.firstRect(forCharacterRange: NSRange(location: self.view.selectedRange().location, length: 0), actualRange: nil).minX } }
    var ghostX: CGFloat? {
        main {
            guard let layout = self.panel.view.layout else { return nil }
            return self.panel.frame.minX + layout.drawOrigin.x + layout.manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minX + layout.manager.location(forGlyphAt: 0).x
        }
    }
    var text: String { main { self.view.string } }
    var visible: Bool { main { self.panel.isVisible } }
    var ghostText: String? { main { self.panel.view.layout?.visibleText } }
}

func main<T>(_ work: () -> T) -> T { DispatchQueue.main.sync(execute: work) }

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
        if CommandLine.arguments.contains("--front-id") {
            print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
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

    /// Reads a field in another app without focusing it: `--read <pid> <url part>` prints what the reader sees.
    static func readWeb(pid: pid_t, url: String) {
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 2)
        func walk(_ e: AXUIElement, _ inside: Bool, _ depth: Int) {
            guard depth < 60, let role = AX.get(e, "AXRole") as? String else { return }
            var inside = inside
            if role == "AXWebArea" {
                guard (AX.get(e, "AXURL").map { "\($0)" } ?? "").contains(url) else { return }  // No other tab is read.
                inside = true
            }
            if inside, Reader.textRoles.contains(role) {
                let id = AX.get(e, "AXDOMIdentifier") as? String ?? "?"
                let start = Date()
                let reading = Reader.read(e, koreanInput: false)
                let readMs = Date().timeIntervalSince(start) * 1000
                let traits = reading.flatMap { Reader.traits(e, before: $0.field.before) }
                let context = Reader.context(of: e)
                print("field", id, role, "editable", Reader.isEditableText(e), "before", reading?.field.before ?? "nil", "after", reading?.field.after ?? "nil", "caret", reading?.caret ?? .null,
                      "frame", reading?.frame ?? .null, "font", traits?.fontSize ?? 0, traits?.fontName ?? "-", "lineLeft", traits?.lineLeft ?? -1, "color", traits?.color?.components ?? [], "read ms", Int(readMs))
                print("  context tail:", String(context.suffix(70)).replacingOccurrences(of: "\n", with: " / "), "| chars", context.count)
                return
            }
            for child in AX.get(e, "AXChildren") as? [AXUIElement] ?? [] { walk(child, inside, depth + 1) }
        }
        walk(ax, false, 0)
    }

    /// `--front`: the frontmost app's focused element, what would be used, and how long it takes. Read-only.
    static func front() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        let ax = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        guard let e = AX.element(AX.get(ax, "AXFocusedUIElement")) else { return print(front.bundleIdentifier ?? "?", "no focused element") }
        let start = Date()
        let reading = Reader.read(e, koreanInput: false)
        let read = Date().timeIntervalSince(start) * 1000
        let traits = reading.flatMap { Reader.traits(e, before: $0.field.before) }
        let t2 = Date()
        let context = Reader.context(of: e)
        print(front.bundleIdentifier ?? "?", AX.get(e, "AXRole") ?? "?" as CFTypeRef, "editable", Reader.isEditableText(e), "before chars", reading?.field.before.count ?? -1, "after chars", reading?.field.after.count ?? -1,
              "caret", reading?.caret ?? .null, "frame", reading?.frame ?? .null, "font", traits?.fontSize ?? 0, "lineLeft", traits?.lineLeft ?? -1, "color", traits?.color?.components ?? [],
              "read ms", Int(read), "context ms", Int(Date().timeIntervalSince(t2) * 1000), "context chars", context.count)
        print("context tail:", context.suffix(50).replacingOccurrences(of: "\n", with: " / "))
    }

    /// `--ime`: does text inserted after a live Hangul composition arrive in order? Selects the Korean input source only for this
    /// window's input context, and refuses unless the user has been idle, as that source can be system-wide.
    static func ime() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        print("idle seconds", Int(idle))
        guard idle > 20 else { return print("not idle, skipping") }
        let h = Harness(completer: FakeCompleter(""))
        defer { h.close() }
        let korean = "com.apple.inputmethod.Korean.2SetKorean"
        let before: String? = ItdaApp.main {
            let context = h.view.inputContext!
            let was = context.selectedKeyboardInputSource
            print("sources", context.keyboardInputSources?.filter { $0.contains("Korean") } ?? [], "was", was ?? "nil")
            context.selectedKeyboardInputSource = korean
            context.activate()
            print("now", context.selectedKeyboardInputSource ?? "nil")
            return was
        }
        defer { ItdaApp.main { h.view.inputContext!.selectedKeyboardInputSource = before; h.view.inputContext!.deactivate() } }
        func key(_ code: CGKeyCode) {
            for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!.postToPid(getpid()) }
            usleep(60_000)
        }
        func state() -> String { ItdaApp.main { "'\(h.view.string)' marked \(h.view.hasMarkedText()) \(h.view.markedRange())" } }
        func clear() { ItdaApp.main { h.view.inputContext!.discardMarkedText(); h.view.string = "" } }
        // 2-set: g ㅎ, k ㅏ, s ㄴ.
        key(5); key(40)
        print("하:", state())
        key(1 + 44)  // n is ㅜ on 2-set; 45 is the n key.
        print("then ㅜ:", state())
        clear()
        key(5); key(40); key(1)  // s
        print("한 (ㄴ joined, so the composition is live):", state())
        Inserter.insert("세요") { $0.postToPid(getpid()) }
        usleep(300_000)
        print("insert 세요:", state())
        key(40)
        print("then ㅏ: if it joined anything the composition was still live:", state())
        clear()
        // No pause between the syllable and the insert, as a fast Tab would be.
        for code: CGKeyCode in [5, 40, 1] { for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!.postToPid(getpid()) } }
        Inserter.insert(" 안녕하세요") { $0.postToPid(getpid()) }
        usleep(400_000)
        print("no pause, 한 + insert:", state())
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

    /// `--engine <gguf>`: the real model behind the real path, in the private window.
    static func engine(path: String) {
        guard let engine = try? Engine(modelPath: path) else { return check(false, "engine loads") }
        print("cold start s", engine.coldStartSeconds)
        let h = Harness(completer: engine)
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        for (typed, wait) in [("Earlier we said we would meet at three. See you to", 6.0), ("morrow at", 6.0), (" 오늘 회의는 세 시에", 6.0)] {
            let start = Date()
            typeToSelf(typed)
            let shown = eventually(wait) { h.visible }
            print("typed '\(typed)' ghost '\(h.ghostText ?? "nil")' after ms", Int(Date().timeIntervalSince(start) * 1000), "shown", shown)
        }
        engine.unload()
    }

    static func run() {
        if let i = CommandLine.arguments.firstIndex(of: "--engine") { return engine(path: CommandLine.arguments[i + 1]) }
        if let i = CommandLine.arguments.firstIndex(of: "--shots") {
            return ItdaApp.main { shots(to: CommandLine.arguments[i + 1]) }
        }
        if CommandLine.arguments.contains("--ime") { return ime() }
        if CommandLine.arguments.contains("--front") { return front() }
        if let i = CommandLine.arguments.firstIndex(of: "--read") { return readWeb(pid: pid_t(CommandLine.arguments[i + 1])!, url: CommandLine.arguments[i + 2]) }
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
        ItdaApp.main { check(h.panel.ignoresMouseEvents && !h.panel.canBecomeKey && !h.panel.isKeyWindow, "panel is click-through and never key") }
        let frontNow = frontmost()
        print("      front:", frontNow.trimmingCharacters(in: .whitespacesAndNewlines), "me:", getpid(), "isActive", ItdaApp.main({ NSApp.isActive }), "text:", h.text)
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
    }

    static func hides() {
        let h = Harness(completer: FakeCompleter(" world"))
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        check(eventually { h.visible }, "ghost appears")
        check(h.tap.armed.load(ordering: .relaxed), "tap armed while it shows")
        ItdaApp.main { h.view.setSelectedRange(NSRange(location: 0, length: 3)) }
        check(eventually { !h.visible }, "selection hides it")
        ItdaApp.main { h.view.setSelectedRange(NSRange(location: 2, length: 0)) }
        usleep(300_000)
        check(!h.visible, "text after the caret hides it")
        check(!h.tap.armed.load(ordering: .relaxed), "tap disarmed when hidden")
        ItdaApp.main { h.view.setSelectedRange(NSRange(location: 5, length: 0)) }
        check(eventually { h.visible }, "back at the end it shows again")
        ItdaApp.main { h.window.setFrameOrigin(CGPoint(x: 100, y: 100)) }
        check(eventually { !h.visible }, "window move hides it")
    }

    static func secure() {
        let h = Harness(completer: FakeCompleter(" world"))
        defer { h.close() }
        ItdaApp.main {
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
#endif
