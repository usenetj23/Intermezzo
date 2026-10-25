import XCTest
@testable import IntermezzoKit

final class RhythmExperimentTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func day(_ d: Int, _ hour: Int = 10, calendar: Calendar? = nil) -> Date {
        (calendar ?? cal).date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    private func record(minutes: Int, on end: Date, switches: Int = 0, calendar: Calendar? = nil) -> PomodoroRecord {
        PomodoroRecord(date: end, startedAt: end.addingTimeInterval(-Double(minutes) * 60), taskID: nil,
                       taskTitle: "", project: "", minutes: minutes, actualSeconds: minutes * 60,
                       internalInterruptions: 0, externalInterruptions: 0, appSwitches: switches, activeSeconds: 0)
    }

    private func experiment(start: Int = 1, calendar: Calendar? = nil) -> RhythmExperiment {
        RhythmExperiment(startedOn: day(start, calendar: calendar))
    }

    func testAlternatesBlocksOfDays() {
        let e = experiment()
        let ids = (0..<7).map { e.arm(for: day(1 + $0), calendar: cal).id }
        XCTAssertEqual(ids, ["A", "A", "A", "B", "B", "B", "A"])
        XCTAssertEqual(e.arm(for: day(1), calendar: cal), RhythmArm.defaultA)
        XCTAssertEqual(RhythmArm.defaultB.workMinutes, 50)
        XCTAssertEqual(RhythmArm.defaultB.shortBreakMinutes, 10)
    }

    func testDayBeforeStartUsesFirstArm() {
        let e = experiment(start: 5)
        XCTAssertEqual(e.arm(for: day(2), calendar: cal).id, "A")
        XCTAssertEqual(e.blockNumber(for: day(2), calendar: cal), 1)
        XCTAssertEqual(e.blockNumber(for: day(8), calendar: cal), 2)
    }

    func testBlockArithmeticSurvivesDSTTransition() {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        // 2026-10-25 has 25 hours; days 0-2 = 24,25,26 (A), day 3 = 27 (B).
        let e = experiment(start: 24, calendar: warsaw)
        XCTAssertEqual(e.arm(for: day(25, 23, calendar: warsaw), calendar: warsaw).id, "A")
        XCTAssertEqual(e.arm(for: day(26, 0, calendar: warsaw), calendar: warsaw).id, "A")
        XCTAssertEqual(e.arm(for: day(26, 23, calendar: warsaw), calendar: warsaw).id, "A")
        XCTAssertEqual(e.arm(for: day(27, 0, calendar: warsaw), calendar: warsaw).id, "B")
    }

    func testIgnoresRecordsWithOtherLength() {
        let e = experiment()
        let records = [record(minutes: 25, on: day(1), switches: 2),
                       record(minutes: 30, on: day(1)),
                       record(minutes: 50, on: day(1))]   // 50 min on an A day: not A's, B's day is later
        let r = e.results(records: records, calendar: cal)
        XCTAssertEqual(r[0].pomodoros, 1)
        XCTAssertEqual(r[0].meanDisruptions, 2)
        XCTAssertEqual(r[1].pomodoros, 0)
    }

    func testContaminatedDayIsSkipped() {
        let e = experiment().markingContaminated(day(2, 15), calendar: cal)
        XCTAssertEqual(e.contaminatedDays, [cal.startOfDay(for: day(2))])
        XCTAssertEqual(e.markingContaminated(day(2, 9), calendar: cal), e)   // idempotent
        let records = [record(minutes: 25, on: day(1)), record(minutes: 25, on: day(2)),
                       record(minutes: 25, on: day(3))]
        let a = e.results(records: records, calendar: cal)[0]
        XCTAssertEqual(a.pomodoros, 2)
        XCTAssertEqual(a.days, 2)
    }

    func testRecordCountsByEndDayAcrossMidnight() {
        let e = experiment()
        let end = day(4, 0)   // started on day 3 (A), ended on day 4 (B)
        let b = e.results(records: [record(minutes: 50, on: end)], calendar: cal)[1]
        XCTAssertEqual(b.pomodoros, 1)
    }

