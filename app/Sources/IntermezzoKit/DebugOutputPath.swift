import Foundation

/// Validates the `out=` path of the debug deeplinks so a URL fired by a web page or another app can
/// only write inside a temporary folder, never over a user file.
public enum DebugOutputPath {
    /// - Returns: the real file the caller may write (symlinks resolved), or nil when refused.
    ///   A nil `raw` gives `defaultName` in the first allowed root that is the temp dir (the last root).
    public static func validated(_ raw: String?, defaultName: String, allowedExtensions: Set<String>,
                                 allowedRoots: [String]) -> URL? {
        let roots = allowedRoots.map { resolved($0) }
        guard let raw else {
            guard let tmp = allowedRoots.last else { return nil }
            return URL(fileURLWithPath: tmp, isDirectory: true).appendingPathComponent(defaultName)
        }
        guard !raw.isEmpty, raw.first == "/" else { return nil }          // no relative paths, no "~"
        let components = raw.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else { return nil }
        let wanted = allowedExtensions.map { $0.lowercased() }
        let ext = URL(fileURLWithPath: raw).pathExtension.lowercased()
        guard wanted.contains(ext) else { return nil }
        // Resolves symlinked directories and, if the file exists, a symlinked file.
        let target = URL(fileURLWithPath: canonical(raw))
        guard wanted.contains(target.pathExtension.lowercased()) else { return nil }
        let parent = target.deletingLastPathComponent().path
        guard roots.contains(where: { parent == $0 || parent.hasPrefix($0 + "/") }) else { return nil }
        return target
    }

    private static func resolved(_ path: String) -> String { canonical(path) }

    /// realpath(3) of the deepest existing ancestor (follows every symlink, also a final one),
    /// with the not-yet-existing tail appended.
    static func canonical(_ path: String) -> String {
        var existing = path
        var tail: [String] = []
        var info = stat()
        while existing.count > 1, lstat(existing, &info) != 0 {
            tail.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        // A dangling symlink cannot be resolved: send it outside every root.
        guard realpath(existing, &buffer) != nil else { return "/.unresolvable" }
        let base = String(cString: buffer)
        var out = base
        for part in tail { out = (out == "/" ? "" : out) + "/" + part }
        return out
    }
}
