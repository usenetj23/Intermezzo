import SwiftUI
import IntermezzoKit

/// Long absences logged as natural breaks (lunch, a walk), kept apart from the app's own breaks.
struct NaturalBreaksSection: View {
    let records: [BreakRecord]

    private func minutes(_ r: BreakRecord) -> Int {
        Int((r.endedAt ?? r.startedAt).timeIntervalSince(r.startedAt) / 60)
    }

    var body: some View {
        let cal = Calendar.current
        let today = records.filter { cal.isDateInToday($0.startedAt) }
        let weekStart = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let week = records.filter { $0.startedAt >= weekStart }
        if !records.isEmpty || UserDefaults.standard.integer(forKey: NaturalBreakKeys.enabled) != 0 {
            Section("Przerwy naturalne (bezczynność)") {
                LabeledContent("Dziś", value: String(localized: "\(today.count), razem \(today.map(minutes).reduce(0, +)) min"))
                LabeledContent("Ostatnie 7 dni", value: String(localized: "\(week.count), razem \(week.map(minutes).reduce(0, +)) min"))
                ForEach(records.prefix(5)) { r in
                    HStack {
                        Image(systemName: "figure.walk").foregroundStyle(.blue)
                        Text(NaturalBreak.category(minutes: minutes(r)).title)
                        Spacer()
                        Text("\(minutes(r)) min · \(r.startedAt.formatted(.dateTime.day().month().hour().minute()))")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Czas poza komputerem, zapisany osobno od przerw z przypomnień. Nie wlicza się do skuteczności, passy ani mapy regularności.")
                    .settingsNote()
            }
        }
    }
}
