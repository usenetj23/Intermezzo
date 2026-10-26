import XCTest
@testable import IntermezzoKit

final class RuleScriptAuthorTests: XCTestCase {
    func testCleanExtractsFencedScriptAndAddsHeader() {
        let answer = "Oto skrypt:\n```applescript\ntell application \"System Events\"\n  return exists process \"Zoom\"\nend tell\n```\nPowodzenia"
        let script = RuleScriptAuthor.clean(answer, fallbackName: "Zoom")
        XCTAssertTrue(script.hasPrefix("-- Intermezzo Rule: Zoom\n"))
        XCTAssertTrue(script.contains("return exists process \"Zoom\""))
        XCTAssertFalse(script.contains("```"))
        XCTAssertFalse(script.contains("Powodzenia"))
    }

    func testCleanKeepsExistingHeaderAndPlainText() {
        let plain = "-- Intermezzo Rule: Moja\nreturn false\n"
        XCTAssertEqual(RuleScriptAuthor.clean(plain, fallbackName: "X"), "-- Intermezzo Rule: Moja\nreturn false")
        let fenced = "```\n-- Intermezzo Rule: Inna\nreturn true\n```"
        XCTAssertEqual(RuleScriptAuthor.clean(fenced, fallbackName: "X"), "-- Intermezzo Rule: Inna\nreturn true")
    }

    func testRisksFindsEachConstructOnce() {
        let script = "do shell script \"rm -rf x\"\nDELETE file\nset x to \"firmware\"\ndo shell script \"ls\""
        XCTAssertEqual(RuleScriptAuthor.risks(in: script), ["do shell script", "rm", "delete"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "return false"), [])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "tell app \"System Events\" to Keystroke \"a\""), ["keystroke"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "set text item delimiters to \"x\"\nreturn confirm"), [])
    }

    func testPromptCarriesContractAndExamplesButNoUserScripts() {
        let request = RuleScriptAuthor.prompt(description: "gdy działa Zoom", examples: ["-- Intermezzo Rule: Przykład\nreturn false"], language: "pl")
        XCTAssertTrue(request.system.contains("-- Intermezzo Rule:"))
        XCTAssertTrue(request.system.contains("true") && request.system.contains("false"))
        XCTAssertTrue(request.system.contains("-- Setting:") || request.system.contains("-- Nastawa:"))
        XCTAssertTrue(request.system.contains("Przykład"))
        XCTAssertTrue(request.system.contains("Polish"))
        XCTAssertEqual(request.user, "gdy działa Zoom")
        XCTAssertFalse((request.system + request.user).contains("/Users/"))
        XCTAssertNil(request.jsonSchema)
    }

    func testRepairPromptIncludesCompilerErrorAndScript() {
        let request = RuleScriptAuthor.repairPrompt(description: "opis", script: "return truee", compilerError: "Expected end of line", language: "en")
        XCTAssertTrue(request.user.contains("Expected end of line"))
        XCTAssertTrue(request.user.contains("return truee"))
        XCTAssertTrue(request.user.contains("opis"))
        XCTAssertTrue(request.system.contains("English"))
    }

    func testRisksCoverMoreWaysToActOnTheMac() {
        XCTAssertEqual(RuleScriptAuthor.risks(in: "tell application \"Zoom\" to quit"), ["quit"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "tell application \"X\" to activate"), ["activate"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "launch application \"X\""), ["launch"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "click button 1 of window 1"), ["click"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "run script file \"x\""), ["run script"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "tell app \"Safari\" to do JavaScript \"1\" in tab 1"), ["do javascript"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "set f to open for access file \"x\" with write permission"), ["open for access"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "«event sysoexec» \"ls\""), ["do shell script"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "do ¬\n    shell script \"ls\""), ["do shell script"])
        XCTAssertEqual(RuleScriptAuthor.risks(in: "set quitFlag to false\nset relaunched to true\nreturn false"), [])
    }

    func testApplicationReferencesAreFound() {
        let script = "tell application \"Zoom\"\nend tell\ntell application id \"com.apple.Safari\" to get name\ntell application \"Zoom\" to get name"
        let refs = RuleScriptAuthor.applicationReferences(in: script)
        XCTAssertEqual(refs.names, ["Zoom"])
        XCTAssertEqual(refs.bundleIDs, ["com.apple.Safari"])
        let none = RuleScriptAuthor.applicationReferences(in: "return false")
        XCTAssertTrue(none.names.isEmpty && none.bundleIDs.isEmpty)
    }
}
