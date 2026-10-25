import XCTest
@testable import IntermezzoKit

final class AudioFitTests: XCTestCase {
    func testTrackLongerThanBreakCoversItAndReportsExcess() {
        let fit = AudioFit.evaluate(trackSeconds: 600, breakSeconds: 300, loop: false)
        XCTAssertEqual(fit, .coversBreak(excess: 300))
        XCTAssertTrue(fit.isFine)
    }

    func testTrackExactlyAsLongAsBreakCovers() {
        XCTAssertEqual(AudioFit.evaluate(trackSeconds: 300, breakSeconds: 300, loop: false),
                       .coversBreak(excess: 0))
    }

    func testShortTrackWithoutLoopEndsEarly() {
        let fit = AudioFit.evaluate(trackSeconds: 30, breakSeconds: 300, loop: false)
        XCTAssertEqual(fit, .endsEarly(silentFor: 270))
        XCTAssertFalse(fit.isFine)
    }

    func testShortTrackWithLoopRepeatsRoundedUp() {
        let fit = AudioFit.evaluate(trackSeconds: 30, breakSeconds: 100, loop: true)
        XCTAssertEqual(fit, .loops(times: 4))
        XCTAssertTrue(fit.isFine)
    }

    func testLoopOnLongTrackStillJustCovers() {
        XCTAssertEqual(AudioFit.evaluate(trackSeconds: 500, breakSeconds: 100, loop: true),
                       .coversBreak(excess: 400))
    }

    func testUnknownOrZeroDurationIsUnknown() {
        XCTAssertEqual(AudioFit.evaluate(trackSeconds: nil, breakSeconds: 300, loop: true), .unknown)
        XCTAssertEqual(AudioFit.evaluate(trackSeconds: 0, breakSeconds: 300, loop: true), .unknown)
    }

    func testClockFormatting() {
        XCTAssertEqual(AudioFit.clock(0), "0:00")
        XCTAssertEqual(AudioFit.clock(5.4), "0:05")
        XCTAssertEqual(AudioFit.clock(205), "3:25")
        XCTAssertEqual(AudioFit.clock(3_725), "1:02:05")
        XCTAssertEqual(AudioFit.clock(-3), "0:00")
    }
}
