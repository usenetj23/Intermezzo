import SwiftUI

extension View {
    /// The one style for explanatory text in Settings (descriptions, hints, notes under options).
    func settingsNote() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}
