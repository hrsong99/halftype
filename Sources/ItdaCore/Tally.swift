import Foundation

/// Counts only, never text: per local day, how many suggestions showed, how many of those a Tab took from, how many Tabs, and how many
/// characters and keys they saved, how many keys were typed by hand, and whether the personal model was on.
public struct Tally: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var shown = 0, taken = 0, tabs = 0, characters = 0
        /// Keys typed by hand that made a character, and keys Tab saved: a Hangul syllable is its jamo keys. 0 on days before 0.1.6.
        public var typed = 0, saved = 0
        /// Some of the day ran with the personal model, or without it. Both make a mixed day, which no comparison counts.
        public var withModel = false, withoutModel = false
        public init(shown: Int = 0, taken: Int = 0, tabs: Int = 0, characters: Int = 0, typed: Int = 0, saved: Int = 0) {
            (self.shown, self.taken, self.tabs, self.characters, self.typed, self.saved) = (shown, taken, tabs, characters, typed, saved)
        }
        /// Older files lack the newer keys, and a failed decode would start the counts over.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func int(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
            (shown, taken, tabs, characters, typed, saved) = (try int(.shown), try int(.taken), try int(.tabs), try int(.characters), try int(.typed), try int(.saved))
            withModel = try c.decodeIfPresent(Bool.self, forKey: .withModel) ?? false
            withoutModel = try c.decodeIfPresent(Bool.self, forKey: .withoutModel) ?? false
        }
        static func + (a: Day, b: Day) -> Day {
            Day(shown: a.shown + b.shown, taken: a.taken + b.taken, tabs: a.tabs + b.tabs, characters: a.characters + b.characters, typed: a.typed + b.typed, saved: a.saved + b.saved)
        }
        /// Of everything typed, the share Tab typed: what the replay bench calls keys saved. Nil before keys were counted.
        public var byTab: Double? { typed == 0 ? nil : Double(saved) / Double(saved + typed) }
    }

    /// Keyed `yyyy-MM-dd` in the user's calendar, as Cotypist's stats are, so the two compare day for day.
    public var days: [String: Day]
    public init(days: [String: Day] = [:]) { self.days = days }

    public static func key(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func shown(on date: Date = Date(), _ calendar: Calendar = .current) { days[Self.key(date, calendar), default: Day()].shown += 1 }
    /// Nil for another model than the one adapters are trained on, which leaves the day out of any comparison.
    public mutating func mark(personal: Bool?, on date: Date = Date(), _ calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        if personal != false { days[key, default: Day()].withModel = true }
        if personal != true { days[key, default: Day()].withoutModel = true }
    }
    public mutating func typed(_ keys: Int, on date: Date = Date(), _ calendar: Calendar = .current) {
        guard keys > 0 else { return }
        days[Self.key(date, calendar), default: Day()].typed += keys
    }
    /// `first` is the suggestion's first Tab, so Tab-Tab through one suggestion counts it taken once.
    public mutating func took(_ characters: Int, keys: Int = 0, first: Bool, on date: Date = Date(), _ calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        days[key, default: Day()].tabs += 1
        days[key, default: Day()].characters += characters
        days[key, default: Day()].saved += keys
        if first { days[key, default: Day()].taken += 1 }
    }

    /// The `count` days up to and including `date`, oldest first, with empty days kept so a chart has no gaps.
    public func last(_ count: Int, to date: Date = Date(), _ calendar: Calendar = .current) -> [(date: Date, day: Day)] {
        (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { ($0, days[Self.key($0, calendar)] ?? Day()) }
        }
    }

    public var total: Day { days.values.reduce(Day(), +) }
    /// Days with counted keys wholly with or wholly without the personal model, suggestions or none: how many, and their sum.
    public func sum(personal: Bool) -> (count: Int, sum: Day) {
        let picked = days.values.filter { $0.typed > 0 && $0.withModel == personal && $0.withoutModel != personal }
        return (picked.count, picked.reduce(Day(), +))
    }
    public var since: String? { days.keys.min() }
}
