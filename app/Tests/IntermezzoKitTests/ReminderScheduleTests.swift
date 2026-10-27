import XCTest
@testable import IntermezzoKit

final class ReminderScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    // 2026-10-20 is a Tuesday (weekday 3).
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: micro-reminders

    func testReminderIsDueOnceItsIntervalHasPassed() {
        let r = MicroReminder(title: "Water", intervalMinutes: 60)
        let since = date(20, 9)
        XCTAssertTrue(ReminderSchedule.dueMicro([r], lastShown: [:], since: since, now: date(20, 9, 59)).isEmpty)
        XCTAssertEqual(ReminderSchedule.dueMicro([r], lastShown: [:], since: since, now: date(20, 10)).count, 1)
    }

    func testShownReminderWaitsAFullIntervalAgain() {
        let r = MicroReminder(title: "Water", intervalMinutes: 60)
        let last = [r.id: date(20, 10)]
        XCTAssertTrue(ReminderSchedule.dueMicro([r], lastShown: last, since: date(20, 9), now: date(20, 10, 59)).isEmpty)
        XCTAssertEqual(ReminderSchedule.dueMicro([r], lastShown: last, since: date(20, 9), now: date(20, 11)).count, 1)
    }

    func testDisabledAndNonsenseIntervalsAreIgnored() {
        var off = MicroReminder(title: "x", intervalMinutes: 5)
        off.enabled = false
        let zero = MicroReminder(title: "y", intervalMinutes: 0)
        XCTAssertTrue(ReminderSchedule.dueMicro([off, zero], lastShown: [:], since: date(20, 9), now: date(20, 12)).isEmpty)
    }

    // MARK: scheduled breaks

    private func lunch(_ days: Set<Int> = [2, 3, 4, 5, 6]) -> ScheduledBreak {
        ScheduledBreak(label: "Lunch", minuteOfDay: 12 * 60, weekdays: days, isLong: true)
    }

    func testScheduledBreakFiresInItsMinuteOnItsWeekday() {
        XCTAssertEqual(ReminderSchedule.dueScheduled([lunch()], lastFired: [:], now: date(20, 12, 0, 30), calendar: cal).count, 1)
        XCTAssertTrue(ReminderSchedule.dueScheduled([lunch()], lastFired: [:], now: date(20, 11, 59, 59), calendar: cal).isEmpty)
    }

    func testScheduledBreakIsSkippedOnOtherWeekdays() {
        // 2026-10-24 is a Saturday (7)
        XCTAssertTrue(ReminderSchedule.dueScheduled([lunch()], lastFired: [:], now: date(24, 12, 0, 10), calendar: cal).isEmpty)
    }

    func testScheduledBreakCatchesUpShortlyAfterButNotLater() {
        XCTAssertEqual(ReminderSchedule.dueScheduled([lunch()], lastFired: [:], now: date(20, 12, 1, 59), calendar: cal).count, 1)
        XCTAssertTrue(ReminderSchedule.dueScheduled([lunch()], lastFired: [:], now: date(20, 12, 3), calendar: cal).isEmpty)
    }

    func testScheduledBreakFiresOncePerDay() {
        let b = lunch()
        let fired = [b.id: date(20, 12, 0, 5)]
        XCTAssertTrue(ReminderSchedule.dueScheduled([b], lastFired: fired, now: date(20, 12, 1), calendar: cal).isEmpty)
        XCTAssertEqual(ReminderSchedule.dueScheduled([b], lastFired: fired, now: date(21, 12, 0, 10), calendar: cal).count, 1)
    }

    // MARK: meal windows

    private func breakfast() -> ScheduledBreak {
        ScheduledBreak(label: "Śniadanie", minuteOfDay: 9 * 60, weekdays: [2, 3, 4, 5, 6], isLong: false, customMinutes: 15)
    }

    func testMealDoesNotFireAtItsStartMinute() {
        XCTAssertTrue(ReminderSchedule.dueScheduled([breakfast()], lastFired: [:], now: date(20, 9, 0, 30), calendar: cal).isEmpty)
    }

    func testMealWindowIsOpenOnlyBetweenStartAndEnd() {
        let b = breakfast()
        XCTAssertNil(ReminderSchedule.mealInWindow([b], lastFired: [:], now: date(20, 8, 59, 59), calendar: cal))
        XCTAssertNotNil(ReminderSchedule.mealInWindow([b], lastFired: [:], now: date(20, 9, 12), calendar: cal))
        XCTAssertNil(ReminderSchedule.mealInWindow([b], lastFired: [:], now: date(20, 9, 15), calendar: cal))
    }

    func testMealFallsBackToTheEndOfItsWindow() {
        let b = breakfast()
        XCTAssertEqual(ReminderSchedule.dueScheduled([b], lastFired: [:], now: date(20, 9, 15, 5), calendar: cal).count, 1)
    }

    func testMealAlreadyStartedTodayIsNeitherInWindowNorDue() {
        let b = breakfast()
        let fired = [b.id: date(20, 9, 12)]
        XCTAssertNil(ReminderSchedule.mealInWindow([b], lastFired: fired, now: date(20, 9, 13), calendar: cal))
        XCTAssertTrue(ReminderSchedule.dueScheduled([b], lastFired: fired, now: date(20, 9, 15, 5), calendar: cal).isEmpty)
    }

    // MARK: storage

    func testListsRoundTripAndGarbageGivesEmpty() {
        let list = [MicroReminder(title: "Blink", intervalMinutes: 20)]
        XCTAssertEqual(MicroReminder.decodeList(MicroReminder.encodeList(list)), list)
        XCTAssertTrue(MicroReminder.decodeList(Data("x".utf8)).isEmpty)
        let sched = [lunch()]
        XCTAssertEqual(ScheduledBreak.decodeList(ScheduledBreak.encodeList(sched)), sched)
        XCTAssertTrue(ScheduledBreak.decodeList(nil).isEmpty)
    }

    func testListSavedBeforeCustomLengthsStillDecodes() {
        let json = """
        [{"id":"\(UUID().uuidString)","label":"Lunch","minuteOfDay":720,"weekdays":[2,3],"isLong":true}]
        """
        let list = ScheduledBreak.decodeList(Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertNil(list[0].customMinutes)
        XCTAssertFalse(list[0].askFirst)
        XCTAssertTrue(list[0].enabled)
    }

    func testCustomLengthAndAskFirstSurviveEncoding() {
        let b = ScheduledBreak(label: "Obiad", minuteOfDay: 750, weekdays: [2], isLong: false, customMinutes: 30, askFirst: true)
        XCTAssertEqual(ScheduledBreak.decodeList(ScheduledBreak.encodeList([b])), [b])
    }

    func testMealPresetsHaveTheirOwnLengths() {
        XCTAssertEqual(ScheduledBreak.mealPresets.map(\.customMinutes), [15, 30, 30])
        XCTAssertEqual(ScheduledBreak.mealPresets.map(\.minuteOfDay), [540, 750, 1080])
    }

    func testPresetsAreOffByDefault() {
        XCTAssertFalse(MicroReminder.presets.isEmpty)
        XCTAssertTrue(MicroReminder.presets.allSatisfy { !$0.enabled })
    }
}
