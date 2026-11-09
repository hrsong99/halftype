import AppKit
import HalftypeCore
import SwiftUI

/// General's Show What the Model Sees: while ⌃⌥ is held over a ghost, a card above it with the prompt's end, the word held back, and
/// each word's chance. The modifiers are only watched, never taken, so every ⌃⌥ shortcut still works. Main thread. What it shows lives
/// in memory with the ghost and goes with it.
final class PeekWatch {
    private var monitors: [Any] = []
    private var holding = false
    private var shown: (peek: Peek, caret: CGRect, ghost: NSRect)?
    private var card: PeekPanel?

    var on = false {
        didSet {
            guard on != oldValue else { return }
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            holding = false
            if on {
                // Global for other apps, local for our own window (Try It).
                monitors.append(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.flags($0.modifierFlags) } as Any)
                monitors.append(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.flags($0.modifierFlags); return $0 } as Any)
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

    private func flags(_ flags: NSEvent.ModifierFlags) {
        holding = flags.intersection([.control, .option, .command, .shift]) == [.control, .option]  // Caps Lock or Fn may be on too.
        update()
    }

    private func update() {
        guard on, holding, let shown else { return card?.clear() ?? () }
        if card == nil { card = PeekPanel() }
        card?.show(shown.peek, caret: shown.caret, ghost: shown.ghost)
    }
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
    func show(_ peek: Peek, caret: CGRect, ghost: NSRect) {
        host.rootView = PeekCard(peek: peek)
        let size = host.fittingSize
        let screen = (NSScreen.screens.first { $0.frame.intersects(ghost) } ?? NSScreen.main)?.visibleFrame ?? ghost
        var origin = CGPoint(x: caret.minX - 18, y: ghost.maxY + 6)
        if origin.y + size.height > screen.maxY { origin.y = ghost.minY - 6 - size.height }
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
    private static let blue = Color(nsColor: GhostView.glassColors[0]), peach = Color(nsColor: GhostView.glassColors[2])

    var body: some View {
        if let peek { card(peek).frame(width: 300).fixedSize(horizontal: false, vertical: true) }
    }

    private func card(_ peek: Peek) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What the model sees").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("⌃⌥").font(.system(size: 10, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
            }
            label(peek.context > 0 ? "Context · \(peek.context) characters from the screen" : "Context · none, only the field")
            Text(prompt(peek)).font(.system(size: 11, design: .monospaced)).lineLimit(4).truncationMode(.head)
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
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .medium)).kerning(0.4).foregroundStyle(.secondary).padding(.top, 9).padding(.bottom, 3)
    }

    /// The screen text faded, the field's own text, then the word held back on a peach chip.
    private func prompt(_ peek: Peek) -> AttributedString {
        let split = peek.tail.range(of: "\n\n", options: .backwards)
        var screen = AttributedString(split.map { String(peek.tail[..<$0.lowerBound]) + " ⏎ " } ?? "")
        screen.foregroundColor = .secondary
        let field = AttributedString(split.map { String(peek.tail[$0.upperBound...]) } ?? peek.tail)
        var held = AttributedString(peek.held)
        held.backgroundColor = Self.peach.opacity(0.35)
        return AttributedString("…") + screen + field + held
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
