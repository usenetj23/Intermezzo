import Foundation

/// Where the work happened: on the office network, or remotely over a work VPN.
public enum WorkPlace: String, CaseIterable, Sendable {
    case office
    case remote
}

/// One stretch of presence at work: from the first to the last keyboard/mouse activity while the Mac
/// was in the work zone (office Wi-Fi, or a work VPN away from it), with short absences bridged.
public struct WorkInterval: Equatable, Sendable {
    public var start: Date
    public var end: Date
    /// Time with recent input inside the stretch (the rest is meetings, the shop floor…).
    public var activeSeconds: TimeInterval
    public var place: WorkPlace
    /// Added or edited by hand in the register (flagged in the export).
    public var isCorrection: Bool
    public var note: String

    public init(start: Date, end: Date, activeSeconds: TimeInterval = 0, place: WorkPlace = .office,
                isCorrection: Bool = false, note: String = "") {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.place = place
        self.isCorrection = isCorrection
        self.note = note
    }
}

/// Folds heartbeat observations into work intervals.
public struct WorkSessionTracker: Sendable {
    /// Absences up to this long (a meeting, a walk to the machines) keep the interval open.
    public let bridge: TimeInterval
    /// Input this recent counts as "at the computer".
    public let activeWithin: TimeInterval
    public private(set) var current: WorkInterval?
    private var lastObservation: Date?

    public init(bridge: TimeInterval = 30 * 60, activeWithin: TimeInterval = 120, resuming: WorkInterval? = nil) {
        self.bridge = bridge
        self.activeWithin = activeWithin
        self.current = resuming
    }

    /// Feed one observation (`place` nil = outside the work zone); returns the interval that just
    /// closed, if any. Moving between office and remote closes one interval and opens the next.
    public mutating func observe(now: Date, lastInputAt: Date, place: WorkPlace?) -> WorkInterval? {
        let step = lastObservation.map { min(max(0, now.timeIntervalSince($0)), 60) } ?? 0
        lastObservation = now
        let active = now.timeIntervalSince(lastInputAt) < activeWithin
        var closed: WorkInterval?

        if let place, active {
            if var open = current, open.place == place, lastInputAt.timeIntervalSince(open.end) <= bridge {
                open.end = max(open.end, lastInputAt)
                open.activeSeconds += step
                current = open
            } else {
                closed = current
                current = WorkInterval(start: lastInputAt, end: lastInputAt, place: place)
            }
        } else if let open = current, now.timeIntervalSince(open.end) > bridge {
            closed = open
            current = nil
        }
        return closed
    }

    /// Stops tracking (quit, sleep): hands back the open interval.
    public mutating func close() -> WorkInterval? {
        defer { current = nil; lastObservation = nil }
        return current
    }
}

/// Contracted hours: which weekdays (bit 0 = Monday) and from–to per day.
public struct WorkSchedule {
    public let daysMask: Int
    public let hours: WeekHours.Window
    public let perDay: WeekHours?

    public init(daysMask: Int, hours: WeekHours.Window, perDay: WeekHours? = nil) {
        self.daysMask = daysMask
        self.hours = hours
        self.perDay = perDay
    }

    /// Working window (minutes of the day) for `date`, nil on a day off.
    public func window(for date: Date, calendar: Calendar) -> WeekHours.Window? {
        let index = (calendar.component(.weekday, from: date) + 5) % 7
        guard daysMask & (1 << index) != 0 else { return nil }
        return perDay?.window(forDay: index, default: hours) ?? hours
    }
}

public struct WorkDaySummary: Equatable, Sendable {
    public let day: Date
    public let isWorkday: Bool
    public let first: Date
    public let last: Date
    /// Presence at work that day, office and remote.
    public let worked: TimeInterval
    /// Part of `worked` done remotely.
    public let remote: TimeInterval
    /// Part of `worked` inside the contracted hours.
    public let inHours: TimeInterval
    public let remoteInHours: TimeInterval
    public let active: TimeInterval
    /// Some time was added or edited by hand.
    public let hasCorrections: Bool
    public let notes: [String]

    public var office: TimeInterval { worked - remote }
    /// Work outside the contracted hours (all of it on a day off).
    public var overtime: TimeInterval { worked - inHours }
    public var remoteOvertime: TimeInterval { remote - remoteInHours }
    public var officeOvertime: TimeInterval { overtime - remoteOvertime }
    /// Office and remote overtime are billed apart, each rounded down to whole quarter hours.
    public var billableOfficeOvertime: TimeInterval { WorkLog.billable(officeOvertime) }
    public var billableRemoteOvertime: TimeInterval { WorkLog.billable(remoteOvertime) }
    public var billableOvertime: TimeInterval { billableOfficeOvertime + billableRemoteOvertime }
}

