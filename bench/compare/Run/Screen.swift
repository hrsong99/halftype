import AppKit
import CompareKit
import ScreenCaptureKit

/// Where the harness types: its own field (`Field`) or a TextEdit document (`TextEditHost`, `--host textedit`).
protocol Host: AnyObject {
    var text: (field: String, composing: String) { get }
    func clear()
    func set(_ text: String)
    /// The host's window is key in the frontmost app, with the field focused: the only state in which keys may be sent.
    var focused: Bool { get }
    func focus() -> Bool
    /// Where the caret was when a frame was shown, in capture pixels.
    func caret(at t: UInt64) -> Int
    /// The field's line on screen, in global top-left points, as ScreenCaptureKit wants it.
    var captureRect: CGRect { get }
    var scale: CGFloat { get }
    /// The host draws a blue caret, which isn't ink (`Frame.ignoresBlue`).
    var caretIsBlue: Bool { get }
    /// macOS's own predictions, which only our own field can switch.
    func predictions(_ on: Bool)
    func show()
    func hide()
}

/// The test field: one long line of 17-point text, black on white, with an invisible caret, so anything drawn right of
/// the caret is a suggestion. The window floats so nothing covers it.
final class Field: NSObject, NSTextViewDelegate, Host {
    let window: NSWindow
    let view: NSTextView
    /// Caret positions in capture pixels, with the time each began, for frames to look up.
    private let lock = NSLock()
    private var carets: [(t: UInt64, x: Int)] = [(0, 0)]
    let scale: CGFloat
    /// The field's line on screen, in global top-left points, as ScreenCaptureKit wants it.
    private(set) var captureRect = CGRect.zero
    static let fontSize: CGFloat = 17
    let caretIsBlue = false  // its caret is clear

    override init() {
        let screen = NSScreen.main!
        scale = screen.backingScaleFactor
        let frame = CGRect(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - 160, width: min(1300, screen.visibleFrame.width - 80), height: 110)
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Halftype comparison: please don't type here"
        window.level = .floating
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        view = NSTextView(frame: CGRect(x: 20, y: 30, width: frame.width - 40, height: 46))
        super.init()
        view.font = .systemFont(ofSize: Field.fontSize)
        view.textColor = .black
        view.backgroundColor = .white
        view.insertionPointColor = .clear
        view.isRichText = false
        view.isHorizontallyResizable = true
        view.textContainer!.widthTracksTextView = false
        view.textContainer!.containerSize = CGSize(width: 100_000, height: 46)
        view.textContainerInset = CGSize(width: 0, height: 12)
        // Nothing of the system's own may change what was typed.
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.inlinePredictionType = .no
        view.delegate = self
        window.contentView!.addSubview(view)
        let line = window.convertToScreen(view.convert(view.bounds, to: nil))
        captureRect = CGRect(x: line.minX, y: screen.frame.maxY - line.maxY, width: line.width, height: line.height)
    }

    var text: (field: String, composing: String) {
        onMain {
            let marked = view.markedRange()
            let composing = view.hasMarkedText() ? (view.string as NSString).substring(with: marked) : ""
            return (view.string, composing)
        }
    }

    func clear() {
        onMain {
            view.inputContext?.discardMarkedText()
            view.unmarkText()
            view.string = ""
            caretMoved()
        }
    }

    func set(_ text: String) {
        onMain {
            view.inputContext?.discardMarkedText()
            view.unmarkText()
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            caretMoved()
        }
    }

    /// Our window is the key window of the frontmost app, with the field focused: the only state in which keys may be sent.
    var focused: Bool { onMain { NSApp.isActive && window.isKeyWindow && window.firstResponder === view } }

    /// A real click on the field: activation macOS grants an app the user clicks, which a process started from the terminal
    /// can't take for itself. The pointer isn't captured.
    func focus() -> Bool {
        onMain { window.orderFrontRegardless() }
        for _ in 0..<3 {
            if focused { return true }
            let r = window.convertToScreen(view.convert(view.bounds, to: nil))
            click(CGPoint(x: r.midX, y: NSScreen.screens[0].frame.maxY - r.midY))
            onMain { _ = window.makeFirstResponder(view) }
            sleepMs(400)
        }
        return focused
    }

    func predictions(_ on: Bool) { onMain { view.inlinePredictionType = on ? .yes : .no } }
    func show() { onMain { window.orderFrontRegardless() } }
    func hide() { onMain { window.orderOut(nil) } }

    func textViewDidChangeSelection(_ notification: Notification) { caretMoved() }
    func textDidChange(_ notification: Notification) { caretMoved() }

    private func caretMoved() {
        let r = view.firstRect(forCharacterRange: NSRange(location: view.selectedRange().location, length: 0), actualRange: nil)
        let x = Int(((r.minX - (captureRect.minX)) * scale).rounded())
        lock.withLock { if carets.last!.x != x { carets.append((now(), x)); if carets.count > 400 { carets.removeFirst(200) } } }
    }

