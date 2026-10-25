import Foundation

/// A task on today's plan, with an estimate in pomodoros (the book's
/// "planning" and "estimating" steps).
public struct PomodoroTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var estimate: Int
    public var done: Int
    public var isFinished: Bool
    /// Free-text project name ("" = none); reports group by it.
    public var project: String

    public init(id: UUID = UUID(), title: String, estimate: Int, done: Int = 0,
                isFinished: Bool = false, project: String = "") {
        self.id = id
        self.title = title
        self.estimate = estimate
        self.done = done
        self.isFinished = isFinished
        self.project = project
    }

    // Data saved before `project` existed must keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        estimate = try c.decode(Int.self, forKey: .estimate)
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
        isFinished = try c.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
    }
}

public enum PomodoroInterruption: String, Codable, Sendable {
    /// Self-inflicted: checking mail, "just one quick look".
    case `internal`
    /// Someone or something else: a colleague, a call.
    case external
}

/// The pomodoro that is running right now.
public struct PomodoroRun: Codable, Equatable, Sendable {
    public var taskID: UUID?
    public var taskTitle: String
    public var minutes: Int
    public var startedAt: Date
    public var project = ""
    public var internalInterruptions = 0
    public var externalInterruptions = 0
    /// Frontmost-app changes during the pomodoro.
    public var appSwitches = 0
    /// Seconds with keyboard/mouse activity.
    public var activeSeconds = 0

    init(taskID: UUID?, taskTitle: String, minutes: Int, startedAt: Date, project: String) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.minutes = minutes
        self.startedAt = startedAt
        self.project = project
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle) ?? ""
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 25
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        internalInterruptions = try c.decodeIfPresent(Int.self, forKey: .internalInterruptions) ?? 0
        externalInterruptions = try c.decodeIfPresent(Int.self, forKey: .externalInterruptions) ?? 0
        appSwitches = try c.decodeIfPresent(Int.self, forKey: .appSwitches) ?? 0
        activeSeconds = try c.decodeIfPresent(Int.self, forKey: .activeSeconds) ?? 0
    }
}

/// A finished pomodoro.
public struct PomodoroRecord: Codable, Equatable, Sendable {
    /// Weights of the "disruption" score used to rank hours (a heuristic, not a measurement of focus).
    public static let interruptionWeight = 3.0
    public static let switchWeight = 1.0

    public var date: Date
    public var startedAt: Date
    public var taskID: UUID?
    public var taskTitle: String
    public var project: String
    public var minutes: Int
    public var actualSeconds: Int
    public var internalInterruptions: Int
    public var externalInterruptions: Int
    public var appSwitches: Int
    public var activeSeconds: Int

    /// Interruptions weigh more than app switches; lower is calmer.
    public var disruptions: Double {
        Double(internalInterruptions + externalInterruptions) * Self.interruptionWeight
            + Double(appSwitches) * Self.switchWeight
    }

    init(date: Date, startedAt: Date, taskID: UUID?, taskTitle: String, project: String, minutes: Int,
         actualSeconds: Int, internalInterruptions: Int, externalInterruptions: Int,
         appSwitches: Int, activeSeconds: Int) {
        self.date = date
        self.startedAt = startedAt
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.project = project
        self.minutes = minutes
        self.actualSeconds = actualSeconds
        self.internalInterruptions = internalInterruptions
        self.externalInterruptions = externalInterruptions
        self.appSwitches = appSwitches
        self.activeSeconds = activeSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 25
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
            ?? date.addingTimeInterval(-Double(minutes) * 60)
        taskID = try c.decodeIfPresent(UUID.self, forKey: .taskID)
        taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        actualSeconds = try c.decodeIfPresent(Int.self, forKey: .actualSeconds) ?? minutes * 60
        internalInterruptions = try c.decodeIfPresent(Int.self, forKey: .internalInterruptions) ?? 0
        externalInterruptions = try c.decodeIfPresent(Int.self, forKey: .externalInterruptions) ?? 0
        appSwitches = try c.decodeIfPresent(Int.self, forKey: .appSwitches) ?? 0
        activeSeconds = try c.decodeIfPresent(Int.self, forKey: .activeSeconds) ?? 0
    }
}

