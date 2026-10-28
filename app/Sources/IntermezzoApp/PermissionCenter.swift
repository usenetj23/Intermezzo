import AppKit
import ApplicationServices
import CoreGraphics
import CoreLocation
import EventKit
import IOKit.hidsystem
import UserNotifications

enum PermissionStatus: Equatable {
    case granted
    /// Never asked (or the system cannot tell): asking shows the system prompt.
    case notDetermined
    /// Refused or revoked: only System Settings can change it.
    case denied
}

enum PermissionKind: String, CaseIterable, Identifiable {
    case inputMonitoring, screenRecording, accessibility, automation, location, notifications, calendar, fullDiskAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputMonitoring: return "Input Monitoring"
        case .screenRecording: return "Screen Recording"
        case .accessibility: return "Accessibility"
        case .automation: return "Automation (System Events)"
        case .location: return "Location"
        case .notifications: return "Notifications"
        case .calendar: return "Calendar"
        case .fullDiskAccess: return "Full Disk Access"
        }
    }

    /// What breaks without it.
    var usedFor: String {
        switch self {
        case .inputMonitoring: return "Natural-break detection (Event Monitor); falls back to polling without it"
        case .screenRecording: return "Real desktop behind rain and glass effects; a procedural backdrop is used without it"
        case .accessibility: return "Gallery scripts that read window titles through System Events"
        case .automation: return "AppleScript rules that ask System Events about apps and windows"
        case .location: return "Weather, sun position, geofence zone and Wi-Fi network name"
        case .notifications: return "Break reminders, hydration and backup alerts"
        case .calendar: return "Meeting and holiday detection, calendar-aware breaks"
        case .fullDiskAccess: return "Reading Focus modes (work zone and pausing by Focus); optional"
        }
    }

    var settingsPane: String {
        switch self {
        case .inputMonitoring: return "Privacy_ListenEvent"
        case .screenRecording: return "Privacy_ScreenCapture"
        case .accessibility: return "Privacy_Accessibility"
        case .automation: return "Privacy_Automation"
        case .location: return "Privacy_LocationServices"
        case .notifications: return "Privacy_Notifications"
        case .calendar: return "Privacy_Calendars"
        case .fullDiskAccess: return "Privacy_AllFiles"
        }
    }

    /// `tccutil` service name; nil where the permission is not stored in TCC.
    var tccService: String? {
        switch self {
        case .inputMonitoring: return "ListenEvent"
        case .screenRecording: return "ScreenCapture"
        case .accessibility: return "Accessibility"
        case .automation: return "AppleEvents"
        case .calendar: return "Calendar"
        case .fullDiskAccess: return "SystemPolicyAllFiles"
        case .location, .notifications: return nil
        }
    }
}

