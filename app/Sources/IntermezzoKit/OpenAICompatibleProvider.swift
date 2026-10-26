import Foundation

/// Refuses every redirect: the address was classified (local or remote) as typed, and the request, with its
/// prompt and key, must not be sent anywhere else.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A server that speaks the OpenAI chat API (LM Studio, Ollama, llama.cpp, OpenAI itself and others).
public struct OpenAICompatibleProvider: AIProvider {
    /// A session that keeps no cookies or cache and does not follow redirects.
    public static func makeSession(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public static let defaultSession = makeSession()
    /// An answer larger than this is refused instead of being parsed.
    public static let maxAnswerBytes = 1_000_000

    private let endpoint: AIEndpoint.Parsed
    private let model: String
    private let apiKey: String?
    private let session: URLSession
    private let timeout: TimeInterval

    public init(endpoint: AIEndpoint.Parsed, model: String, apiKey: String?, session: URLSession = OpenAICompatibleProvider.defaultSession,
                timeout: TimeInterval = 60) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
    }

    public func complete(_ request: AIRequest) async throws -> String {
        do {
            return try await send(request, withSchema: request.jsonSchema != nil)
        } catch AIError.badResponse(let detail) where detail == "400" && request.jsonSchema != nil {
            // Not every server takes a schema: ask again without it, the answer is validated anyway.
            return try await send(request, withSchema: false)
        }
    }

    /// The model ids the server offers (`GET <address>/models`), sorted, each once.
    public static func listModels(endpoint: AIEndpoint.Parsed, apiKey: String?, session: URLSession = defaultSession,
                                  timeout: TimeInterval = 15) async throws -> [String] {
        var request = URLRequest(url: try url(of: endpoint, appending: "models"), timeoutInterval: timeout)
        request.httpMethod = "GET"
        applyKey(apiKey, to: &request)
        let data = try await fetch(request, session: session)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { throw AIError.badResponse("empty") }
        let ids = Set(items.compactMap { $0["id"] as? String }.filter { !$0.isEmpty })
        return ids.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: Chat

    private func send(_ request: AIRequest, withSchema: Bool) async throws -> String {
        var urlRequest = URLRequest(url: try Self.url(of: endpoint, appending: "chat/completions"), timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyKey(apiKey, to: &urlRequest)
        urlRequest.httpBody = try body(request, withSchema: withSchema)
        let data = try await Self.fetch(urlRequest, session: session)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String, !text.isEmpty else { throw AIError.badResponse("empty") }
        return text
    }

    private func body(_ request: AIRequest, withSchema: Bool) throws -> Data {
        var object: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.user]],
            "temperature": 0.2,
        ]
        if withSchema, let text = request.jsonSchema, let schema = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
            object["response_format"] = ["type": "json_schema", "json_schema": ["name": "answer", "schema": schema]]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Shared

    /// `<address>/<path>`; an address without a path gets `/v1` first.
    private static func url(of endpoint: AIEndpoint.Parsed, appending path: String) throws -> URL {
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else { throw AIError.invalidEndpoint }
        var base = components.path
        while base.hasSuffix("/") { base.removeLast() }
        if base.isEmpty { base = "/v1" }
        components.path = base + "/" + path
        guard let url = components.url else { throw AIError.invalidEndpoint }
        return url
    }

    private static func applyKey(_ key: String?, to request: inout URLRequest) {
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
    }

    /// The body of a successful answer; every failure is turned into an `AIError` that carries no secrets.
    private static func fetch(_ request: URLRequest, session: URLSession) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard data.count <= maxAnswerBytes + 2_000 else { throw AIError.badResponse("too large") }
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200..<300: return data
            case 401, 403: throw AIError.unauthorized
            case 429: throw AIError.rateLimited
            case let status: throw AIError.badResponse(String(status))
            }
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw AIError.timeout
            case .cancelled: throw AIError.cancelled
            default: throw AIError.network(error.localizedDescription)
            }
        } catch {
            throw AIError.network(error.localizedDescription)
        }
    }
}
