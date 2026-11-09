import Foundation

/// Counts only, never text: per local day, how many suggestions showed, how many of those a Tab took from, how many Tabs, and how many
/// characters and keys they saved, how many keys were typed by hand, and whether the personal model was on.
public struct Tally: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var shown = 0, taken = 0, tabs = 0, characters = 0
        /// Keys typed by hand that made a character, and keys Tab saved: a Hangul syllable is its jamo keys. 0 on days before 0.1.6.
        public var typed = 0, saved = 0
        /// Words a Tab typed any of; nil on days before they were counted (2026-11-10), which `wordCount` estimates.
        public var words: Int? = 0
        /// Keys typed within 2 s of the key before, and those gaps' seconds: the user's own typing speed, without pauses to think or read.
        public var paced = 0, seconds = 0.0
        /// Some of the day ran with the personal model, or without it. Both make a mixed day, which no comparison counts.
        public var withModel = false, withoutModel = false
        /// The personal models (adapter file names) the with-model hours ran: one, or the day can't stand for one model.
        public var adapters: [String] = []
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
            adapters = try c.decodeIfPresent([String].self, forKey: .adapters) ?? []
            words = try c.decodeIfPresent(Int.self, forKey: .words)
            (paced, seconds) = (try int(.paced), try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0)
        }
        /// Each day's estimate is kept in the sum, so a period mixing days before and after words were counted adds up.
        static func + (a: Day, b: Day) -> Day {
            var sum = Day(shown: a.shown + b.shown, taken: a.taken + b.taken, tabs: a.tabs + b.tabs, characters: a.characters + b.characters, typed: a.typed + b.typed, saved: a.saved + b.saved)
            (sum.words, sum.paced, sum.seconds) = (a.wordCount + b.wordCount, a.paced + b.paced, a.seconds + b.seconds)
            return sum
        }
        /// Of everything typed, the share Tab typed: what the replay bench calls keys saved. Nil before keys were counted.
        public var byTab: Double? { typed == 0 ? nil : Double(saved) / Double(saved + typed) }
        /// Tab typed one key in this many, by `byTab`: nil before keys were counted or with none saved.
        public var oneIn: Int? { saved == 0 || typed == 0 ? nil : Int((Double(saved + typed) / Double(saved)).rounded()) }
        /// The words Tab typed; before they were counted, letters ÷ 5 (the typing-test word, about 3× high for Korean).
        public var wordCount: Int { words ?? characters / 5 }
    }

    /// Words a Tab typed any of: runs of letters or digits, so "rrow and" is two. Korean spaces its words too.
    public static func words(in text: String) -> Int {
        var count = 0, inWord = false
        for character in text {
            let letter = character.isLetter || character.isNumber
            if letter && !inWord { count += 1 }
            inWord = letter
        }
        return count
    }

    /// The user's typing speed in keys a minute, from every day timed. Nil until a minute of typing has been timed: fewer seconds are noise.
    public var speed: Double? {
        let timed = days.values.reduce(Day(), +)
        return timed.seconds < 60 ? nil : Double(timed.paced) / timed.seconds * 60
    }
    /// The keys Tab typed, at the user's own speed: one speed for every day, so days before it was timed count too. Until it's timed,
    /// 200 keys a minute (40 words).
    public func minutes(_ day: Day) -> Double { Double(day.saved) / (speed ?? 200) }

    /// Keyed `yyyy-MM-dd` in the user's calendar, as Cotypist's stats are, so the two compare day for day.
    public var days: [String: Day]
    public init(days: [String: Day] = [:]) { self.days = days }

    public static func key(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func shown(on date: Date = Date(), _ calendar: Calendar = .current) { days[Self.key(date, calendar), default: Day()].shown += 1 }
    /// Nil for another model than the one adapters are trained on, which leaves the day out of any comparison.
    public mutating func mark(personal: Bool?, adapter: String? = nil, on date: Date = Date(), _ calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        if personal == true, let adapter, !days[key, default: Day()].adapters.contains(adapter) { days[key, default: Day()].adapters.append(adapter) }
        if personal != false { days[key, default: Day()].withModel = true }
        if personal != true { days[key, default: Day()].withoutModel = true }
    }
    /// `gap`: seconds since the key before; under 2 s it times the user's typing.
    public mutating func typed(_ keys: Int, after gap: TimeInterval? = nil, on date: Date = Date(), _ calendar: Calendar = .current) {
        guard keys > 0 else { return }
        let key = Self.key(date, calendar)
        days[key, default: Day()].typed += keys
        if let gap, gap >= 0, gap < 2 { days[key, default: Day()].paced += keys; days[key, default: Day()].seconds += gap }
    }
    /// `first` is the suggestion's first Tab, so Tab-Tab through one suggestion counts it taken once.
    public mutating func took(_ characters: Int, keys: Int = 0, words: Int = 0, first: Bool, on date: Date = Date(), _ calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        days[key, default: Day()].words = days[key, default: Day()].wordCount + words
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
    /// The `count` days up to and including `date`, in sum.
    public func sum(_ count: Int, to date: Date, _ calendar: Calendar = .current) -> Day { last(count, to: date, calendar).map(\.day).reduce(Day(), +) }

    /// A week or month of the calendar, for the Stats page to page back through, and the stretch of the one before it to compare with.
    public struct Period: Equatable, Sendable {
        /// The first day, and how many days it has.
        public let start: Date, length: Int
        /// The days so far: all of them in a past period, up to today in this one.
        public let elapsed: Int
        /// The period before: the same days so far while this one runs, so a Monday is set against a Monday, and the whole of it once this one is over.
        public let previousStart: Date, previousLength: Int
    }

    /// The `unit` (`.weekOfYear` or `.month`) holding `now`, `back` of them ago. Weeks start where the user's calendar starts them.
    public static func period(_ unit: Calendar.Component, back: Int, now: Date = Date(), _ calendar: Calendar = .current) -> Period? {
        guard let shifted = calendar.date(byAdding: unit, value: -back, to: now), let this = calendar.dateInterval(of: unit, for: shifted),
              let last = calendar.date(byAdding: .day, value: -1, to: this.start), let before = calendar.dateInterval(of: unit, for: last) else { return nil }
        // Days apart by their dates, read in UTC: a day that starts at 01:00, after a midnight clock change, still counts whole.
        var utc = calendar
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = { (moment: Date) in utc.date(from: calendar.dateComponents([.era, .year, .month, .day], from: moment)) ?? moment }
        let days = { (from: Date, to: Date) in utc.dateComponents([.day], from: date(from), to: date(to)).day ?? 0 }
        let length = days(this.start, this.end), previous = days(before.start, before.end)
        let elapsed = back == 0 ? min(length, days(this.start, now) + 1) : length
        return Period(start: this.start, length: length, elapsed: elapsed, previousStart: before.start, previousLength: back == 0 ? min(elapsed, previous) : previous)
    }

    /// Days with counted keys wholly with or wholly without the personal model, suggestions or none: how many, and their sum.
    /// With `adapter`, only the with-model days that ran that one alone.
    public func sum(personal: Bool, adapter: String? = nil) -> (count: Int, sum: Day) {
        let picked = days.values.filter { $0.typed > 0 && $0.withModel == personal && $0.withoutModel != personal && (adapter == nil || $0.adapters == [adapter!]) }
        return (picked.count, picked.reduce(Day(), +))
    }
    /// Each personal model that ran a whole day alone, in name order (train.sh dates them).
    public var adapters: [String] { Set(days.values.compactMap { $0.adapters.count == 1 ? $0.adapters[0] : nil }).sorted() }
    public var since: String? { days.keys.min() }
}
