import AppKit
import IntermezzoKit

/// Checks that an AppleScript compiles (syntax only: what it does when it runs is up to the "Testuj" button).
enum ScriptCompiler {
    enum Result: Equatable {
        case ok
        case unreadable
        case failed(String)
    }

    /// Applications a script names that are not installed on this Mac. Compiling such a script makes macOS ask
    /// "Where is <app>?" in a window, so the AI path looks first and never compiles it.
    static func missingApplications(in source: String) -> [String] {
        let refs = RuleScriptAuthor.applicationReferences(in: source)
        let names = refs.names.filter { !isInstalled(name: $0) }
        let ids = refs.bundleIDs.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) == nil }
        return names + ids
    }

    private static func isInstalled(name: String) -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == name }) { return true }
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                       "/System/Cryptexes/App/System/Applications", "/System/Library/CoreServices",
                       "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"]
        let file = name.hasSuffix(".app") ? name : name + ".app"
        return folders.contains { FileManager.default.fileExists(atPath: $0 + "/" + file) }
    }

    static func compile(_ source: String) -> Result {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .unreadable }
        if script.compileAndReturnError(&error) { return .ok }
        return .failed(error?[NSAppleScript.errorMessage] as? String ?? "")
    }
}
