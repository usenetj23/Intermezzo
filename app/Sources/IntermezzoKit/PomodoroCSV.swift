import Foundation

/// CSV export of pomodoro records.
public enum PomodoroCSV {
    public static let header = "date,start,end,project,client,task,minutes,actual_minutes,"
        + "internal_interruptions,external_interruptions,app_switches,billable,amount,currency"

    /// Records ending in [from, to), oldest first. Times are ISO 8601 in the local time zone.
    /// `amount`/`currency` are filled only for billable projects with a rate (rounded to 0.01 here, at presentation).
    public static func make(records: [PomodoroRecord], projects: [PomodoroProject],
                            from: Date, to: Date) -> String {
        let dayFmt = formatter("yyyy-MM-dd")
        let timeFmt = formatter("yyyy-MM-dd'T'HH:mm:ss")
        let rows = records
            .filter { $0.date >= from && $0.date < to }
            .sorted { ($0.startedAt, $0.date) < ($1.startedAt, $1.date) }
            .map { r -> String in
                let project = projects.first {
                    $0.name.compare(r.project, options: .caseInsensitive) == .orderedSame
                }
                var amount = "", currency = ""
                if let p = project, p.billable, let rate = p.hourlyRate {
                    amount = String(format: "%.2f", Double(r.actualSeconds) / 3600 * rate)
                    currency = p.currency.uppercased()
                }
                let fields = [
                    dayFmt.string(from: r.date), timeFmt.string(from: r.startedAt), timeFmt.string(from: r.date),
                    r.project, project?.client ?? "", r.taskTitle,
                    String(r.minutes), String(format: "%.1f", Double(r.actualSeconds) / 60),
                    String(r.internalInterruptions), String(r.externalInterruptions), String(r.appSwitches),
                    (project?.billable ?? false) ? "true" : "false", amount, currency,
                ]
                return fields.map(escape).joined(separator: ",")
            }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
