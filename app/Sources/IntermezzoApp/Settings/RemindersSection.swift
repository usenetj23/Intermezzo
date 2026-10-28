import SwiftUI
import IntermezzoKit

/// Independent micro-reminders (water, blinking, posture) and breaks at fixed times.
struct RemindersSection: View {
    @State private var reminders = MicroReminder.decodeList(
        UserDefaults.standard.data(forKey: ReminderController.microKey))
    @State private var scheduled = ScheduledBreak.decodeList(
        UserDefaults.standard.data(forKey: ReminderController.scheduledKey))

    private static let days: [(Int, String)] = [
        (2, String(localized: "Pn")), (3, String(localized: "Wt")), (4, String(localized: "Śr")),
        (5, String(localized: "Cz")), (6, String(localized: "Pt")), (7, String(localized: "So")),
        (1, String(localized: "Nd")),
    ]

    var body: some View {
        Section("Mikro-przypomnienia") {
            ForEach($reminders) { $r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $r.enabled).labelsHidden()
                        Image(systemName: r.symbol).frame(width: 18)
                        TextField("Treść przypomnienia", text: $r.title)
                            .labelsHidden()
                            .textFieldStyle(.editable)
                        Button(role: .destructive) { reminders.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }
                            .controlSize(.small)
                    }
                    Stepper(value: $r.intervalMinutes, in: 5...240, step: 5) {
                        Text("Co \(r.intervalMinutes) min").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Menu("Dodaj przypomnienie") {
                    ForEach(MicroReminder.presets, id: \.title) { p in
                        Button(p.title) { reminders.append(MicroReminder(title: p.title, intervalMinutes: p.intervalMinutes, symbol: p.symbol)) }
                    }
                    Divider()
                    Button("Własne…") { reminders.append(MicroReminder(title: String(localized: "Moje przypomnienie"), intervalMinutes: 45)) }.settingsAnchor("breaks-wlasne")
                }
                .fixedSize()
            }
            Text("Krótkie powiadomienia na własnych odstępach, niezależne od przerw. Pojawiają się tylko podczas pracy.")
                .settingsNote().settingsAnchor("breaks-krotkie-powiadomienia-na-wlasnych-od")
        }
        .onChange(of: reminders) { _, new in
            UserDefaults.standard.set(MicroReminder.encodeList(new), forKey: ReminderController.microKey)
        }

        Section("Przerwy o stałych porach") {
            ForEach($scheduled) { $b in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("", isOn: $b.enabled).labelsHidden()
                        TextField("Nazwa przerwy", text: $b.label)
                            .labelsHidden()
                            .textFieldStyle(.editable)
                        DatePicker("", selection: timeBinding($b), displayedComponents: .hourAndMinute).labelsHidden()
                        Button(role: .destructive) { scheduled.removeAll { $0.id == b.id } } label: { Image(systemName: "trash") }
                            .controlSize(.small)
                    }
                    Picker("Rodzaj", selection: kindBinding($b)) {
                        Text("Krótka (z ustawień)").tag(Kind.short)
                        Text("Długa (z ustawień)").tag(Kind.long)
                        Text("Własny czas").tag(Kind.custom)
                    }
                    if b.customMinutes != nil {
                        Stepper(value: Binding(get: { b.customMinutes ?? 15 }, set: { b.customMinutes = $0 }), in: 1...180) {
                            Text("Czas: \(b.customMinutes ?? 15) min").foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Zapytaj zamiast startować", isOn: $b.askFirst)
                    HStack(spacing: 4) {
                        ForEach(Self.days, id: \.0) { day, name in
                            Toggle(name, isOn: dayBinding($b, day)).toggleStyle(.button).controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Menu("Dodaj przerwę") {
                ForEach(ScheduledBreak.mealPresets, id: \.label) { p in
                    Button("\(p.label) (\(p.customMinutes ?? 0) min)") { scheduled.append(fresh(from: p)) }
                }
                Divider()
                Button("Własna…") {
                    scheduled.append(ScheduledBreak(label: String(localized: "Przerwa"), minuteOfDay: 10 * 60, weekdays: [2, 3, 4, 5, 6],
                                                    isLong: false, customMinutes: 15))
                }.settingsAnchor("breaks-wlasna")
            }
            .fixedSize()
            Text("Własny czas pasuje do przerwy śniadaniowej (9:00, 15 min) albo obiadu (12:30, 30 min). Startuje w podanej minucie, o ile aplikacja nie jest wstrzymana (spotkanie, poza godzinami pracy). Z opcją „Zapytaj” dostaniesz powiadomienie z przyciskiem Zacznij.")
                .settingsNote().settingsAnchor("breaks-wlasny-czas-pasuje-do-przerwy-sniada")
        }
        .onChange(of: scheduled) { _, new in
            UserDefaults.standard.set(ScheduledBreak.encodeList(new), forKey: ReminderController.scheduledKey)
        }
    }

    private enum Kind: Hashable { case short, long, custom }

    private func kindBinding(_ b: Binding<ScheduledBreak>) -> Binding<Kind> {
        Binding(
            get: { b.wrappedValue.customMinutes != nil ? .custom : (b.wrappedValue.isLong ? .long : .short) },
            set: { kind in
                switch kind {
                case .custom: b.wrappedValue.customMinutes = b.wrappedValue.customMinutes ?? 15
                case .short: b.wrappedValue.customMinutes = nil; b.wrappedValue.isLong = false
                case .long: b.wrappedValue.customMinutes = nil; b.wrappedValue.isLong = true
                }
            })
    }

    /// A preset copied with a new identity so it can be added more than once.
    private func fresh(from p: ScheduledBreak) -> ScheduledBreak {
        ScheduledBreak(label: p.label, minuteOfDay: p.minuteOfDay, weekdays: p.weekdays, isLong: p.isLong,
                       customMinutes: p.customMinutes, askFirst: p.askFirst)
    }

    private func timeBinding(_ b: Binding<ScheduledBreak>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(b.wrappedValue.minuteOfDay * 60)) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                b.wrappedValue.minuteOfDay = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private func dayBinding(_ b: Binding<ScheduledBreak>, _ day: Int) -> Binding<Bool> {
        Binding(
            get: { b.wrappedValue.weekdays.contains(day) },
            set: { on in
                if on { b.wrappedValue.weekdays.insert(day) } else { b.wrappedValue.weekdays.remove(day) }
            })
    }
}
