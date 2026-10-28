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
                Toggle("Enable gentle screen flashes", isOn: $flashEnabled).settingsAnchor("flash-enable-gentle-screen-flashes")
                if flashEnabled {
                    Picker("Flash interval", selection: $flashIntervalMinutes) {
                        Text("Every 5 min").tag(5)
                        Text("Every 10 min").tag(10)
                        Text("Every 15 min").tag(15)
                        Text("Every 30 min").tag(30)
                    }.settingsAnchor("flash-flash-interval")
                }
                Button("Play demo") {
                    MainActor.assumeIsolated {
                        AppDelegate.shared?.coordinator?.flash.pulse()
                    }
                }.settingsAnchor("flash-play-demo")
                Text("A subtle flash reminds you to check your posture. Skipped during breaks and pauses.")
                    .settingsNote().settingsAnchor("flash-a-subtle-flash-reminds-you-to-check")
            } header: {
                Text("Flash Reminder")
            }
            Section {
                Toggle("Przypomnienie o mruganiu", isOn: $blinkNudge).settingsAnchor("flash-przypomnienie-o-mruganiu")
                if blinkNudge {
                    Picker("Co ile minut", selection: $blinkNudgeMinutes) {
                        Text("Co 5 min").tag(5)
                        Text("Co 10 min").tag(10)
                        Text("Co 15 min").tag(15)
                        Text("Co 20 min").tag(20)
                    }.settingsAnchor("flash-co-ile-minut")
                }
                Button("Pokaż przykład") {
                    AppDelegate.shared?.coordinator.sendBlinkNudge()
                }.settingsAnchor("flash-pokaz-przyklad")
                Text("Przy ekranie mrugamy ok. 4–6 razy na minutę zamiast 15–20 (Lapa i in. 2023; Kaur i in. 2022). Krótkie okienko przypomina o kilku pełnych mrugnięciach. Tylko w trakcie aktywnej pracy.")
                    .settingsNote().settingsAnchor("flash-przy-ekranie-mrugamy-ok-4-6-razy-na")
            } header: {
                Text("Mruganie")
            }
        }
        .formStyle(.grouped)
    }
}
