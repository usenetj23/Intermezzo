import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct FlashPane: View {
    @AppStorage(Keys.flashEnabled) private var flashEnabled = false
    @AppStorage(Keys.flashIntervalMinutes) private var flashIntervalMinutes = 10
    @AppStorage("blinkNudge") private var blinkNudge = false
    @AppStorage("blinkNudgeMinutes") private var blinkNudgeMinutes = 10

    var body: some View {
        Form {
            Section {
                Toggle("Enable gentle screen flashes", isOn: $flashEnabled)
                if flashEnabled {
                    Picker("Flash interval", selection: $flashIntervalMinutes) {
                        Text("Every 5 min").tag(5)
                        Text("Every 10 min").tag(10)
                        Text("Every 15 min").tag(15)
                        Text("Every 30 min").tag(30)
                    }
                }
                Button("Play demo") {
                    MainActor.assumeIsolated {
                        AppDelegate.shared?.coordinator?.flash.pulse()
                    }
                }
                Text("A subtle flash reminds you to check your posture. Skipped during breaks and pauses.")
                    .settingsNote()
            } header: {
                Text("Flash Reminder")
            }
            Section {
                Toggle("Przypomnienie o mruganiu", isOn: $blinkNudge)
                if blinkNudge {
                    Picker("Co ile minut", selection: $blinkNudgeMinutes) {
                        Text("Co 5 min").tag(5)
                        Text("Co 10 min").tag(10)
                        Text("Co 15 min").tag(15)
                        Text("Co 20 min").tag(20)
                    }
                }
                Button("Pokaż przykład") {
                    AppDelegate.shared?.coordinator.sendBlinkNudge()
                }
                Text("Przy ekranie mrugamy ok. 4–6 razy na minutę zamiast 15–20 (Lapa i in. 2023; Kaur i in. 2022). Krótkie okienko przypomina o kilku pełnych mrugnięciach. Tylko w trakcie aktywnej pracy.")
                    .settingsNote()
            } header: {
                Text("Mruganie")
            }
        }
        .formStyle(.grouped)
    }
}
