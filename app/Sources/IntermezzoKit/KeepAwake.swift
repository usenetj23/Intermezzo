import Foundation

// Keeping the Mac awake: what to hold, and when to let go. Pure decisions; the app owns the IOKit
// assertions, the battery and the thermal readings.

public enum KeepAwakeLevel: String, CaseIterable, Comparable, Sendable {
    /// The Mac does not go to sleep; the screen may still dim and turn off.
    case system
    /// Neither the Mac nor the screen goes to sleep.
    case systemAndDisplay

    public static func < (a: KeepAwakeLevel, b: KeepAwakeLevel) -> Bool { a == .system && b == .systemAndDisplay }
}

public enum ThermalLevel: Int, Comparable, Sendable {
    case nominal, fair, serious, critical
    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

public enum KeepAwakeStop: String, Sendable {
    case timerEnded, thermal, batteryLow, lowPowerMode
}

public struct KeepAwakeRequest: Equatable, Sendable {
    public let level: KeepAwakeLevel
    /// nil: until the user turns it off.
    public let until: Date?
    public init(level: KeepAwakeLevel, until: Date?) {
        self.level = level
        self.until = until
    }
}

public struct KeepAwakeSafety: Equatable, Sendable {
    /// 0 = never stop because of the battery.
    public let batteryFloorPercent: Int
    public let stopOnLowPowerMode: Bool
    public let stopOnThermal: Bool
    public init(batteryFloorPercent: Int, stopOnLowPowerMode: Bool, stopOnThermal: Bool) {
        self.batteryFloorPercent = batteryFloorPercent
        self.stopOnLowPowerMode = stopOnLowPowerMode
        self.stopOnThermal = stopOnThermal
    }
}

public struct PowerConditions: Equatable, Sendable {
    public let onBattery: Bool
    public let batteryPercent: Int?
    public let lowPowerMode: Bool
    public let thermal: ThermalLevel
    public init(onBattery: Bool, batteryPercent: Int?, lowPowerMode: Bool, thermal: ThermalLevel) {
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }
}

public enum KeepAwakeDecision: Equatable, Sendable {
    case hold(KeepAwakeLevel)
    /// The reason is nil when nothing was requested.
    case release(KeepAwakeStop?)
}

public enum KeepAwakePolicy {
    /// The user's own request, with its timer and the safety limits.
    public static func manual(request: KeepAwakeRequest?, safety: KeepAwakeSafety, power: PowerConditions,
                              now: Date) -> KeepAwakeDecision {
        guard let request else { return .release(nil) }
        if let until = request.until, now >= until { return .release(.timerEnded) }
        if let stop = safetyStop(safety, power) { return .release(stop) }
        return .hold(request.level)
    }

    /// A hold started by the app itself (a focus session, a chosen app): safety limits, no timer.
    public static func automatic(wanted: KeepAwakeLevel?, safety: KeepAwakeSafety, power: PowerConditions) -> KeepAwakeLevel? {
        guard let wanted, safetyStop(safety, power) == nil else { return nil }
        return wanted
    }

    public static func combine(_ levels: [KeepAwakeLevel]) -> KeepAwakeLevel? { levels.max() }

    private static func safetyStop(_ safety: KeepAwakeSafety, _ power: PowerConditions) -> KeepAwakeStop? {
        if safety.stopOnThermal, power.thermal >= .serious { return .thermal }
        if power.onBattery, safety.batteryFloorPercent > 0, let level = power.batteryPercent,
           level <= safety.batteryFloorPercent { return .batteryLow }
        if power.onBattery, safety.stopOnLowPowerMode, power.lowPowerMode { return .lowPowerMode }
        return nil
    }
}

public enum KeepAwakeDuration: Equatable, Sendable {
    case minutes(Int)
    /// Until this whole hour (0...23): today, or tomorrow when it has already passed.
    case untilHour(Int)
    case indefinitely

    public func end(from date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .indefinitely: return nil
        case .minutes(let m): return date.addingTimeInterval(Double(max(m, 1)) * 60)
        case .untilHour(let hour):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0),
                                     matchingPolicy: .nextTime)
        }
    }

    /// The next whole hours after `date`, wrapping past midnight (for a "until 17:00" menu).
    public static func nextWholeHours(count: Int, from date: Date, calendar: Calendar = .current) -> [Int] {
        let first = (calendar.component(.hour, from: date) + 1) % 24
        return (0..<count).map { (first + $0) % 24 }
    }
}

public struct HoldingProcess: Equatable, Sendable {
    public let pid: Int
    public let process: String
    public let type: String
    public let reason: String
}

/// The part of `pmset -g assertions` that lists who holds the Mac awake.
public enum PmsetAssertions {
    public static func parse(_ text: String, excluding ownPID: Int? = nil) -> [HoldingProcess] {
        guard let regex = try? NSRegularExpression(
            pattern: #"pid (\d+)\(([^)]*)\):.*?\s(\w+) named: "(.*)""#) else { return [] }
        var result: [HoldingProcess] = []
        for line in text.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range), m.numberOfRanges == 5,
                  let pid = Int(group(s, m, 1)) else { continue }
            if pid == ownPID { continue }
            result.append(HoldingProcess(pid: pid, process: group(s, m, 2), type: group(s, m, 3), reason: group(s, m, 4)))
        }
        return result
    }

    private static func group(_ s: String, _ m: NSTextCheckingResult, _ i: Int) -> String {
        Range(m.range(at: i), in: s).map { String(s[$0]) } ?? ""
    }
}

public enum KeepAwakeApps {
    /// Lower-case name without ".app" / ".exe", the way a typed name and a running app are compared.
    public static func normalized(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces).lowercased()
        for suffix in [".app", ".exe"] where n.hasSuffix(suffix) { n = String(n.dropLast(suffix.count)) }
        return n
    }

    public static func list(fromCommaText text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The first listed name that matches a running app (by display name or executable name).
    public static func firstMatch(wanted: [String], running: [String]) -> String? {
        let runningSet = Set(running.map(normalized))
        return wanted.first { runningSet.contains(normalized($0)) }
    }
}
