import SwiftUI

/// The window's backdrop: two riso inks in halftone, blue from the top and peach from the bottom (docs/design/dither-look, round 3 A).
/// The horizon rises a little as you write, keys bounce the peach up from the bottom like a music visualizer, and a Tab swells it warm up the sky.
struct Sky: View {
    /// How far the writing has come, 0 to 1.
    var rise: Double
    /// Recent keys and Tabs, newest last.
    var keys: [Date]
    var tabs: [Date]

    @Environment(\.colorScheme) private var scheme
    @State private var eased = Eased()
    /// Stops the frame clock once nothing has moved for a while.
    @State private var quiet = false

    var body: some View {
        TimelineView(.animation(paused: quiet)) { timeline in
            Canvas { context, size in draw(&context, size, timeline.date) }
        }
        .task(id: [keys.last, tabs.last].map { $0?.timeIntervalSinceReferenceDate ?? 0 } + [rise]) {
            quiet = false
            try? await Task.sleep(for: .seconds(Sky.life))
            if !Task.isCancelled { quiet = true }
        }
        .accessibilityHidden(true)
    }

    /// How long any one key or Tab still moves the sky.
    static let life = 3.0
    static let bars = 18

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ now: Date) {
        let dark = scheme == .dark
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark ? Color(red: 0.07, green: 0.075, blue: 0.09) : Color(red: 0.988, green: 0.98, blue: 0.965)))
        let progress = eased.toward(rise, at: now)
        let recentKeys = keys.filter { now.timeIntervalSince($0) < 1 }
        let tabAges = tabs.map { now.timeIntervalSince($0) }.filter { $0 >= 0 && $0 < Sky.life }

        // Each key lifts every bar by its own random height, quick in and quickly gone; the sum is capped so fast typing dances rather than climbs.
        var lift = [Double](repeating: 0, count: Sky.bars)
        for key in recentKeys {
            let age = max(now.timeIntervalSince(key), 0), envelope = exp(-age * 7) * min(age * 30, 1)
            let seed = Int(key.timeIntervalSinceReferenceDate * 1000) % 100_000
            for bar in 0..<Sky.bars { lift[bar] += envelope * (0.3 + 0.7 * Sky.hash(bar, seed)) }
        }
        lift = lift.map { min($0, 1.4) * 0.085 }

        let cell = 6.0, radius = cell * 0.62  // Fine print, as in the design's cards.
        let columns = Int(size.width / cell) + 2, rows = Int(size.height / cell) + 2
        var blues = Path(), peaches = Path()
        for j in 0..<rows {
            for i in 0..<columns {
                let u = (Double(i) + 0.25) / Double(columns), v = (Double(j) + 0.25) / Double(rows)
                let horizon = 0.56 - 0.08 * progress - lift[min(Int(u * Double(Sky.bars)), Sky.bars - 1)]
                var peach = Sky.clamp((v - horizon) * 1.45), blue = Sky.clamp(0.62 - v * 1.5 - 0.048 * progress)
                for age in tabAges {
                    // A warm wave from the bottom up, about a second.
                    let swell = exp(-age * 2.2) * min(age * 5, 1), front = Sky.clamp((v - (1 - age * 2)) * 3 + 1)
                    peach += 0.32 * swell * Sky.clamp(v * 1.6) * front
                    blue -= 0.12 * swell
                }
                Sky.dot(&blues, CGPoint(x: Double(i) * cell, y: Double(j) * cell), radius, Sky.clamp(blue))
                Sky.dot(&peaches, CGPoint(x: (Double(i) + 0.5) * cell, y: (Double(j) + 0.5) * cell), radius, Sky.clamp(peach))
            }
        }
        // Inks on paper multiply; on a dark window they add, like light.
        context.blendMode = dark ? .plusLighter : .multiply
        context.fill(blues, with: .color(dark ? Color(red: 0.13, green: 0.22, blue: 0.31) : Color(red: 0.663, green: 0.804, blue: 0.941)))
        context.fill(peaches, with: .color(dark ? Color(red: 0.30, green: 0.19, blue: 0.14) : Color(red: 0.965, green: 0.765, blue: 0.643)))
    }

    /// Dot area is ink, so the radius goes with the square root.
    private static func dot(_ path: inout Path, _ center: CGPoint, _ radius: Double, _ ink: Double) {
        guard ink > 0.04 else { return }
        let r = radius * ink.squareRoot()
        path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    static func hash(_ a: Int, _ b: Int) -> Double {
        let h = sin(Double(a) * 127.1 + Double(b) * 311.7) * 43758.5453
        return h - h.rounded(.down)
    }

    /// The horizon's rise follows the writing over about a second, rather than jumping a step with each letter.
    final class Eased {
        var value = 0.0
        var last: Date?
        func toward(_ goal: Double, at now: Date) -> Double {
            let step = last.map { min(max(now.timeIntervalSince($0), 0) * 4, 1) } ?? 1
            last = now
            value += (goal - value) * step
            return value
        }
    }
}
