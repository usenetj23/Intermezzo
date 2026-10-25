import Foundation
import IntermezzoKit

/// The one place that runs `osascript` on a script file — used by the rule
/// check and by the project sensors. argv only (a single path element, never a
/// shell), absolute executable, stdin from /dev/null, off the main thread,
/// output capped at `ShortcutPlan.outputCap`, supervised timeout
/// (SIGTERM, then SIGKILL after `ShortcutPlan.killGrace`).
enum ScriptRunner {
    static let executablePath = "/usr/bin/osascript"
    /// Rules were unbounded before; this only stops a truly stuck script.
    static let ruleTimeout: TimeInterval = 30
    static let sensorTimeout: TimeInterval = 5
    /// `status` when the script could not be started or was stopped on timeout.
    static let failedStatus = ShortcutPlan.launchFailedStatus

    static func run(path: String, timeout: TimeInterval) async -> (status: Int32, stdout: String) {
        await Task.detached(priority: .utility) { () -> (status: Int32, stdout: String) in
            let handle: ShortcutProcess
            do {
                handle = try ShortcutProcess.launch([path], executable: executablePath)
            } catch {
                return (failedStatus, "")
            }
            switch await ShortcutPlan.supervise(handle, timeout: timeout, killGrace: ShortcutPlan.killGrace) {
            case .exited(let output):
                return (output.status, String(decoding: output.stdout, as: UTF8.self))
            case .timedOut:
                return (failedStatus, "")
            }
        }.value
    }
}
