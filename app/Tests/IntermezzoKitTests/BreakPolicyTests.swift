import XCTest
@testable import IntermezzoKit

final class BreakPolicyTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    // MARK: strictness

    func testClassicKeepsTheCurrentBehaviour() {
        let p = Strictness.classic.policy
        XCTAssertNil(p.snoozeLimit)
        XCTAssertTrue(p.showsSkip)
        XCTAssertTrue(p.escapeSkips)
    }

    func testLevelsGetStricter() {
        XCTAssertEqual(Strictness.casual.policy.snoozeLimit, 6)
        XCTAssertEqual(Strictness.balanced.policy.snoozeLimit, 3)
        XCTAssertEqual(Strictness.hardcore.policy.snoozeLimit, 0)
        XCTAssertFalse(Strictness.hardcore.policy.showsSkip)
        XCTAssertFalse(Strictness.hardcore.policy.escapeSkips)
        XCTAssertTrue(Strictness.balanced.policy.showsSkip)
    }

    func testUnknownStoredValueFallsBackToClassic() {
        XCTAssertEqual(Strictness(stored: "nonsense"), .classic)
        XCTAssertEqual(Strictness(stored: nil), .classic)
        XCTAssertEqual(Strictness(stored: "balanced"), .balanced)
    }

    // MARK: snooze budget

    func testBudgetCountsWithinOneDay() {
        var b = SnoozeBudget()
        b = b.consuming(now: date(20), calendar: cal)
        b = b.consuming(now: date(20, 15), calendar: cal)
        XCTAssertEqual(b.used(on: date(20, 18), calendar: cal), 2)
        XCTAssertEqual(b.remaining(limit: 3, on: date(20), calendar: cal), 1)
    }

    func testBudgetResetsOnANewDay() {
        let b = SnoozeBudget().consuming(now: date(20), calendar: cal)
        XCTAssertEqual(b.used(on: date(21), calendar: cal), 0)
        XCTAssertEqual(b.consuming(now: date(21), calendar: cal).used(on: date(21), calendar: cal), 1)
    }

    func testNoLimitMeansUnlimitedAndNeverNegative() {
        let b = SnoozeBudget().consuming(now: date(20), calendar: cal)
        XCTAssertNil(b.remaining(limit: nil, on: date(20), calendar: cal))
        XCTAssertEqual(b.remaining(limit: 0, on: date(20), calendar: cal), 0)
    }

    func testBudgetSurvivesEncodingAndGarbage() {
        let b = SnoozeBudget().consuming(now: date(20), calendar: cal)
        XCTAssertEqual(SnoozeBudget.decode(b.encoded()), b)
        XCTAssertEqual(SnoozeBudget.decode(Data("garbage".utf8)), SnoozeBudget())
        XCTAssertEqual(SnoozeBudget.decode(nil), SnoozeBudget())
    }

    // MARK: motivation style

    func testStreakStyleKeepsTheEncouragingTexts() {
        let s = MotivationStyle.streak
        XCTAssertEqual(s.progressText(breakNumber: 3), "Break #3 today · let's keep that streak going")
        XCTAssertNotNil(s.chartFooter)
        XCTAssertTrue(s.showsTrendChart)
        XCTAssertTrue(s.showsStreakCounters)
    }

    func testCalmStyleHasNoStreakLanguageOrScoring() {
        let s = MotivationStyle.calm
        XCTAssertEqual(s.progressText(breakNumber: 3), "Break #3 today")
        XCTAssertNil(s.chartFooter)
        XCTAssertFalse(s.showsTrendChart)
        XCTAssertFalse(s.showsStreakCounters)
    }

    func testStoredMotivationFallsBackToStreak() {
        XCTAssertEqual(MotivationStyle(stored: nil), .streak)
        XCTAssertEqual(MotivationStyle(stored: "calm"), .calm)
        XCTAssertEqual(MotivationStyle(stored: "x"), .streak)
    }
}
