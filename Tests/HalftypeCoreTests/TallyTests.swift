import Foundation
import Testing
@testable import HalftypeCore

@Test func tallyCountsPerDayAndKeepsEmptyDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23, minute: 59)))
    let wednesday = try #require(calendar.date(byAdding: .day, value: 2, to: monday))
    var tally = Tally()
    tally.shown(on: monday, calendar); tally.shown(on: monday, calendar)
    tally.took(7, first: true, on: monday, calendar); tally.took(3, first: false, on: monday, calendar)
    tally.took(3, first: true, on: wednesday, calendar)
    #expect(Tally.key(monday, calendar) == "2026-11-09")
    let week = tally.last(3, to: wednesday, calendar)
    #expect(week.map(\.day) == [Tally.Day(shown: 2, taken: 1, tabs: 2, characters: 10), Tally.Day(), Tally.Day(taken: 1, tabs: 1, characters: 3)])
    #expect(tally.total == Tally.Day(shown: 2, taken: 2, tabs: 3, characters: 13))
    let back = try JSONDecoder().decode(Tally.self, from: JSONEncoder().encode(tally))
    #expect(back == tally)
}

@Test func tallyComparesDaysWithAndWithoutThePersonalModelAndReadsOldFiles() throws {
    let old = #"{"days":{"2026-11-07":{"shown":5,"taken":1,"tabs":2,"characters":9}}}"#
    var tally = try JSONDecoder().decode(Tally.self, from: Data(old.utf8))
    #expect(tally.days["2026-11-07"] == Tally.Day(shown: 5, taken: 1, tabs: 2, characters: 9))
    let calendar = Calendar(identifier: .gregorian)
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)))
    let next = try #require(calendar.date(byAdding: .day, value: 1, to: day))
    tally.took(4, keys: 10, first: true, on: day, calendar); tally.typed(30, on: day, calendar); tally.mark(personal: true, on: day, calendar)
    tally.took(5, keys: 5, first: true, on: next, calendar); tally.typed(45, on: next, calendar); tally.mark(personal: false, on: next, calendar)
    let third = try #require(calendar.date(byAdding: .day, value: 1, to: next))  // No suggestions at all still counts, as 0%.
    tally.typed(50, on: third, calendar); tally.mark(personal: false, on: third, calendar)
    #expect(tally.sum(personal: true).count == 1 && tally.sum(personal: true).sum.byTab == 0.25)
    #expect(tally.sum(personal: false).count == 2 && tally.sum(personal: false).sum.byTab == 0.05)  // The old day has no keys, so it's left out.
    tally.mark(personal: true, on: next, calendar)  // A switch mid-day mixes it, and it drops out.
    #expect(tally.sum(personal: false).count == 1 && tally.sum(personal: true).count == 1)
    tally.mark(personal: nil, on: day, calendar)  // Another model, the same.
    #expect(tally.sum(personal: true).count == 0)
}

@Test func eachPersonalModelCountsOnlyTheDaysItRanAlone() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 12))! }
    var tally = Tally()
    for (d, names) in [(10, ["mac"]), (11, ["cloud"]), (12, ["mac", "cloud", "mac"])] {
        tally.typed(10, on: day(d), calendar)
        for n in names { tally.mark(personal: true, adapter: n, on: day(d), calendar) }
    }
    #expect(tally.days["2026-11-12"]?.adapters == ["mac", "cloud"])
    #expect(tally.adapters == ["cloud", "mac"])
    #expect(tally.sum(personal: true).count == 3 && tally.sum(personal: true, adapter: "mac").count == 1)
    let old = try JSONDecoder().decode(Tally.Day.self, from: Data(#"{"shown":1,"withModel":true}"#.utf8))  // before adapters were named
    #expect(old.adapters.isEmpty && old.withModel)
}

@Test func periodsPageBackAndCompareTheSameDaysSoFar() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 2
    let date = { (m: Int, d: Int) in calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23, minute: 30)))
    // This week so far is one day, set against last Monday alone.
    #expect(Tally.period(.weekOfYear, back: 0, now: monday, calendar) == .init(start: date(11, 9), length: 7, elapsed: 1, previousStart: date(11, 2), previousLength: 1))
    #expect(Tally.period(.weekOfYear, back: 1, now: monday, calendar) == .init(start: date(11, 2), length: 7, elapsed: 7, previousStart: date(10, 26), previousLength: 7))
    #expect(Tally.period(.month, back: 0, now: monday, calendar) == .init(start: date(11, 1), length: 30, elapsed: 9, previousStart: date(10, 1), previousLength: 9))
    // March 31 against all of a shorter February, and a past February against all of January.
    let march = try #require(calendar.date(from: DateComponents(year: 2027, month: 3, day: 31, hour: 9)))
    #expect(Tally.period(.month, back: 0, now: march, calendar) == .init(start: calendar.date(from: DateComponents(year: 2027, month: 3, day: 1))!, length: 31, elapsed: 31,
                                                                       previousStart: calendar.date(from: DateComponents(year: 2027, month: 2, day: 1))!, previousLength: 28))
    #expect(Tally.period(.month, back: 1, now: march, calendar)?.previousLength == 31)
    // Santiago's clocks skip midnight on 2026-09-06, so that day starts at 01:00 and is 23 hours long, but still a day.
    var santiago = Calendar(identifier: .gregorian)
    santiago.timeZone = TimeZone(identifier: "America/Santiago")!
    let tuesday = try #require(santiago.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12)))
    let week = try #require(Tally.period(.weekOfYear, back: 0, now: tuesday, santiago))
    #expect(week.length == 7 && week.elapsed == 3 && Tally.key(week.start, santiago) == "2026-09-06")
    var tally = Tally()
    tally.took(3, first: true, on: monday, calendar); tally.took(4, first: true, on: date(11, 2), calendar)
    #expect(tally.sum(7, to: monday, calendar).tabs == 1 && tally.sum(8, to: monday, calendar).characters == 7)
}

@Test func tallyDaySaysTimeWordsAndOneKeyInN() {
    let day = Tally.Day(tabs: 936, characters: 4_143, typed: 27_095, saved: 4_154)
    #expect(day.words == 828 && abs(day.minutesSaved - 20.77) < 0.01 && day.oneIn == 8)
    #expect(Tally.Day(characters: 9).oneIn == nil && Tally.Day(typed: 50).oneIn == nil)  // Before keys were counted, and nothing saved.
}
