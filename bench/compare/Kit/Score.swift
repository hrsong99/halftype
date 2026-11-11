import Foundation

/// One key pressed (a letter, a jamo or Tab), and what the screen did before the next.
public struct KeyRecord: Codable, Sendable {
    public var app: String, lang: String, sentence: String
    public var tab: Bool
    /// The pause after it was a latency probe (1.5 s), not a typing delay.
    public var probe: Bool
    /// No ghost was on screen when it was pressed.
    public var fresh: Bool
    /// Keystroke to the first frame with ink right of the moved caret, if that came before the next key.
    public var latencyMs: Double?
    /// A ghost was on screen when the next key was decided, and whether its first word was the true next word.
    public var shown: Bool, firstRight: Bool
    /// A Hangul syllable was composing after this key.
    public var composing: Bool
    public init(app: String, lang: String, sentence: String, tab: Bool, probe: Bool, fresh: Bool, latencyMs: Double?, shown: Bool, firstRight: Bool, composing: Bool) {
        (self.app, self.lang, self.sentence, self.tab, self.probe, self.fresh, self.latencyMs, self.shown, self.firstRight, self.composing) =
            (app, lang, sentence, tab, probe, fresh, latencyMs, shown, firstRight, composing)
    }
}

/// One sentence typed to the end.
public struct SentenceRecord: Codable, Sendable {
    public var app: String, lang: String, sentence: String
    /// Keys the sentence needs with no help, and keys pressed: letters, Tabs, and the backspaces a wrong Tab would cost.
    public var total: Int, pressed: Int
    public var tabs: Int, wrongTabs: Int
    /// Tabs whose result was exactly what the OCR'd ghost said it would be: how far to trust the OCR for this app.
    public var tabsAsRead: Int
    public init(app: String, lang: String, sentence: String, total: Int, pressed: Int, tabs: Int, wrongTabs: Int, tabsAsRead: Int) {
        (self.app, self.lang, self.sentence, self.total, self.pressed, self.tabs, self.wrongTabs, self.tabsAsRead) = (app, lang, sentence, total, pressed, tabs, wrongTabs, tabsAsRead)
    }
}

/// The app's processes while typing one language, sampled between sentences (sampling suspends the process briefly).
public struct ResourceRecord: Codable, Sendable {
    public var app: String, lang: String
    public var footprintMB: [Double]
    /// Resident pages of mapped .gguf files at the end: the weights, which footprint leaves out. Nil where none is mapped.
    public var modelResidentMB: Double?
    /// CPU time over wall time while typing, in % of one core, all of the app's processes.
    public var cpuPercent: Double?
    public var seconds: Double
    /// Unix time typing began, so `power.py` can pick this app's `powermetrics` samples. Nil in runs before 2026-11-12.
    public var start: Double?
    public init(app: String, lang: String, footprintMB: [Double], modelResidentMB: Double?, cpuPercent: Double?, seconds: Double, start: Double? = nil) {
        (self.app, self.lang, self.footprintMB, self.modelResidentMB, self.cpuPercent, self.seconds, self.start) = (app, lang, footprintMB, modelResidentMB, cpuPercent, seconds, start)
    }
}

/// Typing delays: log-normal around the 264 ms median of docs/measuring.md's typing histogram, seeded, so every app
/// gets the same sequence of pauses for the same sentence.
public struct Delays {
    var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
    public mutating func next() -> Double {
        let g = (-2 * log(max(unit(), 1e-12))).squareRoot() * cos(2 * .pi * unit())
        return min(1200, max(90, 264 * exp(0.5 * g)))
    }
    /// A stable seed from a sentence ID.
    public static func seed(_ id: String) -> UInt64 { id.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
}

public enum Score {
    public static func percentile(_ xs: [Double], _ p: Double) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        return s[min(s.count - 1, Int((p * Double(s.count - 1)).rounded()))]
    }

    /// Keys saved, and a 95% bootstrap interval over sentences.
    public static func saved(_ rows: [SentenceRecord], reps: Int = 2000, seed: UInt64 = 7) -> (value: Double, low: Double, high: Double)? {
        guard !rows.isEmpty else { return nil }
        func rate(_ r: [SentenceRecord]) -> Double { 1 - Double(r.map(\.pressed).reduce(0, +)) / Double(max(1, r.map(\.total).reduce(0, +))) }
        var d = Delays(seed: seed)
        let draws = (0..<reps).map { _ in rate((0..<rows.count).map { _ in rows[min(rows.count - 1, Int(d.unit() * Double(rows.count)))] }) }
        return (rate(rows), percentile(draws, 0.025)!, percentile(draws, 0.975)!)
    }

