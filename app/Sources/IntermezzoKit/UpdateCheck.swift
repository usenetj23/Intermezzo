import Foundation

/// A version such as "1.42.1" (a leading "v" is allowed), comparable part by part.
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        // "1.43.0-beta" and "1.43.0+5" are read as 1.43.0; the release check skips pre-releases itself.
        if let end = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) { trimmed = String(trimmed[..<end]) }
        let numbers = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let count = max(a.parts.count, b.parts.count)
        for i in 0..<count {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}

/// What the app needs to know about the newest GitHub release.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    public let url: URL
    public let notes: String
}

/// "Is there a newer release?": reading GitHub's answer, never a download or an install.
public enum UpdateCheck {
    public static let latestReleaseAPI = "https://api.github.com/repos/usenetj23/Intermezzo/releases/latest"
    public static let releasesPage = "https://github.com/usenetj23/intermezzo/releases"

    private struct Payload: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
    }

    /// nil for anything that is not a published, final release of this repository (a draft, a pre-release, a page
    /// on another site): the address that is later opened must be the project's own releases page.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true,
              let version = AppVersion(payload.tag_name),
              let url = URL(string: payload.html_url), url.scheme == "https",
              payload.html_url.lowercased().hasPrefix(releasesPage) else { return nil }
        return ReleaseInfo(version: version, tag: payload.tag_name, url: url, notes: payload.body ?? "")
    }

    public static func isNewer(_ release: ReleaseInfo, than current: String) -> Bool {
        guard let installed = AppVersion(current) else { return false }
        return release.version > installed
    }

    /// Whether a check is due: never done, or at least `interval` ago (a clock set back counts as due).
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = 24 * 3600) -> Bool {
        guard let last = lastCheck else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= interval || elapsed < 0
    }

    /// The start of the release notes, cut at a line end where possible.
    public static func notesExcerpt(_ body: String, limit: Int = 400) -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let cut = head.lastIndex(of: "\n").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
