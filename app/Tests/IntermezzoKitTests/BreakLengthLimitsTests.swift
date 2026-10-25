import XCTest
@testable import IntermezzoKit

final class BreakLengthLimitsTests: XCTestCase {
    func testShortBreakCannotExceedTheLongOne() {
        XCTAssertEqual(BreakLengthLimits.shortRange(longSeconds: 180), 10...180)
        XCTAssertEqual(BreakLengthLimits.shortRange(longSeconds: 900), 10...600)   // still capped by its own maximum
    }

    func testLongBreakCannotBeShorterThanTheShortOne() {
        XCTAssertEqual(BreakLengthLimits.longRange(shortSeconds: 300), 300...3600)
        XCTAssertEqual(BreakLengthLimits.longRange(shortSeconds: 20), 60...3600)   // still above its own minimum
    }

    func testRangesAreAlwaysUsableBySliders() {
        for short in stride(from: 10, through: 600, by: 10) {
            let r = BreakLengthLimits.longRange(shortSeconds: short)
            XCTAssertLessThan(r.lowerBound, r.upperBound)
        }
        for long in stride(from: 60, through: 3600, by: 30) {
            let r = BreakLengthLimits.shortRange(longSeconds: long)
            XCTAssertLessThan(r.lowerBound, r.upperBound)
        }
    }

    func testStoredShortLongerThanLongRaisesTheLongOne() {
        let fixed = BreakLengthLimits.reconciled(short: 600, long: 180)
        XCTAssertEqual(fixed.short, 600)
        XCTAssertEqual(fixed.long, 600)
    }

    func testValidPairIsLeftAlone() {
        let fixed = BreakLengthLimits.reconciled(short: 60, long: 180)
        XCTAssertEqual(fixed.short, 60)
        XCTAssertEqual(fixed.long, 180)
    }

    func testReconciledAlsoClampsToTheAbsoluteLimits() {
        let fixed = BreakLengthLimits.reconciled(short: 5, long: 99999)
        XCTAssertEqual(fixed.short, 10)
        XCTAssertEqual(fixed.long, 3600)
    }
}
