import XCTest
@testable import IntermezzoKit

final class ReminderEscalationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func after(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    func testFirstReminderIsGentle() {
        var e = ReminderEscalation()
        XCTAssertEqual(e.advance(now: t0, repeatEvery: 600), .gentle)
        XCTAssertNil(e.glowProgress)
    }

    func testNothingHappensUntilTheRepeatInterval() {
        var e = ReminderEscalation()
        _ = e.advance(now: t0, repeatEvery: 600)
        XCTAssertNil(e.advance(now: after(599), repeatEvery: 600))
    }

    func testEachRepeatIsStrongerAndStartsTheGlow() {
        var e = ReminderEscalation()
        _ = e.advance(now: t0, repeatEvery: 600)
        XCTAssertEqual(e.advance(now: after(600), repeatEvery: 600), .stronger(level: 1))
        let first = e.glowProgress
        XCTAssertNotNil(first)
        XCTAssertEqual(e.advance(now: after(1200), repeatEvery: 600), .stronger(level: 2))
        XCTAssertGreaterThan(e.glowProgress ?? 0, first ?? 1)
    }

    func testGlowIsCappedAtFull() {
        var e = ReminderEscalation()
        _ = e.advance(now: t0, repeatEvery: 60)
        for i in 1...30 { _ = e.advance(now: after(Double(i) * 60), repeatEvery: 60) }
        XCTAssertEqual(e.glowProgress, 1)
    }

    func testResetStartsOverWithAGentleReminder() {
        var e = ReminderEscalation()
        _ = e.advance(now: t0, repeatEvery: 60)
        _ = e.advance(now: after(60), repeatEvery: 60)
        e.reset()
        XCTAssertNil(e.glowProgress)
        XCTAssertEqual(e.advance(now: after(500), repeatEvery: 60), .gentle)
    }

    func testClockGoingBackwardsDoesNotRepeat() {
        var e = ReminderEscalation()
        _ = e.advance(now: t0, repeatEvery: 60)
        XCTAssertNil(e.advance(now: after(-300), repeatEvery: 60))
    }
}
