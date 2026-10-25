import Foundation

/// Minimal always-on file trace for diagnosing break-action timing.
/// Writes to ~/Library/Logs/Intermezzo/trace.log on a background serial queue
/// (never blocks the main thread); rotates to trace.log.1 past 2 MB.
enum Trace {
    private static let maxBytes = 2 * 1024 * 1024
    private static let queue = DispatchQueue(label: "com.automit.Intermezzo.trace", qos: .utility)
    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Intermezzo", isDirectory: true)

    static var logPath: String { dir.appendingPathComponent("trace.log").path }

    static func log(_ message: String) {
        let line = "\(Date()) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("trace.log")
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = dir.appendingPathComponent("trace.log.1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    try? data.write(to: url)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
