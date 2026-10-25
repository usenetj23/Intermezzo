import XCTest
@testable import IntermezzoKit

final class SeamGateTests: XCTestCase {

    private let due = Date(timeIntervalSince1970: 2_000_000)

    func testHoldsWhileTyping() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0.5))
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(30), secondsSinceInput: 1))
    }

    func testReleasesAfterQuietPause() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(10), secondsSinceInput: 5))
    }

    func testNeverHoldsLongerThanMaxDelay() {
        var gate = SeamGate()
        // Continuous typing, the engine keeps re-arming the deadline 2 s ahead,
        // so `dueAt` moves every tick — the window is anchored at the FIRST due.
        var t: TimeInterval = 0
        while t < 180 {
            let now = due.addingTimeInterval(t)
            XCTAssertTrue(gate.shouldHold(dueAt: now, now: now, secondsSinceInput: 0), "t=\(t)")
            t += 1
        }
        let late = due.addingTimeInterval(181)
        XCTAssertFalse(gate.shouldHold(dueAt: late, now: late, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(180), secondsSinceInput: 0))
    }

    func testResetStartsNewWindow() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(181), secondsSinceInput: 0))
        gate.reset()
        let next = due.addingTimeInterval(3_000)
        XCTAssertTrue(gate.shouldHold(dueAt: next, now: next, secondsSinceInput: 0))
        XCTAssertTrue(gate.shouldHold(dueAt: next, now: next.addingTimeInterval(170), secondsSinceInput: 0))
    }

    func testCustomMaxDelayIsHonoured() {
        var gate = SeamGate(maxDelay: 60)
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(59), secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(60), secondsSinceInput: 0))
    }

    func testClockJumpBackwardsReanchorsInsteadOfExtendingHold() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0))
        // Wall clock jumps back an hour: the window restarts at the new "now",
        // it must not become 3 600 + 180 s long.
        let back = due.addingTimeInterval(-3_600)
        XCTAssertTrue(gate.shouldHold(dueAt: back, now: back, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: back, now: back.addingTimeInterval(180), secondsSinceInput: 0))
    }

    func testQuietReleaseDoesNotRestartWindow() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(100), secondsSinceInput: 10))
        // Without reset the first-due moment is kept: typing again at +181 s is not held.
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(181), secondsSinceInput: 0))
    }

    func testOnceReleasedStaysReleasedUntilReset() {
        var gate = SeamGate()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due, secondsSinceInput: 0))
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(20), secondsSinceInput: 6))
        // The seam was found — typing again a second later must not re-hold.
        XCTAssertFalse(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(21), secondsSinceInput: 0))
        gate.reset()
        XCTAssertTrue(gate.shouldHold(dueAt: due, now: due.addingTimeInterval(22), secondsSinceInput: 0))
    }
}
