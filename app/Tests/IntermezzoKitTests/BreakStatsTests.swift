import XCTest
@testable import IntermezzoKit

final class BreakStatsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = day; c.hour = hour
        return cal.date(from: c)!
    }

    private func sample(_ day: Int, hour: Int = 10, skipped: Bool = false, kind: String = "short") -> BreakSample {
        BreakSample(kind: kind, startedAt: date(day, hour),
                    endedAt: date(day, hour).addingTimeInterval(300), skipped: skipped)
    }

    func testLastDaysIncludesEmptyDaysOldestFirst() {
        let now = date(23, 15)
        let days = BreakStats.lastDays(4, samples: [sample(23), sample(23, hour: 12, skipped: true), sample(21)],
                                       now: now, calendar: cal)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(days.map(\.completed), [0, 1, 0, 1])      // 20, 21, 22, 23
        XCTAssertEqual(days.map(\.skipped), [0, 0, 0, 1])
        XCTAssertEqual(cal.component(.day, from: days[0].day), 20)
    }

    func testSamplesOutsideWindowAreIgnored() {
        let days = BreakStats.lastDays(2, samples: [sample(10)], now: date(23, 12), calendar: cal)
        XCTAssertEqual(days.map(\.completed), [0, 0])
    }

    func testCompletionRate() {
        let days = BreakStats.lastDays(1, samples: [sample(23), sample(23, hour: 11), sample(23, hour: 12, skipped: true)],
                                       now: date(23, 18), calendar: cal)
        XCTAssertEqual(BreakStats.completionRate(days), 2.0 / 3.0, accuracy: 0.001)
    }

    func testCompletionRateWithNoBreaksIsZero() {
        XCTAssertEqual(BreakStats.completionRate([]), 0)
    }

    func testCSVHasHeaderAndRows() {
        let csv = BreakStats.csv([sample(23)], calendar: cal)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "kind,started_at,ended_at,skipped,duration_seconds")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix("short,2026-10-23T10:00:00Z,2026-10-23T10:05:00Z,false,300"))
    }

    func testCSVOpenBreakHasEmptyEndAndDuration() {
        let open = BreakSample(kind: "long", startedAt: date(23, 9), endedAt: nil, skipped: false)
        let line = BreakStats.csv([open], calendar: cal).split(separator: "\n")[1]
        XCTAssertEqual(line, "long,2026-10-23T09:00:00Z,,false,")
    }
}
