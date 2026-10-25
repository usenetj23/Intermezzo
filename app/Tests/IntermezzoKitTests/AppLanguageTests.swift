import XCTest
@testable import IntermezzoKit

final class AppLanguageTests: XCTestCase {
    func testSystemClearsTheOverride() {
        XCTAssertNil(AppLanguage.system.appleLanguages)
    }

    func testEnglishAndPolishSetASingleLanguage() {
        XCTAssertEqual(AppLanguage.english.appleLanguages, ["en"])
        XCTAssertEqual(AppLanguage.polish.appleLanguages, ["pl"])
    }

    func testStoredValueFallsBackToSystem() {
        XCTAssertEqual(AppLanguage(stored: nil), .system)
        XCTAssertEqual(AppLanguage(stored: "klingon"), .system)
        XCTAssertEqual(AppLanguage(stored: "pl"), .polish)
    }

    func testCurrentIsReadFromTheAppleLanguagesOverride() {
        XCTAssertEqual(AppLanguage.current(appleLanguages: nil), .system)
        XCTAssertEqual(AppLanguage.current(appleLanguages: ["pl", "en"]), .polish)
        XCTAssertEqual(AppLanguage.current(appleLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.current(appleLanguages: ["de"]), .system)
    }
}
