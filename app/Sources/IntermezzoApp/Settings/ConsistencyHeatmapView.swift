import SwiftUI
import IntermezzoKit

/// 12 weeks of breaks as a calendar grid: darker = more breaks taken that day.
struct ConsistencyHeatmapView: View {
    let entries: [ConsistencyHeatmap.Entry]
    let accent: Color

    private static let weeks = 12
    private static let cell: CGFloat = 16
    private static let gap: CGFloat = 4
    private static let dayNames = [String(localized: "Pn"), String(localized: "Wt"), String(localized: "Śr"),
                                   String(localized: "Cz"), String(localized: "Pt"), String(localized: "So"),
                                   String(localized: "Nd")]

    var body: some View {
        let grid = ConsistencyHeatmap.weeks(entries, count: Self.weeks, now: Date(), calendar: .current)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(spacing: Self.gap) {
                    ForEach(Self.dayNames, id: \.self) { name in
                        Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
                            .frame(width: 18, height: Self.cell)
                    }
                }
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: Self.gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(fill(day))
                                .frame(width: Self.cell, height: Self.cell)
                                .contentShape(Rectangle())
                                .help(help(day))
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("mniej").foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(level == 0 ? Color.primary.opacity(0.08) : accent.opacity(0.2 + 0.2 * Double(level)))
                        .frame(width: 12, height: 12)
                }
                Text("więcej").foregroundStyle(.secondary)
            }
            .font(.caption)
            Text("Każdy kwadrat to jeden dzień, każda kolumna to tydzień (od najstarszego po lewej do bieżącego po prawej, poniedziałek u góry). Im ciemniejszy, tym więcej ukończonych przerw: 1–2, 3–4, 5–7, 8 i więcej. Najedź na kwadrat, by zobaczyć dzień. \(ConsistencyHeatmap.activeDays(grid)) dni z przerwą w ostatnich \(Self.weeks) tygodniach; pominięte przerwy nie przyciemniają pola.")
                .settingsNote()
        }
    }

    private func fill(_ day: ConsistencyHeatmap.Cell) -> Color {
        if day.isFuture { return .clear }
        return day.level == 0 ? Color.primary.opacity(0.08) : accent.opacity(0.2 + 0.2 * Double(day.level))
    }

    private func help(_ day: ConsistencyHeatmap.Cell) -> String {
        String(localized: "\(day.day.formatted(date: .abbreviated, time: .omitted)): \(day.completed) ukończone, \(day.skipped) pominięte")
    }
}
