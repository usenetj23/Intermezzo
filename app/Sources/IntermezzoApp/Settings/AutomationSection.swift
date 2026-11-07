import SwiftUI
import AppKit
import IntermezzoKit

/// The state and the events for other programs, then every intermezzo:// address with a copy button (from `AutomationCatalog`).
struct AutomationSection: View {
    @AppStorage(AutomationKeys.publish) private var publish = false

    private var stateFile: String { AutomationBus.stateFileURL.path }

    var body: some View {
        Group {
            Section("Automatyzacja: stan i zdarzenia") {
                Toggle("Publikuj stan i zdarzenia dla innych programów", isOn: $publish).settingsAnchor("general-publikuj-stan-i-zdarzenia-dla-innych")
                Text("Zapisuje stan (timer, przerwa, strefa pracy, spotkanie, Skupienie, bezczynność) do pliku i wysyła powiadomienia systemowe przy zdarzeniach, żeby narzędzia takie jak autoMate nie musiały go odczytywać co kilka sekund. Dane zostają na tym Macu, a w stanie nie ma tytułów wydarzeń ani nazw sieci. Akcje przerw reagujące na zdarzenia działają także przy wyłączonym przełączniku.")
                    .settingsNote().settingsAnchor("general-zapisuje-stan-timer-przerwa-strefa-p")
                if publish {
                    LabeledContent("Plik stanu") {
                        Text(verbatim: stateFile)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Pokaż w Finderze") {
                            NSWorkspace.shared.activateFileViewerSelecting([AutomationBus.stateFileURL])
                        }.settingsAnchor("general-pokaz-w-finderze")
                        Button("Kopiuj ścieżkę") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(stateFile, forType: .string)
                        }.settingsAnchor("general-kopiuj-sciezke")
                        Button("Kopiuj przykład odczytu") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("cat \"\(stateFile)\"", forType: .string)
                        }.settingsAnchor("general-kopiuj-przyklad-odczytu")
                    }
                    .controlSize(.small)
                    Text("Powiadomienia systemowe (DistributedNotificationCenter) przy każdej zmianie stanu i przy każdym zdarzeniu; userInfo zawiera event i json. Nazwy i lista zdarzeń są poniżej. Adres intermezzo://state?x-success=<adres> oddaje stan innej aplikacji, np. Skrótom.")
                        .settingsNote().settingsAnchor("general-powiadomienia-systemowe-distributedn")
                    Text(verbatim: "\(AutomationKeys.stateNotification)\n\(AutomationKeys.eventNotification)\n\(AutomationEvent.allCases.map(\.rawValue).joined(separator: ", "))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            urlSection
        }
    }

    private var urlSection: some View {
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
