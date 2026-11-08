import AppKit
import HalftypeCore

/// Everything needed to draw one ghost, in AX coordinates (origin top-left of the primary display, y down, points).
struct GhostSpec {
    var text: String
    var caret: CGRect
    var frame: CGRect
    var fontSize: CGFloat
    var fontName: String?
    var color: CGColor?
    var lineLeft: CGFloat?
    /// The character the caret rect was measured on, so the baseline uses its metrics: Hangul falls back to another font.
    var previousCharacter: String
    /// Text below the caret would be drawn over, so the ghost then stays on one line.
    var mayWrap: Bool
    /// The caret is a web view's sliver, on screen at page zoom, while the font size beside it is before zoom.
    var webCaret = false
    /// Our own window's field: the suggestion is drawn in the icon's glass rather than the host's colour.
    var glass = false
}

struct GhostLayout {
    /// In AX coordinates, whole points so the window server has nothing to round.
    var window: CGRect
    var drawOrigin: CGPoint
    var storage: NSTextStorage
    var manager: NSLayoutManager
    var glyphs: NSRange
    var glass = false
    var visibleText: String { (storage.string as NSString).substring(with: manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)) }

    static func font(_ spec: GhostSpec) -> NSFont {
        let font = spec.fontName.flatMap { NSFont(name: $0, size: spec.fontSize) } ?? .systemFont(ofSize: spec.fontSize)
        guard spec.webCaret else { return font }
        let zoom = spec.caret.height / NSLayoutManager().defaultLineHeight(for: font)
        // A band, as the page's font goes unnamed and its line can differ from ours by about a tenth, estimated from fonts' metrics. Past it is zoom.
        return zoom > 1.15 || zoom < 1 / 1.15 ? font.withSize(spec.fontSize * zoom) : font
    }

    /// The host's own text colour, translucent, is readable wherever the host's text is. Without one, the label colour.
    static func color(_ spec: GhostSpec) -> NSColor {
        if let c = spec.color, c.alpha > 0.5, let host = NSColor(cgColor: c) { return host.withAlphaComponent(0.42) }
        return .tertiaryLabelColor
    }

    /// Host-like wrapping by TextKit: the first line starts at the caret, further lines at the text edge, and what doesn't fit
    /// the field is dropped at a line break. Nil when nothing would show: a half-typed word the host would have to move.
    static func make(_ spec: GhostSpec) -> GhostLayout? {
        let font = font(spec)
        let line = NSLayoutManager().defaultLineHeight(for: font)
        // T3 can report a whole pane as the line, so a left edge outside the field or past the caret isn't one.
        let lineLeft = spec.lineLeft.flatMap { $0 >= spec.frame.minX && $0 <= spec.caret.minX ? $0 : nil }
        let padding = lineLeft.map { $0 - spec.frame.minX } ?? 0
        let wraps = spec.mayWrap && lineLeft != nil
        let left = wraps ? lineLeft! : spec.caret.minX
        let width = spec.frame.maxX - padding - left
        guard width > 0 else { return nil }
        // shortcut: line spacing is the font's default, not the host's CSS; measure it from two lines if tall fields look off.
        let lines = wraps ? max(Int((spec.frame.maxY - spec.caret.minY) / line), 1) : 1

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = line
        paragraph.maximumLineHeight = line
        paragraph.lineBreakMode = .byWordWrapping
        let storage = NSTextStorage(string: spec.text, attributes: [.font: font, .foregroundColor: spec.glass ? NSColor.black : color(spec), .paragraphStyle: paragraph])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: CGFloat(lines) * line))
        container.lineFragmentPadding = 0
        if spec.caret.minX > left { container.exclusionPaths = [NSBezierPath(rect: CGRect(x: 0, y: 0, width: spec.caret.minX - left, height: line))] }
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return nil }
        var firstLine = NSRange()
        let first = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLine)
        // TextKit splits a word that won't fit a narrow first line, and a half-typed word can't move to the next line as the
        // host would move it, so such a ghost isn't drawn. A word cut at the end of the visible text is dropped whole.
        if splitsWord(spec.text, at: manager.characterIndexForGlyph(at: NSMaxRange(firstLine))) { return nil }
        let end = cleanEnd(spec.text, at: manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).length)
        guard (spec.text as NSString).substring(to: end).contains(where: { !$0.isWhitespace }) else { return nil }
        glyphs = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: end), actualCharacterRange: nil)

        let probe = CTFontCreateForString(font, spec.previousCharacter.isEmpty ? "x" as CFString : spec.previousCharacter as CFString,
                                          CFRange(location: 0, length: spec.previousCharacter.utf16.count))
        let ascent = CTFontGetAscent(probe), descent = CTFontGetDescent(probe)
        // AX rects are centred on the font box (glyph rects) or on a line box with even leading, so the centre sets the baseline.
        let baseline = spec.caret.midY + (ascent - descent) / 2
        let baselineInLine = manager.location(forGlyphAt: glyphs.location).y
        let used = manager.usedRect(for: container)
        let margin: CGFloat = 3  // Tall Hangul or emoji glyphs may overhang the fixed line height.
        let top = baseline - baselineInLine
        let window = CGRect(x: floor(left), y: floor(top - margin), width: ceil(width + left - floor(left)), height: ceil(max(used.maxY, first.maxY) + 2 * margin) + 1)
        return GhostLayout(window: window, drawOrigin: CGPoint(x: left - floor(left), y: top - floor(top - margin)),
                           storage: storage, manager: manager, glyphs: glyphs, glass: spec.glass)
    }

    /// Inside a word of an alphabet: Hangul and other CJK may break between any two characters, in hosts too.
    private static func splitsWord(_ text: String, at index: Int) -> Bool {
        let ns = text as NSString
        guard index > 0, index < ns.length else { return false }
        return isAlphabetic(ns.character(at: index - 1)) && isAlphabetic(ns.character(at: index))
    }

    private static func isAlphabetic(_ unit: unichar) -> Bool {
        unit < 0x1100 && (Unicode.Scalar(unit).map { Character($0).isLetter || Character($0).isNumber } ?? false)
    }

    /// `index` moved back to a word's start if it falls inside one.
    private static func cleanEnd(_ text: String, at index: Int) -> Int {
        var end = index
        if splitsWord(text, at: end) {
            while end > 0, isAlphabetic((text as NSString).character(at: end - 1)) { end -= 1 }
        }
        return end
    }

    /// AX to AppKit: both are global points on the same scale across displays, and only the y axis flips, around the primary display.
    static func appKitRect(_ ax: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: ax.minX, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }
}

