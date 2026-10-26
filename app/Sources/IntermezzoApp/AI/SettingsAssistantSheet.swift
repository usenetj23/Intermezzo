import SwiftUI
import IntermezzoKit

/// "Describe how the program should work": the model proposes changes to a fixed list of settings, the user
/// picks which ones to apply, and the last applications can be undone.
struct SettingsAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = AIService.shared
    @State private var request = ""
    @State private var proposal: SettingsProposal?
    @State private var selected: Set<String> = []
    @State private var message = ""
    @State private var messageIsError = false
    @State private var undoCount = SettingsHistory.count(in: .standard)

    private var language: String { service.languageCode }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Asystent ustawień").font(.headline)
            Text("Opisz, jak ma działać program, np. „pracuję od poniedziałku do piątku od 8 do 16, długa przerwa w południe, nie przerywaj mi w spotkaniach”. Asystent tylko proponuje zmiany; zapisuje je dopiero po Twoim zatwierdzeniu.")
                .settingsNote()
            TextEditor(text: $request)
                .font(.body)
                .frame(minHeight: 70, maxHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button(service.isBusy ? "Pracuję…" : "Zaproponuj") { propose() }
                    .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.isBusy || service.availability() != .ready)
                if service.isBusy { Button("Przerwij") { service.cancel() } }
                Spacer()
                if case .unavailable(let reason) = service.availability() { Text(reason).settingsNote() }
            }
            if !message.isEmpty {
                Label(message, systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(messageIsError ? Color.orange : Color.green)
                    .font(.caption)
            }
            if let proposal { proposalView(proposal) }
            Spacer(minLength: 0)
            HStack {
                Button("Cofnij ostatnie zmiany asystenta") { undo() }
                    .disabled(undoCount == 0)
                Spacer()
                Button("Zamknij") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 440)
        .onDisappear { service.cancel() }
    }

    @ViewBuilder private func proposalView(_ proposal: SettingsProposal) -> some View {
        Divider()
        if let explanation = proposal.explanation, !explanation.isEmpty { Text(explanation).font(.callout) }
        if proposal.changes.isEmpty {
            Text("Asystent nie zaproponował żadnych zmian.").settingsNote()
        } else {
            ForEach(proposal.changes, id: \.key) { change in
                Toggle(isOn: Binding(get: { selected.contains(change.key) },
                                     set: { if $0 { selected.insert(change.key) } else { selected.remove(change.key) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(of: change.key))
                        Text("\(valueText(change.old, key: change.key)) → \(valueText(change.new, key: change.key))").settingsNote()
                    }
                }
            }
            Button("Zastosuj zaznaczone") { apply(proposal) }
                .disabled(selected.isEmpty)
        }
        if !proposal.skipped.isEmpty {
            DisclosureGroup("Pominięte propozycje") {
                ForEach(Array(proposal.skipped.enumerated()), id: \.offset) { _, skipped in
                    Text("\(skipped.key): \(skipped.reason)").settingsNote()
                }
            }
        }
    }

    private func title(of key: String) -> String {
        if key == "workDaysMask" { return String(localized: "Dni pracy") }
        guard let entry = SettingsCatalog.entry(for: key) else { return key }
        return language == "pl" ? entry.descriptionPL : entry.descriptionEN
    }

    private func valueText(_ value: SettingValue?, key: String) -> String {
        switch value {
        case .none: return "–"
        case .flag(let on): return on ? String(localized: "włączone") : String(localized: "wyłączone")
        case .number(let n):
            if SettingsCatalog.entry(for: key)?.kind == .minutesOfDay { return String(format: "%02d:%02d", n / 60, n % 60) }
            if key == "workDaysMask" { return dayNames(of: n) }
            return String(n)
        case .text(let text): return text
        }
    }

    /// "Mon Tue Wed" for the bits of the working-days mask (Monday is bit 0).
    private func dayNames(of mask: Int) -> String {
        let names = [String(localized: "Mon"), String(localized: "Tue"), String(localized: "Wed"), String(localized: "Thu"),
                     String(localized: "Fri"), String(localized: "Sat"), String(localized: "Sun")]
        let chosen = names.indices.filter { mask & (1 << $0) != 0 }.map { names[$0] }
        return chosen.isEmpty ? String(localized: "brak") : chosen.joined(separator: " ")
    }

    private func propose() {
        message = ""
        proposal = nil
        let current = SettingsCatalog.current(in: .standard)
        let ask = SettingsAssistant.prompt(request: request, current: current, language: language)
        Task {
            do {
                let answer = try await service.run(ask)
                let result = SettingsAssistant.parse(answer, current: current)
                proposal = result
                selected = Set(result.changes.map(\.key))
                if result.changes.isEmpty, result.skipped.isEmpty, result.explanation == nil {
                    message = String(localized: "Nie udało się odczytać propozycji. Spróbuj opisać to inaczej.")
                    messageIsError = true
                }
            } catch let error as AIError {
                message = error.message
                messageIsError = true
            } catch {
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }

    private func apply(_ proposal: SettingsProposal) {
        let chosen = proposal.changes.filter { selected.contains($0.key) }
        guard !chosen.isEmpty else { return }
        let defaults = UserDefaults.standard
        SettingsHistory.push(SettingsSnapshot.capture(keys: chosen.map(\.key), from: defaults, now: Date()), to: defaults)
        SettingsCatalog.apply(chosen, to: defaults)
        undoCount = SettingsHistory.count(in: defaults)
        self.proposal = nil
        selected = []
        message = String(localized: "Zmiany zostały zastosowane. Możesz je cofnąć przyciskiem poniżej.")
        messageIsError = false
    }

    private func undo() {
        guard let snapshot = SettingsHistory.popLast(from: .standard) else { return }
        snapshot.restore(into: .standard)
        undoCount = SettingsHistory.count(in: .standard)
        proposal = nil
        message = String(localized: "Przywrócono poprzednie ustawienia.")
        messageIsError = false
    }
}
