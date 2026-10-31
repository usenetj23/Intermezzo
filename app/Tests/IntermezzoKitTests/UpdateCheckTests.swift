import XCTest
@testable import IntermezzoKit

final class UpdateCheckTests: XCTestCase {
    private func payload(tag: String = "1.43.0", url: String = "https://github.com/usenetj23/Intermezzo/releases/tag/1.43.0",
                         body: String? = "notes", draft: Bool = false, prerelease: Bool = false) -> Data {
        let json: [String: Any] = ["tag_name": tag, "html_url": url, "body": body as Any,
                                   "draft": draft, "prerelease": prerelease]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testVersionsCompareNumericallyAndIgnoreAPrefix() {
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("1.10.0")!)
        XCTAssertLessThan(AppVersion("1.42.1")!, AppVersion("v1.43")!)
        XCTAssertEqual(AppVersion("1.42")!, AppVersion("1.42.0")!)
        XCTAssertEqual(AppVersion("1.43.0-beta")!, AppVersion("1.43.0")!)
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
    }

    func testANewerFinalReleaseIsOffered() {
        let release = UpdateCheck.parse(payload())!
        XCTAssertTrue(UpdateCheck.isNewer(release, than: "1.42.1"))
        XCTAssertFalse(UpdateCheck.isNewer(release, than: "1.43.0"))
        XCTAssertFalse(UpdateCheck.isNewer(release, than: "1.44.0"))
        XCTAssertFalse(UpdateCheck.isNewer(release, than: "unknown"))
    }

    func testDraftsPreReleasesAndForeignAddressesAreIgnored() {
        XCTAssertNil(UpdateCheck.parse(payload(draft: true)))
        XCTAssertNil(UpdateCheck.parse(payload(prerelease: true)))
        XCTAssertNil(UpdateCheck.parse(payload(url: "https://evil.example/releases/tag/1.43.0")))
        XCTAssertNil(UpdateCheck.parse(payload(url: "http://github.com/usenetj23/Intermezzo/releases/tag/1.43.0")))
        XCTAssertNil(UpdateCheck.parse(payload(tag: "not-a-version")))
        XCTAssertNil(UpdateCheck.parse(Data("{}".utf8)))
    }

    func testChecksAreDueOncePerIntervalAndAfterAClockChange() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    func testNotesAreCutAtALineEnd() {
        let body = "line one\nline two\nline three is long"
        XCTAssertEqual(UpdateCheck.notesExcerpt(body, limit: 100), body)
        XCTAssertEqual(UpdateCheck.notesExcerpt(body, limit: 20), "line one\nline two…")
    }
}
