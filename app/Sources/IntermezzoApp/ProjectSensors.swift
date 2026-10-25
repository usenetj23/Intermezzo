import Foundation
import IntermezzoKit

// MARK: - Project sensors (opt-in, local, suggestion only)
//
// At the start of a Pomodoro session, ONE small AppleScript from the app's own
// Sensors folder prints a line of text (repo name, document name or Finder
// folder). If a user rule matches it, a toast asks "Project ‘X’?". The text
// is never stored, logged or sent anywhere; the toast shows only the name of
// one of the user's own projects. Never automatic.

enum ProjectSensorKeys {
    static let enabled = "projectSensorsEnabled"      // Int, default 0
    static let script = "projectSensorScript"         // String path
    static let rules = "projectSensorRules"           // JSON [ProjectSensorRule]
}

enum ProjectSensorCatalog {
    static let all: [GalleryScript] = [
        GalleryScript(
            id: "FrontRepo",
            title: "Front terminal: repository",
            summary: "Name of the repository (a folder containing .git) or folder the frontmost Terminal or iTerm window is in. Needs Automation for Terminal/iTerm and System Events.",
            outcomeNote: "Prints text only.",
            source: """
            -- Intermezzo Sensor: FrontRepo (prints text, changes nothing, runs no git)
            try
                tell application "System Events" to set frontApp to name of first application process whose frontmost is true
                set theTTY to ""
                -- App-specific parts are compiled only at run time (run script) and only
                -- when that app is frontmost, so no app is launched or searched for.
                if frontApp is "Terminal" then
                    set theTTY to run script "tell application \\"Terminal\\" to return tty of selected tab of front window"
                else if frontApp is "iTerm2" then
                    set theTTY to run script "tell application \\"iTerm2\\" to return tty of current session of current window"
                end if
                if theTTY is "" then return ""
                set theDir to do shell script "p=$(/bin/ps -t " & quoted form of theTTY & " -o pid= | /usr/bin/tail -n 1 | /usr/bin/tr -d ' '); [ -n \\"$p\\" ] && /usr/sbin/lsof -a -d cwd -p \\"$p\\" -Fn | /usr/bin/sed -n 's/^n//p' | /usr/bin/head -n 1"
                if theDir is "" then return ""
                return do shell script "d=" & quoted form of theDir & "; while [ \\"$d\\" != / ] && [ ! -e \\"$d/.git\\" ]; do d=$(/usr/bin/dirname \\"$d\\"); done; if [ -e \\"$d/.git\\" ]; then /usr/bin/basename \\"$d\\"; else /usr/bin/basename " & quoted form of theDir & "; fi"
            on error
                return ""
            end try
            """),
        GalleryScript(
            id: "FrontDocument",
            title: "Front window: document name",
            summary: "Title of the frontmost window of the frontmost app. Needs Automation for System Events and Accessibility.",
            outcomeNote: "Prints text only.",
            source: """
            -- Intermezzo Sensor: FrontDocument (prints text, changes nothing)
            try
                tell application "System Events"
                    set frontProc to first application process whose frontmost is true
                    if (count of windows of frontProc) is 0 then return ""
                    return name of front window of frontProc
                end tell
            on error
                return ""
            end try
            """),
        GalleryScript(
            id: "FinderFolder",
            title: "Front Finder window: folder",
            summary: "Path of the folder shown in the frontmost Finder window. Needs Automation for System Events and Finder.",
            outcomeNote: "Prints text only.",
            source: """
            -- Intermezzo Sensor: FinderFolder (prints text, changes nothing)
            try
                tell application "System Events" to set frontApp to name of first application process whose frontmost is true
                if frontApp is not "Finder" then return ""
                return run script "tell application \\"Finder\\"
                if (count of Finder windows) is 0 then return \\"\\"
                return POSIX path of (target of front Finder window as alias)
            end tell"
            on error
                return ""
            end try
            """)
    ]
}

/// Outcome of one sensor run, so the UI can tell the cases apart.
enum SensorRun: Equatable {
    /// Nothing ran: no/invalid script path, or a sensor was already running.
    case notRun
    /// Started but failed, or was stopped on timeout.
    case failed
    /// Ran; the text may be empty.
    case ran(String)
}

