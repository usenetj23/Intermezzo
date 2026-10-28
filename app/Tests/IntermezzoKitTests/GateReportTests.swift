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
