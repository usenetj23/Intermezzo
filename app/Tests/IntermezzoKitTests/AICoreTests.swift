import XCTest
@testable import IntermezzoKit

final class AICoreTests: XCTestCase {
    private func locality(_ text: String) -> AIEndpoint.Locality? {
        if case .success(let parsed) = AIEndpoint.parse(text) { return parsed.locality }
        return nil
    }

    func testLocalAddressesAreLocal() {
        for text in ["http://localhost:1234/v1", "http://127.0.0.1:11434", "http://[::1]:8080", "http://mac-mini:8080",
                     "http://mac.local:8080", "http://192.168.1.20:8000", "http://10.0.0.5", "http://172.20.1.1",
                     "http://169.254.3.4", "http://[fd12:3456::1]", "http://[fe80::1]"] {
            XCTAssertEqual(locality(text), .local, text)
        }
    }

    func testRemoteNeedsHTTPS() {
        XCTAssertEqual(AIEndpoint.parse("http://api.example.com/v1"), .failure(.remoteNeedsHTTPS))
        XCTAssertEqual(AIEndpoint.parse("http://172.32.0.1"), .failure(.remoteNeedsHTTPS))
        XCTAssertEqual(AIEndpoint.parse("http://8.8.8.8"), .failure(.remoteNeedsHTTPS))
        XCTAssertEqual(locality("https://api.example.com/v1"), .remote)
        XCTAssertEqual(locality("https://192.168.1.2"), .local)
    }

    func testInvalidEndpoints() {
        for text in ["", "   ", "ftp://x", "localhost:1234", "http://"] {
            XCTAssertEqual(AIEndpoint.parse(text), .failure(.invalidEndpoint), "'\(text)'")
        }
    }

    func testTrailingSlashAndSpacesAreTrimmed() throws {
        let parsed = try AIEndpoint.parse("  http://localhost:1234/v1/  ").get()
        XCTAssertEqual(parsed.url.absoluteString, "http://localhost:1234/v1")
    }

    private func json(_ text: String) -> Any? {
        JSONExtract.firstJSON(in: text).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    func testFirstJSONFindsObjectsArraysAndFences() {
        let fenced = json("Oto: ```json\n{\"a\":[1,2]}\n``` koniec") as? [String: [Int]]
        XCTAssertEqual(fenced?["a"], [1, 2])
        let first = json("[{\"k\":1}] i {\"x\":2}") as? [[String: Int]]
        XCTAssertEqual(first, [["k": 1]])
        XCTAssertEqual((json("{\"s\":\"}{\"}") as? [String: String])?["s"], "}{")
        XCTAssertEqual((json("a { not json } b {\"ok\":true}") as? [String: Bool])?["ok"], true)
        XCTAssertNil(JSONExtract.firstJSON(in: "bez json"))
        XCTAssertNil(JSONExtract.firstJSON(in: "{\"a\":"))
    }

    func testErrorMessagesAreSafe() {
        XCTAssertTrue(AIError.network("boom").message.contains("boom"))
        XCTAssertFalse(AIError.unauthorized.message.contains("Bearer"))
        for error in [AIError.disabled, .unavailable("x"), .unauthorized, .rateLimited, .timeout, .cancelled,
                      .network("n"), .badResponse("b"), .invalidEndpoint, .remoteNeedsHTTPS] {
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    func testNumericHostsAreNotLocal() {
        for text in ["http://134744072", "http://0x08080808", "http://010.0.0.1", "http://0177.0.0.1", "http://8"] {
            XCTAssertEqual(AIEndpoint.parse(text), .failure(.remoteNeedsHTTPS), text)
        }
        XCTAssertEqual(locality("http://127.0.0.1:1234"), .local)
    }

    func testHugeInputIsBoundedAndFast() {
        let started = Date()
        XCTAssertNil(JSONExtract.firstJSON(in: String(repeating: "{", count: 100_000)))
        XCTAssertNil(JSONExtract.firstJSON(in: String(repeating: "[1,", count: 100_000)))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let buried = String(repeating: "x ", count: 200_000) + "{\"a\":1}"
        XCTAssertNil(JSONExtract.firstJSON(in: buried), "the answer is only searched in its first \(JSONExtract.maxCharacters) characters")
        XCTAssertNotNil(JSONExtract.firstJSON(in: "prose {\"a\":1}"))
    }
}
