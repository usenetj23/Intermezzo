import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct AdvancedPane: View {
    @AppStorage(Keys.idleDetection) private var idleDetection = true
    @AppStorage(Keys.idleDetectionMethod) private var idleMethod = "monitor"
    @AppStorage(Keys.idleThresholdSeconds) private var idleThresholdSeconds = 60
    @AppStorage(Keys.hidePause) private var hidePause = false
    @AppStorage(Keys.hideMakeDue) private var hideMakeDue = false
    @AppStorage(Keys.hideReset) private var hideReset = false
    @AppStorage(Keys.hideQuit) private var hideQuit = false
    @AppStorage(Keys.preventSleepDuringBreak) private var preventSleepDuringBreak = false
    @AppStorage(Keys.alertDuplicates) private var alertDuplicates = true
    @State private var scanMessage = ""
    @State private var confirmingReset = false
    @ObservedObject private var permissions = PermissionCenter.shared

    var body: some View {
        Form {
            Section("Natural Break") {
                Picker("Detekcja naturalnej przerwy:", selection: $idleMethod) {
                    Text("Brak").tag("none")
                    Text("Event Source (odpytywanie)").tag("source")
                    Text("Event Monitor (tap zdarzeń)").tag("monitor")
                }
                .settingsAnchor("idle")
                if idleMethod == "monitor" {
                    Text("Needs Input Monitoring permission. Without it Intermezzo falls back to Event Source automatically.")
                        .settingsNote().settingsAnchor("advanced-needs-input-monitoring-permission-wi")
                }
                if idleDetection && idleMethod != "none" {
                    Stepper(value: $idleThresholdSeconds, in: 30...900, step: 30) {
                        Text("Nieaktywność liczy się od: \(idleThresholdSeconds / 60) min")
                    }
                }
            }

            Section("Permissions") {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, status: permissions.status(kind)) {
                        permissions.request(kind)
                    }
                    .settingsAnchor("perm-\(kind.rawValue)")
                }
                HStack {
                    Button("Refresh") { permissions.refresh() }.settingsAnchor("advanced-refresh")
                    Button("Send test notification") {
                        AppDelegate.shared?.coordinator.sendTestNotification()
                    }.settingsAnchor("advanced-send-test-notification")
                    Button("Reset all decisions…") { confirmingReset = true }.settingsAnchor("advanced-reset-all-decisions")
                    Spacer()
                    // macOS hands a running app its old answers, so a new grant often shows only after a restart.
                    Button("Restart") { LanguageSwitch.relaunch() }.settingsAnchor("advanced-restart")
                        .tint(permissions.resetThisRun.isEmpty ? nil : .accentColor)
                }
                .controlSize(.small)
                .confirmationDialog("Reset all permission decisions?", isPresented: $confirmingReset) {
                    Button("Reset", role: .destructive) { permissions.reset(PermissionKind.allCases) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("macOS forgets what you allowed for Intermezzo (input monitoring, screen recording, accessibility, automation, calendar). Until you allow them again, natural-break detection, effects and script rules work in a reduced way.")
                }
                if !permissions.lastMessage.isEmpty {
                    Text(permissions.lastMessage).font(.caption).foregroundStyle(.orange)
                }
                Text("After you allow something in System Settings, click Restart: macOS often shows the new state only to a freshly started app. If a switch is on in System Settings but Intermezzo still shows it as denied after a restart, the app was rebuilt with a different signature: use “Reset all decisions…” and allow again.")
                    .settingsNote().settingsAnchor("advanced-after-you-allow-something-in-system")
            }

            Section("Ukryj przyciski (pokusa do pomijania)") {
                Toggle("Pauza", isOn: $hidePause).settingsAnchor("advanced-pauza")
                Toggle("Zrób przerwę teraz", isOn: $hideMakeDue).settingsAnchor("advanced-zrob-przerwe-teraz")
                Toggle("Reset", isOn: $hideReset).settingsAnchor("advanced-reset")
                Toggle("Wyjdź", isOn: $hideQuit).settingsAnchor("advanced-wyjdz")
            }

            Section("Sen i kopia aplikacji") {
                Toggle("Nie pozwól uśpić Maca podczas przerwy", isOn: $preventSleepDuringBreak).settingsAnchor("advanced-nie-pozwol-uspic-maca-podczas-przerw")
                Toggle("Alarmuj o drugiej kopii Intermezzo", isOn: $alertDuplicates).settingsAnchor("advanced-alarmuj-o-drugiej-kopii-intermezzo")
                HStack {
                    Button("Skanuj teraz") {
                        scanMessage = String(localized: "Skanowanie…")
                        DispatchQueue.global(qos: .utility).async {
                            let found = DuplicateScanner.findOtherCopies(
                                excluding: Bundle.main.bundleURL)
                            DispatchQueue.main.async {
                                scanMessage = found.isEmpty
                                    ? String(localized: "Brak innych kopii na tym Macu.")
                                    : String(localized: "Znaleziono: \(found.joined(separator: ", "))")
                            }
                        }
                    }.settingsAnchor("advanced-skanuj-teraz")
                    Text(scanMessage)
                        .settingsNote()
                }
            }

            Section {
                Text("Intermezzo nic nie wysyła: zero analityki, zero powiadomień od wydawcy, zero kontaktów z siecią. Cała diagnostyka zostaje na tym Macu.")
                    .settingsNote().settingsAnchor("advanced-intermezzo-nic-nie-wysyla-zero-anali")
            }
        }
        .formStyle(.grouped)
        .scrollsToSettingsAnchor()
        .frame(minWidth: 520, minHeight: 440)
        .onAppear { permissions.refresh() }
        // Statuses change in System Settings — re-read every 5 s while this pane is open.
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
