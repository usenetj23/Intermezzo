import SwiftUI
import IntermezzoKit

/// One PDF page: the day ribbon (6:00–22:00) and the list of that day's sessions.
struct DayReportPage: View {
    let day: Date
    let data: ReportData
    let calendar: Calendar

    private static let axisStartHour = 6.0
    private static let axisEndHour = 22.0
    private static let ribbonWidth = 515.0
    private static let maxRows = 24

    private var records: [PomodoroRecord] { data.records(overlapping: day, calendar: calendar) }

    private var segments: [RibbonSegment] {
        let raw = DayRibbon.build(day: day, calendar: calendar, pomodoros: records,
                                  breaks: data.breaks, meetings: data.meetings)
        return DayRibbon.merged(raw)
    }

    private func hour(_ date: Date) -> Double {
        let start = calendar.startOfDay(for: day)
        return date.timeIntervalSince(start) / 3600
    }

    private func color(_ seg: RibbonSegment) -> Color {
        switch seg.kind {
        case .focus: return colorFromHex(data.project(named: seg.label)?.colorHex ?? PomodoroProject.defaultColorHex)
        case .breakTaken: return Color(red: 0.25, green: 0.70, blue: 0.40)
        case .breakSkipped: return Color(red: 0.95, green: 0.55, blue: 0.15)
        case .meeting: return Color(white: 0.62)
        }
    }

    private var title: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        f.locale = ReportData.locale
        return f.string(from: day)
    }

    private func clock(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        let list = records
        let segs = segments
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .bold, design: .serif))
            if list.isEmpty && segs.isEmpty {
                Text("No data for this day").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 8)
            } else {
                ribbon(segs)
                legend
                Divider()
                ForEach(Array(list.prefix(Self.maxRows).enumerated()), id: \.offset) { _, r in sessionRow(r) }
                if list.count > Self.maxRows {
                    Text("+ \(list.count - Self.maxRows) more sessions").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(40)
        .foregroundStyle(Color.black)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func ribbon(_ segs: [RibbonSegment]) -> some View {
        let span = Self.axisEndHour - Self.axisStartHour
        let scale = Self.ribbonWidth / span
        return VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(white: 0.93)).frame(width: Self.ribbonWidth, height: 34)
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    let a = max(hour(seg.start), Self.axisStartHour), b = min(hour(seg.end), Self.axisEndHour)
                    if b > a {
                        Rectangle().fill(color(seg))
                            .frame(width: max(1, (b - a) * scale), height: 34)
                            .offset(x: (a - Self.axisStartHour) * scale)
                    }
                }
            }
            .frame(width: Self.ribbonWidth, height: 34, alignment: .topLeading)
            .clipped()
            ZStack(alignment: .topLeading) {
                ForEach(Int(Self.axisStartHour)...Int(Self.axisEndHour), id: \.self) { h in
                    if h % 2 == 0 {
                        Text(String(format: "%d:00", h)).font(.system(size: 8)).foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: (Double(h) - Self.axisStartHour) * scale - 8)
                    }
                }
            }
            .frame(width: Self.ribbonWidth, height: 10, alignment: .topLeading)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            swatch(Color(red: 0.35, green: 0.55, blue: 0.95), "Focus (project colour)")
            swatch(Color(red: 0.25, green: 0.70, blue: 0.40), "Break")
            swatch(Color(red: 0.95, green: 0.55, blue: 0.15), "Skipped break")
            swatch(Color(white: 0.62), "Meeting")
        }
        .font(.system(size: 9))
    }

    private func swatch(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) { Rectangle().fill(color).frame(width: 10, height: 10); Text(label) }
    }

    private func sessionRow(_ r: PomodoroRecord) -> some View {
        HStack(spacing: 8) {
            Circle().fill(colorFromHex(data.project(named: r.project)?.colorHex ?? PomodoroProject.defaultColorHex))
                .frame(width: 8, height: 8)
            Text(verbatim: "\(clock(r.startedAt))–\(clock(r.date))").monospacedDigit().frame(width: 84, alignment: .leading)
            Text(r.project.isEmpty ? String(localized: "No project") : r.project).lineLimit(1).frame(width: 120, alignment: .leading)
            Text(r.taskTitle).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Text("\(r.internalInterruptions + r.externalInterruptions) int · \(r.appSwitches) sw")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Text("\(Int((Double(r.actualSeconds) / 60).rounded())) min").monospacedDigit()
        }
        .font(.system(size: 11))
    }
}
