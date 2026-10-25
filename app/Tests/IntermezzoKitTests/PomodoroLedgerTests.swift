import XCTest
@testable import IntermezzoKit

final class PomodoroLedgerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testCompletingCountsPomodoroAndAdvancesTask() {
        var ledger = PomodoroLedger()
        ledger = ledger.addingTask(title: "Write report", estimate: 3)
        let id = ledger.tasks[0].id
        ledger = ledger.starting(taskID: id, minutes: 25, at: date(20))
        ledger = ledger.completing(at: date(20, 11))

        XCTAssertNil(ledger.current)
        XCTAssertEqual(ledger.records.count, 1)
        XCTAssertEqual(ledger.records[0].taskTitle, "Write report")
        XCTAssertEqual(ledger.tasks[0].done, 1)
        XCTAssertEqual(ledger.completedCount(on: date(20), calendar: cal), 1)
    }

    func testVoidedPomodoroDoesNotCount() {
        var ledger = PomodoroLedger().addingTask(title: "A", estimate: 1)
        ledger = ledger.starting(taskID: ledger.tasks[0].id, minutes: 25, at: date(20))
        ledger = ledger.voiding(at: date(20, 10))

        XCTAssertNil(ledger.current)
        XCTAssertTrue(ledger.records.isEmpty)
        XCTAssertEqual(ledger.tasks[0].done, 0)
        XCTAssertEqual(ledger.voidedCount(on: date(20), calendar: cal), 1)
    }

    func testInterruptionsAreCountedOnCurrentPomodoroOnly() {
        var ledger = PomodoroLedger()
        ledger = ledger.recordingInterruption(.external)               // nothing running → ignored
        XCTAssertNil(ledger.current)

        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(20))
        ledger = ledger.recordingInterruption(.internal)
        ledger = ledger.recordingInterruption(.external)
        ledger = ledger.recordingInterruption(.external)
        ledger = ledger.completing(at: date(20, 11))

        XCTAssertEqual(ledger.records[0].internalInterruptions, 1)
        XCTAssertEqual(ledger.records[0].externalInterruptions, 2)
        XCTAssertEqual(ledger.interruptions(on: date(20), calendar: cal).internal, 1)
        XCTAssertEqual(ledger.interruptions(on: date(20), calendar: cal).external, 2)
    }

    func testCompletingWithoutRunningPomodoroChangesNothing() {
        let ledger = PomodoroLedger().completing(at: date(20))
        XCTAssertTrue(ledger.records.isEmpty)
    }

    func testStartingTwiceVoidsThePreviousOne() {
        var ledger = PomodoroLedger()
        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(20, 9))
        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(20, 10))
        XCTAssertEqual(ledger.voidedCount(on: date(20), calendar: cal), 1)
        XCTAssertNotNil(ledger.current)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        var ledger = PomodoroLedger()
        for day in [18, 19, 20] {
            ledger = ledger.starting(taskID: nil, minutes: 25, at: date(day)).completing(at: date(day, 11))
        }
        XCTAssertEqual(ledger.streakDays(endingOn: date(20), calendar: cal), 3)
        // No pomodoro yet today: the streak from yesterday is still alive.
        XCTAssertEqual(ledger.streakDays(endingOn: date(21), calendar: cal), 3)
        // A gap of a full day breaks it.
        XCTAssertEqual(ledger.streakDays(endingOn: date(22), calendar: cal), 0)
    }

    func testWeekCountsReturnsSevenDaysOldestFirst() {
        var ledger = PomodoroLedger()
        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(20)).completing(at: date(20, 11))
        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(20, 12)).completing(at: date(20, 13))
        ledger = ledger.starting(taskID: nil, minutes: 25, at: date(18)).completing(at: date(18, 11))
        let week = ledger.weekCounts(endingOn: date(20), calendar: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last, 2)
        XCTAssertEqual(week[4], 1)       // the 18th is two days before the 20th
        XCTAssertEqual(week.reduce(0, +), 3)
    }

    func testEstimateAccuracyComparesDoneWithEstimateOfFinishedTasks() {
        var ledger = PomodoroLedger()
        ledger = ledger.addingTask(title: "A", estimate: 2)   // finished with 3 → under-estimated
        ledger = ledger.addingTask(title: "B", estimate: 4)   // finished with 4 → exact
        ledger = ledger.addingTask(title: "C", estimate: 5)   // still open → ignored
        let (a, b) = (ledger.tasks[0].id, ledger.tasks[1].id)
        for _ in 0..<3 { ledger = ledger.starting(taskID: a, minutes: 25, at: date(20)).completing(at: date(20, 11)) }
        for _ in 0..<4 { ledger = ledger.starting(taskID: b, minutes: 25, at: date(20)).completing(at: date(20, 11)) }
        ledger = ledger.finishingTask(a).finishingTask(b)

        // (3 + 4) done vs (2 + 4) estimated → 7 / 6.
        XCTAssertEqual(ledger.estimateRatio() ?? 0, 7.0 / 6.0, accuracy: 0.0001)
        XCTAssertNil(PomodoroLedger().estimateRatio())
    }

    func testRemovingTaskKeepsHistory() {
        var ledger = PomodoroLedger().addingTask(title: "A", estimate: 1)
        let id = ledger.tasks[0].id
        ledger = ledger.starting(taskID: id, minutes: 25, at: date(20)).completing(at: date(20, 11))
        ledger = ledger.removingTask(id)
        XCTAssertTrue(ledger.tasks.isEmpty)
        XCTAssertEqual(ledger.records.count, 1)
    }

    func testCodableRoundTripAndTolerantDecode() throws {
        var ledger = PomodoroLedger().addingTask(title: "A", estimate: 2)
        ledger = ledger.starting(taskID: ledger.tasks[0].id, minutes: 25, at: date(20))
        let data = PomodoroLedger.encode(ledger)
        XCTAssertEqual(PomodoroLedger.decode(data), ledger)
        XCTAssertEqual(PomodoroLedger.decode(nil), PomodoroLedger())
        XCTAssertEqual(PomodoroLedger.decode(Data("garbage".utf8)), PomodoroLedger())
    }

    func testRecordsAreCappedToKeepStorageSmall() {
        var ledger = PomodoroLedger()
        for i in 0..<(PomodoroLedger.maxRecords + 25) {
            ledger = ledger.starting(taskID: nil, minutes: 25, at: date(1).addingTimeInterval(Double(i)))
                .completing(at: date(1).addingTimeInterval(Double(i) + 1))
        }
        XCTAssertEqual(ledger.records.count, PomodoroLedger.maxRecords)
    }
}
