import Foundation

/// Week-by-week grid of how many breaks were taken each day (like a contribution heatmap).
public enum ConsistencyHeatmap {
    public struct Entry: Equatable {
        public var start: Date
        public var skipped: Bool
        public init(start: Date, skipped: Bool) { self.start = start; self.skipped = skipped }
    }

    public struct Cell: Equatable {
        public var day: Date
        public var completed: Int
        public var skipped: Int
        public var isFuture: Bool
        /// 0 (nothing) ... 4 (a lot).
        public var level: Int { ConsistencyHeatmap.level(forCompleted: completed) }
    }

    public static func level(forCompleted n: Int) -> Int {
        switch n {
        case ..<1: return 0
        case 1...2: return 1
        case 3...4: return 2
        case 5...7: return 3
        default: return 4
        }
    }

    /// `count` columns (oldest first), each a Monday-first week of seven cells; the last column holds `now`.
    public static func weeks(_ entries: [Entry], count: Int, now: Date, calendar: Calendar) -> [[Cell]] {
        var cal = calendar
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: now)
        guard count > 0, let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }

        var completed: [Date: Int] = [:], skipped: [Date: Int] = [:]
        for e in entries {
            let day = cal.startOfDay(for: e.start)
            if e.skipped { skipped[day, default: 0] += 1 } else { completed[day, default: 0] += 1 }
        }
        return (0..<count).map { column in
            let weekStart = cal.date(byAdding: .weekOfYear, value: column - (count - 1), to: thisWeek) ?? thisWeek
            return (0..<7).map { offset in
                let day = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                return Cell(day: day, completed: completed[day] ?? 0, skipped: skipped[day] ?? 0, isFuture: day > today)
            }
        }
    }

    public static func activeDays(_ grid: [[Cell]]) -> Int {
        grid.flatMap { $0 }.filter { $0.completed > 0 }.count
    }
}
