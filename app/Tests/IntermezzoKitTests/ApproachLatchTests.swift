import XCTest
@testable import IntermezzoKit

final class ApproachLatchTests: XCTestCase {
    func testFiresOnceAtTheOffset() {
        var latch = ApproachLatch<String>()
        XCTAssertFalse(latch.enter("a", timeLeft: 100, window: 60))
        XCTAssertFalse(latch.enter("a", timeLeft: 61, window: 60))
        XCTAssertTrue(latch.enter("a", timeLeft: 60, window: 60))
        XCTAssertFalse(latch.enter("a", timeLeft: 59, window: 60))
    }

    /// A 1 s heartbeat with the natural seam holding the break for 300 s: the
    /// deadline is pushed 2 s ahead on every tick, so time-to-break hovers at 1-2 s.
    func testDoesNotReFireDuringASeamHold() {
        var latch = ApproachLatch<String>()
        var fired = 0
        var deadline: TimeInterval = 90
        for now in stride(from: 0.0, through: 390, by: 1) {
            let left = max(0, deadline - now)
            if latch.enter("a", timeLeft: left, window: 60) { fired += 1 }
            if left <= 1.5 { deadline = now + 2 }        // seam hold
        }
        XCTAssertEqual(fired, 1)
    }

    func testReArmsAfterSnoozeMovesTheDeadlineBeyondTheOffset() {
        var latch = ApproachLatch<String>()
        XCTAssertTrue(latch.enter("a", timeLeft: 10, window: 60))
        XCTAssertFalse(latch.enter("a", timeLeft: 50, window: 60), "short snooze inside the window: no re-fire")
        XCTAssertFalse(latch.enter("a", timeLeft: 300, window: 60), "snooze beyond the offset re-arms")
        XCTAssertTrue(latch.enter("a", timeLeft: 60, window: 60))
    }

    func testReArmsAfterABreakStarts() {
        var latch = ApproachLatch<String>()
        XCTAssertTrue(latch.enter("a", timeLeft: 5, window: 60))
        latch.reset()
        XCTAssertTrue(latch.enter("a", timeLeft: 5, window: 60))
    }

    func testSmallWindowUsesHysteresisSoHoldsDoNotReArm() {
        var latch = ApproachLatch<String>()
        XCTAssertTrue(latch.enter("a", timeLeft: 1, window: 1.5))
        XCTAssertFalse(latch.enter("a", timeLeft: 2, window: 1.5), "2 s seam hold is not a new approach")
        XCTAssertFalse(latch.enter("a", timeLeft: 1, window: 1.5))
        XCTAssertFalse(latch.enter("a", timeLeft: 3.5, window: 1.5))
        XCTAssertTrue(latch.enter("a", timeLeft: 1, window: 1.5))
    }

    func testKeysAreIndependentAndDisabledInputsNeverFire() {
        var latch = ApproachLatch<String>()
        XCTAssertTrue(latch.enter("a", timeLeft: 5, window: 60))
        XCTAssertTrue(latch.enter("b", timeLeft: 5, window: 60))
        XCTAssertFalse(latch.enter("c", timeLeft: nil, window: 60))
        XCTAssertFalse(latch.enter("c", timeLeft: 1, window: 0), "offset 0 disables")
        XCTAssertFalse(latch.enter("c", timeLeft: -1, window: 60))
    }
}
