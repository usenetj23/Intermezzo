import IntermezzoKit
import SwiftUI

/// Month grid of the work log: hours per day with markers for overtime, remote work and corrections.
struct WorkCalendar: View {
    let month: Date
    let days: [WorkDaySummary]
    let schedule: WorkSchedule
    let onSelect: (Date) -> Void
    @Environment(\.surfaceTheme) private var theme

    private var calendar: Calendar { .current }

    /// Leading blanks so the 1st lands under its weekday, then one cell per day.
    private var cells: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<31
        let weekday = calendar.component(.weekday, from: month)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: lead)
            + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private var byDay: [Date: WorkDaySummary] {
        Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let lookup = byDay
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    DayCell(date: date, summary: lookup[date],
                            isWorkday: schedule.window(for: date, calendar: calendar) != nil,
                            isToday: calendar.isDateInToday(date), isFuture: date > Date(),
                            accent: theme.accent)
                        .onTapGesture { if date <= Date() { onSelect(date) } }
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayCell: View {
    let date: Date
    let summary: WorkDaySummary?
    let isWorkday: Bool
    let isToday: Bool
    let isFuture: Bool
    let accent: Color
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            Text(date, format: .dateTime.day())
                .font(.callout.weight(isToday ? .bold : .regular))
                .foregroundStyle(isWorkday ? .primary : .secondary)
            if let s = summary {
                Text(WorkLog.hm(s.worked))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                HStack(spacing: 3) {
                    if s.billableOvertime > 0 { Circle().fill(.orange).frame(width: 5, height: 5) }
                    if s.remote >= 60 { Image(systemName: "house.fill") }
                    if s.hasCorrections { Image(systemName: "pencil") }
                }
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .frame(height: 7)
            } else {
                Spacer().frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(summary == nil ? Color.white.opacity(hovered ? 0.06 : 0.02)
                                 : accent.opacity(hovered ? 0.30 : 0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(isToday ? accent : .clear, lineWidth: 1.5))
        .opacity(isFuture ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { hovered = $0 && !isFuture }
        .help(summary.map { String(localized: "Praca \(WorkLog.hm($0.worked)), nadgodziny do rozliczenia \(WorkLog.hm($0.billableOvertime))") } ?? "")
    }
}

/// One day's log: summary and every interval, with a way into the correction editor.
struct WorkDayLog: View {
    let day: Date
    @ObservedObject private var log = WorkLogController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        let _ = log.revision
        let cal = Calendar.current
        let summary = log.days(from: day, to: cal.date(byAdding: .day, value: 1, to: day)!).first
        let records = log.records(on: day)
        VStack(alignment: .leading, spacing: 14) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                .font(.title3.weight(.semibold))
            if let s = summary {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    row("Od – do", "\(Self.time(s.first)) – \(Self.time(s.last))")
                    row("Biuro", WorkLog.hm(s.office))
                    if s.remote >= 60 { row("Zdalnie", WorkLog.hm(s.remote)) }
                    row("Nadgodziny", String(localized: "\(WorkLog.hm(s.overtime)) (do rozliczenia \(WorkLog.hm(s.billableOvertime)))"))
                    row("Aktywnie przy komputerze", WorkLog.hm(s.active))
                }
                .font(.callout)
            } else {
                Text("Tego dnia nie zarejestrowano pracy.").foregroundStyle(.secondary)
            }
            if !records.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(records, id: \.persistentModelID) { r in intervalRow(r) }
                    }
                }
                .frame(maxHeight: 260)
            }
            HStack {
                Button { editing = true } label: { Label("Popraw…", systemImage: "pencil") }
                Spacer()
                Button("Zamknij") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .sheet(isPresented: $editing) { WorkDayEditor(day: day).themedSheet() }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func intervalRow(_ r: WorkSessionRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: r.place == .remote ? "house.fill" : "building.2.fill")
                .foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(Self.time(r.start)) – \(Self.time(r.end))").monospacedDigit()
                    Text(WorkLog.hm(r.end.timeIntervalSince(r.start))).foregroundStyle(.secondary).monospacedDigit()
                    if log.isLive(r) { Label("trwa", systemImage: "record.circle").foregroundStyle(.green) }
                    if r.isCorrection { Label("korekta ręczna", systemImage: "pencil").foregroundStyle(.orange) }
                }
                .font(.callout)
                if r.activeSeconds > 0 {
                    Text("aktywnie \(WorkLog.hm(r.activeSeconds))").settingsNote()
                }
                if !r.note.isEmpty { Text(r.note).font(.caption) }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