/// Time spent on one project over a range.
public struct PomodoroProjectTotal: Equatable, Sendable {
    public let project: String
    public let seconds: Int
    public let count: Int
}

/// An hour of the day ranked by how calm the pomodoros started in it were.
public struct PomodoroHourStat: Equatable, Sendable {
    public let hour: Int
    public let samples: Int
    /// Mean disruption score (lower is calmer).
    public let disruptions: Double
}

/// Plan, running pomodoro and history. A pomodoro is indivisible: it counts
/// only when completed, an abandoned one is voided. All operations return a
/// new value.
public struct PomodoroLedger: Codable, Equatable, Sendable {
    public static let maxRecords = 500

    public internal(set) var tasks: [PomodoroTask] = []
    public internal(set) var records: [PomodoroRecord] = []
    public private(set) var voided: [Date] = []
    public internal(set) var current: PomodoroRun?
    public internal(set) var projects: [PomodoroProject] = []

    public init() {}

    // Tolerant: every field is optional in stored data (v1.19 has no `projects`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([PomodoroTask].self, forKey: .tasks) ?? []
        records = try c.decodeIfPresent([PomodoroRecord].self, forKey: .records) ?? []
        voided = try c.decodeIfPresent([Date].self, forKey: .voided) ?? []
        current = try c.decodeIfPresent(PomodoroRun.self, forKey: .current)
        projects = try c.decodeIfPresent([PomodoroProject].self, forKey: .projects) ?? []
    }

    // MARK: - Plan

    public func addingTask(title: String, estimate: Int, project: String = "") -> PomodoroLedger {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var copy = self
        let typedName = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = self.project(named: typedName)?.name ?? typedName   // keep the stored spelling
        copy.tasks.append(PomodoroTask(title: trimmed, estimate: max(1, estimate), project: projectName))
        return Self.backfillingProjects(copy)
    }

    /// Distinct project names, most used first.
    public var projectNames: [String] {
        let counts = Dictionary(grouping: tasks.map(\.project).filter { !$0.isEmpty }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    public func removingTask(_ id: UUID) -> PomodoroLedger {
        var copy = self
        copy.tasks.removeAll { $0.id == id }
        return copy
    }

    /// Sets the project of an unfinished task that has none yet (never overrides a
    /// choice) and of the running pomodoro for that task. Only ACTIVE projects
    /// are accepted, stored with their canonical spelling. Otherwise unchanged.
    public func assigningProject(_ name: String, toTask id: UUID) -> PomodoroLedger {
        guard let canonical = activeProjectName(name),
              let i = tasks.firstIndex(where: { $0.id == id && !$0.isFinished && $0.project.isEmpty })
        else { return self }
        var copy = self
        copy.tasks[i].project = canonical
        if copy.current?.taskID == id, copy.current?.project.isEmpty == true { copy.current?.project = canonical }
        return copy
    }

    public func finishingTask(_ id: UUID) -> PomodoroLedger {
        var copy = self
        if let i = copy.tasks.firstIndex(where: { $0.id == id }) { copy.tasks[i].isFinished = true }
        return copy
    }

    // MARK: - Running pomodoro

    /// Starts a pomodoro; one that was still running is voided first.
    public func starting(taskID: UUID?, minutes: Int, at date: Date) -> PomodoroLedger {
        var copy = current == nil ? self : voiding(at: date)
        let task = taskID.flatMap { id in tasks.first { $0.id == id } }
        copy.current = PomodoroRun(taskID: taskID, taskTitle: task?.title ?? "", minutes: minutes,
                                   startedAt: date, project: task?.project ?? "")
        return copy
    }

    public func recordingInterruption(_ kind: PomodoroInterruption) -> PomodoroLedger {
        guard var run = current else { return self }
        switch kind {
        case .internal: run.internalInterruptions += 1
        case .external: run.externalInterruptions += 1
        }
        var copy = self
        copy.current = run
        return copy
    }

    /// Adds focus signals gathered since the last call to the running pomodoro.
    public func recordingActivity(appSwitches: Int, activeSeconds: Int) -> PomodoroLedger {
        guard var run = current, appSwitches > 0 || activeSeconds > 0 else { return self }
        run.appSwitches += max(0, appSwitches)
        run.activeSeconds += max(0, activeSeconds)
        var copy = self
        copy.current = run
        return copy
    }

    public func completing(at date: Date) -> PomodoroLedger {
        guard let run = current else { return self }
        var copy = self
        copy.current = nil
        copy.records.append(PomodoroRecord(
            date: date, startedAt: run.startedAt, taskID: run.taskID, taskTitle: run.taskTitle,
            project: run.project, minutes: run.minutes,
            actualSeconds: max(0, Int(date.timeIntervalSince(run.startedAt))),
            internalInterruptions: run.internalInterruptions,
            externalInterruptions: run.externalInterruptions,
            appSwitches: run.appSwitches, activeSeconds: run.activeSeconds))
        if let id = run.taskID, let i = copy.tasks.firstIndex(where: { $0.id == id }) {
            copy.tasks[i].done += 1
        }
        if copy.records.count > Self.maxRecords { copy.records.removeFirst(copy.records.count - Self.maxRecords) }
        return copy
    }

    public func voiding(at date: Date) -> PomodoroLedger {
        guard current != nil else { return self }
        var copy = self
        copy.current = nil
        copy.voided.append(date)
        if copy.voided.count > Self.maxRecords { copy.voided.removeFirst(copy.voided.count - Self.maxRecords) }
        return copy
    }

    // MARK: - Statistics

    public func completedCount(on day: Date, calendar: Calendar) -> Int {
        records.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
    }

    public func voidedCount(on day: Date, calendar: Calendar) -> Int {
        voided.filter { calendar.isDate($0, inSameDayAs: day) }.count
    }

    public func interruptions(on day: Date, calendar: Calendar) -> (internal: Int, external: Int) {
        let today = records.filter { calendar.isDate($0.date, inSameDayAs: day) }
        return (today.reduce(0) { $0 + $1.internalInterruptions },
                today.reduce(0) { $0 + $1.externalInterruptions })
    }

    /// Consecutive days with at least one pomodoro. A day without one yet
    /// (today) does not break a streak that ran up to yesterday.
    public func streakDays(endingOn day: Date, calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: day)
        if completedCount(on: cursor, calendar: calendar) == 0,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var streak = 0
        while completedCount(on: cursor, calendar: calendar) > 0 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Pomodoros per day for the 7 days ending on `day`, oldest first.
    public func weekCounts(endingOn day: Date, calendar: Calendar) -> [Int] {
        (0..<7).reversed().map { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: day) else { return 0 }
            return completedCount(on: d, calendar: calendar)
        }
    }

    /// Done ÷ estimated over finished tasks (> 1 means under-estimated); nil without data.
    public func estimateRatio() -> Double? {
        let finished = tasks.filter { $0.isFinished && $0.estimate > 0 }
        let estimated = finished.reduce(0) { $0 + $1.estimate }
        guard estimated > 0 else { return nil }
        return Double(finished.reduce(0) { $0 + $1.done }) / Double(estimated)
    }

    // MARK: - Reports and insights

    /// Time per project for pomodoros ending in [from, to), longest first.
    public func projectTotals(from: Date, to: Date) -> [PomodoroProjectTotal] {
        let inRange = records.filter { $0.date >= from && $0.date < to }
        return Dictionary(grouping: inRange, by: \.project)
            .map { PomodoroProjectTotal(project: $0.key, seconds: $0.value.reduce(0) { $0 + $1.actualSeconds },
                                        count: $0.value.count) }
            .sorted {
                if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
                if $0.project.isEmpty != $1.project.isEmpty { return !$0.project.isEmpty }   // "no project" last on ties
                return $0.project < $1.project
            }
    }

    /// Hours of the day (by pomodoro start) ordered from calmest to noisiest.
    /// Hours with fewer than `minSamples` pomodoros are left out: too little to say anything.
    public func goldenHours(calendar: Calendar, minSamples: Int = 3) -> [PomodoroHourStat] {
        Dictionary(grouping: records, by: { calendar.component(.hour, from: $0.startedAt) })
            .filter { $0.value.count >= minSamples }
            .map { hour, group in
                PomodoroHourStat(hour: hour, samples: group.count,
                                 disruptions: group.reduce(0) { $0 + $1.disruptions } / Double(group.count))
            }
            .sorted { $0.disruptions != $1.disruptions ? $0.disruptions < $1.disruptions : $0.hour < $1.hour }
    }

    // MARK: - Persistence

    public static func encode(_ ledger: PomodoroLedger) -> Data? {
        try? JSONEncoder().encode(ledger)
    }

    /// Never throws: missing or damaged data gives an empty ledger.
    public static func decode(_ data: Data?) -> PomodoroLedger {
        guard let data, let ledger = try? JSONDecoder().decode(PomodoroLedger.self, from: data) else {
            return PomodoroLedger()
        }
        return backfillingProjects(ledger)
    }
}

