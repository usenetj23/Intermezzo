import SwiftUI

/// Focus ▸ "Natural seam": let a due break wait for a pause in typing.
struct SeamBreaksSection: View {
    @AppStorage(SeamKeys.enabled) private var enabled = false
    @AppStorage(SeamKeys.maxDelaySeconds) private var maxDelaySeconds = SeamKeys.defaultMaxDelay
    @AppStorage(Keys.strictMode) private var strictMode = false

    var body: some View {
        Section("Natural seam") {
            Toggle("Wait for a pause in typing before a break", isOn: $enabled).settingsAnchor("focus-wait-for-a-pause-in-typing-before-a")
                .disabled(strictMode)
            if enabled {
                Stepper("Wait at most \(maxDelaySeconds) s",
                        value: $maxDelaySeconds,
                        in: SeamKeys.maxDelayRange,
                        step: 30)
                    .disabled(strictMode)
            }
            Text("Never longer than the limit; off in strict mode")
                .settingsNote().settingsAnchor("focus-never-longer-than-the-limit-off-in-s")
        }
    }
}