public enum WorkLog {
    public static let billingStep: TimeInterval = 15 * 60

    static func billable(_ seconds: TimeInterval) -> TimeInterval {
        (max(0, seconds) / billingStep).rounded(.down) * billingStep
    }

    /// One summary per calendar day touched by `intervals`, oldest first. Intervals crossing
    /// midnight are split, and time covered twice (a manual entry over recorded time) counts once,
    /// for the interval that started first.
    public static func summarize(_ intervals: [WorkInterval], schedule: WorkSchedule, calendar: Calendar) -> [WorkDaySummary] {
        var pieces: [Date: [WorkInterval]] = [:]
        for interval in intervals where interval.end > interval.start {
            var cursor = interval.start
            let total = interval.end.timeIntervalSince(interval.start)
            while cursor < interval.end {
                let day = calendar.startOfDay(for: cursor)
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                let end = min(next, interval.end)
                var piece = interval
                piece.start = cursor
                piece.end = end
                piece.activeSeconds = interval.activeSeconds * end.timeIntervalSince(cursor) / total
                pieces[day, default: []].append(piece)
                cursor = end
            }
        }
        return pieces.keys.sorted().map { day in
            summarizeDay(day, parts: withoutOverlaps(pieces[day]!), schedule: schedule, calendar: calendar)
        }
    }

    private static func withoutOverlaps(_ parts: [WorkInterval]) -> [WorkInterval] {
        var covered = Date.distantPast
        var out: [WorkInterval] = []
        for p in parts.sorted(by: { $0.start < $1.start }) {
            let start = max(p.start, covered)
            guard start < p.end else { continue }
            var kept = p
            kept.activeSeconds = p.activeSeconds * p.end.timeIntervalSince(start) / p.end.timeIntervalSince(p.start)
            kept.start = start
            out.append(kept)
            covered = max(covered, p.end)
        }
        return out
    }

    private static func summarizeDay(_ day: Date, parts: [WorkInterval], schedule: WorkSchedule,
                                     calendar: Calendar) -> WorkDaySummary {
        let window = schedule.window(for: day, calendar: calendar)
        func inHours(_ list: [WorkInterval]) -> TimeInterval {
            guard let w = window else { return 0 }
            // Through the calendar, so a DST change day keeps 6:30 at 6:30.
            let ws = calendar.date(bySettingHour: w.start / 60, minute: w.start % 60, second: 0, of: day) ?? day
            let we = w.end >= 24 * 60
                ? calendar.date(byAdding: .day, value: 1, to: day)!
                : calendar.date(bySettingHour: w.end / 60, minute: w.end % 60, second: 0, of: day) ?? day
            return list.reduce(0) { $0 + max(0, min($1.end, we).timeIntervalSince(max($1.start, ws))) }
        }
        func length(_ list: [WorkInterval]) -> TimeInterval { list.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
        let remote = parts.filter { $0.place == .remote }
        return WorkDaySummary(day: day, isWorkday: window != nil,
                              first: parts.map(\.start).min() ?? day, last: parts.map(\.end).max() ?? day,
                              worked: length(parts), remote: length(remote),
                              inHours: inHours(parts), remoteInHours: inHours(remote),
                              active: parts.reduce(0) { $0 + $1.activeSeconds },
                              hasCorrections: parts.contains(where: \.isCorrection),
                              notes: parts.map(\.note).filter { !$0.isEmpty })
    }

    /// "H:MM", truncated to the minute.
    public static func hm(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// Column names follow the app language; the key is the Polish header.
    public static var csvHeader: String {
        kitL("Data;Od;Do;Praca;Biuro;Zdalnie;W godzinach;Nadgodziny;Nadgodziny rozliczeniowe;Nadgodziny zdalne;Nadgodziny zdalne rozliczeniowe;Aktywnie przy komputerze;Korekta;Notatki")
    }

    /// Semicolon CSV (opens as columns in Polish Excel), one row per day.
    public static func csv(_ days: [WorkDaySummary], calendar: Calendar) -> String {
        let date = formatter("yyyy-MM-dd", calendar)
        let time = formatter("HH:mm", calendar)
        var lines = [csvHeader]
        for d in days {
            let notes = d.notes.joined(separator: " | ").replacingOccurrences(of: ";", with: ",")
                .replacingOccurrences(of: "\n", with: " ")
            lines.append([date.string(from: d.day), time.string(from: d.first), time.string(from: d.last),
                          hm(d.worked), hm(d.office), hm(d.remote), hm(d.inHours), hm(d.overtime),
                          hm(d.billableOvertime), hm(d.remoteOvertime), hm(d.billableRemoteOvertime),
                          hm(d.active), d.hasCorrections ? kitL("tak") : "", notes]
                .joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