final class GhostView: NSView {
    var layout: GhostLayout? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    /// The icon's glass, pale blue to peach across the suggestion.
    static let glass = NSGradient(colors: [NSColor(srgbRed: 0.373, green: 0.608, blue: 0.847, alpha: 1), NSColor(srgbRed: 0.6, green: 0.69, blue: 0.79, alpha: 1),
                                           NSColor(srgbRed: 0.91, green: 0.561, blue: 0.369, alpha: 1)])!
    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        guard layout.glass, let context = NSGraphicsContext.current?.cgContext else { return layout.manager.drawGlyphs(forGlyphRange: layout.glyphs, at: layout.drawOrigin) }
        // The letters, then the gradient painted only where they are.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        layout.manager.drawGlyphs(forGlyphRange: layout.glyphs, at: layout.drawOrigin)
        context.setBlendMode(.sourceIn)
        // In reading order: each line takes the next stretch of one gradient as long as all the lines laid end to end.
        var lines: [CGRect] = []
        layout.manager.enumerateLineFragments(forGlyphRange: layout.glyphs) { _, _, container, range, _ in
            lines.append(layout.manager.boundingRect(forGlyphRange: NSIntersectionRange(range, layout.glyphs), in: container)
                .offsetBy(dx: layout.drawOrigin.x, dy: layout.drawOrigin.y))
        }
        let total = lines.reduce(0) { $0 + $1.width }
        var before: CGFloat = 0
        for line in lines {
            context.saveGState()
            context.clip(to: line.insetBy(dx: 0, dy: -3))
            Self.glass.draw(from: CGPoint(x: line.minX - before, y: 0), to: CGPoint(x: line.minX - before + total, y: 0), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
            context.restoreGState()
            before += line.width
        }
        context.endTransparencyLayer()
    }
}

/// Click-through, never key, never activates, over everything on every Space including full-screen apps.
class GhostPanel: NSPanel {
    let view = GhostView()
    /// Marks the panel to our own observer: in Try It it is a window of the watched app, and its moves aren't the field's.
    static let accessibilityID = "app.halftype.ghost"

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Above ordinary floating windows, below the host's own menus and popovers.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        setAccessibilityIdentifier(Self.accessibilityID)
        hidesOnDeactivate = false
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// What it drew, which is all Tab may offer: a narrow field clips. Nil if nothing is on the screen that the user can see. Main thread.
    func show(_ spec: GhostSpec) -> String? {
        guard let primary = NSScreen.screens.first, let layout = GhostLayout.make(spec),
              NSScreen.screens.contains(where: { $0.frame.contains(GhostLayout.appKitRect(spec.caret, primaryHeight: primary.frame.height).origin) })
        else { hideGhost(); return nil }
        view.layout = layout
        setFrame(GhostLayout.appKitRect(layout.window, primaryHeight: primary.frame.height), display: false, animate: false)
        view.displayIfNeeded()
        if !isVisible { orderFrontRegardless() }
        // A panel can get stranded on one Space whatever its collection behaviour says, and be drawn where nobody sees it.
        guard isOnActiveSpace else { hideGhost(); return nil }
        return String(Word.withoutTrailingSpaces(layout.visibleText))
    }

    func hideGhost() {
        orderOut(nil)
        view.layout = nil
    }
}
