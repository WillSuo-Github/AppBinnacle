import Foundation
import Testing

struct DayTests {
    @Test func parsesEveryReportFormat() {
        let expected = Day(year: 2026, month: 10, day: 12)
        #expect(Day(iso: "2026-10-12") == expected)
        #expect(Day(compact: "20261012") == expected)
        #expect(Day(slashed: "10/12/2026") == expected)
        #expect(Day(iso: "2026-02-30") == nil)
        #expect(Day(iso: "2026-1-5") == nil)
        #expect(Day(compact: "2026101") == nil)
    }

    @Test func arithmeticCrossesMonthAndYearBoundaries() {
        #expect(Fixtures.day("2026-12-31").adding(days: 1) == Fixtures.day("2027-01-01"))
        #expect(Fixtures.day("2028-03-01").adding(days: -1) == Fixtures.day("2028-02-29"))
        #expect(Fixtures.day("2026-10-01").distance(to: Fixtures.day("2026-10-13")) == 12)
    }

    @Test func rangesKnowTheirPreviousPeriod() {
        let range = DayRange(ending: Fixtures.day("2026-10-12"), length: 7)
        #expect(range.start == Fixtures.day("2026-10-06"))
        #expect(range.length == 7)
        #expect(range.days.count == 7)
        #expect(range.previous == DayRange(start: Fixtures.day("2026-09-29"), end: Fixtures.day("2026-10-05")))
        #expect(range.contains(Fixtures.day("2026-10-06")))
        #expect(!range.contains(Fixtures.day("2026-10-13")))
    }

    @Test func yesterdayUsesPacificTime() {
        // 2026-10-13 03:00 UTC is still 2026-10-12 in California.
        let date = ISO8601.parse("2026-10-13T03:00:00Z")!
        #expect(Day.yesterday(now: date) == Fixtures.day("2026-10-11"))
    }

    @Test func encodesAsISOString() throws {
        let json = try JSONCoding.string(Fixtures.day("2026-10-12"), pretty: false)
        #expect(json == "\"2026-10-12\"")
        #expect(try JSONDecoder().decode(Day.self, from: Data(json.utf8)) == Fixtures.day("2026-10-12"))
    }
}
