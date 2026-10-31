import AppKit
import CoreGraphics
import SwiftUI
import SwiftData
import Combine
import os
import ServiceManagement
import UserNotifications
import IntermezzoKit

/// Borderless panels refuse key status by default; the menu-bar panel must
/// become key so a click elsewhere (resign key) can dismiss it.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the NSStatusItem (icon + live countdown), the menu-bar panel
/// (popup) and deeplink handling.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    private(set) static var shared: AppDelegate!

    private(set) var coordinator: BreakCoordinator!
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var chip: FloatingChip?
    private var lastEscape = Date.distantPast
    private var parkedStreak = 0
    private var hotkeys: HotkeyController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must exist before any deeplink (openURL) event can arrive —
        // AppKit may deliver `application(_:open:)` before didFinishLaunching.
        AppDelegate.shared = self
        // A menu-bar app starts as just its icon. Without this macOS saves the open Settings window when the app
        // quits and brings it back at the next launch (after a login, a restart or a relaunch).
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        if coordinator == nil {
            coordinator = BreakCoordinator(modelContainer: Store.container)
        }
    }

    private var quitGuardMonitor: Any?

    func applicationWillTerminate(_ notification: Notification) {
        // Keep the work-time register exact to the last activity.
        WorkLogController.shared.finish()
        BetterDisplayLight.shared.shutdown()
        LightController.shared.shutdown()
        KeepAwakeController.shared.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchGuardUntil = Date().addingTimeInterval(Self.launchGuardSeconds)
        // `Intermezzo --reset-light`: put the system colours back (a way out if a screen stays tinted).
        if CommandLine.arguments.contains("--reset-light") {
            CGDisplayRestoreColorSyncSettings()
            NSApp.terminate(nil)
            return
        }
        SyncController.shared.start()
        LightController.shared.start()
        UpdateChecker.shared.startAutomaticChecks()
        KeepAwakeController.shared.start()
        if coordinator == nil {
            coordinator = BreakCoordinator(modelContainer: Store.container)
        }
        // Without an explicit request macOS silently drops every notification.
        // (UNUserNotificationCenter traps outside an .app bundle, e.g. `swift run`.)
        if Bundle.main.bundleURL.pathExtension == "app" {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                Trace.log("notifications auth: granted=\(granted) err=\(error?.localizedDescription ?? "-")")
            }
        }
        buildStatusItem()
        let chip = FloatingChip()
        chip.onClick = { [weak self] in self?.statusItemClicked() }
        self.chip = chip
        ToastCenter.shared.topInset = { [weak chip] in chip?.isVisible == true ? 40 : 0 }
        startSettingsWindowWatchdog()
        startLaunchGuard()
        buildPanel()

        // Self-heal login item: if autostart is enabled, (re-)register at every
        // launch so the menu bar icon always comes back after login/reboot.
        if UserDefaults.standard.integer(forKey: Keys.autostart) != 0,
           #available(macOS 13, *) {
            do { try SMAppService.mainApp.register() }
            catch { NSLog("Intermezzo: SMAppService register failed: \(error)") }
        }

        // Duplicate-copy alert (max once per day): two copies
        // of the app on one Mac cause the wrong helper to launch.
        if UserDefaults.standard.integer(forKey: Keys.alertDuplicates) != 0 {
            let lastKey = "lastDuplicateAlertDate"
            let last = UserDefaults.standard.double(forKey: lastKey)
            if Date().timeIntervalSince1970 - last > 86_400 {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                    let copies = DuplicateScanner.findOtherCopies(excluding: Bundle.main.bundleURL)
                    Trace.log("duplicate scan: \(copies.count) hit(s)")
                    guard !copies.isEmpty else { return }
                    DispatchQueue.main.async {
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastKey)
                        self.coordinator.post(
                            title: "Znaleziono drugą kopię Intermezzo",
                            body: copies.joined(separator: "\n") + "\n" + L("Zostaw tylko jedną (sprawdź też Kosz)."),
                            symbol: "exclamationmark.triangle.fill")
                        Trace.log("duplicate copies detected: \(copies)")
                    }
                }
            }
        }

        coordinator.$statusSymbol
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] symbol in
                self?.applyStatusIcon()
                self?.chip?.update(text: self?.coordinator.statusText ?? "", symbol: symbol)
            }
            .store(in: &cancellables)

        // The icon colour follows the timer state; the option itself is read from the defaults.
        GateDiagnostics.shared.$report
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyStatusIcon() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyStatusIcon() }
            .store(in: &cancellables)

        coordinator.$statusText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                if UserDefaults.standard.integer(forKey: Keys.menuBarCountdown) != 0,
                   !(self?.hasNotchScreen ?? false)
                       || UserDefaults.standard.integer(forKey: Keys.menuBarCountdownNotch) != 0 {
                    if self?.statusItem.button?.title != " " + text { self?.statusItem.button?.title = " " + text }
                } else {
                    // Either the user disabled the text, or this is a notched
                    // MacBook: a full menu bar slides wide items behind the
                    // housing. Icon-only always survives — keep the dot,
                    // the countdown lives in the cursor ring instead.
                    if self?.statusItem.button?.title.isEmpty == false { self?.statusItem.button?.title = "" }
                }
                self?.chip?.update(text: text, symbol: self?.coordinator.statusSymbol ?? "timer")
                // When a break starts, the full-screen overlay takes over —
                // drop the popup so nothing floats above it.
                if self?.coordinator.isOnBreak == true, self?.panel.isVisible == true {
                    self?.closePanel()
                }
            }
            .store(in: &cancellables)

        // Global hotkeys (Ctrl+Opt+B/L start break, S skip, P pause toggle).
        let hk = HotkeyController()
        hk.onStartShort = { [weak self] in self?.coordinator.takeShortNow(source: "hotkey"); self?.dismissPanel() }
        hk.onStartLong = { [weak self] in self?.coordinator.takeLongNow(source: "hotkey"); self?.dismissPanel() }
        hk.onSkip = { [weak self] in self?.coordinator.handleSkip(source: "hotkey") }
        hk.onTogglePause = { [weak self] in self?.coordinator.togglePause() }
        hk.onPostpone = { [weak self] in self?.coordinator.snooze(minutes: 5) }
        hk.onPauseAll = { [weak self] in self?.coordinator.pauseAll(); self?.dismissPanel() }
        hk.onResumeAll = { [weak self] in self?.coordinator.resumeAll() }
        hk.onResetAll = { [weak self] in self?.coordinator.resetAll() }
        hk.onStopSound = { [weak self] in self?.coordinator.stopSounds() }
        hk.install()
        hotkeys = hk

        // Block Cmd+Q while a break overlay owns the screen, so a reflex quit
        // can't end the break.
        // Kept for the app's lifetime (an unreferenced monitor shows up as a leak).
        quitGuardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.coordinator.isOnBreak else { return event }
            if event.keyCode == 12, event.modifierFlags.contains(.command) {
                NSSound.beep()
                return nil
            }
            // Emergency exit that needs no mouse: Esc twice within 0.7 s ends the break
            // (not in strict mode). The global hotkey ⌃⌥S does the same from anywhere.
            if event.keyCode == 53, !event.isARepeat,
               UserDefaults.standard.integer(forKey: Keys.strictMode) == 0 {
                if Date().timeIntervalSince(self.lastEscape) < 0.7 {
                    self.lastEscape = .distantPast
                    self.coordinator.handleSkip(source: "esc")
                    return nil
                }
                self.lastEscape = Date()
            }
            return event
        }

        coordinator.startIfNeeded()
        // Warm the weather cache so the FIRST break after launch already has a scene.
        WeatherController.shared.refreshIfNeeded()
    }

    /// Banners are suppressed for the frontmost app by default — and Intermezzo is
    /// frontmost whenever Settings is open. Always present them.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler:
                                            @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// A button pressed on a notification in Notification Center.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let requestID = response.notification.request.identifier
        let actionID = response.actionIdentifier
        Task { @MainActor in
            SystemNotificationActions.shared.handle(requestID: requestID, actionID: actionID)
            completionHandler()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleAutomationURL(url)
        }
    }

    /// Public automation addresses are parsed by `AutomationURL` (Kit) and listed in `AutomationCatalog`.
    /// Debug deeplinks may only write inside temporary folders (see DebugOutputPath).
    /// `roots` defaults to the render roots (shared /tmp + temp folder); the report
    /// passes `DebugOutputPath.reportRoots` (per-user temp folder only).
    private func debugOut(_ raw: String?, _ name: String, _ ext: Set<String>, _ tag: String,
                          roots: [String] = DebugOutputPath.renderRoots(temporaryDirectory: NSTemporaryDirectory())) -> URL? {
        let url = DebugOutputPath.validated(raw, defaultName: name, allowedExtensions: ext, allowedRoots: roots)
        if url == nil {
            Trace.log("debug output path refused (\(tag)): must be a \(ext.sorted().joined(separator: "/")) file inside \(roots.joined(separator: " or "))")
        }
        return url
    }

    /// `debug/report` runs one export at a time, with a cooldown after it.
    private var reportGate = ExclusiveRun(cooldown: 2)

    private func run(_ command: AutomationCommand) {
        switch command {
        case .startShort: coordinator.takeShortNow(source: "url")
        case .startLong: coordinator.takeLongNow(source: "url")
        case .postpone(let minutes): coordinator.snooze(minutes: minutes)
        case .skip: coordinator.handleSkip(source: "url")
        case .button(let title): coordinator.fireButtonTitle(title)
        case .pause: coordinator.pauseAll()
        case .resume: coordinator.resumeAll()
        case .reset: coordinator.resetAll()
        case .stopSound: coordinator.stopSounds()
        case .flash: coordinator.flash.pulse()
        case .notify: coordinator.sendTestNotification()
        case .openPanel: if !panel.isVisible { openPanel() }
        case .closePanel: dismissPanel()
        case .awakeOn: KeepAwakeController.shared.turnOn()
        case .awakeOff: KeepAwakeController.shared.turnOff()
        case .awakeToggle: KeepAwakeController.shared.toggle()
        case .awakeFor(let minutes): KeepAwakeController.shared.turnOn(duration: .minutes(minutes))
        case .lightOn: LightController.shared.setEnabled(true)
        case .lightOff: LightController.shared.setEnabled(false)
        case .lightPause(let minutes): LightController.shared.disable(forMinutes: minutes)
        case .settings(let link):
            // intermezzo://settings/workLog opens a given pane.
            if let link, let pane = SettingsPane(link: link) { SettingsPane.pending = pane }
            openSettingsWindow()
            NotificationCenter.default.post(name: .openSettingsPane, object: nil)
        }
    }

    private func handleAutomationURL(_ url: URL) {
        let parts = url.path.split(separator: "/").map(String.init)
        let next = parts.isEmpty ? nil : parts.first

        if url.host?.lowercased() != "debug", let command = AutomationURL.parse(host: url.host, path: parts) {
            run(command)
            return
        }

        switch url.host {
        case "debug":
            // intermezzo://debug/flag?k=fxNoFog&v=1 — zapis do UserDefaults in-process
            // (natychmiast widoczny w renderingu; służy do binarnego szukania crashy).
            // intermezzo://debug/settings-close — closes the Settings window (for the open/close test).
            if next == "settings-close" { settingsWindow()?.close() }
            if next == "flag" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                // Any web page can open this URL: only the allow-listed fx render
                // flags may be touched (set AND remove). The value is never logged.
                if let k = q.first(where: { $0.name == "k" })?.value {
                    guard DebugFlagPolicy.isAllowed(key: k) else {
                        Trace.log("debug flag refused: key not on the allow-list")
                        return
                    }
                    if let v = q.first(where: { $0.name == "v" })?.value {
                        UserDefaults.standard.set(v, forKey: k)
                    } else {
                        UserDefaults.standard.removeObject(forKey: k)
                    }
                    Trace.log("flag \(k)=\(UserDefaults.standard.string(forKey: k) ?? "(nil)")")
                }
            }
            // intermezzo://debug/weather?effect=rain|snow|fog|storm|cloudy|clear&wind=15
            // intermezzo://debug/hit?fx=0.5&fy=0.9 — which view would receive a click at that
            // fraction of each break-overlay window (logs the view chain).
            if next == "hit" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> Double { Double(q.first { $0.name == name }?.value ?? "") ?? 0.5 }
                for w in NSApp.windows where w.level == .screenSaver && w.isVisible {
                    let p = NSPoint(x: w.frame.width * qp("fx"), y: w.frame.height * (1 - qp("fy")))
                    var chain: [String] = []
                    var v = w.contentView?.hitTest(p)
                    while let cur = v, chain.count < 6 { chain.append(String(describing: type(of: cur))); v = cur.superview }
                    Trace.log("hit-test fx=\(qp("fx")) fy=\(qp("fy")) screen=\(Int(w.frame.width))x\(Int(w.frame.height)) -> \(chain.joined(separator: " < "))")
                }
            }
            // intermezzo://debug/permissions — log what the app itself reads from the system
            // (no windows, no prompts).
            if next == "permissions" {
                PermissionCenter.shared.refresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let line = PermissionKind.allCases
                        .map { "\($0.rawValue)=\(PermissionCenter.shared.status($0))" }
                        .joined(separator: " ")
                    Trace.log("permissions: \(line)")
                }
            }
            // intermezzo://debug/shortcuts — prove `shortcuts list` parsing on this Mac: logs only
            // the count and whether every name parsed (never the names; never runs a shortcut).
            // Only with the feature on, and through the one shared in-flight listing.
            if next == "shortcuts" {
                guard FocusShortcutsStatus.isEnabled else {
                    Trace.log("shortcuts: debug list refused, feature is off")
                    return
                }
                Task {
                    let listing = await FocusShortcutsStatus.shared.sharedListing()
                    let names = listing.names
                    let parsed = names.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isNewline) }
                    Trace.log("shortcuts: available=\(FocusShortcuts.isAvailable) failed=\(listing == .failed) found=\(names.count) namesParse=\(parsed)")
                }
            }
            // intermezzo://debug/report?range=day|week|month&out=<temp dir>/r.pdf (or .csv) — write a
            // report without opening any window; the result goes to the Trace log. The report holds
            // billing data: only the per-user temp folder is allowed, the file is made 0600, and a
            // request arriving while one runs (or within 2 s after) is ignored.
            if next == "report" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                let period: ReportPeriod = qp("range") == "day" ? .today : (qp("range") == "month" ? .month : .week)
                let range = period.range()
                guard let out = debugOut(qp("out"), "intermezzo-report.pdf", ["pdf", "csv"], "report",
                                         roots: DebugOutputPath.reportRoots(temporaryDirectory: NSTemporaryDirectory()))
                else { return }
                guard reportGate.tryBegin(now: Date()) else {
                    Trace.log("report ignored: another report request is running or just finished")
                    return
                }
                defer { reportGate.finish(now: Date()) }
                do {
                    let data = ReportData.load(range: range)
                    if out.pathExtension.lowercased() == "csv" {
                        try ReportExporter.exportCSV(data: data, range: range, to: out)
                    } else {
                        try ReportExporter.exportPDF(data: data, range: range, to: out)
                    }
                    try DebugOutputPath.restrictToOwner(out)
                    Trace.log("report written: \(out.path) pages=\(ReportLayout.pages(range: range, calendar: .current))")
                } catch {
                    Trace.log("report FAILED: \(error.localizedDescription)")
                }
            }
            // intermezzo://debug/rainsnap?w=1400&h=800&seconds=20&storm=0&wind=6&out=/tmp/rain.png
            // Offline render of the Metal rain to a PNG — no window, no overlay on screen.
            if next == "rainsnap" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                let size = CGSize(width: DebugRenderLimits.dimension(qp("w"), default: 1400),
                                  height: DebugRenderLimits.dimension(qp("h"), default: 800))
                guard let outURL = debugOut(qp("out"), "intermezzo-rain.png", ["png"], "rainsnap") else { return }
                let out = outURL.path
                if let img = RainMetalView.snapshot(size: size, seconds: DebugRenderLimits.seconds(qp("seconds"), default: 20),
                                                    storm: qp("storm") == "1",
                                                    windKmh: Double(qp("wind") ?? "") ?? 6),
                   let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                    Trace.log("rainsnap written: \(out)")
                } else {
                    Trace.log("rainsnap FAILED")
                }
            }
            // intermezzo://debug/fxwindow?effect=snow&w=1200&h=700&seconds=12
            // Shows a weather scene in a borderless window BELOW every other window that ignores the
            // mouse (clicks always pass through); logs its window number so it can be captured with
            // `screencapture -l <id>`. Closes itself after `seconds`.
            if next == "fxwindow" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                if let effect = WeatherEffect(rawValue: qp("effect") ?? "snow") {
                    let size = NSSize(width: DebugRenderLimits.dimension(qp("w"), default: 1200),
                                      height: DebugRenderLimits.dimension(qp("h"), default: 700))
                    let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 120), size: size),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
                    win.isReleasedWhenClosed = false
                    win.ignoresMouseEvents = true
                    win.level = NSWindow.Level(rawValue: -1)
                    win.backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1)
                    win.contentView = NSHostingView(rootView: WeatherFXView(effect: effect,
                        windKmh: Double(qp("wind") ?? "") ?? 8).ignoresSafeArea())
                    win.orderBack(nil)
                    Trace.log("fxwindow \(effect.rawValue) id=\(win.windowNumber)")
                    let secs = DebugRenderLimits.seconds(qp("seconds"), default: 12)
                    DispatchQueue.main.asyncAfter(deadline: .now() + secs) { win.orderOut(nil); win.close() }
                }
            }
            // intermezzo://debug/skysnap?mode=clouds|fog|sun&w=1400&h=800&t=40&mx=0.5&my=0.5&out=/tmp/sky.png
            if next == "skysnap" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                let mode: SkyMode = qp("mode") == "fog" ? .fog : qp("mode") == "sun" ? .sun : .clouds
                let size = CGSize(width: DebugRenderLimits.dimension(qp("w"), default: 1400),
                                  height: DebugRenderLimits.dimension(qp("h"), default: 800))
                let mouse = SIMD2<Float>(Float(qp("mx") ?? "") ?? 0.5, Float(qp("my") ?? "") ?? 0.5)
                if let img = SkyMetalView.snapshot(mode: mode, size: size, time: DebugRenderLimits.seconds(qp("t"), default: 40),
                                                   wind: Double(qp("wind") ?? "") ?? 8, mouse: mouse),
                   let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                    if let dest = debugOut(qp("out"), "intermezzo-sky.png", ["png"], "skysnap") {
                        try? png.write(to: dest)
                        Trace.log("skysnap written")
                    }
                } else {
                    Trace.log("skysnap FAILED")
                }
            }
            // intermezzo://debug/themewindow?seconds=10 — the menu-bar panel in the CURRENT surface theme, in a
            // click-through window under every other window (capture with `screencapture -l <id>`).
            if next == "themewindow" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let secs = Double(q.first { $0.name == "seconds" }?.value ?? "") ?? 10
                let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 160), size: Self.panelSize),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
                win.isReleasedWhenClosed = false
                win.ignoresMouseEvents = true
                win.level = NSWindow.Level(rawValue: -1)
                win.isOpaque = false
                win.backgroundColor = .clear
                win.contentView = SurfaceHost.make(MenuBarPanelView(coordinator: coordinator),
                                                   size: Self.panelSize, corner: 20)
                win.orderBack(nil)
                Trace.log("themewindow id=\(win.windowNumber)")
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) { win.orderOut(nil); win.close() }
            }
            if next == "weather" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                if let raw = qp("effect"), let effect = WeatherEffect(rawValue: raw) {
                    WeatherController.shared.debugForce(effect: effect,
                                                        windKmh: Double(qp("wind") ?? "") ?? 12)
                }
            }
            // intermezzo://debug/snapshot?kind=rain&fog=0.22&wind=20&out=/path.png
            // Headless render efektu do PNG (ImageRenderer) — tylko do weryfikacji.
            if next == "snapshot" {
                let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func qp(_ name: String) -> String? { q.first { $0.name == name }?.value }
                let kind = qp("kind") ?? "rain"
                if kind == "livewire" {
                    // cacheDisplay realnego okna overlay (bez uprawnień Nagrywania).
                    // &scope=all → również mniejsze panele (karta przed pauzą).
                    let onlyOverlays = (qp("scope") ?? "overlay") != "all"
                    guard let liveOut = debugOut(qp("out"), "intermezzo-live.png", ["png"], "livewire") else { return }
                    Task { @MainActor in
                        for w in NSApplication.shared.windows {
                            if !w.isVisible || w.alphaValue < 0.1 { continue }
                            if onlyOverlays, w.level != .screenSaver { continue }
                            guard let cv = w.contentView, w.frame.width >= 50 else { continue }
                            Trace.log("livewire win class=\(type(of: w)) frame=\(w.frame) alpha=\(w.alphaValue) level=\(w.level.rawValue) subviews=\(cv.subviews.count)")
                            let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                       pixelsWide: Int(w.frame.width),
                                                       pixelsHigh: Int(w.frame.height),
                                                       bitsPerSample: 8, samplesPerPixel: 4,
                                                       hasAlpha: true, isPlanar: false,
                                                       colorSpaceName: .deviceRGB,
                                                       bytesPerRow: 0, bitsPerPixel: 0)
                            guard let rep2 = rep else { break }
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep2)
                            cv.cacheDisplay(in: NSRect(origin: .zero, size: cv.bounds.size), to: rep2)
                            NSGraphicsContext.restoreGraphicsState()
                            // NSVisualEffectView + nonactivating panel: cacheDisplay bywa
                            // pusty — wymuś pełne odrysowanie i spróbuj ponownie.
                            if let raw = rep2.representation(using: .png, properties: [:]),
                               raw.count < 2000 {
                                cv.displayIfNeeded()
                                cv.cacheDisplay(in: NSRect(origin: .zero, size: cv.bounds.size), to: rep2)
                            }
                            if let data = rep2.representation(using: .png, properties: [:]) {
                                let outPath = liveOut.path
                                    .replacingOccurrences(of: ".png",
                                        with: "-\(w.frame.origin.x)x\(w.frame.origin.y)-\(Int(w.frame.width)).png")
                                try? data.write(to: URL(fileURLWithPath: outPath))
                                Trace.log("livewire captured -> \(outPath)")
                            }
                        }
                    }
                    break
                }
                guard let outURL = debugOut(qp("out"), "intermezzo-fx.png", ["png"], "snapshot") else { return }
                let out = outURL.path
                let fog = qp("fog").flatMap { Double($0) }
                let wind = qp("wind").flatMap { Double($0) }
                Task { @MainActor in
                    let ok = renderWeatherSnapshot(kind: kind, outPath: out, fogOverride: fog, windOverride: wind)
                    Trace.log("debug snapshot \(kind): \(ok ? "ok" : "FAIL") -> \(out)")
                }
            }
        default:        break
        }
    }

    // MARK: - Status item

    /// True when our status item's frame falls into the notch gap of a
    /// notched display (menu-bar full → macOS slides extras behind the
    /// notch and they become invisible). When that happens we drop the
    /// countdown TEXT and keep the icon alone — it is a third of the width
    /// and can slide back into the visible strip. Hysteresis: once we have
    /// seen the overlap we keep the icon-only mode for 5 minutes, otherwise
    /// add-text → shrink → show-text → overlap flickers once per second.
    /// True when any connected display is a MacBook with a camera notch
    /// (safeAreaInsets.top > 0). On those machines a full menu bar hides
    /// wide custom items behind the housing, so we stay icon-only there.
    private var hasNotchScreen: Bool {
        NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    /// True when `f` overlaps the camera-housing gap of a notched display.
    private func frameBehindNotch(_ f: NSRect) -> Bool {
        for screen in NSScreen.screens where screen.frame.intersects(f) {
            guard screen.safeAreaInsets.top > 0,
                  let left = screen.auxiliaryTopLeftArea,
                  let right = screen.auxiliaryTopRightArea,
                  right.minX > left.maxX else { continue }
            if f.minX < right.minX && f.maxX > left.maxX { return true }
        }
        return false
    }

    private var lastStatusIconKey = ""

    /// Sets the menu-bar icon: a template image (follows the menu bar) or, when asked, a symbol in the colour
    /// of the timer state. Skips the work when nothing it depends on changed.
    private func applyStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = coordinator.statusSymbol
        let colored = UserDefaults.standard.integer(forKey: Keys.menuBarColoredIcon) != 0
        let tint = GateDiagnostics.shared.report.tint
        let key = "\(symbol)|\(colored ? tint.rawValue : "-")"
        guard key != lastStatusIconKey else { return }
        lastStatusIconKey = key
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Intermezzo")
        if colored, let base = image {
            let color: NSColor
            switch tint {
            case .running: color = .systemGreen
            case .onBreak: color = .systemBlue
            case .held: color = .systemOrange
            case .outside: color = .systemPurple
            case .manual: color = .systemGray
            }
            image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        button.image = image
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "cup.and.saucer.fill",
                               accessibilityDescription: "Intermezzo")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    @objc private func statusItemClicked() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    // MARK: - Panel

    /// Taller while Pomodoro mode adds its block to the panel, and for each extra row (keep awake, Light).
    private static var panelSize: NSSize {
        let defaults = UserDefaults.standard
        var height: CGFloat = defaults.integer(forKey: PomodoroKeys.enabled) != 0 ? 528 : 440
        height += Self.panelRowHeight                                      // keep awake: always there
        if defaults.bool(forKey: LightKeys.enabled) { height += Self.panelRowHeight }
        return NSSize(width: 300, height: height)
    }

    /// One more ghost button in the panel, with its spacing.
    private static let panelRowHeight: CGFloat = 52

    /// The SwiftUI tree is created only while the panel is on screen. A hidden
    /// NSHostingView still re-lays itself out on every published countdown
    /// tick (~1 s) — measurable idle CPU and a few MB of view state for nothing.
    private func makePanelContent() -> NSView {
        SurfaceHost.make(MenuBarPanelView(coordinator: coordinator),
                         size: Self.panelSize, corner: 20)
    }

    private func buildPanel() {
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
    }

    private func openPanel() {
        panel.setContentSize(Self.panelSize)
        panel.contentView = makePanelContent()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePanel() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// Public for SwiftUI panel buttons.
    func dismissPanel() {
        if panel.isVisible { closePanel() }
    }

    private func positionPanel() {
        // Status item parked by macOS → hang the panel under the floating chip.
        if MenuBarHealth.shared.parked, let chip, chip.isVisible {
            let anchor = chip.frame
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }
                ?? NSScreen.main ?? NSScreen.screens[0]
            var frame = panel.frame
            frame.origin.x = min(max(anchor.midX - frame.width / 2, screen.frame.minX + 8),
                                 screen.frame.maxX - frame.width - 8)
            frame.origin.y = max(anchor.minY - frame.height - 6, screen.frame.minY + 8)
            panel.setFrame(frame, display: true)
            return
        }
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        guard let screen = buttonWindow.screen ?? NSScreen.main else { return }

        var frame = panel.frame
        frame.origin.x = min(max(screenRect.midX - frame.width / 2,
                                 screen.frame.minX + 8),
                             screen.frame.maxX - frame.width - 8)
        frame.origin.y = screen.frame.maxY - frame.height - 6
        panel.setFrame(frame, display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSPanel) === panel {
            closePanel()
        }
    }

    // MARK: - Open settings helper (used by panel buttons)

    /// The SwiftUI Settings scene can be opened by paths we don't control
    /// (Dock relaunch, cmd-, state restore). As an LSUIElement app its
    /// window has no Dock presence and no working minimize button, so a
    /// watchdog enforces the invariant: Settings visible → regular app with
    /// miniaturize enabled; Settings gone → back to accessory.
    private var lastMenuBarOcclusion: Bool?
    /// During the first seconds after launch a Settings window nobody asked for is closed again, so that starting at
    /// login leaves only the menu-bar icon.
    private static let launchGuardSeconds: TimeInterval = 15
    private var launchGuardUntil = Date.distantPast
    private var settingsRequested = false

    private func startLaunchGuard() {
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.settingsRequested, Date() < self.launchGuardUntil else { timer.invalidate(); return }
                for window in NSApp.windows where window.identifier?.rawValue == "com.apple.SwiftUI.settingsWindow" && window.isVisible {
                    window.close()
                    Trace.log("launch: closed a Settings window nobody asked for")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startSettingsWindowWatchdog() {
        let watchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdogTick() }
        }
        watchdog.tolerance = 0.5
    }

    private func watchdogTick() {
        coordinator?.sweepOverlayStrays()
        do {
            // Menu-bar overflow check: on a notch MacBook with a full bar
            // macOS PARKS our status item off-screen (x < screen.minX). The
            // Status pane then tells the user why the countdown is missing —
            // the only real fix is freeing menu-bar space (iStat modules…).
            if let button = statusItem?.button, let win = button.window,
               let scr = win.screen ?? NSScreen.main {
                if lastMenuBarOcclusion == nil {
                    Trace.log("status item geometry: frame=\(win.frame) visible=\(win.isVisible) isVisibleProp=\(statusItem.isVisible) screen=\(scr.frame) notchInset=\(scr.safeAreaInsets.top) title='\(button.title)' image=\(button.image != nil)")
                }
                // macOS parks overflow items as a ZERO-HEIGHT window at the origin
                // (not at negative x), so test for an empty / off-screen / notch frame.
                let f = win.frame
                let onScreen = f.height >= 1 && NSScreen.screens.contains { $0.frame.intersects(f) }
                let parkedNow = !win.isVisible || !onScreen || self.frameBehindNotch(f)
                self.parkedStreak = parkedNow ? self.parkedStreak + 1 : 0
                let parked = self.parkedStreak >= 2     // debounce layout transients
                if parked != self.lastMenuBarOcclusion {
                    self.lastMenuBarOcclusion = parked
                    MenuBarHealth.shared.set(parked: parked)
                    Trace.log(parked ? "menu bar FULL — status item parked, floating chip shown"
                                    : "status item back on screen — floating chip hidden")
                }
                // Chip modes: auto (only while parked) / always / never.
                let mode = UserDefaults.standard.string(forKey: "chipMode") ?? "auto"
                let wantChip = mode == "always" || (mode == "auto" && parked)
                if wantChip, self.chip?.isVisible != true {
                    self.chip?.show(text: self.coordinator.statusText,
                                    symbol: self.coordinator.statusSymbol)
                } else if !wantChip, self.chip?.isVisible == true {
                    self.chip?.hide()
                }
            }
            if let win = settingsWindow(), win.isVisible || win.isMiniaturized {
                if NSApp.activationPolicy() != .regular {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    Trace.log("settings window detected — promoting to regular app")
                }
                if !win.styleMask.contains(.miniaturizable) {
                    win.styleMask.insert([.miniaturizable, .resizable])
                }
            } else if NSApp.activationPolicy() == .regular, Date() >= settingsGraceUntil {
                // Grace: a miniaturized Settings window still exists, only a
                // fully closed one demotes us.
                if !(settingsWindow().map { $0.isVisible || $0.isMiniaturized } ?? false) {
                    NSApp.setActivationPolicy(.accessory)
                    Trace.log("settings window closed — back to accessory")
                }
            }
        }
    }

    /// While a request to open Settings is in flight the background check must not give the Dock icon back.
    private var settingsGraceUntil = Date.distantPast

    /// The Settings window found by what appeared after the show action. Newer macOS versions name the window
    /// differently, and its title is the selected pane, so the identifier and title checks alone can miss it.
    private weak var trackedSettingsWindow: NSWindow?

    private func settingsWindow() -> NSWindow? {
        if let tracked = trackedSettingsWindow, NSApp.windows.contains(tracked) { return tracked }
        return NSApp.windows.first { w in
            let id = w.identifier?.rawValue.lowercased() ?? ""
            return id.contains("settings")
                || w.title.localizedCaseInsensitiveContains("Settings")
                || w.title.localizedCaseInsensitiveContains("Ustawienia")
        }
    }

    /// A titled, ordinary window that was not there before the show action: the Settings window by elimination.
    private func newSettingsCandidate(since known: Set<ObjectIdentifier>) -> NSWindow? {
        NSApp.windows.first { w in
            !known.contains(ObjectIdentifier(w)) && !(w is NSPanel)
                && w.styleMask.contains(.titled) && w.level == .normal
        }
    }

    private var windowsBeforeSettings: Set<ObjectIdentifier> = []

    /// Our own Settings window, used when the SwiftUI Settings scene accepts the show action but opens nothing
    /// (seen on a newer macOS for a menu-bar app). It hosts the same view.
    private var fallbackSettingsWindow: NSWindow?

    private func showFallbackSettingsWindow() {
        if fallbackSettingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView().modelContainer(Store.container))
            let win = NSWindow(contentViewController: host)
            // Content runs under the title bar, as in the SwiftUI Settings window, so the themed backdrop
            // (blur for Glass) fills it instead of leaving a see-through strip.
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.title = "Intermezzo"
            win.identifier = NSUserInterfaceItemIdentifier("intermezzo.settingsWindow")
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 900, height: 680))
            win.center()
            fallbackSettingsWindow = win
        }
        trackedSettingsWindow = fallbackSettingsWindow
        Trace.log("settings: the Settings scene opened nothing, showing our own window")
    }

    private func sendShowSettingsAction() -> Bool {
        if #available(macOS 14, *) {
            if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return true }
        }
        return NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }

    func openSettingsWindow() {
        settingsRequested = true
        dismissPanel()
        // An LSUIElement (.accessory) app cannot bring its Settings window
        // above other apps' windows. Promote → show → activate; demote back
        // to accessory when the window closes so the Dock icon stays hidden.
        settingsGraceUntil = Date().addingTimeInterval(6)
        NSApp.setActivationPolicy(.regular)
        windowsBeforeSettings = Set(NSApp.windows.map(ObjectIdentifier.init))
        trackedSettingsWindow = nil
        let sent = sendShowSettingsAction()
        Trace.log("settings: action sent=\(sent), window exists=\(settingsWindow() != nil)")
        NSApp.activate(ignoringOtherApps: true)
        revealSettingsWindow(attempt: 0)
    }

    /// The system action only creates the window the first time; a window that was closed is brought back
    /// by hand. Retries while SwiftUI is still creating it.
    private func revealSettingsWindow(attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if self.settingsWindow() == nil {
                if let candidate = self.newSettingsCandidate(since: self.windowsBeforeSettings) {
                    self.trackedSettingsWindow = candidate
                    Trace.log("settings: window recognised by elimination (id=\(candidate.identifier?.rawValue ?? "-"), title='\(candidate.title)', class=\(type(of: candidate)))")
                } else if attempt >= 4 {
                    self.showFallbackSettingsWindow()
                }
            }
            if let win = self.settingsWindow() {
                // SwiftUI's Settings scene ships without a minimize button —
                // enable miniaturize/zoom so the window can live in the Dock.
                win.styleMask.insert([.miniaturizable, .resizable])
                if win.isMiniaturized { win.deminiaturize(nil) }
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
                win.orderFrontRegardless()
                NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: win)
                NotificationCenter.default.addObserver(self, selector: #selector(self.settingsWindowWillClose(_:)),
                                                       name: NSWindow.willCloseNotification, object: win)
                Trace.log("settings: window shown (attempt \(attempt)), visible=\(win.isVisible)")
            } else if attempt < 8 {
                if attempt == 3 { _ = self.sendShowSettingsAction() }
                self.revealSettingsWindow(attempt: attempt + 1)
            } else {
                Trace.log("settings: the window did not appear; windows: " + NSApp.windows.map {
                    "[id=\($0.identifier?.rawValue ?? "-") title='\($0.title)' class=\(type(of: $0)) visible=\($0.isVisible) level=\($0.level.rawValue)]"
                }.joined(separator: " "))
                self.settingsGraceUntil = .distantPast
            }
        }
    }

    @objc private func settingsWindowWillClose(_ note: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification,
                                                object: note.object)
        NSApp.setActivationPolicy(.accessory)
    }
}
