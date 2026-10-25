import Foundation

/// How firmly breaks are enforced. `classic` is the behaviour before levels existed.
public enum Strictness: String, CaseIterable, Equatable {
    case classic, casual, balanced, hardcore

    public init(stored: String?) {
        self = stored.flatMap(Strictness.init(rawValue:)) ?? .classic
    }

    public var policy: OverlayPolicy {
        switch self {
        case .classic: return OverlayPolicy(snoozeLimit: nil, showsSkip: true, escapeSkips: true)
        case .casual: return OverlayPolicy(snoozeLimit: 6, showsSkip: true, escapeSkips: true)
        case .balanced: return OverlayPolicy(snoozeLimit: 3, showsSkip: true, escapeSkips: true)
        case .hardcore: return OverlayPolicy(snoozeLimit: 0, showsSkip: false, escapeSkips: false)
        }
    }
}

/// What the break screen offers. `snoozeLimit` is per day; nil = unlimited.
public struct OverlayPolicy: Equatable {
    public var snoozeLimit: Int?
    public var showsSkip: Bool
    public var escapeSkips: Bool
    public init(snoozeLimit: Int?, showsSkip: Bool, escapeSkips: Bool) {
        self.snoozeLimit = snoozeLimit
        self.showsSkip = showsSkip
        self.escapeSkips = escapeSkips
    }
}

/// Snoozes used today; resets by itself on a new calendar day.
public struct SnoozeBudget: Codable, Equatable {
    var day: String = ""
    var count: Int = 0

    public init() {}

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    public func used(on date: Date, calendar: Calendar) -> Int {
        day == Self.key(date, calendar) ? count : 0
    }

    public func remaining(limit: Int?, on date: Date, calendar: Calendar) -> Int? {
        limit.map { max(0, $0 - used(on: date, calendar: calendar)) }
    }

    public func consuming(now: Date, calendar: Calendar) -> SnoozeBudget {
        var next = SnoozeBudget()
        next.day = Self.key(now, calendar)
        next.count = used(on: now, calendar: calendar) + 1
        return next
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data?) -> SnoozeBudget {
        guard let data, let value = try? JSONDecoder().decode(SnoozeBudget.self, from: data) else { return SnoozeBudget() }
        return value
    }
}

/// Tone of the break screen: encouraging streaks, or calm with nothing scored.
public enum MotivationStyle: String, CaseIterable, Equatable {
    case streak, calm

    public init(stored: String?) {
        self = stored.flatMap(MotivationStyle.init(rawValue:)) ?? .streak
    }

    public func progressText(breakNumber: Int) -> String {
        switch self {
        case .streak: return kitL("Break #%lld today · let's keep that streak going", breakNumber)
        case .calm: return kitL("Break #%lld today", breakNumber)
        }
    }

    public var chartFooter: String? {
        self == .streak ? kitL("Break alert! Let's keep that streak going.") : nil
    }
    public var showsTrendChart: Bool { self == .streak }
    public var showsStreakCounters: Bool { self == .streak }
}
