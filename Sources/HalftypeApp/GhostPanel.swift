import AppKit
import QuartzCore
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
    var typed: Typed? = nil
    /// How to draw when the host names no font: the field's last clear `GhostLayout.look`.
    var look: Look? = nil
    var linePitch: CGFloat? = nil
    /// The character the caret rect was measured on, so the baseline uses its metrics: Hangul falls back to another font.
    var previousCharacter: String
    /// Text below the caret would be drawn over, so the ghost then stays on one line.
    var mayWrap: Bool
    /// The caret is a web view's sliver, on screen at page zoom, while the font size beside it is before zoom.
    var webCaret = false
    /// Our own window's field: the suggestion is drawn in the icon's glass rather than the host's colour.
    var glass = false
    /// What the model was given and how sure it was, for the ⌃⌥ card. Nil unless that setting is on.
    var peek: Peek? = nil
}

/// An unnamed font (a web page's) as told by the line typed so far, for as long as the field's font size and caret height hold.
struct Look: Equatable {
    var design: NSFontDescriptor.SystemDesign
    /// The page's zoom: the line's width over the design's at the reported size.
    var zoom: CGFloat
    /// The reported size and the caret's height it was told under: a new size, or a zoom since, makes it stale. One zoom step is 9.5% in
    /// Electron, within what a caret's zoom can miss by, but moves the caret 1.6 pt or more (SF 14), while whole-point rounding moves it 1.
    var size: CGFloat
    var caret: CGFloat
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
        if let named = spec.fontName.flatMap({ NSFont(name: $0, size: spec.fontSize) }) { return named }
        let font = system(spec.look?.design ?? .default, spec.fontSize)
        if let look = spec.look, look.size == spec.fontSize, abs(look.caret - spec.caret.height) < 1.5 { return scaled(font, look.zoom) }
        // No look, or a stale one: the zoom from the caret, outside a band, as the page's font goes unnamed and its line can differ
        // from ours by about a tenth, estimated from fonts' metrics. Past it is zoom.
        let caret = caretZoom(font, spec)
        return caret > 1.15 || caret < 1 / 1.15 ? scaled(font, caret) : font
    }

    private static func system(_ design: NSFontDescriptor.SystemDesign, _ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
    }

    /// The font at the reported size, drawn larger: Chromium's zoom scales the line as set at that size, while SF set at a larger size
    /// tracks tighter (SF 22 sets `it looks fine here, but` 8% narrower than SF 14 scaled to 22). Its fallbacks (Hangul) scale with it.
    private static func scaled(_ font: NSFont, _ zoom: CGFloat) -> NSFont {
        NSFont(descriptor: font.fontDescriptor, textTransform: AffineTransform(scale: zoom)) ?? font.withSize(font.pointSize * zoom)
    }

    /// Chromium names no font and gives its size before page zoom, while its caret is on screen: a rough zoom, to the page font's
    /// difference from ours and a caret rounded to whole points (16 or 17 for SF 14 at 100% in T3). 1 with no web caret.
    private static func caretZoom(_ font: NSFont, _ spec: GhostSpec) -> CGFloat {
        spec.webCaret ? spec.caret.height / NSLayoutManager().defaultLineHeight(for: font) : 1
    }

    /// An unnamed font's look from the line typed so far. Each design implies a zoom, the line's width over that design's at the reported
    /// size (exact for a page in the system font: 1.210 at 121% in T3, 2026-11-14), and the one the caret's zoom agrees with, within the
    /// page font's tenth and by 6% better than the other's (carets round to whole points: 16 or 17 at 100%), is it. Drawn at that zoom,
    /// the ghost sets text as wide as the page does, so a taken suggestion's letters land where the ghost's were. Nil when the line can't
    /// tell: a short one, one both or neither fit ("wwwwi" is 55 pt in SF Mono, 57 in the system font; Hangul falls back to the same font
    /// in both), or one an inline chip or image widens past both; the field then keeps what it had, and the ghost doesn't change as
    /// letters come. A chip can still pass for monospaced, as it did before. No serif: it sets a few percent wider than sans, so a zoomed
    /// sans page read as serif (T3 at 121%).
    static func look(_ spec: GhostSpec) -> Look? {
        guard let typed = spec.typed, typed.text.count >= 8, typed.width > 0 else { return nil }
        let fits = [NSFontDescriptor.SystemDesign.default, .monospaced].map { design -> (look: Look, miss: CGFloat) in
            let font = system(design, spec.fontSize)
            let zoom = typed.width / (typed.text as NSString).size(withAttributes: [.font: font]).width
            let caret = caretZoom(font, spec)
            return (Look(design: design, zoom: zoom, size: spec.fontSize, caret: spec.caret.height), max(zoom / caret, caret / zoom))
        }.sorted { $0.miss < $1.miss }
        return fits[0].miss < 1.15 && fits[1].miss / fits[0].miss > 1.06 ? fits[0].look : nil
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
        let natural = NSLayoutManager().defaultLineHeight(for: font)
        // The host's own line spacing where it was measured: CSS often sets 1.5 lines.
        let line = spec.linePitch.flatMap { $0 >= natural * 0.8 && $0 <= natural * 3 ? $0 : nil } ?? natural
        // T3 can report a whole pane as the line, so a left edge outside the field or past the caret isn't one.
        let lineLeft = spec.lineLeft.flatMap { $0 >= spec.frame.minX && $0 <= spec.caret.minX ? $0 : nil }
        let padding = lineLeft.map { $0 - spec.frame.minX } ?? 0
        let wraps = spec.mayWrap && lineLeft != nil
        let left = wraps ? lineLeft! : spec.caret.minX
        let width = spec.frame.maxX - padding - left
        guard width > 0 else { return nil }
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
        // A native caret is the font box, and Chromium's is the page font's own box, so their centre sets the baseline. WebKit's runs
        // from the line's top to the text's bottom, leaving line spacing above the text (Safari, 2026-11-11: the centre put Georgia 20
        // at line-height 1.8 7 pt high), so a web caret whose host names its font sets it from its bottom.
        let baseline = spec.webCaret && spec.fontName != nil ? spec.caret.maxY - descent : spec.caret.midY + (ascent - descent) / 2
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
    /// The icon's glass, pale blue to peach across the suggestion. Onboarding's welcome draws its headline in the same colours.
    static let glassColors = [NSColor(srgbRed: 0.373, green: 0.608, blue: 0.847, alpha: 1), NSColor(srgbRed: 0.6, green: 0.69, blue: 0.79, alpha: 1),
                              NSColor(srgbRed: 0.91, green: 0.561, blue: 0.369, alpha: 1)]
    static let glass = NSGradient(colors: glassColors)!
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

/// One band of light crossing words just taken, painted only on their letters, which now sit where the ghost drew them. Progress 0 to 1.
/// The app plays it over our own field after a Tab; the README demo draws it frame by frame.
final class GlintView: NSView {
    var manager: NSLayoutManager?
    var glyphs = NSRange()
    var origin = CGPoint.zero
    var progress: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    /// Blue, a pale glass highlight (not white, which vanishes on a white field), peach.
    static let lightColors: [NSColor] = [.clear, NSColor(srgbRed: 0.45, green: 0.65, blue: 0.88, alpha: 1), NSColor(srgbRed: 0.76, green: 0.83, blue: 0.91, alpha: 1),
                                         NSColor(srgbRed: 0.93, green: 0.6, blue: 0.42, alpha: 1), .clear]
    static let light = NSGradient(colors: lightColors)!
    override func draw(_ dirtyRect: NSRect) {
        guard let manager, glyphs.length > 0, progress > 0, progress < 1, let context = NSGraphicsContext.current?.cgContext else { return }
        let words = manager.boundingRect(forGlyphRange: glyphs, in: manager.textContainers[0]).offsetBy(dx: origin.x, dy: origin.y)
        let width = max(40, words.height * 2)
        let band = CGRect(x: words.minX - width + progress * (words.width + width), y: words.minY - 3, width: width, height: words.height + 6)
        // Only the letters under the band, then the light painted onto them alone.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.clip(to: band)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        context.setBlendMode(.sourceIn)
        Self.light.draw(in: band, angle: 0)
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

    /// The ⌃⌥ card, which follows this panel's ghost. Main thread.
    private(set) lazy var peekWatch = PeekWatch()

    /// What it drew, which is all Tab may offer: a narrow field clips. Nil if nothing is on the screen that the user can see. Main thread.
    func show(_ spec: GhostSpec) -> String? {
        guard let primary = NSScreen.screens.first, let layout = GhostLayout.make(spec),
              NSScreen.screens.contains(where: { $0.frame.contains(GhostLayout.appKitRect(spec.caret, primaryHeight: primary.frame.height).origin) })
        else { hideGhost(); return nil }
        view.layout = layout
        caret = spec.caret
        drawing += 1
        taken = 0
        setFrame(GhostLayout.appKitRect(layout.window, primaryHeight: primary.frame.height), display: false, animate: false)
        view.displayIfNeeded()
        if !isVisible { orderFrontRegardless() }
        // A panel can get stranded on one Space whatever its collection behaviour says, and be drawn where nobody sees it.
        guard isOnActiveSpace else { hideGhost(); return nil }
        peekWatch.ghost(spec.peek, caret: GhostLayout.appKitRect(spec.caret, primaryHeight: primary.frame.height), ghost: frame)
        return String(Word.withoutTrailingSpaces(layout.visibleText))
    }

    func hideGhost() {
        orderOut(nil)
        view.layout = nil
        peekWatch.hide()
    }

    private lazy var shine = GlintPanel()
    /// Counts what `show` draws, so a Tab armed on an earlier drawing doesn't glint over this one. Main thread.
    private(set) var drawing = 0
    /// How much of this layout's text Tabs have taken since it was drawn, so quick Tabs before a redraw light the next words, not the first again.
    private var taken = 0
    /// Main thread, once the host was given the ghost's next text, typed or taken by Tab: it's no longer drawn, and the rest stays exactly
    /// where it was, which is where the host is putting it. Nothing hides, moves or overlaps the real text before the host's update draws
    /// the ghost again. Where it was drawn, or nil if this drawing no longer shows it.
    @discardableResult func trim(_ text: String, drawing: Int) -> NSRange? {
        guard drawing == self.drawing, isVisible, var layout = view.layout, let range = Self.next(text, in: layout.storage.string, after: taken) else { return nil }
        taken = NSMaxRange(range)
        let start = layout.manager.glyphIndexForCharacter(at: taken)
        layout.glyphs = NSRange(location: start, length: max(NSMaxRange(layout.glyphs) - start, 0))
        view.layout = layout
        return range
    }

    /// Main thread, right after a Tab took `text` (nil when it typed 2-set keys): trimmed in any app. In our own window the words glint
    /// where this ghost drew them; in another app the host's text may not sit where the ghost was, so the motion waits for `landed`.
    func took(_ text: String?, drawing: Int) {
        leaving = nil  // An older Tab's start mustn't meet this one's landing.
        guard drawing == self.drawing, let layout = view.layout else { return }
        let range = text.flatMap { trim($0, drawing: drawing) }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        if layout.glass { return range.map { shine.play(layout, taken: $0, frame: frame) } ?? () }
        if motion != .off, let caret { leaving = (caret, CACurrentMediaTime()) }
    }

    var motion = AcceptMotion.trail
    /// The caret this ghost was drawn at, which a Tab leaves from.
    private var caret: CGRect?
    private var leaving: (from: CGRect, at: CFTimeInterval)?
    private(set) lazy var caretMotion = CaretMotionPanel()

    /// Main thread, from the read where the field holds all that the last accept typed, so a Shift-Tab's first chunk or another
    /// field's caret can't end it. The motion plays from where the caret was to there.
    func landed(at caret: CGRect) {
        guard let leaving, caret != leaving.from else { return }
        self.leaving = nil
        // Only to drop an accept the host never answered.
        guard CACurrentMediaTime() - leaving.at < 1, let primary = NSScreen.screens.first else { return }
        caretMotion.play(motion, from: leaving.from, to: caret, primaryHeight: primary.frame.height)
    }

    /// Where `text`, just taken, sits in the drawn ghost: right after what earlier Tabs took from it, or nowhere.
    static func next(_ text: String, in ghost: String, after taken: Int) -> NSRange? {
        let range = NSRange(location: taken, length: (text as NSString).length)
        guard range.length > 0, NSMaxRange(range) <= (ghost as NSString).length, (ghost as NSString).substring(with: range) == text else { return nil }
        return range
    }
}

/// What plays where the caret lands after a Tab in another app. Our own window keeps the glint.
enum AcceptMotion: String, CaseIterable {
    /// A streak along the line's foot from the caret's old place to its new one, fading from its tail; a flash when the words wrapped.
    case trail
    /// The caret itself in the icon's blue to peach, fading back to the host's own.
    case flash
    case off

    var duration: CFTimeInterval { self == .trail ? 0.22 : 0.2 }
    /// The glass's blue and the glint's peach.
    static let blue = GhostView.glassColors[0], peach = GlintView.lightColors[3]

    /// Into `context` itself, not AppKit's current one, which a SwiftUI Canvas doesn't set.
    private static func gradient(_ colors: [NSColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    }

    /// Drawn from the two caret rects alone, never the letters, which in most hosts don't sit exactly where the ghost was. Y down.
    /// A trail only along one line, moving right; otherwise the flash.
    static func draw(_ motion: AcceptMotion, from: CGRect, to: CGRect, progress t: CGFloat, in context: CGContext) {
        if motion == .trail, abs(to.midY - from.midY) < from.height / 2, to.minX > from.minX {
            let eased = 1 - pow(1 - t, 3)
            let span = CGRect(x: from.minX, y: to.maxY + 1, width: to.minX - from.minX, height: 2)
            let left = span.maxX - span.width * (1 - eased)
            guard left < span.maxX else { return }
            context.saveGState()
            context.setAlpha(0.9 - 0.7 * eased)
            context.addPath(CGPath(roundedRect: CGRect(x: left, y: span.minY, width: span.maxX - left, height: span.height), cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.clip()
            // Fixed to the whole span, so it is the faint tail that goes.
            context.drawLinearGradient(gradient([blue.withAlphaComponent(0), blue.withAlphaComponent(0.7), peach], [0, 0.6, 1]),
                                       start: CGPoint(x: span.minX, y: 0), end: CGPoint(x: span.maxX, y: 0), options: [])
            context.restoreGState()
        } else if motion != .off {
            let grow: CGFloat = t < 0.35 ? 1.15 - 0.15 * t / 0.35 : 1
            let height = (to.height + 2) * grow
            let bar = CGRect(x: to.midX - 1, y: to.midY - height / 2, width: 2, height: height)
            context.saveGState()
            context.setAlpha(t < 0.35 ? 1 : 1 - (t - 0.35) / 0.65)
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1, cornerHeight: 1, transform: nil))
            context.clip()
            context.drawLinearGradient(gradient([blue, peach], [0, 1]), start: CGPoint(x: 0, y: bar.minY), end: CGPoint(x: 0, y: bar.maxY), options: [])
            context.restoreGState()
        }
    }
}

final class CaretMotionView: NSView {
    var motion = AcceptMotion.trail, from = CGRect.zero, to = CGRect.zero
    var progress: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard progress < 1, let context = NSGraphicsContext.current?.cgContext else { return }
        AcceptMotion.draw(motion, from: from, to: to, progress: progress, in: context)
    }
}

/// Plays one short motion and goes, on the display's clock and in every run loop mode, so a drag or an open menu doesn't stall it.
/// A ghost panel too, so Try It's observer knows its moves aren't the field's.
class OneShotPanel: GhostPanel {
    private var link: CADisplayLink?
    private var start = CFTimeInterval(0), duration = CFTimeInterval(0)
    private var step: (CGFloat) -> Void = { _ in }

    /// `step` gets the time from 0 to 1, and is let go at the end with whatever it holds.
    func run(for duration: CFTimeInterval, in frame: NSRect, _ step: @escaping (CGFloat) -> Void) {
        (self.duration, self.step) = (duration, step)
        step(0)
        setFrame(frame, display: false, animate: false)
        orderFrontRegardless()
        link?.invalidate()
        start = CACurrentMediaTime()
        link = contentView?.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = min((link.targetTimestamp - start) / duration, 1)
        step(t)
        guard t >= 1 else { return }
        link.invalidate()
        self.link = nil
        orderOut(nil)
        step = { _ in }
    }
}

/// Plays one AcceptMotion between two caret rects.
final class CaretMotionPanel: OneShotPanel {
    private let motionView = CaretMotionView()

    override init() {
        super.init()
        contentView = motionView
    }

    /// The rects in AX coordinates.
    func play(_ motion: AcceptMotion, from: CGRect, to: CGRect, primaryHeight: CGFloat) {
        let area = from.union(to).insetBy(dx: -6, dy: -6)
        motionView.motion = motion
        motionView.from = from.offsetBy(dx: -area.minX, dy: -area.minY)
        motionView.to = to.offsetBy(dx: -area.minX, dy: -area.minY)
        run(for: motion.duration, in: GhostLayout.appKitRect(area, primaryHeight: primaryHeight)) { [motionView] in motionView.progress = $0 }
    }
}

/// Plays a GlintView for a quarter of a second.
final class GlintPanel: OneShotPanel {
    private let glint = GlintView()

    override init() {
        super.init()
        contentView = glint
    }

    func play(_ layout: GhostLayout, taken: NSRange, frame: NSRect) {
        glint.manager = layout.manager
        glint.origin = layout.drawOrigin
        glint.glyphs = NSIntersectionRange(layout.manager.glyphRange(forCharacterRange: taken, actualCharacterRange: nil), layout.glyphs)
        // Holds the layout while it plays: a layout manager doesn't keep its text, and the ghost may drop this layout at once.
        run(for: 0.25, in: frame) { [glint] t in withExtendedLifetime(layout) { glint.progress = t * t * (3 - 2 * t) } }
    }
}
