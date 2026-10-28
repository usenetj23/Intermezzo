import IntermezzoKit
import SwiftUI

/// Sheet for correcting one day of the work log: edit, delete or add intervals.
/// Hand-made changes are flagged as corrections in the table and the export.
struct WorkDayEditor: View {
    let day: Date
    @ObservedObject private var log = WorkLogController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []

    /// Editable copy of an interval; `record` nil = new.
    struct Row: Identifiable {
        let id = UUID()
        var record: WorkSessionRecord?
        var start: Date
        var end: Date
        var place: WorkPlace
        var note: String
        var deleted = false
        var isLive = false
        var isCorrection = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.title3.weight(.semibold))
            Text("Popraw godziny, gdy praca była bez komputera (hala, awaria, laptop w domu). Ręczne zmiany są oznaczone w rejestrze i w eksporcie.")
                .settingsNote()
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($rows) { $row in
                        if !row.deleted { rowView($row) }
                    }
                    if rows.allSatisfy(\.deleted) {
                        Text("Brak odcinków tego dnia.").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 160)

            HStack {
                Button { addRow() } label: { Label("Dodaj odcinek", systemImage: "plus") }
                Spacer()
                Button("Anuluj") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Zapisz") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    // The interval being recorded right now cannot be edited and is never saved here;
                    // it starts and ends in the same minute, so it must not block the other rows.
                    .disabled(rows.contains { !$0.deleted && !$0.isLive && $0.end <= $0.start })
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        let r = row.wrappedValue
        // An interval that ends exactly where the live one begins keeps that end: the two are one stretch of work.
        let liveStart = rows.first(where: \.isLive)?.start
        let endLocked = !r.isLive && liveStart.map {
            Calendar.current.isDate(r.end, equalTo: $0, toGranularity: .minute)
        } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DatePicker("Od", selection: row.start, displayedComponents: .hourAndMinute)
                DatePicker("Do", selection: row.end, displayedComponents: .hourAndMinute)
                    .disabled(endLocked)
                    .help(endLocked ? Text("Koniec jest początkiem trwającego odcinka i nie można go zmienić.") : Text(""))
                Picker("", selection: row.place) {
                    Text("Biuro").tag(WorkPlace.office)
                    Text("Zdalnie").tag(WorkPlace.remote)
                }
                .labelsHidden()
                .frame(width: 100)
                Spacer()
                if r.isLive {
                    Label("trwa", systemImage: "record.circle").foregroundStyle(.green).font(.caption)
                } else {
                    Button(role: .destructive) { row.wrappedValue.deleted = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Usuń odcinek")
                }
            }
            .disabled(r.isLive)
            TextField("Notatka (np. awaria linii 3)", text: row.note)
            if endLocked {
                Text("Koniec zablokowany: odcinek łączy się z trwającym.").font(.caption2).foregroundStyle(.secondary)
            }
            if !r.isLive, r.end <= r.start {
                Text("Koniec musi być po początku.").font(.caption).foregroundStyle(.red)
            } else if r.isCorrection || r.record == nil {
                Text("korekta ręczna").font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func load() {
        rows = log.records(on: day).map {
            Row(record: $0, start: $0.start, end: $0.end, place: $0.place, note: $0.note,
                isLive: log.isLive($0), isCorrection: $0.isCorrection)
        }
    }

    private func addRow() {
        let cal = Calendar.current
        let from = rows.filter { !$0.deleted }.map(\.end).max()
            ?? cal.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
        rows.append(Row(record: nil, start: from, end: from.addingTimeInterval(3600), place: .office, note: ""))
    }

    /// An hour-and-minute DatePicker only changes the time, so every row keeps its own date
    /// (an interval that began the evening before stays there).
    private func save() {
        for row in rows where !row.isLive {
            let (start, end) = (row.start, row.end)
            switch (row.record, row.deleted) {
            case (let record?, true): log.delete(record)
            case (let record?, false):
                if record.start != start || record.end != end || record.place != row.place || record.note != row.note {
                    log.update(record, start: start, end: end, place: row.place, note: row.note)
                }
            case (nil, false): log.addCorrection(start: start, end: end, place: row.place, note: row.note)
            case (nil, true): break
            }
        }
    }
}
