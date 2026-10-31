import AppKit
import CoreLocation
import IntermezzoKit

/// Gathers what a bug report needs and puts it on the pasteboard. Nothing is sent anywhere.
@MainActor
enum DiagnosticsCollector {
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func yesNo(_ value: Bool, _ yes: String, _ no: String) -> String { value ? yes : no }

    static func report() -> DiagnosticsReport {
        let info = Bundle.main.infoDictionary
        let defaults = UserDefaults.standard
        let memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())

        let app: [(name: String, value: String)] = [
            ("Version", "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"),
            ("Language", Bundle.main.preferredLocalizations.first ?? "?"),
            ("Theme", defaults.string(forKey: SurfaceTheme.key) ?? "default"),
        ]
        let system: [(name: String, value: String)] = [
            ("macOS", macOSVersion()),
            ("Mac", sysctlString("hw.model") ?? "?"),
            ("Chip", sysctlString("machdep.cpu.brand_string") ?? "?"),
            ("Cores", "\(ProcessInfo.processInfo.processorCount)"),
            ("Memory", "\(memoryGB) GB"),
        ]
        let displays: [(name: String, value: String)] = NSScreen.screens.enumerated().map { index, screen in
            let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height)) @\(Int(screen.backingScaleFactor))x"
            let notch = screen.safeAreaInsets.top > 0 ? ", notch" : ""
            return ("#\(index + 1)", "\(screen.localizedName), \(size)\(notch)")
        }
        let permissions: [(name: String, value: String)] = PermissionKind.allCases.map {
            ($0.title, String(describing: PermissionCenter.shared.status($0)))
        }
        let coordinator = AppDelegate.shared?.coordinator
        let idleMethod = defaults.string(forKey: "idleDetectionMethod") ?? "source"
        var features: [(name: String, value: String)] = [
            ("Idle detection", idleMethod == "monitor"
                ? yesNo(coordinator?.eventMonitor.isRunning == true, "Event Monitor", "Event Monitor requested, fell back to Event Source")
                : idleMethod),
            ("Ambient light sensor", yesNo(AmbientSensor.shared.smoothedLux() != nil, "reads", "no reading")),
            ("Now Playing (MediaRemote)", yesNo(MediaPauser.mediaRemoteLoaded, "loaded", "not available")),
            ("Focus modes", yesNo(WorkDetector.focusSnapshot() != nil, "readable", "not readable (Full Disk Access)")),
            ("BetterDisplay", String(describing: BetterDisplayLight.shared.link)),
            ("Location Services", yesNo(CLLocationManager.locationServicesEnabled(), "on", "off")
                + ", Mac position " + yesNo(defaults.object(forKey: GlassKeys.lat) != nil, "known", "not known yet")),
            ("Light", yesNo(defaults.bool(forKey: LightKeys.enabled), "on", "off")),
            ("Weather on the break screen", WeatherController.shared.snapshot.map {
                "\(WeatherController.shared.lastStatus); data \(Int(Date().timeIntervalSince($0.fetchedAt) / 60)) min old"
            } ?? WeatherController.shared.lastStatus),
        ]
        let unsupported = LightController.shared.unsupportedDisplays
        if !unsupported.isEmpty { features.append(("Displays without colour control", unsupported.joined(separator: ", "))) }

        let raw = (try? String(contentsOfFile: Trace.logPath, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true).suffix(2000).map(String.init) ?? []
        return DiagnosticsReport(
            sections: [.init("App", app), .init("System", system), .init("Displays", displays),
                       .init("Permissions", permissions), .init("Features and fallbacks", features)],
            logLines: DiagnosticsReport.safeLogLines(raw, home: NSHomeDirectory()))
    }

    /// "27.2 (build 26B123)" in English whatever the system language is.
    private static func macOSVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let build = sysctlString("kern.osversion").map { " (build \($0))" } ?? ""
        return "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "") + build
    }

    /// Reads the permission states first: they are only refreshed while the Permissions list is on screen, and the
    /// notification and automation answers arrive a moment later (the report waits for them).
    static func copyToPasteboard(then done: @escaping () -> Void = {}) {
        PermissionCenter.shared.refresh {
            let text = report().markdown()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Trace.log("diagnostics copied to the pasteboard (\(text.count) characters)")
            done()
        }
    }
}
