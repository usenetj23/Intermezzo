import Foundation

/// One work/break rhythm of the personal experiment.
public struct RhythmArm: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var workMinutes: Int
    public var shortBreakMinutes: Int

    public static let defaultA = RhythmArm(id: "A", workMinutes: 25, shortBreakMinutes: 5)
    public static let defaultB = RhythmArm(id: "B", workMinutes: 50, shortBreakMinutes: 10)

    public init(id: String, workMinutes: Int, shortBreakMinutes: Int) {
        self.id = id
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "A"
        workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? 25
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
    }

    /// "25/5"
    public var label: String { "\(workMinutes)/\(shortBreakMinutes)" }
}

/// The user's own numbers for one arm. Plain counts and a mean; never a verdict.
public struct RhythmArmResult: Equatable, Sendable {
    public let arm: RhythmArm
    public let days: Int
    public let pomodoros: Int
    public let meanDisruptions: Double
    public let voided: Int
    public let isEnough: Bool
}

/// Alternates rhythms in blocks of days so the user can compare their own
/// numbers. Block arithmetic uses calendar day differences (DST-safe).
public struct RhythmExperiment: Codable, Equatable, Sendable {
    /// Days per arm before the numbers are shown without the "not enough" note.
    public static let minDaysPerArm = 6
    /// An arm with no pomodoros is never "enough", whatever the day count.
    public static let minPomodorosPerArm = 1

    public var arms: [RhythmArm]
    public var startedOn: Date
    public var daysPerBlock: Int
    /// Start-of-day dates the user broke the rhythm on; they count for nothing.
    public private(set) var contaminatedDays: [Date]

    public init(arms: [RhythmArm] = [.defaultA, .defaultB], startedOn: Date, daysPerBlock: Int = 3,
                contaminatedDays: [Date] = []) {
        self.arms = arms.isEmpty ? [.defaultA, .defaultB] : arms
        self.startedOn = startedOn
        self.daysPerBlock = max(1, daysPerBlock)
        self.contaminatedDays = contaminatedDays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([RhythmArm].self, forKey: .arms) ?? []
        arms = decoded.isEmpty ? [.defaultA, .defaultB] : decoded
        startedOn = try c.decode(Date.self, forKey: .startedOn)
        daysPerBlock = max(1, try c.decodeIfPresent(Int.self, forKey: .daysPerBlock) ?? 3)
        contaminatedDays = try c.decodeIfPresent([Date].self, forKey: .contaminatedDays) ?? []
    }

    /// Whole calendar days from the start day to `day`; a day before the start counts as day 0.
    func dayIndex(of day: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: startedOn)
        let to = calendar.startOfDay(for: day)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    private func armIndex(forDayIndex i: Int) -> Int { (i / daysPerBlock) % arms.count }

    /// The arm for `day`. A day before `startedOn` gets the first arm.
    public func arm(for day: Date, calendar: Calendar) -> RhythmArm {
        arms[armIndex(forDayIndex: dayIndex(of: day, calendar: calendar))]
    }

    /// 1-based block number of `day` (for "block 2 of …").
    public func blockNumber(for day: Date, calendar: Calendar) -> Int {
        dayIndex(of: day, calendar: calendar) / daysPerBlock + 1
    }

    public func isContaminated(_ day: Date, calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        return contaminatedDays.contains { calendar.startOfDay(for: $0) == d }
    }

    public func markingContaminated(_ day: Date, calendar: Calendar) -> RhythmExperiment {
        guard !isContaminated(day, calendar: calendar) else { return self }
        var copy = self
        copy.contaminatedDays.append(calendar.startOfDay(for: day))
        return copy
    }

    /// Per-arm numbers. A record counts for an arm when its length equals the
    /// arm's work minutes and its END day (record `date`) is an uncontaminated
    /// day assigned to that arm. `days` = DAYS WITH DATA: distinct such days
    /// with at least one counted record (idle days, days the app was off or
    /// Pomodoro was off do not count). `voided` = abandoned pomodoros on days
    /// assigned to the arm. Known limit: the first pomodoro after an arm switch
    /// may have been started under the old length and so counts for neither arm.
    public func results(records: [PomodoroRecord], voided: [Date] = [],
                        calendar: Calendar) -> [RhythmArmResult] {
        let startDay = calendar.startOfDay(for: startedOn)
        return arms.indices.map { idx in
            let arm = arms[idx]
            func counts(_ d: Date) -> Bool {
                calendar.startOfDay(for: d) >= startDay && !isContaminated(d, calendar: calendar)
                    && armIndex(forDayIndex: dayIndex(of: d, calendar: calendar)) == idx
            }
            let own = records.filter { $0.minutes == arm.workMinutes && counts($0.date) }
            let dayCount = Set(own.map { calendar.startOfDay(for: $0.date) }).count
            let mean = own.isEmpty ? 0 : own.reduce(0) { $0 + $1.disruptions } / Double(own.count)
            return RhythmArmResult(arm: arm, days: dayCount, pomodoros: own.count, meanDisruptions: mean,
                                   voided: voided.filter(counts).count,
                                   isEnough: dayCount >= Self.minDaysPerArm && own.count >= Self.minPomodorosPerArm)
        }
    }
}

extension RhythmExperiment {
    /// An experiment needs two different rhythms: arms with the same work AND
    /// short-break minutes would compare a rhythm with itself.
    public static func canStart(arms: [RhythmArm]) -> Bool {
        let rhythms = arms.map { [$0.workMinutes, $0.shortBreakMinutes] }
        return arms.count >= 2 && Set(rhythms).count == rhythms.count
    }
}