    public struct Row: Codable, Sendable {
        public var app: String, lang: String
        public var sentences: Int, keys: Int
        public var saved: Double?, savedLow: Double?, savedHigh: Double?
        public var shownShare: Double?, firstRight: Double?
        public var freshP50: Double?, freshP90: Double?, freshN: Int
        /// At 1.5 s pauses from a clean screen: share with no ghost at all, and p50 of the rest.
        public var probeNone: Double?, probeP50: Double?, probeN: Int
        public var composingShown: Double?, composingN: Int
        public var tabs: Int, wrongTabs: Int, tabsAsRead: Int
        public var footprintMedianMB: Double?, footprintMaxMB: Double?, modelResidentMB: Double?, cpuPercent: Double?
    }

    public static func rows(keys: [KeyRecord], sentences: [SentenceRecord], resources: [ResourceRecord]) -> [Row] {
        var out: [Row] = []
        var seen = Set<String>()
        for s in sentences where seen.insert(s.app + "\t" + s.lang).inserted {
            let k = keys.filter { $0.app == s.app && $0.lang == s.lang }
            let ss = sentences.filter { $0.app == s.app && $0.lang == s.lang }
            let res = resources.filter { $0.app == s.app && $0.lang == s.lang }
            let saved = Score.saved(ss)
            let shown = k.filter(\.shown)
            let fresh = k.filter { $0.fresh && !$0.tab }.compactMap(\.latencyMs)
            let probes = k.filter { $0.probe && $0.fresh }
            let probeHit = probes.compactMap(\.latencyMs)
            let composing = k.filter(\.composing)
            let fps = res.flatMap(\.footprintMB)
            func share(_ a: Int, _ b: Int) -> Double? { b == 0 ? nil : Double(a) / Double(b) }
            out.append(Row(app: s.app, lang: s.lang, sentences: ss.count, keys: k.count,
                           saved: saved?.value, savedLow: saved?.low, savedHigh: saved?.high,
                           shownShare: share(shown.count, k.count), firstRight: share(shown.filter(\.firstRight).count, shown.count),
                           freshP50: percentile(fresh, 0.5), freshP90: percentile(fresh, 0.9), freshN: fresh.count,
                           probeNone: share(probes.count - probeHit.count, probes.count), probeP50: percentile(probeHit, 0.5), probeN: probes.count,
                           composingShown: share(composing.filter { $0.shown && $0.latencyMs != nil }.count, composing.count), composingN: composing.count,
                           tabs: ss.map(\.tabs).reduce(0, +), wrongTabs: ss.map(\.wrongTabs).reduce(0, +), tabsAsRead: ss.map(\.tabsAsRead).reduce(0, +),
                           footprintMedianMB: percentile(fps, 0.5), footprintMaxMB: fps.max(),
                           modelResidentMB: res.compactMap(\.modelResidentMB).max(), cpuPercent: res.compactMap(\.cpuPercent).max()))
        }
        return out
    }

    /// The aggregate table, the only part of a run meant for the repo.
    public static func markdown(_ rows: [Row]) -> String {
        func pct(_ x: Double?) -> String { x.map { String(format: "%.1f%%", $0 * 100) } ?? "-" }
        func ms(_ x: Double?) -> String { x.map { String(format: "%.0f ms", $0) } ?? "-" }
        func mb(_ x: Double?) -> String { x.map { String(format: "%.0f MB", $0) } ?? "-" }
        var s = "| App | Text | Sentences, keys | Keys saved (95% CI) | Keys with a ghost | First word right | Right / wrong ghosts per 100 keys | Ghost after a key, fresh p50 / p90 (n) | 1.5 s probe: none, p50 (n) | Mid-syllable ghost (n) | Tabs, wrong, as OCR read | Footprint median / max | Model resident | CPU |\n"
        s += "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
        for r in rows {
            // Helpfulness and noise in one place: right is shown and first word right, wrong the rest of what was shown.
            let per100 = r.shownShare.flatMap { sh in r.firstRight.map { String(format: "%.0f / %.0f", sh * $0 * 100, sh * (1 - $0) * 100) } } ?? "-"
            let ci = r.savedLow.map { String(format: " (%.1f-%.1f)", $0 * 100, r.savedHigh! * 100) } ?? ""
            s += "| \(r.app) | \(r.lang) | \(r.sentences), \(r.keys) | \(pct(r.saved))\(ci) | \(pct(r.shownShare)) | \(pct(r.firstRight)) | \(per100) | \(ms(r.freshP50)) / \(ms(r.freshP90)) (\(r.freshN)) | \(pct(r.probeNone)), \(ms(r.probeP50)) (\(r.probeN)) | \(r.lang == "ko" ? "\(pct(r.composingShown)) (\(r.composingN))" : "-") | \(r.tabs), \(r.wrongTabs), \(r.tabsAsRead) | \(mb(r.footprintMedianMB)) / \(mb(r.footprintMaxMB)) | \(mb(r.modelResidentMB)) | \(r.cpuPercent.map { String(format: "%.0f%%", $0) } ?? "-") |\n"
        }
        return s
    }
}
