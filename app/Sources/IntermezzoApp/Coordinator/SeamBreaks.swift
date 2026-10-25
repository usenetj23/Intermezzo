import Foundation
import IntermezzoKit

/// UserDefaults keys of the "natural seam" feature.
enum SeamKeys {
    /// Int flag, default 0 (off).
    static let enabled = "seamBreaks"
    /// Int seconds, default 180, UI range 60...300.
    static let maxDelaySeconds = "seamMaxDelaySeconds"
    static let defaultMaxDelay = 180
    static let maxDelayRange = 60...300
}

/// "Natural seam": a break that becomes due while the user is typing waits for
/// a short pause in input, never longer than `seamMaxDelaySeconds`.
extension BreakCoordinator {
    /// Each hold pushes the deadline this far past `now`.
    static let seamHoldSeconds: TimeInterval = 2
    /// Act only when the break is due within this many seconds.
    static let seamDueWindow: TimeInterval = 1.5
    /// A deadline further away than this means a new cycle (reset, snooze,
    /// calendar hold, clock jump): forget the remembered first-due moment.
    /// Larger than `seamHoldSeconds`, so our own holds never trigger it.
    static let seamRearmWindow: TimeInterval = 3

    /// Called once per heartbeat right before `engine.tick`, after the rule
    /// and calendar-aware blocks — so a snooze they made wins and the gate
    /// only acts on a break that is still due after them.
    func applySeamGate(now: Date) {
        let d = UserDefaults.standard
        let enabled = d.integer(forKey: SeamKeys.enabled) != 0
            && d.integer(forKey: Keys.strictMode) == 0
        guard enabled, !isOnBreak, !engine.isPaused,
              let left = engine.timeUntilBreak(now: now) else {
            seamGate.reset()
            return
        }
        if left > Self.seamRearmWindow {
            seamGate.reset()
            return
        }
        guard left <= Self.seamDueWindow else { return }

        let configured = d.integer(forKey: SeamKeys.maxDelaySeconds)
        let range = SeamKeys.maxDelayRange
        seamGate.maxDelay = TimeInterval(min(range.upperBound, max(range.lowerBound, configured)))
        let wasHolding = seamGate.firstDue != nil && !seamGate.released
        let hold = seamGate.shouldHold(dueAt: now.addingTimeInterval(left),
                                       now: now,
                                       secondsSinceInput: secondsSinceLastUserInput())
        if hold {
            engine.holdBreak(seconds: Self.seamHoldSeconds, now: now)
            if !wasHolding { Trace.log("seam: holding break, typing") }
        } else if wasHolding {
            let held = seamGate.firstDue.map { Int(now.timeIntervalSince($0)) } ?? 0
            Trace.log("seam: released after \(held) s")
        }
    }
}
