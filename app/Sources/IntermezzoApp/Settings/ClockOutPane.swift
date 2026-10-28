import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct ClockOutPane: View {
    @AppStorage(Keys.clockOutEnabled) private var clockOutEnabled = false
    @AppStorage(Keys.clockOutStartHour) private var clockOutStartHour = 21
    @AppStorage(Keys.clockOutEndHour) private var clockOutEndHour = 6
    @AppStorage(Keys.clockOutTitle) private var clockOutTitle = "Time to Switch Off"
    @AppStorage(Keys.clockOutMessage) private var clockOutMessage = "Zakończ pracę."

    var body: some View {
        Form {
            Section {
                Toggle("Enable Clock Out", isOn: $clockOutEnabled).settingsAnchor("clockout-enable-clock-out")
                if clockOutEnabled {
                    Stepper("From \(clockOutStartHour):00", value: $clockOutStartHour, in: 0...23)
                    Stepper("To \(clockOutEndHour):00 (next day)", value: $clockOutEndHour, in: 0...23)
                    Group {
                        TextField("Title", text: $clockOutTitle)
                        TextField("Description", text: $clockOutMessage)
                    }
                    .expertOnly()
                }
                Text("A gentle evening banner reminds you to finish work during the configured window (wraps past midnight).")
                    .settingsNote().settingsAnchor("clockout-a-gentle-evening-banner-reminds-you")
            } header: {
                Text("Clock Out")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Untouched defaults were seeded as literals: show them in the app's language
            // (from here on they are the user's own text).
            clockOutTitle = L(clockOutTitle)
            clockOutMessage = L(clockOutMessage)
        }
    }
}

// MARK: - Script Gallery