@MainActor
enum ProjectSensors {
    /// `…/Application Scripts/<bundle id>/Sensors` — next to the Rules folder.
    static var folder: URL {
        ScriptGallery.scriptsDir.deletingLastPathComponent().appendingPathComponent("Sensors", isDirectory: true)
    }

    static var isEnabled: Bool { UserDefaults.standard.integer(forKey: ProjectSensorKeys.enabled) != 0 }

    static func path(for script: GalleryScript) -> URL {
        folder.appendingPathComponent("\(script.id).applescript")
    }

    static func isInstalled(_ script: GalleryScript) -> Bool {
        FileManager.default.fileExists(atPath: path(for: script).path)
    }

    @discardableResult
    static func install(_ script: GalleryScript) -> Bool {
        guard SensorScriptPath.isSafeFolder(folder.path) else {
            Trace.log("project sensor install refused: Sensors folder is a symlink")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try script.source.write(to: path(for: script), atomically: true, encoding: .utf8)
            return true
        } catch {
            Trace.log("project sensor install failed \(script.id)")
            return false
        }
    }

    /// Removes only that one file from the Sensors folder.
    static func uninstall(_ script: GalleryScript) {
        try? FileManager.default.removeItem(at: path(for: script))
        if UserDefaults.standard.string(forKey: ProjectSensorKeys.script) == path(for: script).path {
            UserDefaults.standard.removeObject(forKey: ProjectSensorKeys.script)
        }
    }

    static func rules(_ defaults: UserDefaults = .standard) -> [ProjectSensorRule] {
        defaults.data(forKey: ProjectSensorKeys.rules)
            .flatMap { try? JSONDecoder().decode([ProjectSensorRule].self, from: $0) } ?? []
    }

    static func save(rules: [ProjectSensorRule], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: ProjectSensorKeys.rules) }
    }

    private static var running = false

    /// Runs the stored sensor once. The stored path is re-validated on every
    /// call: it must resolve inside `folder` and be a `.applescript` file.
    /// `.notRun` when nothing was run (no/invalid script, or one already running).
    static func runSelected() async -> SensorRun {
        guard !running,
              let stored = UserDefaults.standard.string(forKey: ProjectSensorKeys.script),
              let safe = SensorScriptPath.validated(stored, folder: folder.path) else { return .notRun }
        running = true
        defer { running = false }
        let result = await ScriptRunner.run(path: safe, timeout: ScriptRunner.sensorTimeout)
        return result.status == 0 ? .ran(result.stdout) : .failed
    }

    /// Session start hook. Gated by the flag; only for a current task with no
    /// project; suggests only an existing ACTIVE project; user must tap "Use".
    static func suggestForSessionStart(controller: PomodoroController) {
        guard isEnabled, let task = controller.currentTask, task.project.isEmpty else { return }
        let taskID = task.id
        Task { @MainActor in
            guard isEnabled, case .ran(let output) = await runSelected() else { return }
            guard let name = ProjectSensorMatch.suggest(output: output, rules: rules()),
                  let project = controller.ledger.activeProjectName(name),
                  controller.currentTask?.id == taskID, controller.currentTask?.project.isEmpty == true
            else { return }
            ToastCenter.shared.show(title: L("Project ‘%@’?", project),
                                    body: "Use it for the current task?",
                                    symbol: "folder.badge.questionmark",
                                    actions: [
                                        ToastAction(title: "Use") { controller.assignProject(project, toTask: taskID) },
                                        ToastAction(title: "Not now") {}
                                    ])
        }
    }

    /// Display-safe version of raw sensor text for the Test button: control and
    /// bidi characters removed, truncated. Untrusted text — shown only there.
    static func displayText(_ raw: String, limit: Int = 300) -> String {
        let bidi: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x2028, 0x2029, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                                 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        let scalars = raw.unicodeScalars.map { s -> Character in
            let v = s.value
            if v == 0x0A || v == 0x09 { return " " }
            if v < 0x20 || (0x7F...0x9F).contains(v) || bidi.contains(v) { return "\u{FFFD}" }
            return Character(s)
        }
        let text = String(scalars.filter { $0 != "\u{FFFD}" }).trimmingCharacters(in: .whitespaces)
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
