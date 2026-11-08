import Foundation
import Testing
@testable import ItdaCore

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
}
