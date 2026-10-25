import XCTest
@testable import IntermezzoKit

final class ScriptRuleResultTests: XCTestCase {
    func testReturnFalseIsNotAHitEvenWithExitCodeZero() {
        // osascript prints "false" and exits 0 for `return false` — that must NOT match.
        XCTAssertFalse(ScriptRuleResult.isHit(exitStatus: 0, output: "false\n"))
        XCTAssertFalse(ScriptRuleResult.isHit(exitStatus: 0, output: "FALSE"))
    }

    func testReturnTrueIsAHit() {
        XCTAssertTrue(ScriptRuleResult.isHit(exitStatus: 0, output: "true\n"))
    }

    func testPlainExitCodeScriptsStillWork() {
        XCTAssertTrue(ScriptRuleResult.isHit(exitStatus: 0, output: ""))          // shell-style: exit 0 = true
        XCTAssertFalse(ScriptRuleResult.isHit(exitStatus: 1, output: ""))
    }

    func testNonZeroExitIsNeverAHit() {
        XCTAssertFalse(ScriptRuleResult.isHit(exitStatus: 1, output: "true"))
        XCTAssertFalse(ScriptRuleResult.isHit(exitStatus: 255, output: ""))
    }

    func testOtherOutputWithExitZeroIsAHit() {
        XCTAssertTrue(ScriptRuleResult.isHit(exitStatus: 0, output: "Zoom is running"))
    }
}