    /// One 25-min record on each of the given days.
    private func records(minutes: Int, onDays days: [Int]) -> [PomodoroRecord] {
        days.map { record(minutes: minutes, on: day($0)) }
    }

    func testEmptyDaysDoNotMakeAnArmEnough() {
        let r = experiment().results(records: [], calendar: cal)
        XCTAssertEqual(r.map(\.days), [0, 0])
        XCTAssertTrue(r.allSatisfy { !$0.isEnough })
    }

    func testNeedsSixDaysWithDataPerArm() {
        let e = experiment()
        // A days: 1,2,3, 7,8,9, 13...; with 3-day blocks A = days 1-3, 7-9, 13-15.
        let six = e.results(records: records(minutes: 25, onDays: [1, 2, 3, 7, 8, 9]), calendar: cal)[0]
        XCTAssertEqual(six.days, 6)
        XCTAssertTrue(six.isEnough)
        let five = e.results(records: records(minutes: 25, onDays: [1, 2, 3, 7, 8]), calendar: cal)[0]
        XCTAssertEqual(five.days, 5)
        XCTAssertFalse(five.isEnough)
        // Several records on one day are still one day.
        let sameDay = e.results(records: records(minutes: 25, onDays: [1, 1, 1, 2, 3, 7, 8]), calendar: cal)[0]
        XCTAssertEqual(sameDay.days, 5)
        XCTAssertEqual(RhythmExperiment.minDaysPerArm, 6)
        XCTAssertEqual(RhythmExperiment.minPomodorosPerArm, 1)
        // A contaminated data day does not count.
        let c = e.markingContaminated(day(1), calendar: cal)
            .results(records: records(minutes: 25, onDays: [1, 2, 3, 7, 8, 9]), calendar: cal)[0]
        XCTAssertEqual(c.days, 5)
        XCTAssertFalse(c.isEnough)
    }

    func testVoidedCountedPerArmDay() {
        let e = experiment()
        let r = e.results(records: [], voided: [day(1), day(4), day(4, 11)], calendar: cal)
        XCTAssertEqual(r[0].voided, 1)
        XCTAssertEqual(r[1].voided, 2)
    }

    func testCodableRoundTripTolerant() throws {
        var e = experiment()
        e.daysPerBlock = 4
        e = e.markingContaminated(day(2), calendar: cal)
        let back = try JSONDecoder().decode(RhythmExperiment.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back, e)

        let minimal = try JSONDecoder().decode(RhythmExperiment.self, from: Data(#"{"startedOn": 0}"#.utf8))
        XCTAssertEqual(minimal.arms, [RhythmArm.defaultA, RhythmArm.defaultB])
        XCTAssertEqual(minimal.daysPerBlock, 3)
        XCTAssertTrue(minimal.contaminatedDays.isEmpty)
        let armOnly = try JSONDecoder().decode(RhythmArm.self, from: Data(#"{"id":"A"}"#.utf8))
        XCTAssertEqual(armOnly.workMinutes, 25)
    }
}

final class RhythmArmSetupTests: XCTestCase {
    func testIdenticalArmsCannotStart() {
        let a = RhythmArm(id: "A", workMinutes: 25, shortBreakMinutes: 5)
        XCTAssertFalse(RhythmExperiment.canStart(arms: [a, RhythmArm(id: "B", workMinutes: 25, shortBreakMinutes: 5)]))
        XCTAssertTrue(RhythmExperiment.canStart(arms: [a, RhythmArm(id: "B", workMinutes: 25, shortBreakMinutes: 6)]))
        XCTAssertTrue(RhythmExperiment.canStart(arms: [a, RhythmArm(id: "B", workMinutes: 30, shortBreakMinutes: 5)]))
        XCTAssertTrue(RhythmExperiment.canStart(arms: [.defaultA, .defaultB]))
    }
}
