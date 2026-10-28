import XCTest
@testable import IntermezzoKit

final class GateReportTests: XCTestCase {
    private func factor(_ id: String, _ group: GateGroup, _ verdict: GateVerdict, info: Bool = false) -> GateFactor {
        GateFactor(id: id, group: group, title: id, verdict: verdict, detail: "", informational: info)
    }

    func testHeadlineCountsBlockersWithPolishPlural() {
        func headline(_ n: Int) -> String {
            GateReport(factors: (0..<n).map { factor("b\($0)", .schedule, .blocking) }).headline
        }
        XCTAssertEqual(headline(1), "Timer wstrzymany: 1 powód")
        XCTAssertEqual(headline(2), "Timer wstrzymany: 2 powody")
        XCTAssertEqual(headline(5), "Timer wstrzymany: 5 powodów")
        XCTAssertEqual(headline(12), "Timer wstrzymany: 12 powodów")
        XCTAssertEqual(headline(22), "Timer wstrzymany: 22 powody")
    }

    func testRunningAndBreakHeadlines() {
        XCTAssertEqual(GateReport(running: true).headline, "Timer działa")
        XCTAssertEqual(GateReport(running: true, onBreak: true).headline, "Trwa przerwa")
    }

    func testInformationalFactorsNeverCountAsBlockers() {
        let report = GateReport(factors: [factor("lan", .zone, .blocking, info: true)])
        XCTAssertTrue(report.blockers.isEmpty)
        XCTAssertEqual(report.verdict(of: .zone), .inactive)
    }

    func testGroupVerdictIsTheWorstOne() {
        let report = GateReport(factors: [
            factor("a", .zone, .passing), factor("b", .zone, .blocking),
            factor("c", .detection, .passing), factor("d", .user, .inactive),
        ])
        XCTAssertEqual(report.verdict(of: .zone), .blocking)
        XCTAssertEqual(report.verdict(of: .detection), .passing)
        XCTAssertEqual(report.verdict(of: .user), .inactive)
        XCTAssertEqual(report.verdict(of: .schedule), .inactive)
    }
}

final class FocusModesTests: XCTestCase {
    func testActiveModesComeOnlyFromAssertionRecords() {
        let json = """
        {"data":[{"storeAssertionRecords":[
            {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}},
            {"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.sleep.sleep-mode"}}],
          "storeInvalidationRecords":[
            {"invalidationRecordAssertion":{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.driving"}}}]}]}
        """
        XCTAssertEqual(FocusModes.activeModeIDs(assertions: Data(json.utf8)),
                       ["com.apple.focus.work", "com.apple.sleep.sleep-mode"])
    }

    func testNoActiveModeAndGarbageGiveEmpty() {
        XCTAssertTrue(FocusModes.activeModeIDs(assertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8)).isEmpty)
        XCTAssertTrue(FocusModes.activeModeIDs(assertions: Data("x".utf8)).isEmpty)
    }

    func testNamesAreFoundAtAnyDepth() {
        let json = """
        {"data":[{"modeConfigurations":{"a":{"mode":{"modeIdentifier":"com.apple.focus.work","name":"Praca"}},
                                         "b":{"mode":{"modeIdentifier":"ABC-1","name":"Daily"}}}}]}
        """
        let names = FocusModes.names(configurations: Data(json.utf8))
        XCTAssertEqual(names["com.apple.focus.work"], "Praca")
        XCTAssertEqual(names["ABC-1"], "Daily")
    }

    func testDisplayNameFallsBackToBuiltInThenId() {
        XCTAssertEqual(FocusModes.displayName(for: "com.apple.sleep.sleep-mode", names: [:]), "Sen")
        XCTAssertEqual(FocusModes.displayName(for: "XYZ", names: [:]), "XYZ")
        XCTAssertEqual(FocusModes.displayName(for: "XYZ", names: ["XYZ": "Moj"]), "Moj")
    }

    func testRoleDefaultsWorkForWorkModeAndPauseForTheRest() {
        XCTAssertEqual(FocusModes.role(for: FocusModes.workModeID, stored: [:]), .work)
        XCTAssertEqual(FocusModes.role(for: "ABC", stored: [:]), .pause)
        XCTAssertEqual(FocusModes.role(for: "ABC", stored: ["ABC": .ignore]), .ignore)
        XCTAssertEqual(FocusModes.role(for: FocusModes.workModeID, stored: [FocusModes.workModeID: .pause]), .pause)
    }
}

