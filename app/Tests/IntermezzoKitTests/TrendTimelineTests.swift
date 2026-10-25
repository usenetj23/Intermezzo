import XCTest
@testable import IntermezzoKit

final class TrendTimelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    func testSpacingFollowsRealTime() {
        // 10 min, then 30 min: the second gap is three times wider.
        let l = TrendTimeline.layout(times: [at(0), at(10), at(40)], width: 400, minSpacing: 0)
        XCTAssertEqual(l.x.first!, 0, accuracy: 1e-9)
        XCTAssertEqual(l.x.last!, 400, accuracy: 1e-9)
        XCTAssertEqual((l.x[2] - l.x[1]) / (l.x[1] - l.x[0]), 3, accuracy: 1e-6)
        XCTAssertTrue(l.collapsedGaps.isEmpty)
    }

    func testLongGapIsCollapsedToAFixedWidth() {
        // 20 min, a night (14 h), 20 min.
        let times = [at(0), at(20), at(20 + 14 * 60), at(40 + 14 * 60)]
        let l = TrendTimeline.layout(times: times, width: 500, minSpacing: 0, collapsedWidth: 60)
        XCTAssertEqual(l.collapsedGaps.count, 1)
        XCTAssertEqual(l.collapsedGaps[0].afterIndex, 1)
        XCTAssertEqual(l.collapsedGaps[0].seconds, 14 * 3600, accuracy: 1e-6)
        XCTAssertEqual(l.x[2] - l.x[1], 60, accuracy: 1e-6)
        // The two 20-minute gaps share the rest equally.
        XCTAssertEqual(l.x[1] - l.x[0], l.x[3] - l.x[2], accuracy: 1e-6)
        XCTAssertEqual(l.x[3], 500, accuracy: 1e-6)
    }

    func testMinimumSpacingKeepsIconsApart() {
        // Two breaks a minute apart next to a 2-hour stretch.
        let times = [at(0), at(1), at(110)]
        let l = TrendTimeline.layout(times: times, width: 300, minSpacing: 24)
        XCTAssertGreaterThanOrEqual(l.x[1] - l.x[0], 24 - 1e-6)
        XCTAssertEqual(l.x[2], 300, accuracy: 1e-6)
    }

    func testSimultaneousOrUnsortedTimesStillSpreadEvenly() {
        let l = TrendTimeline.layout(times: [at(5), at(5), at(5)], width: 200, minSpacing: 0)
        XCTAssertEqual(l.x, [0, 100, 200])
    }

    func testFewerThanTwoPoints() {
        XCTAssertEqual(TrendTimeline.layout(times: [at(0)], width: 200).x, [0])
        XCTAssertTrue(TrendTimeline.layout(times: [], width: 200).x.isEmpty)
    }

    func testGapLabels() {
        XCTAssertEqual(TrendTimeline.gapLabel(seconds: 3 * 3600 + 100), "3 h")
        XCTAssertEqual(TrendTimeline.gapLabel(seconds: 30 * 3600), "30 h")
        XCTAssertEqual(TrendTimeline.gapLabel(seconds: 3 * 86400 + 5), "3 d")
    }

    func testOutcomeFallsBackToTheSkippedFlagForOldRecords() {
        XCTAssertEqual(BreakOutcome(raw: nil, wasSkipped: false), .completed)
        XCTAssertEqual(BreakOutcome(raw: nil, wasSkipped: true), .skipped)
        XCTAssertEqual(BreakOutcome(raw: "postponed", wasSkipped: true), .postponed)
        XCTAssertEqual(BreakOutcome(raw: "bogus", wasSkipped: true), .skipped)
    }

    func testOnlyCompletedRaisesMomentum() {
        XCTAssertFalse(BreakOutcome.completed.lowersMomentum)
        for o in [BreakOutcome.skipped, .postponed, .ruleSkipped, .skippedAhead] {
            XCTAssertTrue(o.lowersMomentum, "\(o)")
        }
    }
}
