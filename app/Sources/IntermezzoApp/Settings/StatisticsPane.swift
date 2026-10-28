import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct StatisticsPane: View {
    @Query(sort: \BreakRecord.startedAt, order: .reverse) private var records: [BreakRecord]

    /// Everything the pane shows, worked out in one pass over the records (each property of a stored
    /// record is a SwiftData access, and the pane used to filter the whole history a dozen times per redraw).
    private struct Snapshot {
        var samples: [BreakSample] = []
        var heatmap: [ConsistencyHeatmap.Entry] = []
        var natural: [BreakRecord] = []
        var completedDays = Set<Date>()
        var total = 0, today = 0, week = 0, short = 0, long = 0
    }

    private func snapshot() -> Snapshot {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        var s = Snapshot()
        for record in records {
            let started = record.startedAt
            if record.isNatural { s.natural.append(record); continue }
            let skipped = record.wasSkipped
            let ended = record.endedAt
            let kind = record.kind
            s.samples.append(BreakSample(kind: kind.rawValue, startedAt: started, endedAt: ended, skipped: skipped))
            s.heatmap.append(.init(start: started, skipped: skipped))
            guard !skipped, ended != nil else { continue }
            s.total += 1
            let day = cal.startOfDay(for: started)
            s.completedDays.insert(day)
            if day == startOfToday { s.today += 1 }
            if started >= weekAgo { s.week += 1 }
            if kind == .short { s.short += 1 }
            if kind == .long { s.long += 1 }
        }
        return s
    }

    private func streakDays(_ days: Set<Date>) -> Int {
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    @Environment(\.surfaceTheme) private var theme
    /// Collapsed by default: the list is long and rarely the reason to open Statistics.
    @State private var historyExpanded = false


    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "intermezzo-przerwy.csv")
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BreakStats.csv(snapshot().samples.sorted { $0.startedAt < $1.startedAt })
                .write(to: url, atomically: true, encoding: .utf8)
            Trace.log("stats exported to \(url.path)")
        } catch {
            Trace.log("stats export failed: \(error.localizedDescription)")
        }
    }

    var body: some View {
        let stats = snapshot()
        let currentStreakDays = streakDays(stats.completedDays)
        return Form {
            Section("Ostatnie 7 dni") {
                let days = BreakStats.lastDays(7, samples: stats.samples, now: Date())
                WeekBars(days: days, accent: theme.accent)
                    .frame(height: 96)
                LabeledContent("Skuteczność (ukończone / rozpoczęte)",
                               value: "\(Int((BreakStats.completionRate(days) * 100).rounded()))%")
                Button("Eksportuj historię do CSV…", action: exportCSV).settingsAnchor("statistics-eksportuj-historie-do-csv")
                    .controlSize(.small)
            }
            WeeklySummaryView(samples: stats.samples)
            Section("Regularność (12 tygodni)") {
                ConsistencyHeatmapView(entries: stats.heatmap, accent: theme.accent)
            }
            NaturalBreaksSection(records: stats.natural)
            Section("Break Activity") {
                if BreakStyleSettings.motivation.showsStreakCounters {
                    LabeledContent("Current streak", value: currentStreakDays == 1
                                   ? String(localized: "1 day") : String(localized: "\(currentStreakDays) days"))
                }
                LabeledContent("Total breaks", value: "\(stats.total)")
            }
            Section("Break Statistics") {
                LabeledContent("Today", value: "\(stats.today)")
                LabeledContent("This week", value: "\(stats.week)")
                LabeledContent("Short Breaks", value: "\(stats.short)")
                LabeledContent("Long Breaks", value: "\(stats.long)")
            }
            Section {
                DisclosureGroup(isExpanded: $historyExpanded) {
                    if records.isEmpty {
                        Text("No breaks recorded yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(records.prefix(30)) { record in
                    HStack {
                        Image(systemName: record.isNatural ? "figure.walk" : (record.wasSkipped ? "forward.end.circle" : "checkmark.circle"))
                            .foregroundStyle(record.isNatural ? .blue : (record.wasSkipped ? .orange : .green))
                        Text(record.isNatural ? "Przerwa naturalna" : (record.kind == .long ? "Long break" : "Short break"))
                        if record.wasSkipped {
                            Text("(skipped)").foregroundStyle(.secondary).font(.callout)
                        }
                        Spacer()
                        if let end = record.endedAt {
                            Text("\(Int(end.timeIntervalSince(record.startedAt))) s")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        Text(record.startedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    }
                } label: {
                    HStack {
                        Text("Break History").font(.headline)
                        Spacer()
                        Text("ostatnie \(min(records.count, 30)) z \(records.count)")
                            .settingsNote()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - History

struct HistoryView: View {
    @Query(sort: \BreakRecord.startedAt, order: .reverse) private var records: [BreakRecord]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Break history").font(.headline).padding([.top, .leading])
            if records.isEmpty {
                Text("No breaks recorded yet.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            } else {
                List(records.prefix(50)) { record in
                    HStack {
                        Image(systemName: record.wasSkipped ? "forward.end.circle" : "checkmark.circle")
                            .foregroundStyle(record.wasSkipped ? .orange : .green)
                        Text(record.kind == .long ? "Long break" : "Short break")
                        Spacer()
                        Text(record.startedAt, format: .dateTime.day().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// 7-day bar strip: completed (accent) stacked on skipped (orange).
struct WeekBars: View {
    let days: [DayStats]
    let accent: Color

    var body: some View {
        let peak = max(1, days.map { $0.completed + $0.skipped }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days, id: \.day) { d in
                VStack(spacing: 4) {
                    Text("\(d.completed + d.skipped)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.orange.opacity(0.85))
                                .frame(height: 56 * CGFloat(d.skipped) / CGFloat(peak))
                            Rectangle().fill(accent)
                                .frame(height: 56 * CGFloat(d.completed) / CGFloat(peak))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .frame(height: 56)
                    Text(d.day, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .help("\(d.day.formatted(.dateTime.weekday(.wide).day().month())): ukończone \(d.completed), pominięte \(d.skipped)")
            }
        }
        legend
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                swatch(accent, "ukończone przerwy")
                swatch(Color.orange.opacity(0.85), "pominięte lub odroczone")
            }
            Text("Liczba nad słupkiem to wszystkie rozpoczęte przerwy danego dnia. Wysokość jest względna do najlepszego dnia tygodnia.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.top, 6)
    }

    private func swatch(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}
