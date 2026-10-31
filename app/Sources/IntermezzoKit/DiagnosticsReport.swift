import Foundation

/// The text a user pastes into a GitHub issue: system, Mac, displays, permissions and the features that fell back.
/// Nothing leaves the Mac by itself; this only formats what the app collected and keeps it safe to post in public
/// (no user name in paths, no network names, calendar titles or places: the log excerpt is limited to hardware
/// and media topics).
public struct DiagnosticsReport: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var title: String
        public var items: [(name: String, value: String)]

        public init(_ title: String, _ items: [(name: String, value: String)]) {
            self.title = title
            self.items = items
        }

        public static func == (a: Section, b: Section) -> Bool {
            a.title == b.title && a.items.count == b.items.count
                && zip(a.items, b.items).allSatisfy { $0.name == $1.name && $0.value == $1.value }
        }
    }

    public var sections: [Section]
    public var logLines: [String]

    public init(sections: [Section], logLines: [String] = []) {
        self.sections = sections
        self.logLines = logLines
    }

    public func markdown() -> String {
        var out = ["\(String(repeating: "#", count: 3)) Intermezzo diagnostics", "", "```"]
        for section in sections where !section.items.isEmpty {
            out.append("[\(section.title)]")
            let width = section.items.map { $0.name.count }.max() ?? 0
            for item in section.items {
                out.append("\(item.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(item.value)")
            }
            out.append("")
        }
        if !logLines.isEmpty {
            out.append("[Log excerpt: light, media, sensors, BetterDisplay]")
            out.append(contentsOf: logLines)
            out.append("")
        }
        if out.last == "" { out.removeLast() }
        out.append("```")
        return out.joined(separator: "\n")
    }

    // MARK: Privacy

    /// Topics a log line may belong to; everything else (Wi-Fi and VPN names, calendar, places, rules) stays out.
    static let allowedLogPrefixes = ["light", "media:", "ambient", "betterdisplay", "permission"]

    private static let logLine = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4} (.*)$"#)

    /// The newest `limit` lines about allowed topics, with the user's home folder removed.
    public static func safeLogLines(_ raw: [String], home: String, limit: Int = 30) -> [String] {
        let kept: [String] = raw.compactMap { line in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = logLine.firstMatch(in: line, range: range),
                  let body = Range(match.range(at: 1), in: line).map({ String(line[$0]) }),
                  allowedLogPrefixes.contains(where: { body.hasPrefix($0) }) else { return nil }
            return redact(String(line), home: home)
        }
        return Array(kept.suffix(limit))
    }

    /// Replaces the home folder (and any other `/Users/<name>`) so a path does not name the person.
    public static func redact(_ text: String, home: String) -> String {
        var result = text
        if !home.isEmpty { result = result.replacingOccurrences(of: home, with: "~") }
        let users = try! NSRegularExpression(pattern: #"/Users/[^/\s]+"#)
        return users.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                              withTemplate: "/Users/<user>")
    }
}
