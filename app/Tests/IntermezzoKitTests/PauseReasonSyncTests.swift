import XCTest
@testable import IntermezzoKit

/// Regresje v1.9.12: pauzy z polityk (urlop, święto, reguły…) muszą się
/// zdejmować same, a pauza zgłoszona w trakcie przerwy nie może przepadać.
final class PauseReasonSyncTests: XCTestCase {

    private let policy: Set<PauseReason> = [.vacation, .holiday, .ruleMatch, .outsideWorkingHours]

    private func config() -> BreakConfig {
        var c = BreakConfig()
        c.cycleMinutes = 10
        c.shortBreakSeconds = 60
        c.longBreakSeconds = 120
        c.longBreakEvery = 3
        return c
    }

    private func startedEngine(_ t0: Date) -> BreakEngine {
        var e = BreakEngine()
        e.start(now: t0, config: config())
        return e
    }

    // MARK: - syncReasons

    func testVacationEndingResumesTimer() {
        let t0 = Date(timeIntervalSince1970: 10_000_000)
        var e = startedEngine(t0)
        e.syncReasons([.vacation], managed: policy, now: t0)
        XCTAssertTrue(e.isPaused)
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(3600))
        XCTAssertFalse(e.isPaused, "urlop wygasł — licznik musi ruszyć")
    }

    func testHolidayPassingResumesTimer() {
        let t0 = Date(timeIntervalSince1970: 11_000_000)
        var e = startedEngine(t0)
        e.syncReasons([.holiday], managed: policy, now: t0)
        XCTAssertTrue(e.isPaused)
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(86_400))
        XCTAssertFalse(e.isPaused)
    }

    func testSyncIsIdempotent() {
        let t0 = Date(timeIntervalSince1970: 12_000_000)
        var e = startedEngine(t0)
        e.syncReasons([.ruleMatch], managed: policy, now: t0)
        e.syncReasons([.ruleMatch], managed: policy, now: t0.addingTimeInterval(30))
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(60))
        XCTAssertFalse(e.isPaused)
    }

    func testSyncDoesNotTouchUnmanagedReasons() {
        let t0 = Date(timeIntervalSince1970: 13_000_000)
        var e = startedEngine(t0)
        e.pause(reason: .manual, now: t0)
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(10))
        XCTAssertTrue(e.isPaused, "ręczna pauza nie należy do polityk")
    }

    func testSyncSwapsReasonsWithoutResuming() {
        let t0 = Date(timeIntervalSince1970: 14_000_000)
        var e = startedEngine(t0)
        e.syncReasons([.vacation], managed: policy, now: t0)
        e.syncReasons([.holiday], managed: policy, now: t0.addingTimeInterval(5))
        XCTAssertTrue(e.isPaused)
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(10))
        XCTAssertFalse(e.isPaused)
    }

    func testSyncPreservesFrozenRemaining() {
        let t0 = Date(timeIntervalSince1970: 15_000_000)
        var e = startedEngine(t0)
        // 4 minut pracy, potem pauza polityki na godzinę.
        e.syncReasons([.vacation], managed: policy, now: t0.addingTimeInterval(4 * 60))
        e.syncReasons([], managed: policy, now: t0.addingTimeInterval(64 * 60))
        let left = e.timeUntilBreak(now: t0.addingTimeInterval(64 * 60)) ?? -1
        XCTAssertEqual(left, 6 * 60, accuracy: 1)
    }

    // MARK: - pauzy w trakcie przerwy

    private func engineOnBreak(_ t0: Date) -> BreakEngine {
        var e = startedEngine(t0)
        _ = e.tick(now: t0.addingTimeInterval(10 * 60 + 1), config: config())
        XCTAssertNotNil(e.activeBreakKind)
        return e
    }

    func testPauseDuringBreakAppliesAfterCompletion() {
        let t0 = Date(timeIntervalSince1970: 16_000_000)
        var e = engineOnBreak(t0)
        e.pause(reason: .userAway, now: t0.addingTimeInterval(10 * 60 + 10))
        let events = e.tick(now: t0.addingTimeInterval(10 * 60 + 62), config: config())
        XCTAssertEqual(events, [.breakCompleted])
        XCTAssertTrue(e.isPaused, "użytkownik jest nieobecny — licznik nie może biec")
        _ = e.resume(reason: .userAway, now: t0.addingTimeInterval(3600))
        let left = e.timeUntilBreak(now: t0.addingTimeInterval(3600)) ?? -1
        XCTAssertEqual(left, 10 * 60, accuracy: 1, "po przerwie pełny cykl")
    }

    func testPauseDuringBreakAppliesAfterSkip() {
        let t0 = Date(timeIntervalSince1970: 17_000_000)
        var e = engineOnBreak(t0)
        e.pause(reason: .manual, now: t0.addingTimeInterval(10 * 60 + 5))
        _ = e.skipBreak(now: t0.addingTimeInterval(10 * 60 + 6), config: config())
        XCTAssertTrue(e.isPaused)
    }

    func testPauseDuringBreakAppliesAfterPostpone() {
        let t0 = Date(timeIntervalSince1970: 18_000_000)
        var e = engineOnBreak(t0)
        e.pause(reason: .manual, now: t0.addingTimeInterval(10 * 60 + 5))
        _ = e.postponeBreak(minutes: 5, now: t0.addingTimeInterval(10 * 60 + 6))
        XCTAssertTrue(e.isPaused)
        _ = e.resume(reason: .manual, now: t0.addingTimeInterval(20 * 60))
        let left = e.timeUntilBreak(now: t0.addingTimeInterval(20 * 60)) ?? -1
        XCTAssertEqual(left, 5 * 60, accuracy: 1)
    }

    func testResumeDuringBreakCancelsPendingPause() {
        let t0 = Date(timeIntervalSince1970: 19_000_000)
        var e = engineOnBreak(t0)
        e.pause(reason: .userAway, now: t0.addingTimeInterval(10 * 60 + 5))
        _ = e.resume(reason: .userAway, now: t0.addingTimeInterval(10 * 60 + 20))
        _ = e.tick(now: t0.addingTimeInterval(10 * 60 + 62), config: config())
        XCTAssertFalse(e.isPaused)
        XCTAssertNotNil(e.timeUntilBreak(now: t0.addingTimeInterval(10 * 60 + 62)))
    }

    func testTakeBreakNowKeepsManualPause() {
        let t0 = Date(timeIntervalSince1970: 20_000_000)
        var e = startedEngine(t0)
        e.pause(reason: .manual, now: t0)
        _ = e.takeBreakNow(kind: .short, now: t0.addingTimeInterval(5), config: config())
        _ = e.tick(now: t0.addingTimeInterval(70), config: config())
        XCTAssertTrue(e.isPaused, "po przerwie na żądanie pauza ręczna nadal obowiązuje")
        XCTAssertEqual(e.activeBreakKind, nil)
    }

    func testPendingPauseIsToggleable() {
        let t0 = Date(timeIntervalSince1970: 22_000_000)
        var e = engineOnBreak(t0)
        e.pause(reason: .manual, now: t0.addingTimeInterval(10 * 60 + 5))
        XCTAssertTrue(e.isPausePending(.manual))
        _ = e.resume(reason: .manual, now: t0.addingTimeInterval(10 * 60 + 6))
        XCTAssertFalse(e.isPausePending(.manual))
    }

    func testPlainBreakStillReturnsToWorking() {
        let t0 = Date(timeIntervalSince1970: 21_000_000)
        var e = engineOnBreak(t0)
        _ = e.tick(now: t0.addingTimeInterval(10 * 60 + 62), config: config())
        XCTAssertFalse(e.isPaused)
    }
}
