import SwiftUI

/// The window's backdrop: two riso inks in halftone, blue from the top and peach from the bottom (docs/design/dither-look, round 3 A).
/// The inks fade out at the edges of the content, so they keep their distance at any window size.
/// The horizon rises a little as you write, keys bounce the peach up from the bottom like a music visualizer, and a Tab swells it warm up the sky.
struct Sky: View {
    /// How far the writing has come, 0 to 1.
    var rise: Double
    /// Recent keys and Tabs, newest last.
    var keys: [Date]
    var tabs: [Date]
    /// The band, in points from the top, that the inks fade out before; nil keeps them where the design put them.
    var clear: ClosedRange<CGFloat>? = nil

    @Environment(\.colorScheme) private var scheme
    @State private var eased = Eased()
    /// Stops the frame clock once nothing has moved for a while.
    @State private var quiet = false

    var body: some View {
        TimelineView(.animation(paused: quiet)) { timeline in
            GeometryReader { geometry in
                Rectangle().colorEffect(shader(geometry.size, timeline.date))
            }
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

    /// The dots are drawn on the GPU (Sky.metal): ten thousand of them cost 139 ms a frame on the CPU.
    private func shader(_ size: CGSize, _ now: Date) -> Shader {
        let dark = scheme == .dark
        // Each key lifts every bar by its own random height, quick in and quickly gone; the sum is capped so fast typing dances rather than climbs.
        var lift = [Float](repeating: 0, count: Sky.bars)
        for key in keys where now.timeIntervalSince(key) < 1 {
            let age = max(now.timeIntervalSince(key), 0), envelope = exp(-age * 7) * min(age * 30, 1)
            let seed = Int(key.timeIntervalSinceReferenceDate * 1000) % 100_000
            for bar in 0..<Sky.bars { lift[bar] += Float(envelope * (0.3 + 0.7 * Sky.hash(bar, seed))) }
        }
        lift = lift.map { min($0, 1.4) * 0.085 }
        let ages = tabs.reversed().map { now.timeIntervalSince($0) }.filter { $0 >= 0 && $0 < Sky.life }.prefix(3)
        let tab = { (n: Int) in Float(n < ages.count ? ages[ages.startIndex + n] : -1) }
        return ShaderLibrary.bundle(.module).sky(
            .float2(size), .float2(clear?.lowerBound ?? size.height * 0.413, clear?.upperBound ?? size.height * 0.56), .float(eased.toward(rise, at: now)), .floatArray(lift), .float3(tab(0), tab(1), tab(2)),
            .color(dark ? Color(red: 0.07, green: 0.075, blue: 0.09) : Color(red: 0.988, green: 0.98, blue: 0.965)),
            .color(dark ? Color(red: 0.13, green: 0.22, blue: 0.31) : Color(red: 0.663, green: 0.804, blue: 0.941)),
            .color(dark ? Color(red: 0.30, green: 0.19, blue: 0.14) : Color(red: 0.965, green: 0.765, blue: 0.643)),
            .float(dark ? 1 : 0))
    }

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
