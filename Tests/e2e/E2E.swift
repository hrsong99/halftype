// End-to-end checks against a private window, run by scripts/e2e.sh. The test runner can't host this: it needs a
// real NSApplication run loop to serve AX and events, as the shipped app has.
import AppKit
import Carbon
@testable import ItdaApp
import ItdaCore
@testable import ItdaEngine
import Metal
import SwiftUI
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

/// Hands each request's callback to the test, to release when it likes.
final class HeldCompleter: Completer, @unchecked Sendable {
    let held = Mutex<(@Sendable (Suggestion?) -> Void)?>(nil)
    let cancels = Atomic<Int>(0)
    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void) { held.withLock { $0 = onResult } }
    func release(_ text: String) { held.withLock { $0 }?(Suggestion(text: text, gate: 0)) }
    func cancel() { cancels.add(1, ordering: .relaxed) }
    func unload() {}
}

final class TestTextView: NSTextView {
    /// False says of a live composition what Chromium says: nothing. True leaves the native attribute, which 2-set leaves empty over a live syllable.
    var reportsMarkedText = true
    /// What a host that does report one says, as no host here does live: the positive branch needs its own fixture.
    var reportedMark: NSRange?
    override func accessibilityAttributeValue(_ attribute: NSAccessibility.Attribute) -> Any? {
        guard attribute.rawValue == "AXTextInputMarkedRange" else { return super.accessibilityAttributeValue(attribute) }
        return reportsMarkedText ? reportedMark.map { NSValue(range: $0) } ?? super.accessibilityAttributeValue(attribute) : nil
    }
    override func complete(_ sender: Any?) {}  // Escape's completion list.

    /// One font read that comes back empty, as a host's can in passing.
    var failsNextAttributes = false
    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        if failsNextAttributes {
            failsNextAttributes = false
            return nil
        }
        return super.accessibilityAttributedString(for: range)
    }

    /// A host that hasn't got to its keys yet, or never will.
    var holdsKeys = false
    private var heldKeys: [NSEvent] = []
    override func keyDown(with event: NSEvent) {
        if holdsKeys { heldKeys.append(event) } else { super.keyDown(with: event) }
    }
    func letKeysThrough() {
        holdsKeys = false
        heldKeys.forEach(keyDown)
        heldKeys = []
    }
}

/// What the watcher reads for context, to stall that read as a slow app would. AX to this process runs on the calling thread.
final class ContextLabel: NSTextField {
    let onRead = Mutex<(@Sendable () -> Void)?>(nil)
    override func accessibilityValue() -> String? {
        onRead.withLock { let once = $0; $0 = nil; return once }?()
        return super.accessibilityValue()
    }
}

/// The real panel, with its boundaries visible to the test.
final class TestPanel: GhostPanel {
    var afterShow: (() -> Void)?
    var lastShow: Bool?
    var hiddenAt: Date?
    var gaps: [Double] = []
    override func show(_ spec: GhostSpec) -> Bool {
        let shown = super.show(spec)
        lastShow = shown
        if shown, let hiddenAt { gaps.append(Date().timeIntervalSince(hiddenAt) * 1000) }
        if shown { hiddenAt = nil }
        let hook = afterShow
        afterShow = nil
        hook?()
        return shown
    }
    override func hideGhost() {
        if isVisible { hiddenAt = Date() }
        super.hideGhost()
    }
}

/// A real text view in a window of this process, reached the way the app reaches any other: through AX, with the real
/// observer and panel. Key events go to this process only, so nothing else on the Mac sees them. It never activates.
final class Harness {
    var window: NSPanel!
    var view: TestTextView!
    var panel: TestPanel!
    var label: ContextLabel!
    let tap = Harness.sharedTap
    var watcher: Watcher!
    /// The real tap, on this process only: key events go past it to the window, and nobody else sees them.
    static let sharedTap: KeyTap = {
        let tap = KeyTap(pid: getpid())
        guard tap.start() else { fatalError("tap needs Accessibility") }
        return tap
    }()