/// Single source of truth for every permission the app depends on. Statuses are
/// always read from the system, never inferred from "we asked once".
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    @Published private(set) var lastMessage = ""
    /// Reset with tccutil in this run. The system APIs keep answering from the
    /// process's cache until a relaunch, so these show as "not decided" until then.
    @Published private(set) var resetThisRun: Set<PermissionKind> = []

    private let bundleID = Bundle.main.bundleIdentifier ?? "com.automit.Intermezzo"
    private static let askedKey = "permissionAsked."

    func status(_ kind: PermissionKind) -> PermissionStatus { statuses[kind] ?? .notDetermined }

    // MARK: - Reading

    func refresh() {
        var next = statuses
        next[.inputMonitoring] = Self.inputMonitoring()
        next[.screenRecording] = CGPreflightScreenCaptureAccess()
            ? .granted : (asked(.screenRecording) ? .denied : .notDetermined)
        next[.accessibility] = AXIsProcessTrusted()
            ? .granted : (asked(.accessibility) ? .denied : .notDetermined)
        next[.location] = Self.location(CLLocationManager().authorizationStatus)
        next[.calendar] = Self.calendar(EKEventStore.authorizationStatus(for: .event))
        next[.fullDiskAccess] = Self.fullDiskAccess()
        for kind in resetThisRun where kind != .automation { next[kind] = .notDetermined }
        statuses = next

        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let value = Self.notifications(settings.authorizationStatus)
                Task { @MainActor in self.statuses[.notifications] = value }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            let value = Self.automation(ask: false)
            Task { @MainActor in self.statuses[.automation] = value }
        }
    }

    nonisolated static func inputMonitoring() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .notDetermined
        }
    }

    /// macOS has no API for Full Disk Access: it is granted when a protected file (the Focus database) can be read.
    nonisolated static func fullDiskAccess() -> PermissionStatus {
        let path = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
        if FileManager.default.isReadableFile(atPath: path), FileManager.default.contents(atPath: path) != nil { return .granted }
        return FileManager.default.fileExists(atPath: path) ? .denied : .notDetermined
    }

    nonisolated static func location(_ s: CLAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    nonisolated static func calendar(_ s: EKAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied              // write-only cannot read titles
        }
    }

    nonisolated static func notifications(_ s: UNAuthorizationStatus) -> PermissionStatus {
        switch s {
        case .authorized, .provisional, .ephemeral: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Asks System Events whether we may drive it. `ask: false` never prompts.
    nonisolated static func automation(ask: Bool) -> PermissionStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let code = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        switch Int(code) {
        case 0: return .granted
        case -1743: return .denied                 // errAEEventNotPermitted
        default: return .notDetermined             // -1744 would prompt; -600 System Events not running
        }
    }

    /// The system only prompts for a target that is running (otherwise -600), so start System Events hidden first.
    nonisolated static func launchSystemEventsIfNeeded() {
        let id = "com.apple.systemevents"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + 5)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Asking / opening

    func request(_ kind: PermissionKind) {
        switch (kind, status(kind)) {
        case (_, .granted):
            return
        case (.inputMonitoring, .notDetermined):
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case (.screenRecording, .notDetermined):
            markAsked(.screenRecording)
            CGRequestScreenCaptureAccess()
        case (.accessibility, .notDetermined):
            markAsked(.accessibility)
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case (.automation, .notDetermined):
            DispatchQueue.global(qos: .userInitiated).async {
                Self.launchSystemEventsIfNeeded()
                let result = Self.automation(ask: true)
                Trace.log("automation permission request -> \(result)")
                Task { @MainActor in
                    self.refresh()
                    // No prompt appeared (still unknown): send the user to the pane instead of doing nothing.
                    if result == .notDetermined { self.openSettings(.automation) }
                }
            }
        case (.location, .notDetermined):
            WorkDetector.shared.requestLocationAuthorization()
        case (.notifications, .notDetermined):
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { @MainActor in self.refresh() }
            }
        case (.calendar, .notDetermined):
            WorkDetector.shared.requestAccess()
        default:
            openSettings(kind)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.refresh() }
    }

    func openSettings(_ kind: PermissionKind) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Reset

    /// Forget the stored decision so the system asks again. Returns a message for the UI.
    @discardableResult
    func reset(_ kinds: [PermissionKind]) -> String {
        var failed: [String] = []
        for kind in kinds {
            guard let service = kind.tccService else { continue }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleID]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus != 0 {
                    failed.append(L(kind.title))
                } else {
                    resetThisRun.insert(kind)
                }
            } catch {
                failed.append(L(kind.title))
            }
            UserDefaults.standard.removeObject(forKey: Self.askedKey + kind.rawValue)
        }
        lastMessage = failed.isEmpty
            ? String(localized: "Decisions reset in macOS. Intermezzo sees the new state only after a restart: click Restart, then Allow… on each row. Location and notifications can only be changed in System Settings.")
            : String(localized: "Could not reset: \(failed.joined(separator: ", "))")
        refresh()
        return lastMessage
    }

    private func asked(_ kind: PermissionKind) -> Bool {
        UserDefaults.standard.bool(forKey: Self.askedKey + kind.rawValue)
    }

    private func markAsked(_ kind: PermissionKind) {
        UserDefaults.standard.set(true, forKey: Self.askedKey + kind.rawValue)
    }
}