final class StatusTintTests: XCTestCase {
    private func blocker(_ id: String) -> GateFactor {
        GateFactor(id: id, group: .detection, title: id, verdict: .blocking, detail: "")
    }

    func testTintFollowsTheTimerState() {
        XCTAssertEqual(GateReport(running: true).tint, .running)
        XCTAssertEqual(GateReport(running: true, onBreak: true).tint, .onBreak)
        XCTAssertEqual(GateReport().tint, .manual)
        XCTAssertEqual(GateReport(factors: [blocker("manual")]).tint, .manual)
        XCTAssertEqual(GateReport(factors: [blocker("meeting")]).tint, .held)
        XCTAssertEqual(GateReport(factors: [blocker("meeting"), blocker("hours")]).tint, .outside)
        XCTAssertEqual(GateReport(factors: [blocker("zone")]).tint, .outside)
    }
}

final class CalendarRulesTests: XCTestCase {
    private func event(_ title: String, calendar: String = "work", allDay: Bool = false, busy: Bool = true,
                       declined: Bool = false) -> CalendarEventInfo {
        CalendarEventInfo(calendarID: calendar, title: title, isAllDay: allDay, isBusy: busy, isDeclined: declined)
    }

    func testEmptyKeywordsMatchAnyTitleInTheChosenCalendar() {
        let rule = CalendarRule(calendarID: "work")
        XCTAssertTrue(CalendarRules.matches(rule, event("Warsztaty szkoleniowe")))
        XCTAssertFalse(CalendarRules.matches(rule, event("Kolacja", calendar: "home")))
    }

    func testKeywordsAreFragmentsOfTheTitleAnyOneIsEnough() {
        let rule = CalendarRule(keywords: "Praca, szkolen")
        XCTAssertTrue(CalendarRules.matches(rule, event("Warsztaty szkoleniowe")))
        XCTAssertTrue(CalendarRules.matches(rule, event("PRACA zdalna")))
        XCTAssertFalse(CalendarRules.matches(rule, event("Siłownia")))
    }

    func testBusyAllDayAndDeclinedFiltersApplyOnlyWhenSwitchedOn() {
        let strict = CalendarRule()
        XCTAssertFalse(CalendarRules.matches(strict, event("x", busy: false)))
        XCTAssertFalse(CalendarRules.matches(strict, event("x", allDay: true)))
        XCTAssertFalse(CalendarRules.matches(strict, event("x", declined: true)))
        let loose = CalendarRule(onlyBusy: false, skipAllDay: false, skipDeclined: false)
        XCTAssertTrue(CalendarRules.matches(loose, event("x", allDay: true, busy: false, declined: true)))
    }

    func testDisabledRuleNeverMatchesAndFirstMatchWins() {
        let off = CalendarRule(enabled: false)
        XCTAssertFalse(CalendarRules.matches(off, event("x")))
        let a = CalendarRule(calendarID: "home"), b = CalendarRule(calendarID: "work")
        XCTAssertEqual(CalendarRules.firstMatch([a, b], event("x"))?.id, b.id)
    }

    func testLegacyRuleKeepsTheOldBehaviour() {
        let rule = CalendarRules.legacy(keywords: "work, praca")
        XCTAssertTrue(CalendarRules.matches(rule, event("Praca", calendar: "anything", allDay: true, busy: false)))
        XCTAssertFalse(CalendarRules.matches(rule, event("Szkolenie")))
    }

    func testRulesRoundTripAndGarbageGivesEmpty() {
        let rules = [CalendarRule(calendarID: "w", calendarName: "Praca", keywords: "a")]
        XCTAssertEqual(CalendarRules.decode(CalendarRules.encode(rules)), rules)
        XCTAssertTrue(CalendarRules.decode(Data("x".utf8)).isEmpty)
        XCTAssertTrue(CalendarRules.decode(nil).isEmpty)
    }
}
