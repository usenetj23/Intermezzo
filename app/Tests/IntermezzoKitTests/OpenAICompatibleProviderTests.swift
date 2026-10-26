import XCTest
@testable import IntermezzoKit

private final class StubProtocol: URLProtocol {
    enum Reply { case http(Int, String), failure(URLError.Code), redirect(String) }
    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        var body = Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.bodies.append(body)
        let reply = Self.replies.isEmpty ? Reply.http(500, "") : Self.replies.removeFirst()
        switch reply {
        case .http(let code, let text):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .redirect(let location):
            let response = HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": location])!
            var next = URLRequest(url: URL(string: location)!)
            next.httpMethod = request.httpMethod
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            // Like the network when the delegate declines to follow: the redirect response itself is the answer.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class OpenAICompatibleProviderTests: XCTestCase {
    private let ok = #"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#

    override func setUp() {
        StubProtocol.replies = []
        StubProtocol.requests = []
        StubProtocol.bodies = []
    }

    private func provider(_ base: String = "http://localhost:1234", key: String? = nil) throws -> OpenAICompatibleProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OpenAICompatibleProvider(endpoint: try AIEndpoint.parse(base).get(), model: "test-model", apiKey: key,
                                        session: OpenAICompatibleProvider.makeSession(configuration: configuration))
    }

    func testRedirectsAreNotFollowed() async throws {
        StubProtocol.replies = [.redirect("http://8.8.8.8/steal"), .http(200, ok)]
        do {
            _ = try await provider(key: "test-key").complete(request)
            XCTFail("a redirect must not be followed")
        } catch let error as AIError {
            XCTAssertEqual(error, .badResponse("307"))
        }
        XCTAssertEqual(StubProtocol.requests.count, 1)
        XCTAssertEqual(StubProtocol.requests.first?.url?.host, "localhost")
    }

    private let request = AIRequest(system: "sys", user: "usr")

    func testBuildsChatCompletionsRequest() async throws {
        StubProtocol.replies = [.http(200, ok)]
        _ = try await provider().complete(request)
        let sent = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(sent.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: StubProtocol.bodies[0]) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.map { $0["content"] }, ["sys", "usr"])
        XCTAssertNotNil(body["temperature"])
    }

    func testKeepsAnExistingVersionPath() async throws {
        StubProtocol.replies = [.http(200, ok)]
        _ = try await provider("http://localhost:1234/v1/").complete(request)
        XCTAssertEqual(StubProtocol.requests.first?.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
    }

    func testAddsBearerOnlyWithKey() async throws {
        StubProtocol.replies = [.http(200, ok), .http(200, ok), .http(200, ok)]
        _ = try await provider(key: "test-key").complete(request)
        _ = try await provider(key: nil).complete(request)
        _ = try await provider(key: "").complete(request)
        XCTAssertEqual(StubProtocol.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertNil(StubProtocol.requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(StubProtocol.requests[2].value(forHTTPHeaderField: "Authorization"))
    }

    func testSchemaSentThenRetriedWithoutOn400() async throws {
        StubProtocol.replies = [.http(400, "{}"), .http(200, ok)]
        let withSchema = AIRequest(system: "s", user: "u", jsonSchema: #"{"type":"object"}"#)
        let result = try await provider().complete(withSchema)
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(StubProtocol.requests.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: StubProtocol.bodies[0]) as? [String: Any])
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: StubProtocol.bodies[1]) as? [String: Any])
        XCTAssertNotNil(first["response_format"])
        XCTAssertNil(second["response_format"])
    }

    func testAnAbsurdlyLargeAnswerIsRefused() async throws {
        let huge = String(repeating: "x", count: OpenAICompatibleProvider.maxAnswerBytes + 5_000)
        StubProtocol.replies = [.http(200, #"{"choices":[{"message":{"content":"\#(huge)"}}]}"#)]
        do {
            _ = try await provider().complete(request)
            XCTFail("expected the answer to be refused")
        } catch let error as AIError {
            XCTAssertEqual(error, .badResponse("too large"))
        }
    }

    func testParsesContent() async throws {
        StubProtocol.replies = [.http(200, ok)]
        let text = try await provider().complete(request)
        XCTAssertEqual(text, "ok")
    }

    func testErrorMapping() async throws {
        let cases: [(StubProtocol.Reply, AIError)] = [
            (.http(401, ""), .unauthorized), (.http(403, ""), .unauthorized), (.http(429, ""), .rateLimited),
            (.http(500, ""), .badResponse("500")), (.http(200, "{}"), .badResponse("empty")),
            (.failure(.timedOut), .timeout), (.failure(.cancelled), .cancelled),
        ]
        for (reply, expected) in cases {
            StubProtocol.replies = [reply]
            do {
                _ = try await provider().complete(request)
                XCTFail("expected \(expected)")
            } catch let error as AIError {
                XCTAssertEqual(error, expected)
            }
        }
        StubProtocol.replies = [.failure(.cannotConnectToHost)]
        do {
            _ = try await provider().complete(request)
            XCTFail("expected a network error")
        } catch let error as AIError {
            guard case .network = error else { return XCTFail("got \(error)") }
        }
    }

    private func listModels(_ base: String = "http://localhost:1234", key: String? = nil) async throws -> [String] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return try await OpenAICompatibleProvider.listModels(
            endpoint: try AIEndpoint.parse(base).get(), apiKey: key,
            session: OpenAICompatibleProvider.makeSession(configuration: configuration))
    }

    func testListModelsSendsAGetAndReturnsSortedUniqueIds() async throws {
        StubProtocol.replies = [.http(200, #"{"object":"list","data":[{"id":"b-model"},{"id":"A-model"},{"id":"b-model"},{"name":"no id"}]}"#)]
        let models = try await listModels(key: "test-key")
        XCTAssertEqual(models, ["A-model", "b-model"])
        let sent = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.url?.absoluteString, "http://localhost:1234/v1/models")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testListModelsWithoutKeyAndWithVersionPath() async throws {
        StubProtocol.replies = [.http(200, #"{"data":[]}"#)]
        let models = try await listModels("http://127.0.0.1:8000/v1/")
        XCTAssertTrue(models.isEmpty)
        XCTAssertEqual(StubProtocol.requests.first?.url?.absoluteString, "http://127.0.0.1:8000/v1/models")
        XCTAssertNil(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testListModelsErrors() async throws {
        let cases: [(StubProtocol.Reply, AIError)] = [
            (.http(401, ""), .unauthorized), (.http(404, ""), .badResponse("404")),
            (.http(200, "{}"), .badResponse("empty")), (.http(200, "not json"), .badResponse("empty")),
            (.failure(.timedOut), .timeout),
        ]
        for (reply, expected) in cases {
            StubProtocol.replies = [reply]
            do {
                _ = try await listModels(key: "test-key")
                XCTFail("expected \(expected)")
            } catch let error as AIError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(String(describing: error).contains("test-key"))
            }
        }
    }

    func testErrorsDoNotLeakTheKey() async throws {
        for reply in [StubProtocol.Reply.http(401, "test-key"), .http(500, "test-key"), .failure(.cannotConnectToHost)] {
            StubProtocol.replies = [reply]
            do {
                _ = try await provider(key: "test-key").complete(request)
                XCTFail("expected an error")
            } catch let error as AIError {
                XCTAssertFalse(String(describing: error).contains("test-key"))
                XCTAssertFalse(error.message.contains("test-key"))
            }
        }
    }
}