    /// Where the caret was when a frame was shown: the field redraws after the selection changes, never before.
    func caret(at t: UInt64) -> Int { lock.withLock { carets.last(where: { $0.t <= t })?.x ?? carets.last!.x } }
}

/// Frames of the field's line at up to 60 Hz, from the screen as the user would see it, every app's overlay included.
/// ScreenCaptureKit only sends a frame when the region changes, so the last frame is what is on screen now.
final class Capture: NSObject, SCStreamOutput, @unchecked Sendable {
    struct Seen { let t: UInt64, ink: Ink?, caret: Int }
    private let field: Host
    private let lock = NSLock()
    private var frames: [Seen] = []
    private var read: [Ink: String] = [:]
    private var reading = Set<Ink>()
    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "frames"), ocrQueue = DispatchQueue(label: "ocr")
    var korean = false
    /// Binarized crops of the first ghosts each app showed, with what OCR read, for checking the OCR by eye after a run.
    var cropDir: String?
    private var crops = 0

    init(field: Host) { self.field = field }

    func start() throws {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<SCShareableContent, Error>!
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, e in result = c.map { .success($0) } ?? .failure(e!); sem.signal() }
        sem.wait()
        let content = try result.get()
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { throw NSError(domain: "no main display", code: 1) }
        let config = SCStreamConfiguration()
        config.sourceRect = field.captureRect
        config.width = Int(field.captureRect.width * field.scale)
        config.height = Int(field.captureRect.height * field.scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.queueDepth = 6
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        var failed: Error?
        stream.startCapture { failed = $0; sem.signal() }
        sem.wait()
        if let failed { throw failed }
        self.stream = stream
    }

    func stop() {
        let sem = DispatchSemaphore(value: 0)
        stream?.stopCapture { _ in sem.signal() }
        if stream != nil { sem.wait() }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init) == .complete,
              let t = info[.displayTime] as? UInt64, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let frame = Frame(base: CVPixelBufferGetBaseAddress(pixels)!, width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels),
                          bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), ignoresBlue: field.caretIsBlue)
        let caret = field.caret(at: t)
        let ink = Ghost.ink(in: frame, fromX: caret + 1)
        let needsRead: Bool = lock.withLock {
            frames.append(Seen(t: t, ink: ink, caret: caret))
            if frames.count > 1200 { frames.removeFirst(600) }
            guard let ink, read[ink] == nil, !reading.contains(ink) else { return false }
            reading.insert(ink)
            return true
        }
        guard needsRead, let ink, let image = Ghost.binarized(frame, fromX: caret + 1) else { return }
        let korean = korean
        ocrQueue.async {
            let text = Ghost.read(image, korean: korean)
            self.lock.withLock { self.read[ink] = text; self.reading.remove(ink) }
            self.keepCrop(image, text)
        }
    }

    private func keepCrop(_ image: CGImage, _ text: String) {
        guard let cropDir, crops < 40 else { return }
        crops += 1
        let url = URL(fileURLWithPath: cropDir + String(format: "/%02d.png", crops))
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        if let h = FileHandle(forWritingAtPath: cropDir + "/read.tsv") ?? { FileManager.default.createFile(atPath: cropDir + "/read.tsv", contents: nil); return FileHandle(forWritingAtPath: cropDir + "/read.tsv") }() {
            h.seekToEndOfFile(); h.write(Data(String(format: "%02d\t%@\n", crops, text).utf8)); h.closeFile()
        }
    }

    func resetCrops(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        lock.withLock { cropDir = dir; crops = 0; read = [:] }
    }

    /// The ink on screen now.
    var inkNow: Ink? { lock.withLock { frames.last?.ink } }

    /// The ghost on screen now, as text with its leading space, waiting up to `wait` ms for the OCR of it.
    func ghost(wait: Double) -> String? {
        let deadline = now() + UInt64(wait / msPerTick)
        while true {
            let (seen, text) = lock.withLock { (frames.last, frames.last?.ink.flatMap { read[$0] }) }
            guard let seen, let ink = seen.ink else { return nil }
            if let text {
                guard !text.isEmpty else { return nil }
                let lead = Ghost.leadingSpace(caretX: seen.caret, ink: ink, emPixels: Double(Field.fontSize * field.scale))
                return (lead && !text.hasPrefix(" ") ? " " : "") + text
            }
            if now() > deadline { return nil }
            usleep(3_000)
        }
    }

    /// Milliseconds from `t0` to the first frame shown after it with ink that differs from what was there at `t0`.
    func firstChange(after t0: UInt64, from before: Ink?) -> Double? {
        // Ink that OCR read as nothing (a box's edge, a shadow) isn't a suggestion.
        lock.withLock { frames.first(where: { $0.t > t0 && $0.ink != nil && $0.ink != before && read[$0.ink!] != "" }).map { ms(t0, $0.t) } }
    }
}
