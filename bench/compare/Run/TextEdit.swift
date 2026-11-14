import AppKit

/// A TextEdit document as the field (`--host textedit`), for an app that suggests in TextEdit but not in our own window
/// (Cotypist, README "Apps this harness can't measure"). One line of 17-point Helvetica, plain text, black on white, the
/// system's corrections off for this launch only; the text and caret are read over Accessibility. TextEdit must not be running.
final class TextEditHost: Host {
    private let pid: pid_t, appElement: AXUIElement, area: AXUIElement
    let scale: CGFloat, captureRect: CGRect
    /// TextEdit draws its caret in the accent colour, blue.
    let caretIsBlue = true
    private let lineX: CGFloat
    private let lock = NSLock()
    /// The caret as read at a time: a frame's caret is the first read begun after it, as TextEdit updates its text before drawing it.
    private var reads: [(t: UInt64, x: Int)] = []
    private var polling = true

    /// Argument-domain defaults: they hold for this launch and leave the user's TextEdit settings alone.
    static let defaults: [String: String] = [
        "ApplePersistenceIgnoreState": "YES", "NSRequiresAquaSystemAppearance": "YES", "RichText": "NO",
        "NSFixedPitchFont": "Helvetica", "NSFixedPitchFontSize": "17", "ShowRuler": "NO",
        "CheckSpellingWhileTyping": "NO", "CheckGrammarWithSpelling": "NO", "CorrectSpellingAutomatically": "NO",
        "SmartQuotes": "NO", "SmartDashes": "NO", "SmartLinks": "NO", "SmartCopyPaste": "NO", "DataDetectors": "NO", "TextReplacement": "NO",
        "NSAutomaticCapitalizationEnabled": "NO", "NSAutomaticPeriodSubstitutionEnabled": "NO", "NSAutomaticSpellingCorrectionEnabled": "NO",
        "NSAutomaticTextCompletionEnabled": "NO", "NSAutomaticInlinePredictionEnabled": "NO",
    ]

    init(file: String) {
        // A file, not an untitled document: it saves itself on quit, so nothing is left for the user's next TextEdit to restore.
        FileManager.default.createFile(atPath: file, contents: Data())
        sh("/usr/bin/open", ["-g", "-a", "TextEdit", file, "--args"] + Self.defaults.flatMap { ["-" + $0.key, $0.value] })
        var found: (pid_t, AXUIElement, AXUIElement)?
        for _ in 0..<100 where found == nil {
            sleepMs(200)
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else { continue }
            let el = AXUIElementCreateApplication(app.processIdentifier)
            // Not windows.first: TextEdit can have a small untitled window of its own besides the document.
            if let a = ((ax(el, kAXWindowsAttribute) as? [AXUIElement]) ?? []).lazy.compactMap({ first(role: kAXTextAreaRole, in: $0) }).first { found = (app.processIdentifier, el, a) }
        }
        guard let (pid, appElement, area) = found else { fatalError("TextEdit opened no window with a text area") }
        (self.pid, self.appElement, self.area) = (pid, appElement, area)
        let window = ax(area, kAXWindowAttribute) as! AXUIElement
        // Where our own field sits, on the main display (the one captured).
        let screen = NSScreen.screens[0], vf = screen.visibleFrame
        scale = screen.backingScaleFactor
        var origin = CGPoint(x: vf.minX + 40, y: screen.frame.maxY - vf.maxY + 40), size = CGSize(width: min(1300, vf.width - 80), height: 200)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
        sleepMs(300)
        // The first line, from two letters typed into it: one ascender, one descender.
        AXUIElementSetAttributeValue(area, kAXValueAttribute as CFString, "Hg" as CFString)
        sleepMs(200)
        let line = bounds(area, 0, 2)!, frame = frameOf(area)
        lineX = line.minX
        // TextEdit's first line starts at the text area's top, against the title bar's edge: 2 points down leaves the edge out.
        let top = max(frame.minY + 2, line.minY - 4)
        captureRect = CGRect(x: frame.minX, y: top, width: frame.width - 20, height: min(frame.maxY, line.maxY + 12) - top)
        // What the capture sees, with the two letters in, to check by eye after a run.
        let shot = (file as NSString).deletingLastPathComponent
        sh("/usr/sbin/screencapture", ["-x", "-R", "\(Int(captureRect.minX)),\(Int(captureRect.minY)),\(Int(captureRect.width)),\(Int(captureRect.height))", shot + "/capture-line.png"])
        sh("/usr/sbin/screencapture", ["-x", "-m", shot + "/capture-screen.png"])
        print("  TextEdit: line \(line), text area \(frame), capture \(captureRect)")
        AXUIElementSetAttributeValue(area, kAXValueAttribute as CFString, "" as CFString)
        Thread { [weak self] in
            while let self, self.polling {
                let t = now(), x = self.caretX()
                self.lock.withLock { self.reads.append((t, x)); if self.reads.count > 400 { self.reads.removeFirst(200) } }
                sleepMs(8)
            }
        }.start()
    }

