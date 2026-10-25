import Foundation

/// Lays the remaining pomodoros of the plan onto today's calendar: work and
/// breaks run back to back, meetings are skipped, and the day ends at the end
/// of working hours.
public enum PomodoroForecast {
    public struct Cycle: Equatable, Sendable {
        public var workMinutes: Int
        public var shortBreakMinutes: Int
        public var longBreakMinutes: Int
        public var longEvery: Int

        public init(workMinutes: Int, shortBreakMinutes: Int, longBreakMinutes: Int, longEvery: Int) {
            self.workMinutes = workMinutes
            self.shortBreakMinutes = shortBreakMinutes
            self.longBreakMinutes = longBreakMinutes
            self.longEvery = max(1, longEvery)
        }
    }

    public struct Result: Equatable, Sendable {
        /// Pomodoros that fit before the end of the day.
        public let fitting: Int
        /// Pomodoros that do not fit today.
        public let spill: Int
        /// End of the last pomodoro when everything fits, otherwise nil.
        public let finishAt: Date?
    }

    /// - Parameter startingAtIndex: work periods already done since the last long break
    ///   cycle began (decides which upcoming break is the long one).
    public static func plan(pomodoros: Int, from start: Date, until end: Date, busy: [DateInterval],
                            cycle: Cycle, startingAtIndex: Int) -> Result {
        guard pomodoros > 0 else { return Result(fitting: 0, spill: 0, finishAt: nil) }
        let meetings = busy.sorted { $0.start < $1.start }
        let work = TimeInterval(cycle.workMinutes * 60)
        var cursor = start
        var placed = 0
        var lastEnd: Date?

        for i in 0..<pomodoros {
            cursor = clear(of: meetings, from: cursor, needing: work)
            let finish = cursor.addingTimeInterval(work)
            guard finish <= end else { break }
            placed += 1
            lastEnd = finish
            let isLong = (startingAtIndex + i + 1) % cycle.longEvery == 0
            cursor = finish.addingTimeInterval(TimeInterval((isLong ? cycle.longBreakMinutes : cycle.shortBreakMinutes) * 60))
        }
        return Result(fitting: placed, spill: pomodoros - placed, finishAt: placed == pomodoros ? lastEnd : nil)
    }

    /// First moment at or after `from` where `length` seconds fit before the next meeting.
    private static func clear(of meetings: [DateInterval], from: Date, needing length: TimeInterval) -> Date {
        var cursor = from
        var moved = true
        while moved {
            moved = false
            for m in meetings where m.end > cursor && m.start < cursor.addingTimeInterval(length) {
                cursor = m.end
                moved = true
            }
        }
        return cursor
    }
}
