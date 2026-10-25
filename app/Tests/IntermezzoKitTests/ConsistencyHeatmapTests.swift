import XCTest
@testable import IntermezzoKit

final class ConsistencyHeatmapTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        c.firstWeekday = 2   // Monday
        return c
    }()
    // 2026-10-21 is a Wednesday.
    private func date(_ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private let now = Date(timeIntervalSince1970: 0)

    private func grid(_ records: [ConsistencyHeatmap.Entry], weeks: Int = 12) -> [[ConsistencyHeatmap.Cell]] {
        ConsistencyHeatmap.weeks(records, count: weeks, now: date(10, 21), calendar: cal)
    }

    func testGridHasTheRequestedWeeksOfSevenDaysStartingOnMonday() {
        let g = grid([])
        XCTAssertEqual(g.count, 12)
        XCTAssertTrue(g.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cal.component(.weekday, from: g[0][0].day), 2)
    }

    func testLastColumnIsTheCurrentWeekAndFutureDaysAreMarked() {
        let g = grid([])
        let last = g[11]
        XCTAssertTrue(last[0].day <= date(10, 21))
        XCTAssertFalse(last[2].isFuture)      // Wednesday = today
        XCTAssertTrue(last[3].isFuture)       // Thursday
    }

    func testCompletedBreaksRaiseTheLevelAndSkippedOnesDoNot() {
        let entries = (0..<4).map { _ in ConsistencyHeatmap.Entry(start: date(10, 20), skipped: false) }
            + [ConsistencyHeatmap.Entry(start: date(10, 21), skipped: true)]
        let g = grid(entries)
        XCTAssertEqual(g[11][1].completed, 4)
        XCTAssertGreaterThan(g[11][1].level, 1)
        XCTAssertEqual(g[11][2].completed, 0)
        XCTAssertEqual(g[11][2].skipped, 1)
        XCTAssertEqual(g[11][2].level, 0)
    }

    func testLevelsAreMonotonicAndCapped() {
        XCTAssertEqual(ConsistencyHeatmap.level(forCompleted: 0), 0)
        XCTAssertEqual(ConsistencyHeatmap.level(forCompleted: 1), 1)
        XCTAssertEqual(ConsistencyHeatmap.level(forCompleted: 20), 4)
        var prev = 0
        for n in 0...20 {
            let l = ConsistencyHeatmap.level(forCompleted: n)
            XCTAssertGreaterThanOrEqual(l, prev)
            prev = l
        }
    }

    func testRecordsOlderThanTheWindowAreIgnored() {
        let old = ConsistencyHeatmap.Entry(start: date(1, 5), skipped: false)
        XCTAssertTrue(grid([old]).flatMap { $0 }.allSatisfy { $0.completed == 0 })
    }

    func testActiveDaysCountsDaysWithAtLeastOneCompletedBreak() {
        let entries = [ConsistencyHeatmap.Entry(start: date(10, 19), skipped: false),
                       ConsistencyHeatmap.Entry(start: date(10, 19, 15), skipped: false),
                       ConsistencyHeatmap.Entry(start: date(10, 20), skipped: false)]
        XCTAssertEqual(ConsistencyHeatmap.activeDays(grid(entries)), 2)
    }
}
