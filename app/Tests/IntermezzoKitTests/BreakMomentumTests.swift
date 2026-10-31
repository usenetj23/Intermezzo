import XCTest
@testable import IntermezzoKit

final class BreakMomentumTests: XCTestCase {
    private func o(_ skipped: Bool, _ weight: Double = 1) -> BreakMomentum.Outcome {
        .init(skipped: skipped, weight: weight)
    }

    func testFewerThanTwoBreaksGiveNoSeries() {
        XCTAssertTrue(BreakMomentum.levels([]).isEmpty)
        XCTAssertTrue(BreakMomentum.levels([o(false)]).isEmpty)
    }

    func testCompletedBreaksClimbAndSkippedOnesDrop() {
        let l = BreakMomentum.levels([o(false), o(false), o(true), o(false)])
        XCTAssertGreaterThan(l[1], l[0])
        XCTAssertLessThan(l[2], l[1])
        XCTAssertGreaterThan(l[3], l[2])
    }

    func testThreeShortAndOneLongSkippedEndInTheRedZone() {
        let l = BreakMomentum.levels([o(true), o(true), o(true), o(true, 3)])
        XCTAssertEqual(l.last, 0)
    }

    func testRunOfSkipsAfterGoodStreakStillFalls() {
        let good = Array(repeating: o(false), count: 6)
        let l = BreakMomentum.levels(good + [o(true), o(true), o(true), o(true, 3)])
        XCTAssertEqual(l.last, 0)
        XCTAssertEqual(l[5], 1)
    }

    func testAllCompletedStaysInRangeAndRises() {
        let l = BreakMomentum.levels(Array(repeating: o(false), count: 8))
        XCTAssertEqual(l, l.sorted())
        XCTAssertTrue(l.allSatisfy { (0...1).contains($0) })
    }

    func testLongBreakWeightScalesWithItsLengthAndIsClamped() {
        XCTAssertEqual(BreakMomentum.weight(seconds: 300, shortSeconds: 300), 1)
        XCTAssertEqual(BreakMomentum.weight(seconds: 900, shortSeconds: 300), 3)
        XCTAssertEqual(BreakMomentum.weight(seconds: 3000, shortSeconds: 300), 3)
        XCTAssertEqual(BreakMomentum.weight(seconds: 60, shortSeconds: 300), 1)
        XCTAssertEqual(BreakMomentum.weight(seconds: 60, shortSeconds: 0), 1)
    }

    func testPostponingLowersTheLineOnlyALittle() {
        let base = [o(false), o(false)]
        let skipped = BreakMomentum.levels(base + [o(true)]).last!
        let postponed1 = BreakMomentum.levels(base + [.init(skipped: true, lossShare: BreakMomentum.postponeShare(minutes: 1))]).last!
        let postponed5 = BreakMomentum.levels(base + [.init(skipped: true, lossShare: BreakMomentum.postponeShare(minutes: 5))]).last!
        let completed = BreakMomentum.levels(base + [o(false)]).last!
        XCTAssertLessThan(postponed1, BreakMomentum.levels(base).last!)   // it does lower the line
        XCTAssertGreaterThan(postponed1, skipped)
        XCTAssertGreaterThan(postponed5, skipped)
        XCTAssertGreaterThan(postponed1, postponed5)   // +5 drops more than +1
        XCTAssertLessThan(postponed5, completed)
    }

    func testPostponeShareIsCapped() {
        XCTAssertEqual(BreakMomentum.postponeShare(minutes: 1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(BreakMomentum.postponeShare(minutes: 60), 0.5, accuracy: 1e-9)
    }
}
