import SwiftUI
import AppKit
import IntermezzoKit

/// Every intermezzo:// address with its description and a copy button (the list comes from `AutomationCatalog`).
struct AutomationSection: View {
    var body: some View {
        Section("Automatyzacja: adresy intermezzo://") {
            Text("Adresy działają w Skrótach macOS, skryptach, cronie i terminalu. „Kopiuj” wkłada do schowka gotowy przykład.")
                .settingsNote().settingsAnchor("general-adresy-dzialaja-w-skrotach-macos-skr")
            ForEach(AutomationCatalog.urls, id: \.display) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "intermezzo://\(entry.display)")
                            .font(.system(.body, design: .monospaced))
                        Text(verbatim: entry.summary).settingsNote()
                    }
                    Spacer()
                    Button("Kopiuj") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("intermezzo://\(entry.example)", forType: .string)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
