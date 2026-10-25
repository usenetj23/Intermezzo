import Foundation

public enum BreakKind: String, Codable, CaseIterable, Equatable {
    case short
    case long
}

public enum PauseReason: String, Codable, Hashable {
    case manual
    case userAway
    case outsideWorkingHours
    case inMeeting
    case watchingVideo
    case inFocusMode
    /// Outside the configured "work zone" (calendar/VPN/Wi-Fi/GPS whitelist).
    case outsideWorkZone
    /// A user-defined Rule asked to hold breaks.
    case ruleMatch
    /// Today is a vacation/holiday (calendar event "urlop/vacation/…" or the
    /// explicit "Vacation mode" switch) — no breaks until it passes.
    case holiday
    case vacation
}

/// Where the break scheduler currently is.
public enum EngineState: Equatable {
    case paused(reasons: Set<PauseReason>)
    case working(until: Date)
    case onBreak(kind: BreakKind, until: Date)
}

/// Everything that can happen as a result of a tick / user action.
public enum EngineEvent: Equatable {
    case breakStarted(BreakKind)
    case breakCompleted
    case breakSkipped(BreakKind)
    /// "+1 / +5" pressed while the break popup is up: the popup closes NOW
    /// and the next popup is scheduled `minutes` from now (skip-and-retry).
    case breakPostponed(BreakKind)
    case resumed
}

public struct BreakConfig: Equatable {
    /// Minutes of work between breaks.
    public var cycleMinutes: Int = 45
    /// Duration of a short break, in seconds.
    public var shortBreakSeconds: Int = 300
    /// Duration of a long break, in seconds.
    public var longBreakSeconds: Int = 900
    /// A long break happens after this many short breaks.
    public var longBreakEvery: Int = 4
    /// Working hours in MINUTES from midnight (end exclusive). Outside these hours the engine pauses.
    public var workingHoursStart: Int = 8 * 60
    public var workingHoursEnd: Int = 18 * 60
    public var enforceWorkingHours: Bool = false

    public init() {}

    public func breakDuration(for kind: BreakKind) -> TimeInterval {
        switch kind {
        case .short: return TimeInterval(shortBreakSeconds)
        case .long:  return TimeInterval(longBreakSeconds)
        }
    }
}

/// Pure, clock-injected state machine. All time comes from `now` arguments so
/// it is fully unit-testable.
public struct BreakEngine {
    public private(set) var state: EngineState = .paused(reasons: [.manual])
    public private(set) var completedShortBreaks: Int = 0
    /// Remaining time frozen at the moment of pausing (working phase only).
    private var frozenRemaining: TimeInterval?
    /// Pause reasons raised while a break was live. A break is never
    /// interrupted, but the reasons are applied the moment it ends.
    private var pendingReasons: Set<PauseReason> = []

    public init() {}

    // MARK: - Lifecycle

    public mutating func start(now: Date, config: BreakConfig) {
        guard case .paused = state else { return }
        state = .working(until: now.addingTimeInterval(TimeInterval(config.cycleMinutes * 60)))
    }

    public mutating func tick(now: Date, config: BreakConfig) -> [EngineEvent] {
        var events: [EngineEvent] = []
        switch state {
        case .paused:
            break
        case .working(let until):
            if now >= until {
                let kind = previewNextKind(config: config)
                state = .onBreak(kind: kind, until: now.addingTimeInterval(config.breakDuration(for: kind)))
                events.append(.breakStarted(kind))
            }
        case .onBreak(let kind, let until):
            if now >= until {
                if kind == .short { completedShortBreaks += 1 } else { completedShortBreaks = 0 }
                leaveBreak(remaining: TimeInterval(config.cycleMinutes * 60), now: now)
                events.append(.breakCompleted)
            }
        }
        return events
    }

    // MARK: - User actions

    public mutating func skipBreak(now: Date, config: BreakConfig) -> EngineEvent? {
        guard case .onBreak(let kind, _) = state else { return nil }
        if kind == .short { completedShortBreaks += 1 } else { completedShortBreaks = 0 }
        leaveBreak(remaining: TimeInterval(config.cycleMinutes * 60), now: now)
        return .breakSkipped(kind)
    }

    public mutating func takeBreakNow(kind: BreakKind, now: Date, config: BreakConfig) -> EngineEvent? {
        if case .onBreak = state { return nil }
        // Allowed while working AND while paused (e.g. manual pause). Active
        // pause reasons are carried over and re-applied once the break ends;
        // a break always restarts the work cycle at full length.
        if case .paused(let reasons) = state { pendingReasons = reasons }
        frozenRemaining = nil
        state = .onBreak(kind: kind, until: now.addingTimeInterval(config.breakDuration(for: kind)))
        return .breakStarted(kind)
    }

