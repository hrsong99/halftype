import AppKit
import HalftypeCore
import SwiftUI

/// General's Show What the Model Sees: a tap of ⌃⌥ turns on a card above every ghost with the prompt's end, the word held back, and
/// each word's chance; ⌃⌥⇧ the whole prompt; the same tap again turns it off. The keys are only watched, never taken, so every ⌃⌥
/// shortcut still works. Main thread. What it shows lives in memory with the ghost and goes with it.
final class PeekWatch {
    private var monitors: [Any] = []
    private var tap = PeekTap(), showing = false, whole = false
    private var shown: (peek: Peek, caret: CGRect, ghost: NSRect)?
    private var card: PeekPanel?

    var on = false {
        didSet {
            guard on != oldValue else { return }
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            (tap, showing) = (PeekTap(), false)
            if on {
                // Global for other apps, local for our own window (Try It). Key presses only spoil a tap; nothing of them is kept.
                let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
                monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in self?.event($0) } as Any)
                monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] in self?.event($0); return $0 } as Any)
            }
            update()
        }
    }

    /// The ghost now drawn, with its card's contents if the setting is on, or nil once it hides. Both rects in AppKit coordinates.
    func ghost(_ peek: Peek?, caret: CGRect, ghost: NSRect) {
        shown = peek.map { ($0, caret, ghost) }
        update()
    }

    func hide() {
        shown = nil
        update()
    }

    private func event(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return tap.key() }
        guard let wantsWhole = tap.flags(event.modifierFlags) else { return }
        (showing, whole) = showing && whole == wantsWhole ? (false, whole) : (true, wantsWhole)
        update()
    }

    private func update() {
        guard on, showing, let shown else { return card?.clear() ?? () }
        if card == nil { card = PeekPanel() }
        card?.show(shown.peek, whole: whole, caret: shown.caret, ghost: shown.ghost)
    }
}

/// A tap of ⌃⌥, ⇧ optional: pressed and let go with no other key or modifier between, so ⌃⌥← and the like aren't one.
struct PeekTap {
    private var chord: NSEvent.ModifierFlags = [], spoiled = false

    /// On letting go of ⌃ or ⌥ after a tap: whether it had ⇧. Caps Lock and Fn don't count. Not on the last key up: once ⌃⌥ are gone,
    /// KeyTap may swallow an Esc that these monitors never see.
    mutating func flags(_ flags: NSEvent.ModifierFlags) -> Bool? {
        let held = flags.intersection([.control, .option, .command, .shift])
        let peaked = chord.isSuperset(of: [.control, .option])
        chord.formUnion(held)
        guard !held.isSuperset(of: [.control, .option]), peaked || held.isEmpty else { return nil }
        defer { (chord, spoiled) = ([], false) }
        return peaked && !spoiled && !chord.contains(.command) ? chord.contains(.shift) : nil
    }

    /// A key pressed with modifiers down; typing between taps doesn't count.
    mutating func key() { if !chord.isEmpty { spoiled = true } }
}

/// A ghost panel too, so Try It's observer knows its moves aren't the field's.
final class PeekPanel: GhostPanel {
    private let host = NSHostingView(rootView: PeekCard(peek: nil))

    override init() {
        super.init()
        hasShadow = true
        contentView = host
    }

    /// Above the ghost, starting near the caret, inside the screen; below the line when there's no room above.
    func show(_ peek: Peek, whole: Bool, caret: CGRect, ghost: NSRect) {
        host.rootView = PeekCard(peek: peek, whole: whole)
        let size = host.fittingSize
        let screen = (NSScreen.screens.first { $0.frame.intersects(ghost) } ?? NSScreen.main)?.visibleFrame ?? ghost
        var origin = CGPoint(x: caret.minX - 18, y: ghost.maxY + 6)
        if origin.y + size.height > screen.maxY { origin.y = max(ghost.minY - 6 - size.height, screen.minY + 8) }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
        if !isVisible { orderFrontRegardless() }
    }