    init(completer: Completer, reportsMarkedText: Bool = true) {
        DispatchQueue.main.sync {
            window = NSPanel(contentRect: CGRect(x: 80, y: 80, width: 420, height: 160), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            window.level = .floating
            label = ContextLabel(labelWithString: "Earlier message from the other person")
            label.frame = CGRect(x: 10, y: 130, width: 400, height: 20)
            view = TestTextView(frame: CGRect(x: 10, y: 10, width: 400, height: 110))
            view.reportsMarkedText = reportsMarkedText
            view.font = .systemFont(ofSize: 15)
            view.isAutomaticQuoteSubstitutionEnabled = false
            window.contentView!.addSubview(label)
            window.contentView!.addSubview(view)
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            panel = TestPanel()
            watcher = Watcher(tap: tap, panel: panel)
            watcher.completer = completer
        }
    }

    var armed: Bool { tap.state.withLock { $0.armed != nil } }

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

/// A key as the user presses it: through the tap, so not marked as ours.
func physical(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    event.flags = flags
    event.postToPid(getpid())
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
    up.flags = flags
    up.postToPid(getpid())
}
func physical(typing text: String) {
    for stroke in TwoSetLayout.strokes(Hangul.keys(text))! { physical(stroke.code, stroke.shift ? .maskShift : []) }
}
func tabKey(all: Bool = false) { physical(48, all ? .maskShift : []) }
/// Typing whatever the input source: text, but through the tap as input.
func physical(character: String) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    event.keyboardSetUnicodeString(stringLength: character.utf16.count, unicodeString: Array(character.utf16))
    event.postToPid(getpid())
}

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
        if CommandLine.arguments.contains("--key-idle") {
            print(Int(CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)))
            exit(0)
        }
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

    /// `--window-shots <dir>`: the real window's pages, rendered without opening anything on screen.
    static func windowShots(to dir: String) {
        let app = App()
        app.ready = true
        app.trusted = true
        for (name, page, dark) in [("field", Root.Page.field, false), ("field-dark", .field, true), ("models", .models, false), ("general", .general, false), ("apps", .apps, false), ("picker", .field, false)] {
            let host = NSHostingView(rootView: Root(app: app, page: page, sidebar: page != .field, picking: name == "picker"))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 720, height: 500)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("window-\(name).png"))
        }
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
        let started = Date()
        if let i = CommandLine.arguments.firstIndex(of: "--engine") { return engine(path: CommandLine.arguments[i + 1]) }
        if let i = CommandLine.arguments.firstIndex(of: "--measure") { return measure(path: CommandLine.arguments[i + 1]) }
        if CommandLine.arguments.contains("--own-window") { return ownWindow() }
        if let i = CommandLine.arguments.firstIndex(of: "--window-shots") {
            return onMain { windowShots(to: CommandLine.arguments[i + 1]) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--shots") {
            return onMain { shots(to: CommandLine.arguments[i + 1]) }
        }
        if CommandLine.arguments.contains("--ime") { return ime() }
        if CommandLine.arguments.contains("--flicker") { return flicker() }
        if CommandLine.arguments.contains("--stale") { return staleSnapshots() }
        frontAtStart = frontmost()
        ghostAtCaret()
        ownWindow()
        hides()
        secure()
        insertion()
        hung()
        races()
        staleSnapshots()
        latency()
        flicker()
        sessionPath()
        // The test panel holds keyboard focus without activating, so real keys land in it and read as failures.
        if CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < Date().timeIntervalSince(started) { print("WARNING: someone typed during this run. Its failures may only be those keys, and those keys didn't reach their app.") }
        check(frontmost() == frontAtStart && !frontAtStart.isEmpty, "frontmost app unchanged by the whole run: \(frontAtStart.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    nonisolated(unsafe) static var frontAtStart = ""

    /// Itda's own window: the field there is reached like any other app's, through AX, and takes the ghost and Tab.
    static func ownWindow() {
        let h = Harness(completer: FakeCompleter(" there friend"))
        defer { h.close() }
        func textView(in view: NSView) -> NSTextView? { (view as? NSTextView) ?? view.subviews.lazy.compactMap(textView).first }
        let (window, field): (NSPanel, NSTextView?) = onMain {
            h.window.orderOut(nil)
            let app = App()
            app.trusted = true
            app.ready = true
            let window = NSPanel(contentRect: CGRect(x: 80, y: 80, width: 720, height: 500), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: Root(app: app))
            window.orderFrontRegardless()
            window.makeKey()
            window.contentView!.layoutSubtreeIfNeeded()
            return (window, textView(in: window.contentView!))
        }
        defer { onMain { window.orderOut(nil) } }
        guard let field else { return check(false, "own window has a text view") }
        onMain { _ = window.makeFirstResponder(field) }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        check(eventually { onMain { field.string } == "hello" }, "own window: keys reach the field: '\(onMain { field.string })'")
        check(eventually { h.visible }, "own window: ghost appears")
        tabKey()
        check(eventually { onMain { field.string } == "hello there" }, "own window: Tab accepts the next word: '\(onMain { field.string })'")
    }

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

        tabKey()
        check(eventually { h.text == "hello there" }, "Tab accepts the next word")
        check(eventually { h.ghostText?.hasPrefix(" friend") == true }, "ghost shrinks to what's left without asking the model again: \(h.ghostText ?? "nil")")
        check(abs((h.ghostX ?? -99) - h.caretX) < 1, "ghost moved with the caret")
        // Tab-Tab with no time for the host to report the first: each word goes in once.
        tabKey()
        tabKey()
        check(eventually { h.text == "hello there friend, how" }, "two fast Tabs accept two words: \(h.text)")
        _ = eventually { h.armed }
        tabKey(all: true)
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
        check(h.armed, "tap armed while it shows")
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
        check(!h.armed, "tap disarmed when hidden")
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

    /// A ghost up in a fresh harness, its model holding the rest back. A blocked queue stands for an unresponsive AX read.
    static func raceHarness() -> (h: Harness, model: HeldCompleter) {
        let model = HeldCompleter()
        let h = Harness(completer: model)
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        _ = eventually { model.held.withLock { $0 != nil } && h.text == "hello" }
        usleep(50_000)
        model.release(" there friend how")
        _ = eventually { h.armed }
        return (h, model)
    }

    static func blockingReader(_ h: Harness, while work: () -> Void) {
        let gate = DispatchSemaphore(value: 0)
        h.watcher.queue.async { gate.wait() }
        work()
        gate.signal()
        h.watcher.queue.sync {}
    }

    /// What a late AX read, display or result must not be able to do.
    static func races() {
        do {
            let (h, _) = raceHarness()
            defer { h.close() }
            check(h.armed, "race: ghost armed")
            blockingReader(h) {
                tabKey()
                check(eventually { h.text == "hello there" }, "Tab lands with the reader blocked: '\(h.text)'")
                physical(36)
                check(eventually { h.text == "hello there\n" }, "then Return, in order")
                check(!h.armed, "Return disarms at once")
                tabKey()
                check(eventually { h.text == "hello there\n\t" }, "the next Tab is the app's: '\(h.text.debugDescription)'")
            }
            usleep(200_000)
            check(h.text == "hello there\n\t", "nothing inserted when the reader comes back: \(h.text.debugDescription)")
        }
        do {
            let (h, model) = raceHarness()
            defer { h.close() }
            let hold = DispatchSemaphore(value: 0), holding = DispatchSemaphore(value: 0)
            DispatchQueue.main.async { holding.signal(); hold.wait() }
            holding.wait()
            model.release(" there friend how are you")  // Its display waits behind the blocked main thread.
            h.watcher.queue.sync {}
            h.tap.invalidate()
            hold.signal()
            onMain {}
            check(h.ghostText == " there friend how" && !h.armed, "a display held over a hide doesn't arm: '\(h.ghostText ?? "nil")'")
        }
        do {
            let (h, model) = raceHarness()
            defer { h.close() }
            let cancels = model.cancels.load(ordering: .relaxed)
            physical(53)
            check(eventually { !h.visible && !h.armed }, "Escape hides")
            h.watcher.queue.sync {}
            check(model.cancels.load(ordering: .relaxed) > cancels, "Escape cancels the engine")
            model.release(" there friend how are you")
            usleep(150_000)
            check(!h.visible && !h.armed, "the callback held over Escape shows nothing")
        }
        do {
            let (h, _) = raceHarness()
            defer { h.close() }
            let other = onMain {
                let other = NSTextView(frame: CGRect(x: 10, y: 10, width: 400, height: 30))
                h.window.contentView!.addSubview(other)
                return other
            }
            blockingReader(h) {
                onMain { _ = h.window.makeFirstResponder(other) }
                check(eventually { !h.armed && !h.visible }, "focus moved, reader blocked: disarmed and hidden")
                tabKey()
                check(eventually { onMain { other.string } == "\t" }, "Tab is the new field's: '\(onMain { other.string }.debugDescription)'")
            }
            usleep(150_000)
            check(h.text == "hello" && onMain({ other.string }) == "\t", "no completion in either field: '\(h.text)'")
        }
    }

    /// The tap reads as input a key the host may not have reached, and a counter can't tell: these hold the host back too.
    static func staleSnapshots() {
        do {
            // Read `hello`, stall on the context, a key meanwhile. No field read follows before the answer.
            let model = HeldCompleter()
            let h = Harness(completer: model)
            defer { h.close() }
            let stalled = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
            h.label.onRead.withLock { $0 = { stalled.signal(); resume.wait() } }
            onMain { h.view.holdsKeys = true }
            h.watcher.bind(pid: getpid())
            usleep(100_000)
            onMain { h.view.insertText("hello", replacementRange: h.view.selectedRange()) }
            h.watcher.scheduleUpdate()
            check(stalled.wait(timeout: .now() + 3) == .success, "held context: the read is stalled")
            physical(character: "x")
            check(eventually { h.tap.state.withLock { $0.generation > 0 } }, "held context: the key got as far as the tap")
            usleep(50_000)
            resume.signal()
            check(eventually { model.held.withLock { $0 != nil } }, "held context: the model was asked")
            model.release(" there friend")
            h.watcher.queue.sync {}
            onMain {}
            check(!h.armed && !h.visible, "held context: a key since the read: no ghost, no arm")
            tabKey()
            usleep(100_000)
            onMain { h.view.letKeysThrough() }
            check(eventually { h.text == "hellox\t" }, "held context: Tab is the app's, nothing inserted: \(h.text.debugDescription)")
        }
        do {
            // A key the host ignores, or hasn't reached. No update comes, or an update reads the same.
            let (h, _) = raceHarness()
            defer { h.close() }
            onMain { h.view.holdsKeys = true }
            check(h.visible && h.armed, "held key: ghost up")
            physical(124)
            check(eventually(0.05) { !h.visible && !h.armed }, "held key: gone within 50 ms, not left unacceptable on screen")
            h.watcher.scheduleUpdate()
            h.watcher.queue.sync {}
            onMain {}
            check(!h.visible && !h.armed, "held key: a read of the same text doesn't bring it back")
            tabKey()
            usleep(100_000)
            onMain { h.view.letKeysThrough() }
            check(eventually { h.text == "hello\t" }, "held key: Tab is the app's: \(h.text.debugDescription)")
        }
        do {
            // Tab, then Backspace before any read: the real field wins over what was predicted.
            let (h, _) = raceHarness()
            defer { h.close() }
            blockingReader(h) {
                tabKey()
                _ = eventually { h.text == "hello there" }  // Posting to a pid goes behind what's queued; the proxy doesn't. sessionPath checks that.
                physical(51)
                check(eventually { h.text == "hello ther" }, "Tab then Backspace land: '\(h.text)'")
                check(h.tap.state.withLock { $0.pending == nil }, "and the prediction is gone")
            }
            check(eventually { h.ghostText == "e friend how" && h.armed }, "the ghost follows the real field: '\(h.ghostText ?? "nil")'")
            tabKey(all: true)
            check(eventually { h.text == "hello there friend how" }, "and Shift-Tab completes that, not `ther friend`: '\(h.text)'")
        }
        do {
            // The field narrows with no key and no resize notification: the new layout can't draw a whole word.
            let (h, _) = raceHarness()
            defer { h.close() }
            onMain {
                let caret = h.view.firstRect(forCharacterRange: h.view.selectedRange(), actualRange: nil).minX - h.window.frame.minX - h.view.frame.minX
                h.panel.lastShow = nil
                h.view.setFrameSize(CGSize(width: caret + 6, height: 20))
            }
            h.watcher.scheduleUpdate()
            check(eventually { onMain { h.panel.lastShow } == false }, "failed draw: the layout really failed")
            check(eventually { !h.visible && !h.armed }, "failed draw: hidden and disarmed")
            tabKey()
            check(eventually { h.text == "hello\t" }, "failed draw: Tab is the app's: \(h.text.debugDescription)")
        }
        do {
            // A key in the gap between drawing and arming.
            let (h, _) = raceHarness()
            defer { h.close() }
            onMain {
                h.view.holdsKeys = true
                h.panel.afterShow = {
                    let was = h.tap.generation
                    physical(124)
                    check(eventually { h.tap.generation != was }, "key between draw and arm: the tap has it")
                }
            }
            h.watcher.redraw()
            h.watcher.queue.sync {}
            onMain {}
            onMain {}
            check(!h.visible && !h.armed, "key between draw and arm: the draw is gone at once")
            onMain { h.view.letKeysThrough() }
        }
        do {
            // Key A's hide comes due while key B's update is still on its way, called by hand as the 12 ms between them can't be posted reliably.
            let (h, _) = raceHarness()
            defer { h.close() }
            let a = h.tap.generation
            let b = h.tap.state.withLock { s -> Int in
                s.generation += 1
                s.armed = nil
                return s.generation
            }
            h.tap.onInput?(a)
            usleep(60_000)
            check(onMain { h.panel.isVisible }, "overlapping keys: the older key's hide leaves the newer key's grace alone")
            h.tap.onInput?(b)
            check(eventually { !h.visible }, "overlapping keys: the newer key's own hide still comes")
        }
        do {
            // One failed font read, then a notification that reads the same field: a read isn't a draw.
            let (h, _) = raceHarness()
            defer { h.close() }
            onMain { h.view.failsNextAttributes = true }
            h.watcher.redraw()
            check(eventually { !h.visible && !h.armed }, "failed font read: hidden and disarmed")
            check(onMain { !h.view.failsNextAttributes }, "failed font read: it really failed")
            h.watcher.scheduleUpdate()
            check(eventually { h.visible && h.armed }, "failed font read: the same reading draws it again")
        }
    }

    /// The tap as it ships, on the session stream, in front of a last tap that eats everything the test marks or the tap posts, so
    /// nothing reaches the app in front. This is the one place the system's own target pid and `tapPostEvent` are used.
    static func sessionPath() {
        let mark: Int64 = 0x7E57
        final class Log { let keys = Mutex<[Int64]>([]) }
        let log = Log()
        let thread = Thread {
            let callback: CGEventTapCallBack = { _, type, event, refcon in
                let data = event.getIntegerValueField(.eventSourceUserData)
                guard data == 0x7E57 || data == KeyTap.ownEvent else { return Unmanaged.passUnretained(event) }
                if type == .keyDown { Unmanaged<Log>.fromOpaque(refcon!).takeUnretainedValue().keys.withLock { $0.append(event.getIntegerValueField(.keyboardEventKeycode)) } }
                return nil
            }
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: 1 << 10 | 1 << 11,
                                               callback: callback, userInfo: Unmanaged.passRetained(log).toOpaque()) else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.start()
        let tap = KeyTap()
        guard tap.start() else { return check(false, "session tap starts") }
        usleep(200_000)
        func send(_ code: CGKeyCode) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.setIntegerValueField(.eventSourceUserData, value: mark)
            event.post(tap: .cghidEventTap)
        }
        func arm(_ text: String, pid: pid_t) { _ = tap.arm(.init(pid: pid, ghost: Ghost(remainder: text), typesKeys: true, committed: "", before: ""), generation: tap.generation) }
        func seen() -> [Int64] {
            usleep(300_000)
            return log.keys.withLock { let out = $0; $0 = []; return out }
        }
        guard eventually(20, { idleSeconds > 1 }) else { return check(false, "session path: the user never paused") }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let burst = String(repeating: " 다음", count: 20)
        arm(burst, pid: front)
        send(48)
        send(36)
        send(48)
        // Next word then Return then Tab handed back, with Return queued right behind the first Tab.
        check(seen() == [49, 14, 40, 2, 46, 0, 36, 48], "session: Tab's keys come before a key queued behind it, and the next Tab passes")
        arm(burst, pid: front)
        physicalShiftTab(mark)
        let all = TwoSetLayout.strokes(Hangul.keys(burst))!.map { Int64($0.code) }
        check(seen() == all, "session: \(all.count) keys at burst speed, none lost or reordered")
        arm(burst, pid: front + 1)
        send(48)
        check(seen() == [48], "session: Tab aimed at another app passes")
        tap.invalidate()
    }

    private static func physicalShiftTab(_ mark: Int64) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        event.flags = .maskShift
        event.setIntegerValueField(.eventSourceUserData, value: mark)
        event.post(tap: .cghidEventTap)
    }

    /// What the hide after a key costs while typing through a suggestion. See docs/measuring.md for what reaches the screen.
    static func flicker() {
        let h = Harness(completer: FakeCompleter(String(repeating: " abcde", count: 12)))
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("hello")
        _ = eventually { h.visible }
        for c in String(repeating: " abcde", count: 8).map(String.init) {
            physical(character: c)
            usleep(120_000)
        }
        let gaps = onMain { h.panel.gaps }.sorted()
        print("      typing through a suggestion: \(gaps.count) of 48 keys blanked it, ms: p50 \(gaps.isEmpty ? 0 : gaps[gaps.count / 2]) p90 \(gaps.isEmpty ? 0 : gaps[gaps.count * 9 / 10]) max \(gaps.last ?? 0)")
        check(h.text.count == 53 && h.visible && h.armed, "typed through, ghost up and armed: '\(h.text)'")
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

    /// `--ime`: Tab against Apple's real 2-set input method in the private window, through the real tap, once with the native marked range and once
    /// saying nothing, as Chromium does. Selecting the source reaches the whole system, so it only runs with the user
    /// idle and stops the moment they aren't; scripts/e2e.sh puts the source back.
    static func ime() {
        guard idleSeconds > 15 else { return check(false, "needs the user idle for 15 s, was \(Int(idleSeconds)) s: run again") }
        for reports in [false, true] { ime(reportsMarkedText: reports) }
    }

    static func ime(reportsMarkedText: Bool) {
        print("      --- host \(reportsMarkedText ? "reports" : "doesn't report") marked text")
        let h = Harness(completer: FakeCompleter(""), reportsMarkedText: reportsMarkedText)
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

        func stopIfBack() {
            if idleSeconds < 1 {
                print("the user is back: stopping")
                exit(3)
            }
        }
        func clear() {
            // A key ends the composition in the input method too. `discardMarkedText` ends it only on this side, and the input method, out of
            // step, then drops the syllable after its next commit: 다라가 comes out 다가, every time.
            physical(124)
            _ = eventually(0.5) { onMain { !h.view.hasMarkedText() } }
            // AX to this same process runs on the calling thread, and deadlocks with TextKit on main, so the watcher holds still. Another app is IPC.
            h.watcher.queue.sync { onMain { h.view.string = "" } }
            h.tap.state.withLock { ($0.composing, $0.pending) = (false, nil) }
            h.tap.invalidate()
            usleep(50_000)
        }
        func press(_ text: String) {
            stopIfBack()
            physical(typing: text)
        }
        func begin(_ start: String = "그 ", suggestion: String) {
            clear()
            h.watcher.completer = FakeCompleter(suggestion)
            typeToSelf(start)
            _ = eventually { h.text == start }
        }

        // The table against the live input method: each key alone, shift included.
        var wrong: [String] = []
        for key in "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ1234567890!@#$%^&*()-_=+[{]};:'\",<.>/? " {
            clear()
            press(String(key))
            if !eventually(1, { h.text == String(key) }) { wrong.append("\(key) gave '\(h.text)'") }
        }
        check(wrong.isEmpty, "all 33 jamo and every symbol type themselves on the live input method \(wrong)")

        func accepts(_ name: String, start: String = "그 ", typed: String, suggestion: String, ghost: String, first: String, rest: String) {
            begin(start, suggestion: suggestion)
            press(typed)
            check(eventually { h.ghostText == ghost && h.armed }, "\(name): shows '\(ghost)', field '\(h.text)', ghost '\(h.ghostText ?? "nil")'")
            tabKey()
            check(eventually { h.text == start + first }, "\(name): Tab gives '\(first)': '\(h.text)'")
            tabKey(all: true)
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
        accepts("punctuation and digits", typed: "ㅎㅏ", suggestion: " 한 3시, 다음(5)? 네!", ghost: " 3시, 다음(5)? 네!", first: "한 3시", rest: ", 다음(5)? 네!")
        accepts("on from a committed syllable", start: "그 하", typed: "", suggestion: "늘은 맑아", ghost: "늘은 맑아", first: "늘은", rest: " 맑아")

        // Every composition state of harder words: type a prefix of the keys, Tab for all of it at burst speed, expect the word.
        var bad: [String] = [], missing: [String] = [], states = 0
        for word in ["괜찮아요", "닭고기", "없어요", "앉아서", "많이", "의사", "뷁", "왜요", "떡볶이", "빨리", "까치", "짜장", "쌀밥", "예의", "외워", "됐어", "읽어"] {
            let keys = Array(Hangul.keys(word))
            for count in 1..<keys.count {
                begin(suggestion: " " + word + " 끝")
                // A burst can land before this fixed answer does, and it only fits the field as it was asked: it'd say nothing of the app.
                check(eventually { h.armed }, "\(word)@\(count): the answer is in before its keys")
                press(String(keys[..<count]))
                _ = eventually(1) { Hangul.keys(h.text) == "그 " + String(keys[..<count]) }
                // ` 끝` is always left to draw, so every state has a ghost.
                guard eventually(1, { h.armed }) else {
                    missing.append("\(word)@\(count): '\(h.text)'")
                    continue
                }
                states += 1
                tabKey(all: true)
                if !eventually(1, { h.text == "그 \(word) 끝" }) { bad.append("\(word)@\(count): '\(h.text)'") }
            }
        }
        check(bad.isEmpty && missing.isEmpty && states > 40, "\(states) composing states of 17 hard words finish right \(bad), none without a ghost \(missing)")

        // A long sentence in one burst, through every kind of key.
        let sentence = " 오늘 회의는 세 시에 시작하고, 끝나면 3층에서 다시 정리해서 공유드리겠습니다! 괜찮으세요? 네(확인)."
        begin(suggestion: sentence)
        _ = eventually { h.armed }
        tabKey(all: true)
        check(eventually(3) { h.text == "그" + sentence }, "\(sentence.count) characters in one burst: '\(h.text)'")

        // Tab-Tab with no time between them, through a two-key syllable.
        begin(suggestion: " 값이 싸 정말")
        press("ㄱㅏ")
        _ = eventually { h.ghostText == "이 싸 정말" }
        tabKey()
        tabKey()
        check(eventually { h.text == "그 값이 싸" }, "two fast Tabs, each word once: '\(h.text)'")

        // Under 2-set a suggestion stops where the keys do.
        begin(suggestion: " 자전거 file")
        press("ㅈ")
        check(eventually { h.ghostText == "전거" }, "Latin is cut off: '\(h.ghostText ?? "nil")'")
        tabKey(all: true)
        check(eventually { h.text == "그 자전거" }, "and what's left is typed: '\(h.text)'")

        // An arrow commits the syllable with no change in the field, and the tap saw it: the ghost that needed 한 goes, and no jamo can stand alone.
        func committed(_ how: String, _ commit: () -> Void) {
            begin(suggestion: " 한 다음")
            press("ㅎㅏ")
            check(eventually { h.ghostText == " 다음" }, "\(how): composing 하, ghost up")
            h.watcher.completer = FakeCompleter("")  // A model asked again may rightly continue the committed 하 as it stands.
            commit()
            check(eventually { !h.visible && !h.armed }, "\(how): committed 하, suggestion needs 한: ghost gone, field '\(h.text)'")
            usleep(200_000)
            tabKey()
            usleep(200_000)
            check(!h.text.contains("ㄴ") && !h.text.contains("다음") && h.text.hasPrefix("그 하"), "\(how): 그 하ㄴ 다음 can't happen: '\(h.text)'")
        }
        committed("arrows") {
            physical(123)
            physical(124)
        }
        committed("focus away and back") {
            let other = onMain {
                let other = NSTextView(frame: CGRect(x: 10, y: 10, width: 100, height: 30))
                h.window.contentView!.addSubview(other)
                _ = h.window.makeFirstResponder(other)
                return other
            }
            usleep(150_000)
            onMain { other.removeFromSuperview(); _ = h.window.makeFirstResponder(h.view) }
        }

        // Backspace within a syllable keeps it open; past its last jamo what's left was committed.
        begin("그 가", suggestion: "")
        press("ㅎㅏ")
        _ = eventually { h.text == "그 가하" }
        physical(51)
        _ = eventually { h.text == "그 가ㅎ" }
        physical(51)
        check(eventually { h.text == "그 가" }, "backspace past the composition: '\(h.text)'")
        h.watcher.queue.sync {}
        check(!h.tap.state.withLock { $0.composing }, "backspaced to committed 가: nothing is open any more, so no suggestion can need 간")
        begin(suggestion: " 한 다음")
        press("ㅎㅏ")
        press("ㄴ")
        _ = eventually { h.text == "그 한" }
        physical(51)
        check(eventually { h.text == "그 하" }, "backspace to 하: '\(h.text)'")
        check(eventually { h.ghostText == " 다음" }, "still composing 하, ghost back: '\(h.ghostText ?? "nil")'")
        usleep(50_000)  // No hand presses Tab within a read of the key before.
        tabKey()
        check(eventually { h.text == "그 한 다음" }, "and Tab finishes it: '\(h.text)'")

        // No wait this time. Tab finishes it if the ghost got back in time, else it is the app's: never a wrong syllable.
        begin(suggestion: " 한 다음")
        press("ㅎㅏㄴ")
        _ = eventually { h.text == "그 한" }
        usleep(100_000)
        physical(51)
        tabKey()
        check(eventually { h.text == "그 한 다음" || h.text == "그 하\t" }, "Backspace then Tab at once: '\(h.text.debugDescription)'")

        // Tab then Backspace at once, before any read: the real field wins over what was predicted.
        begin(suggestion: " 한 다음 날")
        press("ㅎㅏ")
        _ = eventually { h.ghostText == " 다음 날" && h.armed }
        // The reader held, so nothing reads between them. Posting to a pid goes behind what's queued, so the insert has to land first here.
        blockingReader(h) {
            tabKey()
            _ = eventually { h.text == "그 한 다음" }
            physical(51)
            check(eventually { h.text == "그 한 다으" }, "Tab then Backspace: '\(h.text)'")
            check(h.tap.state.withLock { $0.pending == nil }, "and the prediction is gone")
        }
        check(eventually { h.ghostText == " 날" && h.armed }, "the ghost follows what's really there: '\(h.ghostText ?? "nil")'")
        tabKey()
        check(eventually { h.text == "그 한 다음 날" }, "and Tab finishes that: '\(h.text)'")

        // The positive signal alone keeps a syllable open: the key history says it's committed, and only the host says otherwise.
        begin(suggestion: " 한 다음")
        press("ㅎㅏ")
        _ = eventually { h.ghostText == " 다음" }
        onMain { h.view.reportedMark = NSRange(location: 2, length: 1) }
        let marked = h.watcher.queue.sync { () -> Bool in
            let field = AX.element(AX.get(AXUIElementCreateApplication(getpid()), "AXFocusedUIElement"))
            return field.flatMap(Reader.read)?.marked ?? false
        }
        check(marked == reportsMarkedText, "AX reports the marked range: \(marked)")
        h.watcher.completer = FakeCompleter("")
        h.tap.state.withLock { $0.composing = false }
        h.watcher.redraw()
        usleep(150_000)  // It would be up either way until this read lands.
        onMain { h.view.reportedMark = nil }
        if reportsMarkedText {
            check(h.ghostText == " 다음" && h.armed, "history says committed, host says marked: ghost stays: '\(h.ghostText ?? "nil")'")
            tabKey()
            check(eventually { h.text == "그 한 다음" }, "and Tab finishes it: '\(h.text)'")
        } else {
            check(!h.visible && !h.armed, "history says committed, host says nothing: ghost goes")
        }

        // Any other Korean layout: no ghost at all on Hangul, and text inserted elsewhere.
        h.watcher.twoSet.store(false, ordering: .relaxed)
        begin(suggestion: " 하늘은 맑아")
        press("ㅎㅏ")
        usleep(400_000)
        check(!h.visible, "not 2-set, last character Hangul: no ghost")
        begin("그 a", suggestion: " 하늘은 맑아")
        check(eventually { h.ghostText == " 하늘은 맑아" && h.armed }, "not 2-set, last character not Hangul: ghost '\(h.ghostText ?? "nil")'")
        tabKey()
        check(eventually { h.text == "그 a 하늘은" }, "and Tab inserts it: '\(h.text)'")
        clear()
    }

    /// `--engine <gguf>`: the real model behind the real path, with the real composing argument, on the live input method.
    static func engine(path: String) {
        guard let engine = try? Engine(modelPath: path) else { return check(false, "engine loads") }
        defer { engine.unload() }
        let h = Harness(completer: engine, reportsMarkedText: false)
        defer { h.close() }
        h.watcher.bind(pid: getpid())
        usleep(100_000)
        typeToSelf("Thanks, see you to")
        check(eventually(6) { h.ghostText?.hasPrefix("morrow") == true }, "real engine, English: '\(h.ghostText ?? "nil")'")
        h.watcher.queue.sync { onMain { h.view.string = "" } }
        h.watcher.koreanInput.store(true, ordering: .relaxed)
        h.watcher.twoSet.store(true, ordering: .relaxed)
        h.tap.state.withLock { $0.composing = true }
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
