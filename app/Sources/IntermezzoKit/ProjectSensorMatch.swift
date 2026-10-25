import Foundation

/// "If the sensor output contains `pattern`, suggest `project`." Stored as JSON
/// under `projectSensorRules`; older/partial data must keep loading.
public struct ProjectSensorRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pattern: String
    public var project: String

    public init(id: UUID = UUID(), pattern: String, project: String) {
        self.id = id
        self.pattern = pattern
        self.project = project
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
    }
}

/// Pure matching of a sensor's text against the user's rules.
public enum ProjectSensorMatch {
    /// Only this many characters of the output are looked at.
    public static let outputCap = 4096

    /// Name of the project of the first rule whose pattern the output contains.
    /// Case-insensitive literal `contains` (not diacritic-insensitive, no regex).
    /// Blank output or blank pattern never match. The caller must still check
    /// that the project exists and is active.
    public static func suggest(output: String, rules: [ProjectSensorRule]) -> String? {
        let text = String(output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(outputCap))
        guard !text.isEmpty else { return nil }
        for rule in rules {
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, !rule.project.isEmpty else { continue }
            if text.range(of: pattern, options: [.caseInsensitive, .literal]) != nil { return rule.project }
        }
        return nil
    }
}

/// Confines a stored script path to the app's own Sensors folder.
public enum SensorScriptPath {
    static func hasControlCharacter(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    private static func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// The Sensors folder and its parent must not themselves be symlinks
    /// (checked with lstat semantics, not on resolved paths), so a swapped-in
    /// link cannot widen the root.
    public static func isSafeFolder(_ folder: String) -> Bool {
        let url = URL(fileURLWithPath: folder).standardizedFileURL
        return !isSymlink(url.path) && !isSymlink(url.deletingLastPathComponent().path)
    }

    /// The fully resolved path when `path` is an absolute, `..`-free,
    /// regular `.applescript` file that really lives (symlinks of the file AND
    /// of every directory resolved) inside `folder`; otherwise nil.
    public static func validated(_ path: String, folder: String) -> String? {
        guard path.hasPrefix("/"), folder.hasPrefix("/"),
              !hasControlCharacter(path), !hasControlCharacter(folder),
              isSafeFolder(folder),
              !path.split(separator: "/").contains(".."),
              path.lowercased().hasSuffix(".applescript") else { return nil }
        let root = URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard file.pathExtension.lowercased() == "applescript",
              file.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return file.path
    }
}
