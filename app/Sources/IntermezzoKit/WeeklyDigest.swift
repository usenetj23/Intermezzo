import Foundation

// The numbers behind the weekly summary: the last seven days against the seven before, worked out here so that
// the model only describes them and never computes anything. No project names, apps or networks.

public struct WeeklyDigest: Equatable, Sendable {
    public struct Week: Equatable, Sendable {
        public let completed: Int
        public let skipped: Int

        public var completionPercent: Int? {
            let all = completed + skipped
            return all == 0 ? nil : Int((Double(completed) / Double(all) * 100).rounded())
        }
    }

    public let thisWeek: Week
    public let previousWeek: Week
    /// Completed breaks per weekday of the last seven days, Monday first.
    public let completedByWeekday: [Int]
    /// Skipped breaks of the last seven days by `morning` (6–12), `afternoon` (12–17), `evening` (17–22), `other`.
    public let skippedByPartOfDay: [String: Int]

    public var isEmpty: Bool { [thisWeek, previousWeek].allSatisfy { $0.completed + $0.skipped == 0 } }

    private static let parts = ["morning", "afternoon", "evening", "other"]

    public static func build(samples: [BreakSample], now: Date, calendar: Calendar = .current) -> WeeklyDigest {
        let days = BreakStats.lastDays(14, samples: samples, now: now, calendar: calendar)
        func week(_ slice: ArraySlice<DayStats>) -> Week {
            Week(completed: slice.reduce(0) { $0 + $1.completed }, skipped: slice.reduce(0) { $0 + $1.skipped })
        }
        let thisStart = days.dropFirst(7).first?.day ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: thisStart) ?? now
        var weekdays = [Int](repeating: 0, count: 7)
        var skippedParts = Dictionary(uniqueKeysWithValues: parts.map { ($0, 0) })
        for sample in samples where sample.startedAt >= thisStart && sample.startedAt < end {
            if sample.skipped {
                skippedParts[partOfDay(calendar.component(.hour, from: sample.startedAt)), default: 0] += 1
            } else {
                weekdays[(calendar.component(.weekday, from: sample.startedAt) + 5) % 7] += 1
            }
        }
        return WeeklyDigest(thisWeek: week(days.dropFirst(7)), previousWeek: week(days.prefix(7)),
                            completedByWeekday: weekdays, skippedByPartOfDay: skippedParts)
    }

    private static func partOfDay(_ hour: Int) -> String {
        switch hour {
        case 6..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "other"
        }
    }

    /// Short lines with the finished numbers, in English (the model answers in the app's language).
    public func text() -> String {
        func line(_ title: String, _ week: Week) -> String {
            guard let percent = week.completionPercent else { return "\(title): no breaks recorded." }
            return "\(title): breaks done \(week.completed), skipped \(week.skipped), completion rate \(percent)%."
        }
        if isEmpty { return "No breaks were recorded in the last 14 days." }
        let weekdays = completedByWeekday.map(String.init).joined(separator: ", ")
        let skipped = Self.parts.map { "\($0) \(skippedByPartOfDay[$0] ?? 0)" }.joined(separator: ", ")
        return [line("Last 7 days", thisWeek), line("Previous 7 days", previousWeek),
                "Breaks done by weekday (Monday to Sunday): \(weekdays).",
                "Skipped breaks by part of the day: \(skipped)."].joined(separator: "\n")
    }

    public static func prompt(digest: WeeklyDigest, language: String) -> AIRequest {
        let system = """
        You write a short weekly review for a user of a break reminder app. Use only the numbers you are given: \
        do not calculate new ones and do not invent any. Write at most 150 words: describe the week, compare it with \
        the previous one when there are numbers for it, then give 2 or 3 practical tips (for example about the parts \
        of the day when breaks are skipped). Do not give medical or health advice. Write in \
        \(language == "pl" ? "Polish" : "English").
        """
        return AIRequest(system: system, user: digest.text())
    }
}
