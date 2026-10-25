import XCTest
@testable import IntermezzoKit

final class ReportRangeTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testDayRangeIsOneDay() {
        let r = ReportRange.day(date(20))
        XCTAssertEqual(r.days(calendar: cal), [date(20, 0)])
        XCTAssertEqual(r.interval(calendar: cal), DateInterval(start: date(20, 0), end: date(21, 0)))
    }

    func testWeekHasSevenDaysEndingOnDay() {
        let days = ReportRange.week(endingOn: date(20)).days(calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, date(14, 0))
        XCTAssertEqual(days.last, date(20, 0))
        XCTAssertEqual(ReportRange.week(endingOn: date(20)).interval(calendar: cal),
                       DateInterval(start: date(14, 0), end: date(21, 0)))
    }

    func testMonthCoversWholeMonth() {
        let r = ReportRange.month(containing: date(20))
        let days = r.days(calendar: cal)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.first, date(1, 0))
        XCTAssertEqual(days.last, date(31, 0))
        XCTAssertEqual(r.interval(calendar: cal).end,
                       cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
    }

    func testEmptyRangeStillProducesPages() {
        XCTAssertEqual(ReportLayout.pages(range: .day(date(20)), calendar: cal), 2)
        XCTAssertEqual(ReportLayout.pages(range: .week(endingOn: date(20)), calendar: cal), 8)
        XCTAssertEqual(ReportLayout.pages(range: .month(containing: date(20)), calendar: cal), 32)
    }

    func testPageCountConsistencyCheck() {
        let days = ReportRange.week(endingOn: date(20)).days(calendar: cal)
        XCTAssertTrue(ReportLayout.isConsistent(pageCount: 8, days: days))
        XCTAssertFalse(ReportLayout.isConsistent(pageCount: 7, days: days), "a page went missing")
        XCTAssertFalse(ReportLayout.isConsistent(pageCount: 9, days: days))
        XCTAssertFalse(ReportLayout.isConsistent(pageCount: 0, days: []), "a report always has a summary")
        XCTAssertTrue(ReportLayout.isConsistent(pageCount: 1, days: []))
    }
}
