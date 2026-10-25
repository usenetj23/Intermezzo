import Foundation

/// The span of days a report covers.
public enum ReportRange: Equatable, Sendable {
    case day(Date)
    /// Seven days, the last being the day of the given date.
    case week(endingOn: Date)
    /// The whole calendar month containing the date.
    case month(containing: Date)

    /// Start of every day in the range, oldest first.
    public func days(calendar: Calendar) -> [Date] {
        switch self {
        case .day(let d):
            return [calendar.startOfDay(for: d)]
        case .week(let end):
            let last = calendar.startOfDay(for: end)
            return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
        case .month(let d):
            guard let month = calendar.dateInterval(of: .month, for: d) else { return [calendar.startOfDay(for: d)] }
            var out: [Date] = []
            var cursor = calendar.startOfDay(for: month.start)
            while cursor < month.end {
                out.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return out
        }
    }

    /// From the first day's start to the start of the day after the last one.
    public func interval(calendar: Calendar) -> DateInterval {
        let days = days(calendar: calendar)
        let first = days.first ?? Date()
        let last = days.last ?? first
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return DateInterval(start: first, end: max(end, first))
    }
}

/// How many PDF pages a report has: one summary page plus one page per day (also for empty days).
public enum ReportLayout {
    public static func pages(range: ReportRange, calendar: Calendar) -> Int {
        range.days(calendar: calendar).count + 1
    }

    /// True when the PDF actually written has `pageCount` pages = one summary page
    /// plus one per day. The exporter passes the page count read back from the
    /// rendered file, so a render that silently lost a page is caught.
    public static func isConsistent(pageCount: Int, days: [Date]) -> Bool {
        pageCount == days.count + 1
    }
}
