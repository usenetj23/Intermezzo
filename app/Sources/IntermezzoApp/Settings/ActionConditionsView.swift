import SwiftUI
import IntermezzoKit

/// The filter icon on a Break Action row: opens the conditions for that action (work zone, meeting, lock screen, cooldown).
struct ActionConditionsButton: View {
    @Binding var conditions: ActionConditions
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: conditions.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help("Warunki uruchomienia")
        .popover(isPresented: $shown) {
            ActionConditionsEditor(conditions: $conditions)
                .padding(16)
                .frame(width: 340)
        }
    }
}

struct ActionConditionsEditor: View {
    @Binding var conditions: ActionConditions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Warunki uruchomienia").font(.headline)
            Picker("Strefa pracy", selection: $conditions.zone) {
                Text("Bez znaczenia").tag(ActionConditions.Zone.any)
                Text("Tylko w strefie pracy").tag(ActionConditions.Zone.inside)
                Text("Tylko poza strefą pracy").tag(ActionConditions.Zone.outside)
            }
            Toggle("Nie podczas spotkania", isOn: $conditions.notInMeeting)
            Toggle("Tylko gdy ekran nie jest zablokowany", isOn: $conditions.screenUnlocked)
            Stepper("Odstęp między uruchomieniami: \(conditions.cooldownSeconds) s",
                    value: $conditions.cooldownSeconds, in: 0...86_400, step: 10)
            Text("Warunki są sprawdzane w chwili uruchomienia akcji. Strefa pracy wymaga włączonego co najmniej jednego źródła w Ogólne; bez tego nie wiadomo, czy jesteś w niej, i warunek nie jest spełniony.")
                .settingsNote()
                .fixedSize(horizontal: false, vertical: true)
            if !conditions.isDefault {
                Button("Wyczyść warunki") { conditions = ActionConditions() }
                    .controlSize(.small)
            }
        }
    }
}

enum ActionConditionsSummary {
    /// "tylko w strefie pracy · nie podczas spotkania", or nil when nothing is set.
    static func text(_ c: ActionConditions) -> String? {
        var parts: [String] = []
        switch c.zone {
        case .any: break
        case .inside: parts.append(String(localized: "tylko w strefie pracy"))
        case .outside: parts.append(String(localized: "tylko poza strefą pracy"))
        }
        if c.notInMeeting { parts.append(String(localized: "nie podczas spotkania")) }
        if c.screenUnlocked { parts.append(String(localized: "tylko przy odblokowanym ekranie")) }
        if c.cooldownSeconds > 0 { parts.append(String(localized: "odstęp co najmniej \(c.cooldownSeconds) s")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The "Run Shortcut" action: which of the person's Shortcuts, a test run, and what it receives.
struct RunShortcutRow: View {
    @Binding var name: String
    let trigger: BreakActionWhen
    @State private var names: [String] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Shortcut:", selection: $name) {
                    Text("— wybierz —").tag("")
                    ForEach(names, id: \.self) { Text(ShortcutPlan.displayName($0)).tag($0) }
                    // Keep a saved name visible even if it is gone from Shortcuts.
                    if !name.isEmpty && !names.contains(name) {
                        Text("\(ShortcutPlan.displayName(name)) (missing)").tag(name)
                    }
                }
                Button(loading ? "Refreshing…" : "Refresh list") { refresh() }
                    .disabled(loading)
                Button("Run now") {
                    AutomationShortcutRunner.run(name: name, trigger: "test", event: nil)
                }
                .disabled(name.isEmpty)
            }
            Text("Skrót dostaje jako dane wejściowe plik JSON: nazwę wyzwalacza, zdarzenie i stan Intermezzo (timer, strefa pracy, spotkanie, Skupienie, bezczynność). W skrócie użyj „Pobierz słownik z danych wejściowych”, a potem „Pobierz wartość słownika”.")
                .settingsNote()
        }
        .onAppear(perform: refresh)
    }

    @MainActor private func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            let listing = await FocusShortcutsStatus.shared.sharedListing()
            names = listing.names
            loading = false
        }
    }
}
