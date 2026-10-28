import IntermezzoKit
import SwiftUI

/// Which calendar events count as work: one rule per calendar (or all), with the titles and kinds of event to accept.
struct CalendarRulesView: View {
    @AppStorage(Keys.calendarRules) private var rulesData = Data()
    @AppStorage(Keys.calendarWorkKeywords) private var legacyKeywords = "work, praca, meeting, spotkanie"
    @ObservedObject private var work = WorkDetector.shared
    @State private var calendars: [WorkDetector.CalendarChoice] = []

    private var rules: [CalendarRule] { CalendarRules.decode(rulesData) }

    private func save(_ list: [CalendarRule]) { rulesData = CalendarRules.encode(list) }

    private func update(_ id: UUID, _ change: (inout CalendarRule) -> Void) {
        var list = rules
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
        save(list)
    }

    private func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<CalendarRule, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { rules.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { value in update(id) { $0[keyPath: keyPath] = value } })
    }

    private func calendarChoice(_ rule: CalendarRule) -> Binding<String?> {
        Binding(
            get: { rule.calendarID },
            set: { id in
                let name = calendars.first { $0.id == id }?.title ?? ""
                update(rule.id) { $0.calendarID = id; $0.calendarName = name }
            })
    }

    var body: some View {
        Group {
            ForEach(rules) { rule in card(rule) }
            Button("Dodaj regułę kalendarza") { save(rules + [CalendarRule()]) }
                .controlSize(.small)
            Text("Wydarzenie liczy się jako praca, gdy pasuje do którejkolwiek włączonej reguły: kalendarz (albo wszystkie), tytuł zawiera jedno ze słów (puste = każdy tytuł) i rodzaj wydarzenia. „Zajęty” to dostępność inna niż „wolny”. „Niepotwierdzone” to zaproszenia bez odpowiedzi lub przyjęte tylko „wstępnie”; własne wydarzenia bez gości liczą się jako potwierdzone.")
                .settingsNote()
        }
        .onAppear {
            calendars = work.availableCalendars()
            // The first time, the old keyword list becomes an ordinary rule you can edit.
            if UserDefaults.standard.object(forKey: Keys.calendarRules) == nil {
                save([CalendarRules.legacy(keywords: legacyKeywords)])
            }
        }
    }

    private func card(_ rule: CalendarRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Reguła włączona", isOn: binding(rule.id, \.enabled, default: true))
                    .labelsHidden()
                Picker("Kalendarz", selection: calendarChoice(rule)) {
                    Text("Wszystkie kalendarze").tag(String?.none)
                    ForEach(calendars) { calendar in
                        Text("\(calendar.title) — \(calendar.source)").tag(String?.some(calendar.id))
                    }
                    if let id = rule.calendarID, !calendars.contains(where: { $0.id == id }) {
                        Text("\(rule.calendarName) (niedostępny)").tag(String?.some(id))
                    }
                }
                Button(role: .destructive) { save(rules.filter { $0.id != rule.id }) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Usuń regułę")
            }
            TextField("Tytuł zawiera (po przecinku, puste = każdy tytuł)", text: binding(rule.id, \.keywords, default: ""))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 14) {
                    Toggle("Tylko jako zajęty", isOn: binding(rule.id, \.onlyBusy, default: true))
                    Toggle("Pomijaj całodniowe", isOn: binding(rule.id, \.skipAllDay, default: true))
                }
                HStack(spacing: 14) {
                    Toggle("Pomijaj odrzucone", isOn: binding(rule.id, \.skipDeclined, default: true))
                    Toggle("Pomijaj niepotwierdzone", isOn: binding(rule.id, \.skipUnconfirmed, default: false))
                }
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
