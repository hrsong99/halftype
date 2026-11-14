import CoreGraphics
import Foundation
import Vision

/// Ink in a BGRA frame of the test field, right of the caret. Nothing is typed right of the caret, so whatever is drawn
/// there is some app's suggestion, whatever its colour.
public struct Ink: Equatable, Hashable, Sendable {
    public var minX: Int, maxX: Int, minY: Int, maxY: Int, count: Int
    /// Of the inked pixels' places, so two ghosts with the same box and ink count still differ.
    public var hash: UInt64 = 14_695_981_039_346_656_037
}

/// A frame as ScreenCaptureKit hands it over: 32-bit BGRA, rows of `bytesPerRow`.
public struct Frame: @unchecked Sendable {
    public let base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int
    /// Blue isn't ink: TextEdit's caret is a blue bar a ghost's first letter can sit under, and it blinks. Ghosts are grey.
    public var ignoresBlue = false
    public init(base: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, ignoresBlue: Bool = false) {
        (self.base, self.width, self.height, self.bytesPerRow, self.ignoresBlue) = (base, width, height, bytesPerRow, ignoresBlue)
    }

    @inline(__always) func isInk(_ x: Int, _ y: Int) -> Bool {
        guard light(x, y) < Ghost.inkBelow else { return false }
        guard ignoresBlue else { return true }
        let p = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
        return Int(p[0]) - Int(p[2]) < 25  // BGRA: blue well over red is the caret, or its edge blended into white
    }

    /// Lightness of a pixel, 0 black to 255 white.
    @inline(__always) func light(_ x: Int, _ y: Int) -> Int {
        let p = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
        return (Int(p[0]) * 29 + Int(p[1]) * 150 + Int(p[2]) * 77) >> 8
    }
}

public enum Ghost {
    /// Darker than this is ink. The field is white; a light grey ghost is about 150-200.
    public static let inkBelow = 232
    /// Fewer inked pixels than this is noise, not text.
    public static let minInk = 12

    /// The ink from `fromX` on, or nil if there's none.
    public static func ink(in f: Frame, fromX: Int) -> Ink? {
        var ink = Ink(minX: .max, maxX: -1, minY: .max, maxY: -1, count: 0)
        let x0 = max(0, fromX)
        for y in 0..<f.height {
            for x in x0..<f.width where f.isInk(x, y) {
                ink.count += 1
                ink.hash = (ink.hash ^ UInt64((x - x0) &* 4099 &+ y)) &* 1_099_511_628_211  // Relative to the caret, as a ghost moves with it.
                ink.minX = min(ink.minX, x); ink.maxX = max(ink.maxX, x)
                ink.minY = min(ink.minY, y); ink.maxY = max(ink.maxY, y)
            }
        }
        return ink.count >= minInk ? ink : nil
    }

    /// A gap of more than this share of the font's size between caret and ink is a space typed by the ghost.
    /// A letter's own side bearing is under 0.12 em; a space in the system font is about 0.27 em.
    public static func leadingSpace(caretX: Int, ink: Ink, emPixels: Double) -> Bool {
        Double(ink.minX - caretX) > 0.2 * emPixels
    }

    /// The ink from `fromX` on as black on white, with a margin, for OCR: a grey ghost reads like print. Cut to the ink, as
    /// Vision reads nothing in a few letters at the end of a field-wide strip: of 80 saved Halftype crops ("ing", "eed"), 4 read
    /// uncut and 66 cut (2026-11-09).
    public static func binarized(_ f: Frame, fromX: Int, margin: Int = 10) -> CGImage? {
        let x0 = max(0, fromX), h = f.height + 2 * margin
        var inkMaxX = -1
        for y in 0..<f.height { for x in x0..<f.width where f.isInk(x, y) { inkMaxX = max(inkMaxX, x) } }
        guard inkMaxX >= 0 else { return nil }
        let w = max(inkMaxX - x0 + 1 + margin + h / 2, 2 * h)
        var bytes = [UInt8](repeating: 255, count: w * h)
        for y in 0..<f.height { for x in x0..<f.width where f.isInk(x, y) { bytes[(y + margin) * w + x - x0 + margin] = 0 } }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Loads Vision's models, which takes seconds the first time: before typing, not at the first ghost.
    public static func warmUp() {
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        for korean in [false, true] { _ = read(ctx.makeImage()!, korean: korean) }
    }

    /// Vision's reading, left to right, without its language correction (which would "fix" a ghost into what it expects).
    public static func read(_ image: CGImage, korean: Bool) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = korean ? ["ko-KR", "en-US"] : ["en-US"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
    }
}
