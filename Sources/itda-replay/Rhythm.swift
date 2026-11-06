/// Real inter-key delays from one author's typing in T3 Code and ego lite, about half of it Korean: AX selection events
/// (one per key), 20 ms to 5 s, n=107. A small sample. Only delays are kept, no text. Bins: (from ms, to ms, count).
let rhythm: [(from: Int, to: Int, count: Int)] = [(40, 60, 2), (60, 80, 3), (80, 100, 5), (100, 120, 6), (120, 150, 7), (150, 200, 18), (200, 250, 9), (250, 300, 9), (300, 400, 10), (400, 500, 8), (500, 700, 9), (700, 1000, 7), (1000, 1500, 7), (1500, 2000, 1), (2000, 3000, 4), (3000, 5000, 2)]

/// A small seeded generator, so a replay's rhythm repeats.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func sampleDelayMs(using rng: inout SplitMix) -> Double {
    var pick = Int.random(in: 0..<rhythm.reduce(0) { $0 + $1.count }, using: &rng)
    for bin in rhythm {
        if pick < bin.count { return Double(Int.random(in: bin.from..<bin.to, using: &rng)) }
        pick -= bin.count
    }
    return 250
}
