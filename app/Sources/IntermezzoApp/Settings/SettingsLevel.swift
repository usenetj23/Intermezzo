import SwiftUI
import AppKit

/// Basic vs. all settings: in basic mode the expert panes and sections are hidden, so a new user
/// sees what makes the app work and nothing that needs knowing the rest first.
enum SettingsLevel {
    static let key = "settingsShowAll"
}

private struct HideUnlessAll: ViewModifier {
    @AppStorage(SettingsLevel.key) private var showAll = false

    func body(content: Content) -> some View {
        if showAll { content }
    }
}

extension View {
    /// Shown only with "All settings" on (sections, rows, whole groups of controls).
    func expertOnly() -> some View { modifier(HideUnlessAll()) }
}

/// Segmented switch at the bottom of the sidebar.
struct SettingsLevelPicker: View {
    @AppStorage(SettingsLevel.key) private var showAll = false
    @AppStorage(Keys.hideQuit) private var hideQuit = false

    var body: some View {
        HStack(spacing: 6) {
            Picker("Zakres ustawień", selection: $showAll) {
                Text("Podstawowe").tag(false)
                Text("Wszystkie").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Podstawowe ukrywają ustawienia eksperckie. Nic nie jest wyłączane: ukryte opcje działają dalej tak, jak je ustawiono.")
            // Same quit as in the menu-bar panel, and hidden by the same setting.
            if !hideQuit {
                PanelButton(title: String(localized: "Zakończ"), symbol: "power", kind: .ghost, iconOnly: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(10)
    }
}
