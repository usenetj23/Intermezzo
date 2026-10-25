import SwiftUI
import IntermezzoKit

/// Page 1 of the PDF: totals per project, amounts per currency, counts.
struct ReportSummaryPage: View {
    let data: ReportData
    let interval: DateInterval
    let calendar: Calendar

    private struct Row: Identifiable {
        let id: String
        let project: String
        let client: String
        let colorHex: String
        let count: Int
        let seconds: Int
        let amount: String
    }

    private var inRange: [PomodoroRecord] {
        data.records.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    private var rows: [Row] {
        Dictionary(grouping: inRange, by: { $0.project.lowercased() }).values.map { group in
            let name = group[0].project
            let p = data.project(named: name)
            let seconds = group.reduce(0) { $0 + $1.actualSeconds }
            var amount = ""
            if let p, p.billable, let rate = p.hourlyRate {
                amount = Self.money(Double(seconds) / 3600 * rate, p.currency)
            }
            return Row(id: name.lowercased(), project: name.isEmpty ? String(localized: "No project") : name, client: p?.client ?? "",
                       colorHex: p?.colorHex ?? PomodoroProject.defaultColorHex, count: group.count,
                       seconds: seconds, amount: amount)
        }.sorted { ($0.seconds, $1.project) > ($1.seconds, $0.project) }
    }

    /// Per currency, billable projects with a rate only; rounded to 0.01 only here.
    private var currencyTotals: [(String, Double)] {
        var sums: [String: Double] = [:]
        for r in inRange {
            guard let p = data.project(named: r.project), p.billable, let rate = p.hourlyRate else { continue }
            sums[p.currency.uppercased(), default: 0] += Double(r.actualSeconds) / 3600 * rate
        }
        return sums.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private static func money(_ value: Double, _ currency: String) -> String {
        String(format: "%.2f %@", value, currency.uppercased())
    }

    private var periodText: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = ReportData.locale
        let last = interval.end.addingTimeInterval(-1)
        let a = f.string(from: interval.start), b = f.string(from: last)
        return a == b ? a : "\(a) – \(b)"
    }

    var body: some View {
        let list = rows
        let breaks = data.breaks.filter { $0.start >= interval.start && $0.start < interval.end }
        VStack(alignment: .leading, spacing: 14) {
            Text("Intermezzo report").font(.system(size: 26, weight: .bold, design: .serif))
            Text(periodText).font(.system(size: 13)).foregroundStyle(.secondary)
            Divider()
            HStack(alignment: .top, spacing: 28) {
                figure("\(inRange.count)", "pomodoros")
                figure(AudioFit.clock(TimeInterval(inRange.reduce(0) { $0 + $1.actualSeconds })), "focus time")
                figure("\(breaks.filter { !$0.skipped }.count)", "breaks taken")
                figure("\(breaks.filter(\.skipped).count)", "breaks skipped")
                figure("\(inRange.reduce(0) { $0 + $1.internalInterruptions }) / \(inRange.reduce(0) { $0 + $1.externalInterruptions })",
                       "self / other interruptions")
            }
            Text("By project").font(.system(size: 14, weight: .semibold)).padding(.top, 6)
            if list.isEmpty {
                Text("No data for this period").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(list.prefix(16)) { row in
                HStack(spacing: 8) {
                    Circle().fill(colorFromHex(row.colorHex)).frame(width: 9, height: 9)
                    Text(row.client.isEmpty ? row.project : "\(row.project) · \(row.client)").lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(row.count) 🍅").foregroundStyle(.secondary)
                    Text(AudioFit.clock(TimeInterval(row.seconds))).monospacedDigit().frame(width: 60, alignment: .trailing)
                    Text(row.amount).monospacedDigit().frame(width: 100, alignment: .trailing)
                }
                .font(.system(size: 12))
            }
            if list.count > 16 { Text("+ \(list.count - 16) more projects").font(.system(size: 11)).foregroundStyle(.secondary) }
            if !currencyTotals.isEmpty {
                Divider().padding(.top, 4)
                Text("Amounts").font(.system(size: 14, weight: .semibold))
                ForEach(currencyTotals, id: \.0) { code, value in
                    HStack { Text(code); Spacer(); Text(Self.money(value, code)).monospacedDigit() }
                        .font(.system(size: 12))
                }
                Text("Billable projects with an hourly rate only.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(40)
        .foregroundStyle(Color.black)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
        }
    }
}
