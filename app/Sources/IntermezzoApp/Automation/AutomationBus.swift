import Foundation
import IntermezzoKit

enum AutomationKeys {
    /// On when the person switched publishing for other programs on (off by default).
    static let publish = "automationPublish"
    /// Posted on every change of the state; userInfo "json" holds the state.
    static let stateNotification = "com.automit.Intermezzo.state"
    /// Posted for every event; userInfo "event" holds its name and "json" the state.
    static let eventNotification = "com.automit.Intermezzo.event"
}

/// Keeps the latest state, turns changes into events, and (when the person switched it on) publishes both for other
/// programs: a JSON file, and notifications that automation tools can listen to. Nothing leaves the Mac.
@MainActor
final class AutomationBus {
    static let shared = AutomationBus()

    /// Off by default: only then are the file and the notifications written. Break Actions that react to events
    /// work either way.
    static let publishKey = AutomationKeys.publish
    static let stateNotification = AutomationKeys.stateNotification
    static let eventNotification = AutomationKeys.eventNotification

    private(set) var state: AutomationState?
    /// Called for every event, whether or not publishing is on (Break Actions listen here).
    var onEvent: ((AutomationEvent, AutomationState) -> Void)?

    private var lastPublish = Date.distantPast
    private var fileWritten = false

    var publishing: Bool { UserDefaults.standard.bool(forKey: Self.publishKey) }

    static var stateFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Intermezzo", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    /// Called every tick with a fresh state: events for what changed, and a write only when something did
    /// (plus a refresh now and then, so a reader can tell the app is alive).
    func update(_ new: AutomationState) {
        let old = state
        state = new
        let changed = old.map { !$0.sameContent(as: new) } ?? true
        if let old, changed {
            for event in AutomationEvent.diff(from: old, to: new) { emit(event, state: new) }
        }
        guard publishing else {
            if fileWritten { removeFile() }
            return
        }
        if changed || new.updatedAt.timeIntervalSince(lastPublish) > 60 { publish(new) }
    }

    /// One event: to the Break Actions, and to other programs when publishing is on.
    func emit(_ event: AutomationEvent, state: AutomationState) {
        Trace.log("automation event: \(event.rawValue)")
        onEvent?(event, state)
        guard publishing else { return }
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(Self.eventNotification), object: nil,
            userInfo: ["event": event.rawValue, "json": state.jsonString(pretty: false)], deliverImmediately: true)
    }

    private func publish(_ state: AutomationState) {
        lastPublish = state.updatedAt
        writeFile(state)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(Self.stateNotification), object: nil,
            userInfo: ["json": state.jsonString(pretty: false), "timer": state.timer], deliverImmediately: true)
    }

    private func writeFile(_ state: AutomationState) {
        let url = Self.stateFileURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try state.jsonData().write(to: url, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            fileWritten = true
        } catch {
            Trace.log("automation state file could not be written: \(error.localizedDescription)")
        }
    }

    private func removeFile() {
        try? FileManager.default.removeItem(at: Self.stateFileURL)
        fileWritten = false
    }
}

/// Runs one of the person's own Shortcuts with the event and the state as its input (a JSON file).
enum AutomationShortcutRunner {
    /// Longer than the Focus shortcuts get: a shortcut for automation may do real work.
    private static let timeout: TimeInterval = 60

    @MainActor static func run(name: String, trigger: String, event: AutomationEvent?) {
        guard FocusShortcuts.isAvailable else {
            Trace.log("run shortcut: the Shortcuts command line tool is not available")
            return
        }
        let payload = AutomationPayload(trigger: trigger, event: event?.rawValue, state: AutomationBus.shared.state)
        let data = payload.jsonData()
        Task {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("intermezzo-input-\(UUID().uuidString).json")
            do {
                try data.write(to: url, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                Trace.log("run shortcut: the input file could not be written")
                return
            }
            defer { try? FileManager.default.removeItem(at: url) }
            let result = await ShortcutPlan.run(
                name,
                lister: { await FocusShortcutsStatus.shared.sharedListing().names },
                launcher: { name in try ShortcutProcess.launch(["run", name, "-i", url.path]) },
                timeout: timeout)
            switch result {
            case .success: Trace.log("run shortcut: ran (\(trigger))")
            case .failure(let error): Trace.log("run shortcut: failed (\(error))")
            }
        }
    }
}
