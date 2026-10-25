import Foundation
import os

/// "Script Actions": run an AppleScript (or any executable
/// script) when a break starts, and another when it ends for any reason.

enum ScriptActionKeys {
    static let enabled = "scriptsEnabled"
    static let startPath = "breakStartScriptPath"
    static let endPath = "breakEndScriptPath"
}

@MainActor
final class ScriptActionController {

    private var running: [Process] = []
    private let log = Logger(subsystem: "com.automit.Intermezzo", category: "scripts")

    /// Fire-and-forget: launch the script configured under `key` if the
    /// feature is enabled and the file exists. Never blocks the UI.
    func run(configuredUnder key: String) {
        let d = UserDefaults.standard
        guard d.integer(forKey: ScriptActionKeys.enabled) != 0 else { return }
        guard let path = d.string(forKey: key), !path.isEmpty else { return }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            log.warning("script not found: \(path, privacy: .public)")
            return
        }

        let p = Process()
        let lower = path.lowercased()
        if lower.hasSuffix(".scpt") || lower.hasSuffix(".applescript") {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = [path]
        } else {
            // Assume a POSIX shell script (or binary): execute it directly.
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [path]
        }

        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            if proc.terminationStatus != 0 {
                Task { @MainActor in
                    self?.log.warning("break script exited \(proc.terminationStatus): \(path, privacy: .public)")
                }
            }
            Task { @MainActor in
                if let idx = self?.running.firstIndex(of: proc) {
                    self?.running.remove(at: idx)
                }
            }
        }
        do {
            running.append(p)
            try p.run()
            log.info("break script started: \(path, privacy: .public)")
        } catch {
            log.error("failed to run break script: \(error, privacy: .public)")
        }
    }

    func breakDidStart() {
        run(configuredUnder: ScriptActionKeys.startPath)
    }

    func breakDidEnd() {
        run(configuredUnder: ScriptActionKeys.endPath)
    }
}
