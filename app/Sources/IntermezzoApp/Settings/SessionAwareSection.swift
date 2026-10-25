import SwiftUI

/// Focus ▸ "Match the break to the session you just finished".
struct SessionAwareSection: View {
    @AppStorage(SessionAwareKeys.enabled) private var enabled = false

    var body: some View {
        Section("Break content") {
            Toggle("Match the break to the session you just finished", isOn: $enabled)
            Text("Rules of thumb, first match wins: 3 or more interruptions → a breathing exercise; mostly active typing with 50+ minutes at the screen → an eye exercise; a long break in clear, mild weather → go outside; a session of 45+ minutes → a leg exercise. Your own assigned exercises always win.")
                .settingsNote()
        }
    }
}
