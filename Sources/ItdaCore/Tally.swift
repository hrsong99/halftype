import Foundation

/// Counts only, never text: per local day, how many suggestions showed, how many of those a Tab took from, how many Tabs, and how many
/// characters they added, how many keys were typed by hand, and whether the personal model was on.
public struct Tally: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var shown = 0, taken = 0, tabs = 0, characters = 0
        /// Keys that typed a character, counted since 0.1.6, so 0 on older days.
        public var typed = 0
        public var personal = false
        public init(shown: Int = 0, taken: Int = 0, tabs: Int = 0, characters: Int = 0, typed: Int = 0, personal: Bool = false) {
            (self.shown, self.taken, self.tabs, self.characters, self.typed, self.personal) = (shown, taken, tabs, characters, typed, personal)
        }
        /// Older files lack the newer keys, and a failed decode would start the counts over.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func int(_ key: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: key) ?? 0 }
            (shown, taken, tabs, characters, typed) = (try int(.shown), try int(.taken), try int(.tabs), try int(.characters), try int(.typed))
            personal = try c.decodeIfPresent(Bool.self, forKey: .personal) ?? false
        }
        static func + (a: Day, b: Day) -> Day {
            Day(shown: a.shown + b.shown, taken: a.taken + b.taken, tabs: a.tabs + b.tabs, characters: a.characters + b.characters, typed: a.typed + b.typed)
        }
        /// Of everything typed, the share Tab typed: what the replay bench calls keys saved. Nil before keys were counted.
        public var byTab: Double? { typed == 0 ? nil : Double(characters) / Double(characters + typed) }
    }

    /// Keyed `yyyy-MM-dd` in the user's calendar, as Cotypist's stats are, so the two compare day for day.
    public var days: [String: Day]
    public init(days: [String: Day] = [:]) { self.days = days }

    public static func key(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func shown(personal: Bool = false, on date: Date = Date(), _ calendar: Calendar = .current) {
        days[Self.key(date, calendar), default: Day()].shown += 1
        days[Self.key(date, calendar), default: Day()].personal = personal
    }
    public mutating func typed(_ keys: Int, on date: Date = Date(), _ calendar: Calendar = .current) {
        guard keys > 0 else { return }
        days[Self.key(date, calendar), default: Day()].typed += keys
    }
    /// `first` is the suggestion's first Tab, so Tab-Tab through one suggestion counts it taken once.
    public mutating func took(_ characters: Int, first: Bool, on date: Date = Date(), _ calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        days[key, default: Day()].tabs += 1
        days[key, default: Day()].characters += characters
        if first { days[key, default: Day()].taken += 1 }
    }

    /// The `count` days up to and including `date`, oldest first, with empty days kept so a chart has no gaps.
    public func last(_ count: Int, to date: Date = Date(), _ calendar: Calendar = .current) -> [(date: Date, day: Day)] {
        (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { ($0, days[Self.key($0, calendar)] ?? Day()) }
        }
    }

    public var total: Day { days.values.reduce(Day(), +) }
    /// Days with suggestions and counted keys, with or without the personal model: how many, and their sum.
    public func sum(personal: Bool) -> (count: Int, sum: Day) {
        let picked = days.values.filter { $0.personal == personal && $0.shown > 0 && $0.typed > 0 }
        return (picked.count, picked.reduce(Day(), +))
    }
    public var since: String? { days.keys.min() }
}
