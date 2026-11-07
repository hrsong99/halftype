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
