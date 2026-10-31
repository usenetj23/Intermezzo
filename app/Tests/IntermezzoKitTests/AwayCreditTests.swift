import XCTest
@testable import IntermezzoKit

final class AwayCreditTests: XCTestCase {
    private var config: BreakConfig {
        var c = BreakConfig()
        c.shortBreakSeconds = 300
        c.longBreakSeconds = 900
        c.longBreakEvery = 4
        return c
    }

    func testTooShortAnAbsenceCountsAsNothing() {
        XCTAssertNil(AwayCredit.kind(awaySeconds: 120, nextKind: .short, config: config))
        XCTAssertNil(AwayCredit.kind(awaySeconds: 600, nextKind: .long, config: config))
    }

    func testAbsenceAsLongAsTheNextShortBreakIsAShortBreak() {
        XCTAssertEqual(AwayCredit.kind(awaySeconds: 300, nextKind: .short, config: config), .short)
        XCTAssertEqual(AwayCredit.kind(awaySeconds: 600, nextKind: .short, config: config), .short)
    }

    func testAbsenceAsLongAsTheLongBreakIsALongBreakEvenWhenAShortOneWasNext() {
        XCTAssertEqual(AwayCredit.kind(awaySeconds: 900, nextKind: .short, config: config), .long)
        XCTAssertEqual(AwayCredit.kind(awaySeconds: 3600, nextKind: .long, config: config), .long)
    }

    func testCreditMovesTheCycleLikeARealBreak() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var engine = BreakEngine()
        engine.start(now: now, config: config)
        engine.creditAway(kind: .short, now: now, config: config)
        engine.creditAway(kind: .short, now: now, config: config)
        XCTAssertEqual(engine.completedShortBreaks, 2)
        engine.creditAway(kind: .long, now: now, config: config)
        XCTAssertEqual(engine.completedShortBreaks, 0)
        XCTAssertEqual(engine.timeUntilBreak(now: now), TimeInterval(config.cycleMinutes * 60))
    }

    func testReadingIsNotAwayUntilALongStretchOrAConfirmedLeave() {
        XCTAssertFalse(AwayPolicy.shouldPause(idleSeconds: 90, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertFalse(AwayPolicy.shouldPause(idleSeconds: 599, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertTrue(AwayPolicy.shouldPause(idleSeconds: 600, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertTrue(AwayPolicy.shouldPause(idleSeconds: 61, confirmed: true, unconfirmedSeconds: 600))
    }
}
