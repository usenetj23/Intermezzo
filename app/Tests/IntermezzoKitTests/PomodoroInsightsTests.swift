import XCTest
@testable import IntermezzoKit

final class PomodoroInsightsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// One finished pomodoro starting at `start`, with the given signals.
    private func run(_ ledger: PomodoroLedger, start: Date, minutes: Int = 25, project: String = "",
                     internalCount: Int = 0, external: Int = 0, switches: Int = 0, active: Int = 0) -> PomodoroLedger {
        var l = ledger.addingTask(title: "t", estimate: 1, project: project)
        let id = l.tasks.last!.id
        l = l.starting(taskID: id, minutes: minutes, at: start)
        for _ in 0..<internalCount { l = l.recordingInterruption(.internal) }
        for _ in 0..<external { l = l.recordingInterruption(.external) }
        l = l.recordingActivity(appSwitches: switches, activeSeconds: active)
        return l.completing(at: start.addingTimeInterval(Double(minutes) * 60))
    }

    // MARK: - projects and real time

    func testProjectIsKeptOnRecord() {
        let l = run(PomodoroLedger(), start: date(20, 9), project: "Alpha")
        XCTAssertEqual(l.records[0].project, "Alpha")
    }

    func testActualSecondsComeFromStartAndEnd() {
        let l = run(PomodoroLedger(), start: date(20, 9), minutes: 25)
        XCTAssertEqual(l.records[0].actualSeconds, 25 * 60)
    }

    func testProjectTotalsGroupAndSortByTime() {
        var l = PomodoroLedger()
        l = run(l, start: date(20, 9), minutes: 25, project: "Alpha")
        l = run(l, start: date(20, 10), minutes: 25, project: "Beta")
        l = run(l, start: date(20, 11), minutes: 50, project: "Beta")
        l = run(l, start: date(20, 13), minutes: 25, project: "")
        let totals = l.projectTotals(from: date(20, 0), to: date(21, 0))
        XCTAssertEqual(totals.map(\.project), ["Beta", "Alpha", ""])
        XCTAssertEqual(totals[0].seconds, 75 * 60)
        XCTAssertEqual(totals[0].count, 2)
    }

    func testProjectTotalsRespectTheRange() {
        var l = PomodoroLedger()
        l = run(l, start: date(19, 9), project: "Alpha")
        l = run(l, start: date(20, 9), project: "Alpha")
        XCTAssertEqual(l.projectTotals(from: date(20, 0), to: date(21, 0)).first?.count, 1)
    }

    func testOldStoredDataWithoutNewFieldsStillDecodes() {
        let json = """
        {"tasks":[{"id":"\(UUID().uuidString)","title":"Old","estimate":2,"done":1,"isFinished":false}],
         "records":[{"date":0,"taskTitle":"Old","minutes":25,"internalInterruptions":1,"externalInterruptions":0}],
         "voided":[]}
        """
        let ledger = PomodoroLedger.decode(Data(json.utf8))
        XCTAssertEqual(ledger.tasks.count, 1)
        XCTAssertEqual(ledger.tasks[0].project, "")
        XCTAssertEqual(ledger.records.count, 1)
        XCTAssertEqual(ledger.records[0].appSwitches, 0)
    }

    // MARK: - golden hours

    func testGoldenHourIsTheCalmestHourWithEnoughSamples() {
        var l = PomodoroLedger()
        for day in 14...16 {                                   // 9:00: noisy
            l = run(l, start: date(day, 9), internalCount: 2, external: 1, switches: 20)
        }
        for day in 14...16 {                                   // 10:00: calm
            l = run(l, start: date(day, 10), switches: 3)
        }
        let golden = l.goldenHours(calendar: cal, minSamples: 3)
        XCTAssertEqual(golden.first?.hour, 10)
        XCTAssertEqual(golden.last?.hour, 9)
        XCTAssertLessThan(golden[0].disruptions, golden[1].disruptions)
    }

    func testHoursWithTooFewSamplesAreIgnored() {
        var l = PomodoroLedger()
        l = run(l, start: date(14, 9), switches: 1)
        l = run(l, start: date(15, 9), switches: 1)
        XCTAssertTrue(l.goldenHours(calendar: cal, minSamples: 3).isEmpty)
    }

    // MARK: - day forecast

    private let cycle = PomodoroForecast.Cycle(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longEvery: 4)

    func testForecastFitsEverythingWhenTheDayIsFree() {
        let f = PomodoroForecast.plan(pomodoros: 4, from: date(20, 9), until: date(20, 17), busy: [], cycle: cycle, startingAtIndex: 0)
        XCTAssertEqual(f.fitting, 4)
        // 25+5, 25+5, 25+5, 25 (no break needed after the last one) = 115 min
        XCTAssertEqual(f.finishAt, date(20, 10, 55))
        XCTAssertEqual(f.spill, 0)
    }

    func testForecastUsesLongBreakEveryNth() {
        let f = PomodoroForecast.plan(pomodoros: 5, from: date(20, 9), until: date(20, 17), busy: [], cycle: cycle, startingAtIndex: 0)
        // 25+5, 25+5, 25+5, 25+15, 25 = 155 min
        XCTAssertEqual(f.finishAt, date(20, 11, 35))
    }

    func testForecastSkipsMeetings() {
        let meeting = DateInterval(start: date(20, 9, 30), end: date(20, 10, 30))
        let f = PomodoroForecast.plan(pomodoros: 2, from: date(20, 9), until: date(20, 17), busy: [meeting], cycle: cycle, startingAtIndex: 0)
        // first pomodoro 9:00-9:25, break to 9:30, meeting to 10:30, second 10:30-10:55
        XCTAssertEqual(f.finishAt, date(20, 10, 55))
        XCTAssertEqual(f.fitting, 2)
    }

    func testForecastReportsWhatDoesNotFitBeforeTheEndOfWork() {
        let f = PomodoroForecast.plan(pomodoros: 6, from: date(20, 9), until: date(20, 10, 30), busy: [], cycle: cycle, startingAtIndex: 0)
        XCTAssertEqual(f.fitting, 3)               // 9:00-9:25, 9:30-9:55, 10:00-10:25
        XCTAssertEqual(f.spill, 3)
        XCTAssertNil(f.finishAt)
    }

    func testForecastWithNothingPlannedIsEmpty() {
        let f = PomodoroForecast.plan(pomodoros: 0, from: date(20, 9), until: date(20, 17), busy: [], cycle: cycle, startingAtIndex: 0)
        XCTAssertEqual(f.fitting, 0)
        XCTAssertNil(f.finishAt)
    }
}
