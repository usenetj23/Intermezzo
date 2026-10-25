import Foundation

/// A value a rule script exposes for editing without touching its code.
public enum ScriptSettingValue: Equatable, Sendable {
    case list([String])
    case number(Int)
    case flag(Bool)
    case text(String)
}

/// One `property name : value` line of a rule script.
public struct ScriptSetting: Equatable, Sendable {
    public var name: String
    public var value: ScriptSettingValue
    /// Label from a `-- Nastawa: …` / `-- Setting: …` comment right above the property.
    public var comment: String?

    public init(name: String, value: ScriptSettingValue, comment: String? = nil) {
        self.name = name
        self.value = value
        self.comment = comment
    }
}

/// Reads and rewrites the editable settings ("nastawy") of a rule script: top-level
/// AppleScript properties holding a list of strings, an integer, a boolean or a string.
/// Everything else in the script is left exactly as written.
public enum ScriptSettings {
    private static let headerPrefix = "-- Intermezzo Rule:"
    private static let labelPrefixes = ["-- Nastawa:", "-- Setting:"]

    public static func parse(_ source: String) -> [ScriptSetting] {
        var result: [ScriptSetting] = []
        var previous = ""
        for line in source.components(separatedBy: "\n") {
            if let (name, raw) = propertyParts(line), let value = parseValue(raw) {
                result.append(ScriptSetting(name: name, value: value, comment: label(in: previous)))
            }
            previous = line
        }
        return result
    }

    /// Writes each setting back into its `property` line; names not in the script are ignored.
    public static func apply(_ settings: [ScriptSetting], to source: String) -> String {
        let byName = Dictionary(settings.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        return source.components(separatedBy: "\n").map { line in
            guard let (name, raw) = propertyParts(line), parseValue(raw) != nil,
                  let value = byName[name] else { return line }
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            return "\(indent)property \(name) : \(literal(value))"
        }.joined(separator: "\n")
    }

    public static func literal(_ value: ScriptSettingValue) -> String {
        switch value {
        case .list(let items): return "{" + items.map(quoted).joined(separator: ", ") + "}"
        case .number(let n): return String(n)
        case .flag(let b): return b ? "true" : "false"
        case .text(let s): return quoted(s)
        }
    }

    public static func list(fromCommaText text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func commaText(_ items: [String]) -> String {
        items.joined(separator: ", ")
    }

    /// The name in the `-- Intermezzo Rule: Name` header, if the script has one.
    public static func ruleName(in source: String) -> String? {
        guard let first = source.components(separatedBy: "\n").first,
              first.hasPrefix(headerPrefix) else { return nil }
        let name = first.dropFirst(headerPrefix.count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    public static func withRuleName(_ name: String, in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        let header = "\(headerPrefix) \(name)"
        if lines.first?.hasPrefix(headerPrefix) == true {
            lines[0] = header
        } else {
            lines.insert(header, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// A file name stem made of ASCII letters, digits and dashes.
    public static func fileSlug(_ name: String) -> String {
        let folded = name.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        for ch in folded {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                slug.append(ch)
            } else if !slug.isEmpty && slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.last == "-" { slug.removeLast() }
        return slug.isEmpty ? "Skrypt" : slug
    }

    public static func uniqueSlug(_ slug: String, taken: Set<String>) -> String {
        guard taken.contains(slug) else { return slug }
        var n = 2
        while taken.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }

    // MARK: - Parsing

    private static func propertyParts(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("property ") else { return nil }
        let rest = trimmed.dropFirst("property ".count)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let name = rest[..<colon].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        return (name, rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }

    private static func parseValue(_ raw: String) -> ScriptSettingValue? {
        if raw == "true" { return .flag(true) }
        if raw == "false" { return .flag(false) }
        if let n = Int(raw) { return .number(n) }
        if raw.hasPrefix("\"") {
            var i = raw.startIndex
            guard let s = parseString(raw, at: &i), i == raw.endIndex else { return nil }
            return .text(s)
        }
        if raw.hasPrefix("{") && raw.hasSuffix("}") {
            var items: [String] = []
            var i = raw.index(after: raw.startIndex)
            let end = raw.index(before: raw.endIndex)
            skipSpaces(raw, &i, end)
            if i == end { return .list([]) }
            while i < end {
                guard let s = parseString(raw, at: &i) else { return nil }
                items.append(s)
                skipSpaces(raw, &i, end)
                if i == end { break }
                guard raw[i] == "," else { return nil }
                i = raw.index(after: i)
                skipSpaces(raw, &i, end)
            }
            return .list(items)
        }
        return nil
    }

    private static func skipSpaces(_ s: String, _ i: inout String.Index, _ end: String.Index) {
        while i < end, s[i] == " " || s[i] == "\t" { i = s.index(after: i) }
    }

    /// An AppleScript string literal starting at `i`; leaves `i` after the closing quote.
    private static func parseString(_ s: String, at i: inout String.Index) -> String? {
        guard i < s.endIndex, s[i] == "\"" else { return nil }
        var out = ""
        var j = s.index(after: i)
        while j < s.endIndex {
            let ch = s[j]
            if ch == "\\" {
                let next = s.index(after: j)
                guard next < s.endIndex else { return nil }
                out.append(s[next])
                j = s.index(after: next)
            } else if ch == "\"" {
                i = s.index(after: j)
                return out
            } else {
                out.append(ch)
                j = s.index(after: j)
            }
        }
        return nil
    }

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func label(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in labelPrefixes where trimmed.hasPrefix(prefix) {
            let text = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
