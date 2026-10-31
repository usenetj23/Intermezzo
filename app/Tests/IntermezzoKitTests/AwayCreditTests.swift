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

    func testOnlyALockedScreenOrALongStretchCountsAsAnAbsence() {
        XCTAssertFalse(AwayPolicy.isRealAbsence(idleSeconds: 90, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertFalse(AwayPolicy.isRealAbsence(idleSeconds: 599, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertTrue(AwayPolicy.isRealAbsence(idleSeconds: 600, confirmed: false, unconfirmedSeconds: 600))
        XCTAssertTrue(AwayPolicy.isRealAbsence(idleSeconds: 61, confirmed: true, unconfirmedSeconds: 600))
    }

    func testTheStretchBeforeTheTimerStoppedIsGivenBack() {
        var c = BreakConfig()
        c.cycleMinutes = 10
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let stop = t0.addingTimeInterval(60)         // 1 min without input: the timer stops with 9:00 left
        let back = stop.addingTimeInterval(300)

        var plain = BreakEngine()
        plain.start(now: t0, config: c)
        plain.pause(reason: .userAway, now: stop)
        _ = plain.resume(reason: .userAway, now: back)
        XCTAssertEqual(plain.timeUntilBreak(now: back) ?? -1, 540, accuracy: 0.5)

        var refunded = BreakEngine()
        refunded.start(now: t0, config: c)
        refunded.pause(reason: .userAway, now: stop)
        refunded.refundWorkTime(seconds: 60, config: c)      // that minute is given back
        _ = refunded.resume(reason: .userAway, now: back)
        XCTAssertEqual(refunded.timeUntilBreak(now: back) ?? -1, 600, accuracy: 0.5)
    }

    func testRefundNeverGoesBeyondAFullCycle() {
        var c = BreakConfig()
        c.cycleMinutes = 10
        var engine = BreakEngine()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        engine.start(now: t0, config: c)
        let stop = t0.addingTimeInterval(5)
        engine.pause(reason: .userAway, now: stop)
        engine.refundWorkTime(seconds: 3600, config: c)
        _ = engine.resume(reason: .userAway, now: stop)
        XCTAssertEqual(engine.timeUntilBreak(now: stop) ?? -1, 600, accuracy: 0.5)
    }
}