    /// Hidden, and the typed text it showed let go.
    func clear() {
        orderOut(nil)
        host.rootView = PeekCard(peek: nil)
    }
}

struct PeekCard: View {
    let peek: Peek?
    var whole = false
    private static let blue = Color(nsColor: GhostView.glassColors[0]), peach = Color(nsColor: GhostView.glassColors[2])

    var body: some View {
        if let peek { card(peek).frame(width: whole ? 520 : 300).fixedSize(horizontal: false, vertical: true) }
    }

    private func card(_ peek: Peek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What the model sees").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(whole ? "⌃⌥⇧" : "⌃⌥").font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
            }
            label(peek.screen.isEmpty ? "From the screen · nothing" : "From the screen · \(count(peek.screen.count, of: peek.context))")
            if !peek.screen.isEmpty { prompt(Text(end(peek.screen, lines: 2))).foregroundStyle(.secondary) }
            label("In the field · \(peek.field.count + peek.held.count) characters")
            prompt(Text(end(peek.field, lines: 3)) + Text(field(peek.held)))
            label("Its words · chance, and running")
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(Array(peek.steps.enumerated()), id: \.offset) { _, step in
                    GridRow {
                        Text(step.text.trimmingCharacters(in: .whitespaces)).strikethrough(!step.kept).lineLimit(1)
                            .frame(width: 92, alignment: .leading)
                        Text(Self.percent(step.logprob)).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                        bar(step.running).opacity(step.kept ? 1 : 0.35)
                        Text(Self.percent(step.running)).frame(width: 34, alignment: .trailing)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(step.kept ? .primary : .secondary)
                }
            }
            Text(verdict(peek)).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 8)
            if !whole { Text("⌃⌥⇧ for the whole prompt, ⌃⌥ again to hide.").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 3) }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .medium)).kerning(0.4).foregroundStyle(.secondary).padding(.top, 9).padding(.bottom, 3)
    }

    private func prompt(_ text: Text) -> some View {
        text.font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
    }

    /// Its last lines only, nearest the caret, unless ⇧ asks for all of it. By hand: SwiftUI truncates many lines only at their end.
    private func end(_ text: String, lines: Int) -> String {
        guard !whole else { return text }
        let last = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n").suffix(38 * lines)
        return (last.count < text.count ? "…" : "") + last
    }

    /// The word held back, on a peach chip.
    private func field(_ held: String) -> AttributedString {
        var held = AttributedString(held)
        held.backgroundColor = Self.peach.opacity(0.35)
        return held
    }

    /// "412 characters", or "1200 of 1800 characters" when the window cut its start.
    private func count(_ given: Int, of read: Int) -> String {
        read > given ? "\(given) of \(read) characters" : "\(given) characters"
    }

    private func bar(_ running: Double) -> some View {
        Capsule().fill(.quaternary).frame(width: 100, height: 5).overlay(alignment: .leading) {
            Capsule().fill(LinearGradient(colors: [Self.blue, Self.peach], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, 100 * exp(running)), height: 5)
        }
    }

    private func verdict(_ peek: Peek) -> String {
        let first = "First word \(Self.percent(peek.steps[0].running)), needs \(Self.percent(peek.threshold)). "
        let why = switch peek.end {
        case .floor: "Stopped: the running chance fell under \(Self.percent(peek.floor))."
        case .punctuation: "Ends at punctuation."
        case .line: "Ends at a line break."
        case .limit: "Ends at the \(Stop.maxTokens)-token limit."
        case .model: "The model ended it."
        case .writing: "Still writing…"
        }
        return first + why
    }

    static func percent(_ logprob: Double) -> String {
        let p = exp(logprob) * 100
        return p >= 10 || p == 0 ? "\(Int(p.rounded()))%" : String(format: "%.1f%%", p)
    }
}