extension PomodoroLedger {
    /// UserDefaults key holding the raw bytes of a stored ledger that could not be decoded.
    public static let corruptKey = "pomodoroLedger.corrupt"

    public enum LoadOutcome: Equatable, Sendable {
        case loaded
        /// Nothing stored yet.
        case empty
        /// Undecodable bytes were parked under `corruptKey`.
        case parkedCorrupt
        /// Undecodable bytes, but `corruptKey` already holds an earlier blob (kept, single slot).
        case corruptSlotTaken
    }

    /// Like `decode`, but an undecodable non-empty blob is kept under `corruptKey`
    /// before the caller starts from an empty ledger (whose next save overwrites it).
    public static func load(_ data: Data?, parkingCorruptIn defaults: UserDefaults)
        -> (ledger: PomodoroLedger, outcome: LoadOutcome) {
        guard let data, !data.isEmpty else { return (PomodoroLedger(), .empty) }
        if let ledger = try? JSONDecoder().decode(PomodoroLedger.self, from: data) {
            return (backfillingProjects(ledger), .loaded)
        }
        guard defaults.object(forKey: corruptKey) == nil else { return (PomodoroLedger(), .corruptSlotTaken) }
        defaults.set(data, forKey: corruptKey)
        return (PomodoroLedger(), .parkedCorrupt)
    }
}

// MARK: - Sync

extension PomodoroLedger {
    /// Another Mac's ledger folded into this one: finished pomodoros and voided ones add up (one per
    /// start time), the plan (tasks, projects) comes from whichever ledger changed last, and a
    /// pomodoro running here keeps running.
    public func merged(with other: PomodoroLedger, otherIsNewer: Bool) -> PomodoroLedger {
        var next = self
        var byStart: [Date: PomodoroRecord] = [:]
        for r in records + other.records where byStart[r.startedAt] == nil { byStart[r.startedAt] = r }
        next.records = Array(byStart.values.sorted { $0.startedAt < $1.startedAt }.suffix(Self.maxRecords))
        next.voided = Array(Set(voided + other.voided)).sorted()
        if otherIsNewer {
            next.tasks = other.tasks
            next.projects = other.projects
        }
        return next
    }
}
