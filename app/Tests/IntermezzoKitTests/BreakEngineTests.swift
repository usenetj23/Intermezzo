import XCTest
@testable import IntermezzoKit

final class BreakEngineTests: XCTestCase {

    private func config() -> BreakConfig {
        var c = BreakConfig()
        c.cycleMinutes = 10
        c.shortBreakSeconds = 60
        c.longBreakSeconds = 120
        c.longBreakEvery = 3
        return c
    }

    func testStartBeginsWorking() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.start(now: t0, config: config())
        XCTAssertNotNil(engine.timeUntilBreak(now: t0))
        XCTAssertTrue(engine.isPaused == false)
    }

    func testResetCycleAfterLongAbsenceRestartsFullTimer() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 1_500_000)
        let c = config()
        engine.start(now: t0, config: c)
        // Pause with 1 minute left on the clock, then simulate a long absence.
        engine.pause(reason: .userAway, now: t0.addingTimeInterval(9 * 60))
        engine.resetCycle(now: t0.addingTimeInterval(50 * 60), config: c)
        _ = engine.resume(reason: .userAway, now: t0.addingTimeInterval(50 * 60))
        let left = engine.timeUntilBreak(now: t0.addingTimeInterval(50 * 60)) ?? 0
        XCTAssertEqual(left, 10 * 60, accuracy: 1)
        // And the break really fires a full cycle later, not immediately.
        let events = engine.tick(now: t0.addingTimeInterval(50 * 60 + 30), config: c)
        XCTAssertTrue(events.isEmpty)
    }

    func testBreakFiresAfterCycle() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let c = config()
        engine.start(now: t0, config: c)

        var events = engine.tick(now: t0.addingTimeInterval(9 * 60), config: c)
        XCTAssertTrue(events.isEmpty)

        events = engine.tick(now: t0.addingTimeInterval(10 * 60 + 1), config: c)
        XCTAssertEqual(events, [.breakStarted(.short)])
        XCTAssertEqual(engine.activeBreakKind, .short)

        events = engine.tick(now: t0.addingTimeInterval(10 * 60 + 61), config: c)
        XCTAssertEqual(events, [.breakCompleted])
        XCTAssertEqual(engine.completedShortBreaks, 1)
        XCTAssertNotNil(engine.timeUntilBreak(now: t0))
    }

    func testLongBreakAfterNShortOnes() {
        var engine = BreakEngine()
        let c = config() // long every 3
        var t = Date(timeIntervalSince1970: 3_000_000)
        engine.start(now: t, config: c)

        var kinds: [BreakKind] = []
        for _ in 0..<7 {
            // Advance until the break actually fires (skip any auto-complete tick).
            var fired: BreakKind?
            for _ in 0..<50 {
                t = t.addingTimeInterval(60)
                _ = engine.tick(now: t, config: c)
                if let k = engine.activeBreakKind { fired = k; break }
            }
            let kind = try? XCTUnwrap(fired)
            kinds.append(kind ?? .short)
            t = t.addingTimeInterval(c.breakDuration(for: kinds.last!) + 1)
            _ = engine.tick(now: t, config: c)
        }
        XCTAssertEqual(kinds, [.short, .short, .long, .short, .short, .long, .short])
    }

    func testSkipResetsCycleAndCounts() {
        var engine = BreakEngine()
        let c = config()
        let t0 = Date(timeIntervalSince1970: 4_000_000)
        engine.start(now: t0, config: c)
        _ = engine.tick(now: t0.addingTimeInterval(10 * 60 + 1), config: c)
        let ev = engine.skipBreak(now: t0.addingTimeInterval(10 * 60 + 5), config: c)
        XCTAssertEqual(ev, .breakSkipped(.short))
        XCTAssertEqual(engine.completedShortBreaks, 1)
        XCTAssertNil(engine.activeBreakKind)
    }

    func testPostponeBreakClosesPopupAndReschedules() {
        var engine = BreakEngine()
        let c = config()
        let t0 = Date(timeIntervalSince1970: 4_500_000)
        engine.start(now: t0, config: c)
        _ = engine.tick(now: t0.addingTimeInterval(10 * 60 + 1), config: c)
        XCTAssertNotNil(engine.activeBreakKind, "break must be live first")
        let before = engine.completedShortBreaks
        let ev = engine.postponeBreak(minutes: 5, now: t0.addingTimeInterval(10 * 60 + 5))
        XCTAssertEqual(ev, .breakPostponed(.short))
        XCTAssertNil(engine.activeBreakKind, "popup closes immediately")
        let left = engine.timeUntilBreak(now: t0.addingTimeInterval(10 * 60 + 5))
        XCTAssertEqual(left ?? -1, 5 * 60, accuracy: 1, "next popup exactly +5 min")
        XCTAssertEqual(engine.completedShortBreaks, before, "postpone must NOT advance cycle")
        // and the postponed break really fires after the full 5 minutes pass
        let events = engine.tick(now: t0.addingTimeInterval(10 * 60 + 5 + 5 * 60 + 1), config: c)
        XCTAssertTrue(events.contains(.breakStarted(.short)),
                      "the same break must reappear after 5 minutes")
    }

    func testSnoozePushesBreakBack() {
        var engine = BreakEngine()
        let c = config()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        engine.start(now: t0, config: c)
        engine.snooze(minutes: 5, now: t0.addingTimeInterval(9 * 60))
        let events = engine.tick(now: t0.addingTimeInterval(10 * 60 + 1), config: c)
        XCTAssertTrue(events.isEmpty, "break should have been pushed 5 minutes back")
        let events2 = engine.tick(now: t0.addingTimeInterval(14 * 60 + 1), config: c)
        XCTAssertTrue(events2.isEmpty) // snooze pushed it to +15 min
        let fired = engine.tick(now: t0.addingTimeInterval(15 * 60 + 1), config: c)
        XCTAssertEqual(fired, [.breakStarted(.short)])
    }

    func testTakeBreakNow() {
        var engine = BreakEngine()
        let c = config()
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        engine.start(now: t0, config: c)
        let ev = engine.takeBreakNow(kind: .long, now: t0.addingTimeInterval(60), config: c)
        XCTAssertEqual(ev, .breakStarted(.long))
        XCTAssertEqual(engine.activeBreakKind, .long)
    }

    func testPauseFreezesAndResumeContinues() {
        var engine = BreakEngine()
        let c = config()
        let t0 = Date(timeIntervalSince1970: 7_000_000)
        engine.start(now: t0, config: c)
        engine.pause(reason: .userAway, now: t0)
        XCTAssertTrue(engine.isPaused)
        let events = engine.tick(now: t0.addingTimeInterval(60 * 60), config: c)
        XCTAssertTrue(events.isEmpty, "paused engine must not fire breaks")

        _ = engine.resume(reason: .userAway, now: t0.addingTimeInterval(60 * 60))
        // ~10 minutes were left when paused; resuming at +60min means break
        // is due within the remaining window, not immediately.
        let justAfterResume = engine.tick(now: t0.addingTimeInterval(60 * 60 + 1), config: c)
        XCTAssertTrue(justAfterResume.isEmpty)
        let soon = engine.tick(now: t0.addingTimeInterval(60 * 60 + 5 * 60), config: c)
        XCTAssertTrue(soon.isEmpty) // still only ~5 min left of the frozen countdown
        let fired = engine.tick(now: t0.addingTimeInterval(60 * 60 + 10 * 60 + 1), config: c)
        XCTAssertEqual(fired, [.breakStarted(.short)])
    }

    func testStackedPauseReasonsNeedAllCleared() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 8_000_000)
        engine.start(now: t0, config: config())
        engine.pause(reason: .manual, now: t0)
        engine.pause(reason: .userAway, now: t0)
        let r1 = engine.resume(reason: .manual, now: t0)
        XCTAssertNil(r1)
        XCTAssertTrue(engine.isPaused)
        let r2 = engine.resume(reason: .userAway, now: t0)
        XCTAssertEqual(r2, .resumed)
        XCTAssertFalse(engine.isPaused)
    }

    func testExtendBreakPushesEndOut() {
        var engine = BreakEngine()
        let start = Date()
        var config = BreakConfig()
        config.shortBreakSeconds = 60
        engine.takeBreakNow(kind: .short, now: start, config: config)
        // During a live break +1 extends the rest end; it never ends early.
        engine.extendBreak(minutes: 1, now: start.addingTimeInterval(10))
        guard case .onBreak(let kind, let until) = engine.state else {
            return XCTFail("expected live break")
        }
        XCTAssertEqual(kind, .short)
        XCTAssertEqual(until.timeIntervalSince(start), 120, accuracy: 1)
    }

    // MARK: - holdBreak (natural seam)

    func testHoldBreakMovesDeadlineWithoutCountingBreaks() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let c = config()
        engine.start(now: t0, config: c)
        let due = t0.addingTimeInterval(10 * 60)
        let before = engine.completedShortBreaks
        engine.holdBreak(seconds: 2, now: due.addingTimeInterval(-1))   // until <= now + 1
        XCTAssertEqual(engine.state, .working(until: due.addingTimeInterval(1)))
        XCTAssertEqual(engine.completedShortBreaks, before)
        // Hold at exactly due, then repeated holds keep moving relative to now.
        engine.holdBreak(seconds: 2, now: due.addingTimeInterval(1))
        XCTAssertEqual(engine.state, .working(until: due.addingTimeInterval(3)))
        engine.holdBreak(seconds: 2, now: due.addingTimeInterval(2))
        XCTAssertEqual(engine.state, .working(until: due.addingTimeInterval(4)))
        XCTAssertEqual(engine.completedShortBreaks, before)
        // tick contract: nothing fires before the held deadline, fires right after.
        XCTAssertEqual(engine.tick(now: due.addingTimeInterval(3), config: c), [])
        XCTAssertEqual(engine.tick(now: due.addingTimeInterval(4), config: c), [.breakStarted(.short)])
        XCTAssertEqual(engine.completedShortBreaks, before)
    }

    func testHoldBreakIgnoredWhenNotDue() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 3_100_000)
        engine.start(now: t0, config: config())
        let until = t0.addingTimeInterval(10 * 60)
        engine.holdBreak(seconds: 2, now: until.addingTimeInterval(-10 * 60))
        XCTAssertEqual(engine.state, .working(until: until))
        engine.holdBreak(seconds: 2, now: until.addingTimeInterval(-1.5))
        XCTAssertEqual(engine.state, .working(until: until))
    }

    func testHoldBreakIgnoredWhilePausedOrOnBreak() {
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 3_200_000)
        let c = config()
        engine.start(now: t0, config: c)
        engine.pause(reason: .manual, now: t0.addingTimeInterval(599.5))
        let paused = engine.state
        engine.holdBreak(seconds: 2, now: t0.addingTimeInterval(600))
        XCTAssertEqual(engine.state, paused)
        engine.resume(reason: .manual, now: t0.addingTimeInterval(700))
        // Frozen remaining (0.5 s) is untouched by the ignored hold.
        XCTAssertEqual(engine.timeUntilBreak(now: t0.addingTimeInterval(700)) ?? -1, 0.5, accuracy: 0.001)
        _ = engine.takeBreakNow(kind: .short, now: t0.addingTimeInterval(701), config: c)
        let onBreak = engine.state
        engine.holdBreak(seconds: 2, now: t0.addingTimeInterval(702))
        XCTAssertEqual(engine.state, onBreak)
    }

    func testMealCountsAsLongOnlyWhenLongerThanShortAndAtLeastTheLongBreak() {
        var c = BreakConfig()
        c.shortBreakSeconds = 180
        c.longBreakSeconds = 600
        XCTAssertEqual(c.kindForCustomLength(seconds: 900), .long)
        XCTAssertEqual(c.kindForCustomLength(seconds: 600), .long)
        XCTAssertEqual(c.kindForCustomLength(seconds: 599), .short)
        XCTAssertEqual(c.kindForCustomLength(seconds: 120), .short)
    }

    func testStartKindOverridesTheCycleAndCountsLikeThatBreak() {
        var c = BreakConfig()
        c.cycleMinutes = 1
        c.shortBreakSeconds = 60
        c.longBreakSeconds = 600
        c.longBreakEvery = 4
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.start(now: t0, config: c)
        let events = engine.tick(now: t0.addingTimeInterval(61), config: c, startKind: .long)
        XCTAssertEqual(events, [.breakStarted(.long)])
        _ = engine.tick(now: t0.addingTimeInterval(61 + 601), config: c)
        XCTAssertEqual(engine.completedShortBreaks, 0)   // a long break resets the count of short ones
    }
}
