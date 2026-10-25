import Foundation

/// Interprets the outcome of a rule script run through `osascript`.
/// `osascript` exits 0 even for `return false` (it just prints "false"), so the exit code
/// alone cannot tell "condition false" from "condition true".
public enum ScriptRuleResult {
    public static func isHit(exitStatus: Int32, output: String) -> Bool {
        guard exitStatus == 0 else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "false"
    }
}
