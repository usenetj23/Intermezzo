import XCTest
@testable import IntermezzoKit

final class ScriptSettingsTests: XCTestCase {
    private let source = """
    -- Intermezzo Rule: Test
    -- Nastawa: Aplikacje
    property apps : {"zoom.us", "Microsoft Teams"}
    property fromHour : 12
    property enabled : true
    property marker : "Meet -"
    tell application "System Events"
        set frontName to name of first process whose frontmost is true
    end tell
    return apps contains frontName
    """

    func testParsesSupportedProperties() {
        let s = ScriptSettings.parse(source)
        XCTAssertEqual(s.map(\.name), ["apps", "fromHour", "enabled", "marker"])
        XCTAssertEqual(s[0].value, .list(["zoom.us", "Microsoft Teams"]))
        XCTAssertEqual(s[0].comment, "Aplikacje")
        XCTAssertEqual(s[1].value, .number(12))
        XCTAssertNil(s[1].comment)
        XCTAssertEqual(s[2].value, .flag(true))
        XCTAssertEqual(s[3].value, .text("Meet -"))
    }

    func testSkipsUnsupportedValuesAndNonPropertyLines() {
        let s = ScriptSettings.parse("""
        property d : current date
        property mixed : {1, "a"}
        set apps to {"x"}
        property empty : {}
        """)
        XCTAssertEqual(s.map(\.name), ["empty"])
        XCTAssertEqual(s[0].value, .list([]))
    }

    func testApplyRewritesOnlyChangedLines() {
        var s = ScriptSettings.parse(source)
        s[0].value = .list(["Webex", "Say \"hi\"", "back\\slash"])
        s[1].value = .number(13)
        let out = ScriptSettings.apply(s, to: source)
        XCTAssertTrue(out.contains(#"property apps : {"Webex", "Say \"hi\"", "back\\slash"}"#))
        XCTAssertTrue(out.contains("property fromHour : 13"))
        XCTAssertTrue(out.contains("return apps contains frontName"))
        XCTAssertEqual(ScriptSettings.parse(out)[0].value, .list(["Webex", "Say \"hi\"", "back\\slash"]))
    }

    func testApplyKeepsIndentationAndUnknownNames() {
        let src = "  property n : 5\nreturn n"
        let out = ScriptSettings.apply([ScriptSetting(name: "n", value: .number(7)),
                                        ScriptSetting(name: "other", value: .number(1))], to: src)
        XCTAssertEqual(out, "  property n : 7\nreturn n")
    }

    func testListFromCommaText() {
        XCTAssertEqual(ScriptSettings.list(fromCommaText: " a, b ,,c "), ["a", "b", "c"])
        XCTAssertEqual(ScriptSettings.commaText(["a", "b"]), "a, b")
    }

    func testRuleNameFromHeader() {
        XCTAssertEqual(ScriptSettings.ruleName(in: source), "Test")
        XCTAssertNil(ScriptSettings.ruleName(in: "return true"))
        XCTAssertEqual(ScriptSettings.withRuleName("Nowa nazwa", in: source).components(separatedBy: "\n").first,
                       "-- Intermezzo Rule: Nowa nazwa")
        XCTAssertEqual(ScriptSettings.withRuleName("X", in: "return true"), "-- Intermezzo Rule: X\nreturn true")
    }

    func testFileSlug() {
        XCTAssertEqual(ScriptSettings.fileSlug("Spotkanie w Łodzi: żółć!"), "Spotkanie-w-Lodzi-zolc")
        XCTAssertEqual(ScriptSettings.fileSlug("  ***  "), "Skrypt")
        XCTAssertEqual(ScriptSettings.uniqueSlug("A", taken: ["A", "A-2"]), "A-3")
        XCTAssertEqual(ScriptSettings.uniqueSlug("B", taken: ["A"]), "B")
    }
}
