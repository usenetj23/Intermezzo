import XCTest
@testable import IntermezzoKit

final class NaturalBreakTests: XCTestCase {
    func testAbsenceBelowTheMinimumIsNotLogged() {
        XCTAssertFalse(NaturalBreak.shouldLog(awaySeconds: 9 * 60, minMinutes: 10))
        XCTAssertTrue(NaturalBreak.shouldLog(awaySeconds: 10 * 60, minMinutes: 10))
    }

    func testVeryLongAbsenceIsTreatedAsTheDayEndingNotABreak() {
        XCTAssertTrue(NaturalBreak.shouldLog(awaySeconds: 5 * 3600, minMinutes: 10))
        XCTAssertFalse(NaturalBreak.shouldLog(awaySeconds: 9 * 3600, minMinutes: 10))
    }

    func testMinimumIsClampedToASaneRange() {
        XCTAssertFalse(NaturalBreak.shouldLog(awaySeconds: 3 * 60, minMinutes: 0))      // never below 5 min
        XCTAssertTrue(NaturalBreak.shouldLog(awaySeconds: 6 * 60, minMinutes: -3))
    }

    func testCategoriesFollowTheLength() {
        XCTAssertEqual(NaturalBreak.category(minutes: 12), .pause)
        XCTAssertEqual(NaturalBreak.category(minutes: 40), .meal)
        XCTAssertEqual(NaturalBreak.category(minutes: 120), .long)
        XCTAssertFalse(NaturalBreak.Category.meal.title.isEmpty)
    }

    func testRawMarkerIsStableBecauseItIsStored() {
        XCTAssertEqual(NaturalBreak.rawKind, "natural")
    }
}