    /// A typographic apostrophe reads as the typed one: Cotypist's Tab puts in "Joe’s" for "Joe's", which a person takes as right,
    /// and the oracle would otherwise delete it and Tab again, 95 times in one sentence (2026-11-14). Same length, so ranges hold.
    var text: (field: String, composing: String) { (((ax(area, kAXValueAttribute) as? String) ?? "").replacingOccurrences(of: "\u{2019}", with: "'"), "") }

    func clear() { set("") }

    func set(_ text: String) {
        AXUIElementSetAttributeValue(area, kAXValueAttribute as CFString, text as CFString)
        var end = CFRange(location: (text as NSString).length, length: 0)
        AXUIElementSetAttributeValue(area, kAXSelectedTextRangeAttribute as CFString, AXValueCreate(.cfRange, &end)!)
        for _ in 0..<50 where self.text.field != text { sleepMs(10) }
    }

    var focused: Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, let f = ax(appElement, kAXFocusedUIElementAttribute) else { return false }
        return CFEqual(f, area)
    }

    /// TextEdit brought forward (`open -a` activates it, which a process started from the terminal can't do itself), then a
    /// real click below the text, as `Field.focus` does, and the caret to the end. A click alone would land on the window in front.
    func focus() -> Bool {
        for _ in 0..<3 {
            if focused { return true }
            sh("/usr/bin/open", ["-a", "TextEdit"])
            sleepMs(500)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { continue }
            click(CGPoint(x: captureRect.midX, y: captureRect.maxY + 30))
            sleepMs(400)
            set(text.field)
        }
        return focused
    }

    func caret(at t: UInt64) -> Int {
        for _ in 0..<40 {
            if let x = lock.withLock({ reads.first(where: { $0.t > t })?.x }) { return x }
            usleep(2_000)
        }
        return lock.withLock { reads.last?.x ?? 0 }
    }

    private func caretX() -> Int {
        guard let v = ax(area, kAXSelectedTextRangeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return 0 }
        var r = CFRange()
        AXValueGetValue(v as! AXValue, .cfRange, &r)
        let x = r.location == 0 ? lineX : (bounds(area, r.location - 1, 1)?.maxX ?? lineX)
        return Int(((x - captureRect.minX) * scale).rounded())
    }

    func predictions(_ on: Bool) {}
    func show() { _ = focus() }

    /// Quits TextEdit, which saves the document to its file without asking.
    func hide() {
        polling = false
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.terminate()
        for _ in 0..<50 where !app.isTerminated { sleepMs(200) }
        if !app.isTerminated { app.forceTerminate() }
    }
}

func ax(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func first(role: String, in el: AXUIElement) -> AXUIElement? {
    if ax(el, kAXRoleAttribute) as? String == role { return el }
    for c in (ax(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let f = first(role: role, in: c) { return f } }
    return nil
}

/// A range's box on screen, in global top-left points.
func bounds(_ el: AXUIElement, _ location: Int, _ length: Int) -> CGRect? {
    var range = CFRange(location: location, length: length), v: CFTypeRef?, r = CGRect.zero
    guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, AXValueCreate(.cfRange, &range)!, &v) == .success,
          let v, AXValueGetValue(v as! AXValue, .cgRect, &r), r.width > 0 else { return nil }
    return r
}

func frameOf(_ el: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = ax(el, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = ax(el, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}
