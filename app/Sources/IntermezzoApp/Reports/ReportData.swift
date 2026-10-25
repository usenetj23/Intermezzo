import Foundation
import SwiftData
import IntermezzoKit

/// Everything a report needs, gathered up front so the exporter can be driven without SwiftData or EventKit.
struct ReportData {
    var records: [PomodoroRecord] = []
    var projects: [PomodoroProject] = []
    var breaks: [RibbonBreak] = []
    var meetings: [DateInterval] = []

    /// Reads the pomodoro ledger, SwiftData breaks and (if allowed) calendar busy times for `range`.
    @MainActor
    static func load(range: ReportRange, calendar: Calendar = .current) -> ReportData {
        let interval = range.interval(calendar: calendar)
        let ledger = PomodoroController.shared.ledger
        let context = ModelContext(Store.container)
        let end = interval.end
        let descriptor = FetchDescriptor<BreakRecord>(predicate: #Predicate { $0.startedAt < end })
        let stored = (try? context.fetch(descriptor)) ?? []
        let breaks = stored.compactMap { record -> RibbonBreak? in
            let finish = record.endedAt ?? record.startedAt
            guard finish >= interval.start else { return nil }
            return RibbonBreak(start: record.startedAt, end: finish, skipped: record.wasSkipped)
        }
        return ReportData(records: ledger.records, projects: ledger.projects, breaks: breaks,
                          meetings: WorkDetector.shared.busyIntervals(from: interval.start, to: interval.end))
    }

    /// Dates in the report follow the app language (the format templates stay fixed).
    static var locale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    func project(named name: String) -> PomodoroProject? {
        projects.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// Pomodoros that overlap the day (not just those that end in it).
    func records(overlapping day: Date, calendar: Calendar) -> [PomodoroRecord] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return records.filter { $0.startedAt < end && $0.date > start }
            .sorted { $0.startedAt < $1.startedAt }
    }
}
