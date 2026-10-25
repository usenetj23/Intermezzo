import XCTest
@testable import IntermezzoKit

final class DebugFlagPolicyTests: XCTestCase {

    func testAcceptsRealFxFlags() {
        for key in ["fxNoFog", "fxNoTrails", "fxNoImg"] {
            XCTAssertTrue(DebugFlagPolicy.isAllowed(key: key), key)
        }
    }

    func testRejectsFocusShortcutKeys() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "focusShortcutsEnabled"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "focusShortcut.breakEnd"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "focusShortcut.sessionStart"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "focusShortcut.breakStart"))
    }

    func testRejectsOtherSettings() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "strictMode"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "seamBreaks"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "pomodoroLedger"))
    }

    func testRejectsEmptyKey() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: ""))
    }

    func testRejectsUnusualCharacters() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fxNoFog\n"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: " fxNoFog"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fxNoFog\u{202E}"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fx/../strictMode"))
    }

    func testRejectsCaseVariants() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "FocusShortcutsEnabled"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "FXNOFOG"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fxnofog"))
    }

    func testRejectsUnlistedFxPrefixedKeys() {
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fxwindow"))
        XCTAssertFalse(DebugFlagPolicy.isAllowed(key: "fxAnything"))
    }
}
