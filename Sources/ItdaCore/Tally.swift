import Foundation

/// Counts only, never text: per local day, how many suggestions showed, how many of those a Tab took from, how many Tabs, and how many
/// characters they added.
public struct Tally: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var shown = 0, taken = 0, tabs = 0, characters = 0
        public init(shown: Int = 0, taken: Int = 0, tabs: Int = 0, characters: Int = 0) {
            (self.shown, self.taken, self.tabs, self.characters) = (shown, taken, tabs, characters)
        }
    }

    /// Keyed `yyyy-MM-dd` in the user's calendar, as Cotypist's stats are, so the two compare day for day.
    public var days: [String: Day]
    public init(days: [String: Day] = [:]) { self.days = days }

    public static func key(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func shown(on date: Date = Date(), _ calendar: Calendar = .current) { days[Self.key(date, calendar), default: Day()].shown += 1 }
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

    public var total: Day {
        days.values.reduce(into: Day()) { ($0.shown, $0.taken, $0.tabs, $0.characters) = ($0.shown + $1.shown, $0.taken + $1.taken, $0.tabs + $1.tabs, $0.characters + $1.characters) }
    }
    public var since: String? { days.keys.min() }
}
