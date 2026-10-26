import Foundation

// The common ground of the optional AI features: what is asked, what can go wrong, which server addresses
// count as "on this computer" and how a JSON answer is found in the model's text. Pure logic; the providers
// and the screens that use it live elsewhere.

public struct AIRequest: Equatable, Sendable {
    public let system: String
    public let user: String
    /// A JSON Schema (as text) for the answer, when the provider can enforce one.
    public let jsonSchema: String?

    public init(system: String, user: String, jsonSchema: String? = nil) {
        self.system = system
        self.user = user
        self.jsonSchema = jsonSchema
    }
}

public enum AIError: Error, Equatable, Sendable {
    case disabled
    case unavailable(String)
    case unauthorized
    case rateLimited
    case timeout
    case cancelled
    case network(String)
    case badResponse(String)
    case invalidEndpoint
    case remoteNeedsHTTPS

    /// A short text for the user. It never carries a key or a request body.
    public var message: String {
        switch self {
        case .disabled: return kitL("Funkcje AI są wyłączone.")
        case .unavailable(let reason): return kitL("Model jest niedostępny: %@", reason)
        case .unauthorized: return kitL("Serwer odrzucił dostęp. Sprawdź klucz.")
        case .rateLimited: return kitL("Serwer ogranicza liczbę zapytań. Spróbuj za chwilę.")
        case .timeout: return kitL("Model nie odpowiedział w wyznaczonym czasie.")
        case .cancelled: return kitL("Przerwano.")
        case .network(let detail): return kitL("Błąd połączenia: %@", detail)
        case .badResponse(let detail): return kitL("Nieoczekiwana odpowiedź modelu (%@).", detail)
        case .invalidEndpoint: return kitL("Adres serwera jest niepoprawny.")
        case .remoteNeedsHTTPS: return kitL("Zdalny serwer musi mieć adres zaczynający się od https://.")
        }
    }
}

public protocol AIProvider: Sendable {
    func complete(_ request: AIRequest) async throws -> String
}

public enum AIEndpoint {
    public enum Locality: Equatable, Sendable {
        /// This computer or the local network: nothing leaves it.
        case local
        case remote
    }

    public struct Parsed: Equatable, Sendable {
        public let url: URL
        public let locality: Locality
    }

    public static func parse(_ text: String) -> Result<Parsed, AIError> {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let rawHost = components.host, !rawHost.isEmpty,
              let url = URL(string: trimmed) else { return .failure(.invalidEndpoint) }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        let locality: Locality = isLocal(host: host) ? .local : .remote
        if locality == .remote, scheme == "http" { return .failure(.remoteNeedsHTTPS) }
        return .success(Parsed(url: url, locality: locality))
    }

    private static func isLocal(host: String) -> Bool {
        if host.contains(":") { return isLocalIPv6(host) }
        // 134744072 and 0x08080808 are other ways to write 8.8.8.8: never treat a bare number as a local name.
        if host.hasPrefix("0x") || host.allSatisfy(\.isNumber) { return false }
        if let octets = ipv4(host) { return isPrivateIPv4(octets) }
        return host == "localhost" || !host.contains(".") || host.hasSuffix(".local")
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        // A leading zero makes the resolver read the part as octal (010 is 8), so such a part is not plain decimal.
        guard pieces.count == 4, pieces.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
        let parts = pieces.map { Int($0) }
        guard parts.allSatisfy({ $0 != nil && (0...255).contains($0!) }) else { return nil }
        return parts.compactMap { $0 }
    }

    private static func isPrivateIPv4(_ o: [Int]) -> Bool {
        o[0] == 127 || o[0] == 10 || (o[0] == 172 && (16...31).contains(o[1])) || (o[0] == 192 && o[1] == 168)
            || (o[0] == 169 && o[1] == 254)
    }

    private static func isLocalIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let linkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        let uniqueLocal = (bytes[0] & 0xfe) == 0xfc
        return loopback || linkLocal || uniqueLocal
    }
}

public enum JSONExtract {
    /// Only the beginning of an answer is searched, and each search is one pass over it, so a runaway answer
    /// of brackets cannot keep the app busy.
    public static let maxCharacters = 256_000
    private static let maxRestarts = 4
    private static let maxCandidates = 100

    /// The first complete JSON object or array in `text` (a model often wraps it in a sentence or a code fence).
    public static func firstJSON(in text: String) -> Data? {
        let chars = Array(text.utf8.prefix(maxCharacters))
        var from = 0
        for _ in 0..<maxRestarts {
            guard let first = (from..<chars.count).first(where: { isOpener(chars[$0]) }) else { return nil }
            // Matching brackets from here on; a stray quote earlier in the prose can confuse the string tracking,
            // so the search is repeated from the next bracket a few times.
            for (open, close) in pairs(in: chars, from: first).prefix(maxCandidates) {
                let candidate = Data(chars[open...close])
                if (try? JSONSerialization.jsonObject(with: candidate)) != nil { return candidate }
            }
            from = first + 1
        }
        return nil
    }

    private static func isOpener(_ c: UInt8) -> Bool { c == UInt8(ascii: "{") || c == UInt8(ascii: "[") }

    /// The matched pairs of brackets (opening index, closing index) found in one pass, in order of the opening one.
    private static func pairs(in chars: [UInt8], from start: Int) -> [(Int, Int)] {
        var stack: [Int] = []
        var found: [(Int, Int)] = []
        var inString = false
        var escaped = false
        for index in start..<chars.count {
            let c = chars[index]
            if inString {
                if escaped { escaped = false } else if c == UInt8(ascii: "\\") { escaped = true } else if c == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch c {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["): stack.append(index)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                guard let open = stack.popLast() else { continue }
                let wanted = chars[open] == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
                if c == wanted { found.append((open, index)) }
            default: break
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }
}
