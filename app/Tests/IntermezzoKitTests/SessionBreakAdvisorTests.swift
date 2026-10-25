import XCTest
@testable import IntermezzoKit

final class SessionBreakAdvisorTests: XCTestCase {
    private func record(seconds: Int = 1500, active: Int = 0, interruptions: Int = 0) -> PomodoroRecord {
        PomodoroRecord(date: Date(), startedAt: Date(), taskID: nil, taskTitle: "t", project: "",
                       minutes: seconds / 60, actualSeconds: seconds,
                       internalInterruptions: interruptions, externalInterruptions: 0,
                       appSwitches: 0, activeSeconds: active)
    }

    private func advise(_ r: PomodoroRecord?, screen: Int = 0, outdoors: Bool = false,
                        kind: BreakKind = .short) -> SessionAdvice {
        SessionBreakAdvisor.advise(last: r, continuousScreenMinutes: screen,
                                   outdoorsWeather: outdoors, kind: kind)
    }

    func testManyInterruptionsSuggestBreathing() {
        XCTAssertEqual(advise(record(interruptions: 3)), .category(.breathing))
        XCTAssertEqual(advise(record(interruptions: 2)), .rotation)
    }

    func testIntenseScreenSessionSuggestsEyes() {
        XCTAssertEqual(advise(record(seconds: 1500, active: 1200), screen: 50), .category(.eyes))
        XCTAssertEqual(advise(record(seconds: 1500, active: 1200), screen: 49), .rotation)
        XCTAssertEqual(advise(record(seconds: 1500, active: 1100), screen: 60), .rotation)
    }

    func testLongBreakAndGoodWeatherSuggestsOutdoors() {
        XCTAssertEqual(advise(record(), outdoors: true, kind: .long), .outdoors)
        XCTAssertEqual(advise(record(), outdoors: true, kind: .short), .rotation)
    }

    func testLongSessionSuggestsLegs() {
        XCTAssertEqual(advise(record(seconds: 45 * 60)), .category(.legs))
        XCTAssertEqual(advise(record(seconds: 45 * 60 - 1)), .rotation)
    }

    func testNoRecordFallsBackToRotation() {
        XCTAssertEqual(advise(nil, screen: 200, outdoors: true, kind: .long), .rotation)
    }

    func testRuleOrderBreathingWinsOverEyes() {
        let r = record(seconds: 1500, active: 1400, interruptions: 4)
        XCTAssertEqual(advise(r, screen: 90, outdoors: true, kind: .long), .category(.breathing))
    }

    func testEyesWinOverOutdoorsAndOutdoorsOverLegs() {
        let busy = record(seconds: 3000, active: 2800)
        XCTAssertEqual(advise(busy, screen: 60, outdoors: true, kind: .long), .category(.eyes))
        XCTAssertEqual(advise(record(seconds: 3000), outdoors: true, kind: .long), .outdoors)
    }

    func testZeroActualSecondsDoesNotDivideByZero() {
        XCTAssertEqual(advise(record(seconds: 0, active: 0), screen: 120), .rotation)
    }

    func testOutdoorsWeatherRules() {
        XCTAssertTrue(SessionBreakAdvisor.isOutdoorsWeather(effect: .clear, uvIndex: 4, temperatureC: 18))
        XCTAssertTrue(SessionBreakAdvisor.isOutdoorsWeather(effect: .clear, uvIndex: nil, temperatureC: 18))
        for e in [WeatherEffect.rain, .storm, .snow, .fog, .cloudy, .none] {
            XCTAssertFalse(SessionBreakAdvisor.isOutdoorsWeather(effect: e, uvIndex: 1, temperatureC: 18), "\(e)")
        }
        XCTAssertFalse(SessionBreakAdvisor.isOutdoorsWeather(effect: .clear, uvIndex: 9, temperatureC: 18))
        XCTAssertFalse(SessionBreakAdvisor.isOutdoorsWeather(effect: .clear, uvIndex: 2, temperatureC: 35))
        XCTAssertFalse(SessionBreakAdvisor.isOutdoorsWeather(effect: .clear, uvIndex: 2, temperatureC: -3))
    }

    // MARK: - justFinished / pickExercise

    private func ledger(endingAt date: Date?) throws -> PomodoroLedger {
        guard let date else { return PomodoroLedger() }
        let rec = PomodoroRecord(date: date, startedAt: date.addingTimeInterval(-1500), taskID: nil,
                                 taskTitle: "t", project: "", minutes: 25, actualSeconds: 1500,
                                 internalInterruptions: 0, externalInterruptions: 0,
                                 appSwitches: 0, activeSeconds: 0)
        var l = PomodoroLedger()
        l.records = [rec]
        return l
    }

    func testJustFinishedReturnsRecordWithinWindow() throws {
        let now = Date()
        XCTAssertNotNil(try ledger(endingAt: now.addingTimeInterval(-2)).justFinished(at: now))
        XCTAssertNotNil(try ledger(endingAt: now).justFinished(at: now))
    }

    func testJustFinishedNilForYesterdayEmptyAndFuture() throws {
        let now = Date()
        XCTAssertNil(try ledger(endingAt: now.addingTimeInterval(-86_400)).justFinished(at: now))
        XCTAssertNil(try ledger(endingAt: nil).justFinished(at: now))
        XCTAssertNil(try ledger(endingAt: now.addingTimeInterval(60)).justFinished(at: now))
    }

    func testJustFinishedWindowBoundary() throws {
        let now = Date()
        XCTAssertNotNil(try ledger(endingAt: now.addingTimeInterval(-5)).justFinished(at: now))
        XCTAssertNil(try ledger(endingAt: now.addingTimeInterval(-5.01)).justFinished(at: now))
        XCTAssertNotNil(try ledger(endingAt: now.addingTimeInterval(5)).justFinished(at: now))
        XCTAssertNil(try ledger(endingAt: now.addingTimeInterval(5.01)).justFinished(at: now))
    }

    func testPickExerciseEmptyCandidatesYieldsNil() {
        XCTAssertNil(SessionBreakAdvisor.pickExercise(category: .breathing, kind: .short, from: []))
        let eyesOnly = ExerciseLibrary.all.filter { $0.category == .eyes }
        XCTAssertNil(SessionBreakAdvisor.pickExercise(category: .breathing, kind: .long, from: eyesOnly))
        XCTAssertEqual(SessionBreakAdvisor.pickExercise(category: .breathing, kind: .long,
                                                        from: ExerciseLibrary.all)?.category, .breathing)
    }
}
