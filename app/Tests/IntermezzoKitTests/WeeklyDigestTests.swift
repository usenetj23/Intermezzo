import XCTest
@testable import IntermezzoKit

final class WeeklyDigestTests: XCTestCase {
    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday, midday.
    private var now: Date { at(28, 12, 0) }

    private func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sample(_ day: Int, _ hour: Int, _ minute: Int = 0, skipped: Bool = false) -> BreakSample {
        let start = at(day, hour, minute)
        return BreakSample(kind: "short", startedAt: start, endedAt: skipped ? nil : start.addingTimeInterval(300), skipped: skipped)
    }

    private func build(_ samples: [BreakSample]) -> WeeklyDigest { WeeklyDigest.build(samples: samples, now: now, calendar: utc) }

    func testCountsThisAndPreviousWeek() {
        let digest = build([sample(27, 10), sample(28, 9), sample(28, 10), sample(28, 11, skipped: true),
                            sample(20, 10), sample(20, 11), sample(21, 12, skipped: true), sample(21, 13, skipped: true)])
        XCTAssertEqual(digest.thisWeek.completed, 3)
        XCTAssertEqual(digest.thisWeek.skipped, 1)
        XCTAssertEqual(digest.thisWeek.completionPercent, 75)
        XCTAssertEqual(digest.previousWeek.completed, 2)
        XCTAssertEqual(digest.previousWeek.skipped, 2)
        XCTAssertEqual(digest.previousWeek.completionPercent, 50)
        XCTAssertFalse(digest.isEmpty)
    }

    func testEmptyHistory() {
        let digest = build([])
        XCTAssertTrue(digest.isEmpty)
        XCTAssertNil(digest.thisWeek.completionPercent)
        XCTAssertNil(digest.previousWeek.completionPercent)
        XCTAssertFalse(digest.text().isEmpty)
        XCTAssertFalse(digest.text().contains("NaN"))
    }

    func testOnlyCurrentWeek() {
        let digest = build([sample(27, 10), sample(28, 9, skipped: true)])
        XCTAssertNil(digest.previousWeek.completionPercent)
        XCTAssertTrue(digest.text().lowercased().contains("previous 7 days: no breaks"))
    }

    func testWeekdayAndPartOfDayBuckets() {
        let digest = build([sample(27, 10), sample(28, 18, 30, skipped: true), sample(28, 3, skipped: true),
                            sample(27, 7, skipped: true), sample(27, 13, skipped: true)])
        XCTAssertEqual(digest.completedByWeekday, [0, 1, 0, 0, 0, 0, 0])
        XCTAssertEqual(digest.skippedByPartOfDay["evening"], 1)
        XCTAssertEqual(digest.skippedByPartOfDay["other"], 1)
        XCTAssertEqual(digest.skippedByPartOfDay["morning"], 1)
        XCTAssertEqual(digest.skippedByPartOfDay["afternoon"], 1)
    }

    func testSamplesAcrossMidnightAndDayBoundary() {
        let digest = build([sample(22, 0, 0), sample(21, 23, 59), sample(15, 0, 0), sample(14, 23, 59)])
        XCTAssertEqual(digest.thisWeek.completed, 1)
        XCTAssertEqual(digest.previousWeek.completed, 2)
    }

    func testPromptHasOnlyAggregates() {
        let digest = build([sample(27, 10), sample(28, 9, skipped: true)])
        let request = WeeklyDigest.prompt(digest: digest, language: "pl")
        XCTAssertEqual(request.user, digest.text())
        XCTAssertFalse(request.user.contains("2026"))
        XCTAssertFalse(request.user.contains("short"))
        XCTAssertTrue(request.system.contains("150"))
        XCTAssertTrue(request.system.lowercased().contains("medical"))
        XCTAssertTrue(request.system.contains("Polish"))
        XCTAssertTrue(WeeklyDigest.prompt(digest: digest, language: "en").system.contains("English"))
    }
}
