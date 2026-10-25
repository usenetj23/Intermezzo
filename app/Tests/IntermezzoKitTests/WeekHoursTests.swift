import XCTest
@testable import IntermezzoKit

final class WeekHoursTests: XCTestCase {
    private let base = WeekHours.Window(start: 8 * 60, end: 16 * 60)

    func testDayWithoutOverrideUsesTheDefaultWindow() {
        XCTAssertEqual(WeekHours().window(forDay: 2, default: base), base)
    }

    func testOverrideReplacesTheDefaultOnlyForThatDay() {
        let friday = WeekHours.Window(start: 8 * 60, end: 12 * 60)
        let w = WeekHours().setting(friday, forDay: 4)
        XCTAssertEqual(w.window(forDay: 4, default: base), friday)
        XCTAssertEqual(w.window(forDay: 3, default: base), base)
    }

    func testContainsIsStartInclusiveEndExclusive() {
        XCTAssertTrue(base.contains(minute: 8 * 60))
        XCTAssertTrue(base.contains(minute: 16 * 60 - 1))
        XCTAssertFalse(base.contains(minute: 16 * 60))
        XCTAssertFalse(base.contains(minute: 7 * 60 + 59))
    }

    func testRemovingAnOverrideRestoresTheDefault() {
        let w = WeekHours().setting(.init(start: 0, end: 60), forDay: 1).clearing(day: 1)
        XCTAssertEqual(w.window(forDay: 1, default: base), base)
    }

    func testRoundTripAndGarbage() {
        let w = WeekHours().setting(.init(start: 9 * 60, end: 13 * 60), forDay: 5)
        XCTAssertEqual(WeekHours.decode(w.encoded()), w)
        XCTAssertEqual(WeekHours.decode(Data("junk".utf8)), WeekHours())
        XCTAssertEqual(WeekHours.decode(nil), WeekHours())
    }

    func testNonsenseWindowNeverContainsAnything() {
        XCTAssertFalse(WeekHours.Window(start: 600, end: 600).contains(minute: 600))
        XCTAssertFalse(WeekHours.Window(start: 700, end: 600).contains(minute: 650))
    }
}
