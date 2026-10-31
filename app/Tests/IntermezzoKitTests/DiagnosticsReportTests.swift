import XCTest
@testable import IntermezzoKit

final class DiagnosticsReportTests: XCTestCase {
    func testMarkdownListsSectionsInOrderInsideACodeBlock() {
        let report = DiagnosticsReport(sections: [
            .init("System", [("macOS", "26.0"), ("Chip", "Apple M4")]),
            .init("Empty", []),
            .init("Displays", [("1", "Built-in 3024x1964")]),
        ])
        let text = report.markdown()
        XCTAssertTrue(text.hasPrefix("### Intermezzo diagnostics"))
        XCTAssertTrue(text.hasSuffix("```"))
        XCTAssertFalse(text.contains("[Empty]"))
        XCTAssertLessThan(text.range(of: "[System]")!.lowerBound, text.range(of: "[Displays]")!.lowerBound)
        XCTAssertTrue(text.contains("Chip   Apple M4"))   // names padded to one column
    }

    func testLogExcerptKeepsOnlyAllowedTopicsAndTheNewestLines() {
        let stamp = "2026-10-30 09:11:00 +0000"
        let raw = [
            "\(stamp) light: neutral displays [1]",
            "\(stamp) workdetect wifi=HomeNetwork",
            "\(stamp) media: pausing for the break (Music)",
            "not a log line light",
            "\(stamp) light.123 write (fade): #1=6400 K",
            "\(stamp) location: one-shot failed (kCLErrorDomain 0)",
            "\(stamp) weather: refresh requested",
        ]
        let lines = DiagnosticsReport.safeLogLines(raw, home: "/Users/anna", limit: 4)
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("media:"))
        XCTAssertTrue(lines[1].contains("light.123"))
        XCTAssertTrue(lines[2].contains("location:"))
        XCTAssertTrue(lines[3].contains("weather:"))
        XCTAssertFalse(lines.joined().contains("HomeNetwork"))
    }

    func testPathsDoNotNameThePerson() {
        let home = "/Users/anna"
        XCTAssertEqual(DiagnosticsReport.redact("open /Users/anna/Library/Logs/x", home: home), "open ~/Library/Logs/x")
        XCTAssertEqual(DiagnosticsReport.redact("/Users/bob/Documents", home: home), "/Users/<user>/Documents")
    }

    func testLogSectionAppearsOnlyWithLines() {
        XCTAssertFalse(DiagnosticsReport(sections: [.init("S", [("a", "b")])]).markdown().contains("Log excerpt"))
        XCTAssertTrue(DiagnosticsReport(sections: [], logLines: ["x"]).markdown().contains("Log excerpt"))
    }
}
