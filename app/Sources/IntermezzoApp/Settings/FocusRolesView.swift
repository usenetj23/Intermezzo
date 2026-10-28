import AppKit
import IntermezzoKit
import SwiftUI

/// What the app does for each Focus mode (work, hold breaks, ignore), with the modes read from macOS.
struct FocusRolesView: View {
    @AppStorage(Keys.focusRoles) private var rolesData = Data()
    @State private var snapshot: WorkDetector.FocusSnapshot?
    @State private var checked = false

    private var roles: [String: FocusRole] {
        (try? JSONDecoder().decode([String: FocusRole].self, from: rolesData)) ?? [:]
    }

    private func binding(_ id: String) -> Binding<FocusRole> {
        Binding(
            get: { FocusModes.role(for: id, stored: roles) },
            set: { role in
                var next = roles
                next[id] = role
                rolesData = (try? JSONEncoder().encode(next)) ?? Data()
            })
    }

    var body: some View {
        Group {
            if let snapshot {
                LabeledContent("Włączony teraz") {
                    Group {
                        if snapshot.active.isEmpty {
                            Text("żaden")
                        } else {
                            Text(snapshot.active.map(\.name).joined(separator: ", "))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(snapshot.known) { mode in
                    Picker(mode.name, selection: binding(mode.id)) {
                        ForEach(FocusRole.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Text("Telefon przełącza Focus po lokalizacji GPS i synchronizuje go z Makiem, więc tryb oznaczony jako praca mówi, że jesteś w pracy. Pozostałe tryby domyślnie wstrzymują przerwy (jeśli włączone jest wykrywanie Focus).")
                    .settingsNote()
            } else if checked {
                Label("Nie mogę odczytać trybów Focus. macOS chroni ten folder: dodaj Intermezzo w Prywatność i ochrona → Pełny dostęp do dysku, potem uruchom aplikację ponownie.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Otwórz ustawienia prywatności") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Sprawdź ponownie", action: reload)
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        snapshot = WorkDetector.focusSnapshot()
        checked = true
    }
}
