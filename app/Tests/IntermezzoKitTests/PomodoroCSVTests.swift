import XCTest
@testable import IntermezzoKit

final class PomodoroCSVTests: XCTestCase {
    private let cal = Calendar.current
    private let header = "date,start,end,project,client,task,minutes,actual_minutes,internal_interruptions,external_interruptions,app_switches,billable,amount,currency"

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func record(_ day: Int = 20, project: String = "Alpha", task: String = "Write",
                        seconds: Int = 1500) -> PomodoroRecord {
        let start = date(day, 9)
        return PomodoroRecord(date: start.addingTimeInterval(Double(seconds)), startedAt: start, taskID: nil,
                              taskTitle: task, project: project, minutes: 25, actualSeconds: seconds,
                              internalInterruptions: 1, externalInterruptions: 2, appSwitches: 3, activeSeconds: 0)
    }

    private func make(_ r: [PomodoroRecord], _ p: [PomodoroProject] = []) -> [String] {
        PomodoroCSV.make(records: r, projects: p, from: date(1, 0), to: date(31, 0))
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func testCSVHasExactHeaderAndOneLinePerRecord() {
        XCTAssertEqual(make([]), [header])
        let lines = make([record(), record(21)])
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], header)
        XCTAssertTrue(lines[1].hasPrefix("2026-10-20,2026-10-20T09:00:00,2026-10-20T09:25:00,Alpha,,Write,25,25.0,1,2,3,false,,"))
    }

    func testCSVEscapesCommasAndQuotes() {
        let lines = make([record(task: "Tasks, \"big\"")])
        XCTAssertTrue(lines[1].contains(",\"Tasks, \"\"big\"\"\","))
    }

    func testCSVAmountOnlyForBillable() {
        let billable = PomodoroProject(name: "Alpha", client: "ACME", hourlyRate: 120, currency: "eur", billable: true)
        let free = PomodoroProject(name: "Beta", hourlyRate: 120, billable: false)
        let lines = make([record(seconds: 1800), record(project: "Beta", seconds: 1800)], [billable, free])
        XCTAssertTrue(lines[1].hasSuffix(",true,60.00,EUR"))
        XCTAssertTrue(lines[1].contains(",ACME,"))
        XCTAssertTrue(lines[2].hasSuffix(",false,,"))
    }
}