    /// Push the next break back by `minutes` (snooze).
    public mutating func snooze(minutes: Int, now: Date) {
        guard case .working(let until) = state else { return }
        state = .working(until: max(until, now).addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Natural-seam hold: while the break is due (deadline within 1 s of
    /// `now`) move the deadline to `now + seconds`. Not a snooze and not a
    /// break — `completedShortBreaks` is untouched. No-op while paused, on a
    /// break, or when the deadline is further away than 1 s.
    public mutating func holdBreak(seconds: TimeInterval, now: Date) {
        guard case .working(let until) = state,
              until <= now.addingTimeInterval(1) else { return }
        state = .working(until: now.addingTimeInterval(seconds))
    }

    /// "+1 / +5" on the LIVE break popup: end the break NOW and schedule the
    /// next popup `minutes` from now — behaves like "skip this one, ask me
    /// again in N minutes". The cycle counter does NOT advance, so the same
    /// (now postponed) break is the next one shown.
    public mutating func postponeBreak(minutes: Int, now: Date) -> EngineEvent? {
        guard case .onBreak(let kind, _) = state else { return nil }
        leaveBreak(remaining: TimeInterval(minutes * 60), now: now)
        return .breakPostponed(kind)
    }

    /// Extend a LIVE break by `minutes` ("+1 / +5" on the popup:
    /// you keep resting longer, the countdown to its end is pushed out).
    public mutating func extendBreak(minutes: Int, now: Date) {
        guard case .onBreak(let kind, let until) = state else { return }
        state = .onBreak(kind: kind, until: until.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// "Timer reset": restart the next working period at FULL
    /// length (used after a long absence — no instant break bombardment on
    /// return). Works while paused AND while working (resets the countdown).
    public mutating func resetCycle(now: Date, config: BreakConfig) {
        switch state {
        case .paused:
            frozenRemaining = TimeInterval(config.cycleMinutes * 60)
        case .working:
            frozenRemaining = nil
            state = .working(until: now.addingTimeInterval(TimeInterval(config.cycleMinutes * 60)))
        case .onBreak:
            break
        }
    }

    // MARK: - Pause / resume

    public mutating func pause(reason: PauseReason, now: Date = Date()) {
        switch state {
        case .working(let until):
            frozenRemaining = max(0, until.timeIntervalSince(now))
            state = .paused(reasons: [reason])
        case .paused(let reasons):
            state = .paused(reasons: reasons.union([reason]))
        case .onBreak:
            pendingReasons.insert(reason) // never interrupt a live break; apply when it ends
        }
    }

    /// Make the set of active pause reasons among `managed` equal `desired`:
    /// missing ones are paused, stale ones resumed. Idempotent — call every tick
    /// so a policy (vacation, holiday, rule…) can never leave a pause behind.
    public mutating func syncReasons(_ desired: Set<PauseReason>,
                                     managed: Set<PauseReason>,
                                     now: Date = Date()) {
        for reason in managed.subtracting(desired) { resume(reason: reason, now: now) }
        for reason in managed.intersection(desired) { pause(reason: reason, now: now) }
    }

    @discardableResult
    public mutating func resume(reason: PauseReason, now: Date = Date()) -> EngineEvent? {
        if case .onBreak = state {
            pendingReasons.remove(reason)
            return nil
        }
        guard case .paused(let reasons) = state, reasons.contains(reason) else { return nil }
        let remaining = reasons.subtracting([reason])
        if remaining.isEmpty {
            let frozen = frozenRemaining ?? TimeInterval(0)
            frozenRemaining = nil
            state = .working(until: now.addingTimeInterval(frozen))
            return .resumed
        } else {
            state = .paused(reasons: remaining)
            return nil
        }
    }

    /// True when `reason` was raised during a live break and will apply when it ends.
    public func isPausePending(_ reason: PauseReason) -> Bool {
        pendingReasons.contains(reason)
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public var activeBreakKind: BreakKind? {
        if case .onBreak(let kind, _) = state { return kind }
        return nil
    }

    public func timeUntilBreak(now: Date) -> TimeInterval? {
        switch state {
        case .working(let until): return max(0, until.timeIntervalSince(now))
        default: return nil
        }
    }

    /// Common exit from a live break: back to working, or straight into the
    /// pauses that were requested while the break was on screen.
    private mutating func leaveBreak(remaining: TimeInterval, now: Date) {
        if pendingReasons.isEmpty {
            state = .working(until: now.addingTimeInterval(remaining))
        } else {
            frozenRemaining = remaining
            state = .paused(reasons: pendingReasons)
            pendingReasons = []
        }
    }

    // MARK: - Cycle maths

    /// Kind of the next break given the current cycle position.
    public func previewNextKind(config: BreakConfig) -> BreakKind {
        (completedShortBreaks + 1) % max(1, config.longBreakEvery) == 0 ? .long : .short
    }
}
