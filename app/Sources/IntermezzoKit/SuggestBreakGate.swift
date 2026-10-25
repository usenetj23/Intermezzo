import Foundation

/// Decides when a "suggest a break now" rule may actually speak up: the condition (e.g. a long
/// build is running) must hold continuously for `sustainSeconds`, enough work must have passed
/// since the last break, and offers are spaced by `cooldownSeconds`.
public struct SuggestBreakGate {
    public let sustainSeconds: TimeInterval
    public let cooldownSeconds: TimeInterval
    public let minWorkedSeconds: TimeInterval
    private var trueSince: Date?
    private var lastOffer: Date?

    public init(sustainSeconds: TimeInterval = 60,
                cooldownSeconds: TimeInterval = 1800,
                minWorkedSeconds: TimeInterval = 600) {
        self.sustainSeconds = sustainSeconds
        self.cooldownSeconds = cooldownSeconds
        self.minWorkedSeconds = minWorkedSeconds
    }

    /// Call once per evaluation; returns true exactly when an offer should be shown now.
    public mutating func shouldOffer(conditionMet: Bool, workedSeconds: TimeInterval, now: Date) -> Bool {
        guard conditionMet else { trueSince = nil; return false }
        let since = trueSince ?? now
        trueSince = since
        guard now.timeIntervalSince(since) >= sustainSeconds else { return false }
        guard workedSeconds >= minWorkedSeconds else { return false }
        if let last = lastOffer, now.timeIntervalSince(last) < cooldownSeconds { return false }
        lastOffer = now
        return true
    }
}
