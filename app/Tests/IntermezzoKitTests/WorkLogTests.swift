import XCTest
@testable import IntermezzoKit

final class WorkLogTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    /// Monday 2026-10-19 at hh:mm, Warsaw time.
    private func mon(_ h: Int, _ m: Int = 0, plusDays: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: 19 + plusDays, hour: h, minute: m))!
    }

    /// 6:30–14:30, Monday to Friday.
    private var schedule: WorkSchedule {
        WorkSchedule(daysMask: 0b001_1111, hours: .init(start: 6 * 60 + 30, end: 14 * 60 + 30))
    }

    // MARK: Tracker

    func testActivityInTheZoneOpensAndExtendsASession() {
        var t = WorkSessionTracker()
        XCTAssertNil(t.observe(now: mon(6, 40), lastInputAt: mon(6, 40), place: .office))
        XCTAssertNil(t.observe(now: mon(7, 0), lastInputAt: mon(6, 59), place: .office))
        XCTAssertEqual(t.current?.start, mon(6, 40))
        XCTAssertEqual(t.current?.end, mon(6, 59))
    }

    func testShortAbsenceIsBridgedLongOneSplits() {
        var t = WorkSessionTracker(bridge: 30 * 60)
        _ = t.observe(now: mon(8), lastInputAt: mon(8), place: .office)
        // 20 minutes away (a meeting), back at the desk: same session.
        XCTAssertNil(t.observe(now: mon(8, 20), lastInputAt: mon(8, 20), place: .office))
        XCTAssertEqual(t.current?.start, mon(8))
        // An hour and a half away: the first session closes, a new one starts.
        let closed = t.observe(now: mon(9, 50), lastInputAt: mon(9, 50), place: .office)
        XCTAssertEqual(closed?.start, mon(8))
        XCTAssertEqual(closed?.end, mon(8, 20))
        XCTAssertEqual(t.current?.start, mon(9, 50))
    }

    func testLeavingTheZoneClosesAfterTheBridge() {
        var t = WorkSessionTracker(bridge: 30 * 60)
        _ = t.observe(now: mon(14), lastInputAt: mon(14), place: .office)
        XCTAssertNil(t.observe(now: mon(14, 10), lastInputAt: mon(14, 10), place: nil))
        XCTAssertEqual(t.current?.end, mon(14))         // activity outside the zone is not work
        let closed = t.observe(now: mon(14, 31), lastInputAt: mon(14, 31), place: nil)
        XCTAssertEqual(closed?.end, mon(14))
        XCTAssertNil(t.current)
    }

    func testIdleInputDoesNotExtend() {
        var t = WorkSessionTracker()
        _ = t.observe(now: mon(10), lastInputAt: mon(10), place: .office)
        _ = t.observe(now: mon(10, 5), lastInputAt: mon(10), place: .office)
        XCTAssertEqual(t.current?.end, mon(10))
    }

    func testActiveSecondsCountOnlyWhileInputIsRecent() {
        var t = WorkSessionTracker(activeWithin: 120)
        _ = t.observe(now: mon(10), lastInputAt: mon(10), place: .office)
        for s in stride(from: 15, through: 300, by: 15) {   // input stops after 60 s
            let input = mon(10).addingTimeInterval(min(Double(s), 60))
            _ = t.observe(now: mon(10).addingTimeInterval(Double(s)), lastInputAt: input, place: .office)
        }
        // Active until 60 s + 120 s grace = 180 s.
        XCTAssertEqual(t.current!.activeSeconds, 180, accuracy: 15)
    }

    func testResumeContinuesAStoredSession() {
        var t = WorkSessionTracker(resuming: WorkInterval(start: mon(7), end: mon(9), activeSeconds: 3600))
        XCTAssertNil(t.observe(now: mon(9, 10), lastInputAt: mon(9, 10), place: .office))
        XCTAssertEqual(t.current?.start, mon(7))
    }

    // MARK: Day summary

    func testRegularDayHasNoOvertime() {
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(14, 30))], schedule: schedule, calendar: cal)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].worked, 8 * 3600, accuracy: 1)
        XCTAssertEqual(d[0].overtime, 0, accuracy: 1)
        XCTAssertEqual(d[0].first, mon(6, 30))
        XCTAssertEqual(d[0].last, mon(14, 30))
    }

    func testStayingUntilFourIsOvertimeRoundedDownToFifteen() {
        // Breakdown: left at 16:07 instead of 14:30 → 1 h 37 min overtime, billed 1 h 30 min.
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(16, 7))], schedule: schedule, calendar: cal)
        XCTAssertEqual(d[0].overtime, 97 * 60, accuracy: 1)
        XCTAssertEqual(d[0].billableOvertime, 90 * 60, accuracy: 1)
        XCTAssertEqual(d[0].inHours, 8 * 3600, accuracy: 1)
    }

    func testEarlyStartAlsoCountsAsOvertime() {
        let d = WorkLog.summarize([WorkInterval(start: mon(5, 45), end: mon(14, 30))], schedule: schedule, calendar: cal)
        XCTAssertEqual(d[0].overtime, 45 * 60, accuracy: 1)
    }

    func testWeekendIsAllOvertime() {
        let sat = mon(10, plusDays: 5)
        let d = WorkLog.summarize([WorkInterval(start: sat, end: sat.addingTimeInterval(2 * 3600 + 10 * 60))],
                                  schedule: schedule, calendar: cal)
        XCTAssertFalse(d[0].isWorkday)
        XCTAssertEqual(d[0].overtime, 130 * 60, accuracy: 1)
        XCTAssertEqual(d[0].billableOvertime, 120 * 60, accuracy: 1)
    }

    func testSessionOverMidnightIsSplitIntoTwoDays() {
        let d = WorkLog.summarize([WorkInterval(start: mon(22), end: mon(1, plusDays: 1))], schedule: schedule, calendar: cal)
        XCTAssertEqual(d.count, 2)
        XCTAssertEqual(d[0].worked, 2 * 3600, accuracy: 1)
        XCTAssertEqual(d[1].worked, 3600, accuracy: 1)
    }

    func testSeveralSessionsInADayAddUp() {
        let d = WorkLog.summarize([WorkInterval(start: mon(7), end: mon(11), activeSeconds: 3 * 3600),
                                   WorkInterval(start: mon(12), end: mon(15), activeSeconds: 3600)],
                                  schedule: schedule, calendar: cal)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d[0].worked, 7 * 3600, accuracy: 1)
        XCTAssertEqual(d[0].overtime, 30 * 60, accuracy: 1)   // 14:30–15:00
        XCTAssertEqual(d[0].active, 4 * 3600, accuracy: 1)
        XCTAssertEqual(d[0].first, mon(7))
        XCTAssertEqual(d[0].last, mon(15))
    }

    func testPerDayHoursOverrideTheGeneralWindow() {
        let friday = WeekHours().setting(.init(start: 6 * 60 + 30, end: 12 * 60 + 30), forDay: 4)
        let s = WorkSchedule(daysMask: 0b001_1111, hours: .init(start: 390, end: 870), perDay: friday)
        let fri = mon(6, 30, plusDays: 4)
        let d = WorkLog.summarize([WorkInterval(start: fri, end: fri.addingTimeInterval(8 * 3600))], schedule: s, calendar: cal)
        XCTAssertEqual(d[0].overtime, 2 * 3600, accuracy: 1)
    }

    // MARK: Formatting

    func testDurationFormat() {
        XCTAssertEqual(WorkLog.hm(0), "0:00")
        XCTAssertEqual(WorkLog.hm(97 * 60 + 20), "1:37")
        XCTAssertEqual(WorkLog.hm(10 * 3600 + 5 * 60), "10:05")
    }

    func testCSVHasAHeaderAndOneRowPerDay() {
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(16, 7), activeSeconds: 6 * 3600)],
                                  schedule: schedule, calendar: cal)
        let lines = WorkLog.csv(d, calendar: cal).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(String(lines[1]), "2026-10-19;06:30;16:07;9:37;9:37;0:00;8:00;1:37;1:30;0:00;0:00;6:00;;")
    }

    // MARK: Remote work

    func testChangingPlaceSplitsTheInterval() {
        var t = WorkSessionTracker()
        _ = t.observe(now: mon(8), lastInputAt: mon(8), place: .office)
        let closed = t.observe(now: mon(8, 10), lastInputAt: mon(8, 10), place: .remote)
        XCTAssertEqual(closed?.place, .office)
        XCTAssertEqual(closed?.end, mon(8))
        XCTAssertEqual(t.current?.place, .remote)
        XCTAssertEqual(t.current?.start, mon(8, 10))
    }

    func testRemoteOvertimeIsCountedApart() {
        // Office 6:30–14:30, then from home on the VPN 18:00–19:40.
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(14, 30)),
                                   WorkInterval(start: mon(18), end: mon(19, 40), place: .remote)],
                                  schedule: schedule, calendar: cal)[0]
        XCTAssertEqual(d.worked, 9 * 3600 + 40 * 60, accuracy: 1)
        XCTAssertEqual(d.remote, 100 * 60, accuracy: 1)
        XCTAssertEqual(d.overtime, 100 * 60, accuracy: 1)
        XCTAssertEqual(d.remoteOvertime, 100 * 60, accuracy: 1)
        XCTAssertEqual(d.officeOvertime, 0, accuracy: 1)
        XCTAssertEqual(d.billableRemoteOvertime, 90 * 60, accuracy: 1)
        XCTAssertEqual(d.billableOvertime, 90 * 60, accuracy: 1)
    }

    func testOfficeAndRemoteOvertimeAreRoundedSeparately() {
        // 20 min office overtime + 20 min remote overtime → 15 + 15, not 30 from 40.
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(14, 50)),
                                   WorkInterval(start: mon(20), end: mon(20, 20), place: .remote)],
                                  schedule: schedule, calendar: cal)[0]
        XCTAssertEqual(d.billableOfficeOvertime, 15 * 60, accuracy: 1)
        XCTAssertEqual(d.billableRemoteOvertime, 15 * 60, accuracy: 1)
        XCTAssertEqual(d.billableOvertime, 30 * 60, accuracy: 1)
    }

    // MARK: Corrections

    func testOverlappingIntervalsCountOnce() {
        // A manual entry covering time that was also recorded automatically.
        let d = WorkLog.summarize([WorkInterval(start: mon(7), end: mon(12)),
                                   WorkInterval(start: mon(11), end: mon(15), isCorrection: true)],
                                  schedule: schedule, calendar: cal)[0]
        XCTAssertEqual(d.worked, 8 * 3600, accuracy: 1)
        XCTAssertEqual(d.overtime, 30 * 60, accuracy: 1)
        XCTAssertTrue(d.hasCorrections)
    }

    func testNotesAndCorrectionFlagReachTheCSV() {
        let d = WorkLog.summarize([WorkInterval(start: mon(6, 30), end: mon(14, 30)),
                                   WorkInterval(start: mon(14, 30), end: mon(16), isCorrection: true,
                                                note: "awaria linii; bez laptopa")],
                                  schedule: schedule, calendar: cal)
        XCTAssertEqual(d[0].notes, ["awaria linii; bez laptopa"])
        let row = String(WorkLog.csv(d, calendar: cal).split(separator: "\n")[1])
        XCTAssertTrue(row.hasSuffix(";tak;awaria linii, bez laptopa"), row)
    }
}
