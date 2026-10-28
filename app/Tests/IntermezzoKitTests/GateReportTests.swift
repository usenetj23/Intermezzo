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
