import Foundation

public struct BreakSample: Equatable {
    public let kind: String
    public let startedAt: Date
    public let endedAt: Date?
    public let skipped: Bool

    public init(kind: String, startedAt: Date, endedAt: Date?, skipped: Bool) {
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.skipped = skipped
    }
}

public struct DayStats: Equatable {
    public let day: Date          // start of day
    public let completed: Int
    public let skipped: Int
}

public enum BreakStats {
    /// Per-day counts for the last `n` days ending today, oldest first,
    /// including days without any break.
    public static func lastDays(_ n: Int, samples: [BreakSample], now: Date,
                                calendar: Calendar = .current) -> [DayStats] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, n)).reversed().compactMap { back -> DayStats? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let inDay = samples.filter { $0.startedAt >= day && $0.startedAt < next }
            return DayStats(day: day,
                            completed: inDay.filter { !$0.skipped }.count,
                            skipped: inDay.filter { $0.skipped }.count)
        }
    }

    /// Share of started breaks that were completed rather than skipped (0…1).
    public static func completionRate(_ days: [DayStats]) -> Double {
        let done = days.reduce(0) { $0 + $1.completed }
        let all = days.reduce(0) { $0 + $1.completed + $1.skipped }
        return all == 0 ? 0 : Double(done) / Double(all)
    }

    public static func csv(_ samples: [BreakSample], calendar: Calendar = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = ["kind,started_at,ended_at,skipped,duration_seconds"]
        for s in samples {
            let end = s.endedAt.map { formatter.string(from: $0) } ?? ""
            let duration = s.endedAt.map { String(Int($0.timeIntervalSince(s.startedAt))) } ?? ""
            lines.append("\(s.kind),\(formatter.string(from: s.startedAt)),\(end),\(s.skipped),\(duration)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
