import Foundation

/// "Once per approaching break" latch, keyed per action / check.
///
/// `enter` returns true the first time the time-to-break falls inside `window`
/// and false on every later call for the same approach. The key re-arms only
/// when the deadline moves out again (a new cycle, a snooze, a postpone) beyond
/// `max(window, minimumRearmSeconds)`, or on `reset()` (a break started).
/// A natural-seam hold keeps time-to-break at about 1-2 s for minutes, so a
/// wall-clock suppression would run out; this one is state-based and cannot.
public struct ApproachLatch<Key: Hashable>: Equatable {
    /// Hysteresis for small windows: the seam's own 2 s holds never re-arm.
    public static var minimumRearmSeconds: TimeInterval { 3 }

    private var latched: Set<Key> = []

    public init() {}

    /// - Parameters:
    ///   - timeLeft: seconds until the break is due (nil: none scheduled, nothing changes).
    ///   - window: fire when `timeLeft <= window` (0 or less: never).
    public mutating func enter(_ key: Key, timeLeft: TimeInterval?, window: TimeInterval) -> Bool {
        guard let timeLeft, window > 0, timeLeft >= 0 else { return false }
        if timeLeft > max(window, Self.minimumRearmSeconds) {
            latched.remove(key)
            return false
        }
        guard timeLeft <= window else { return false }
        return latched.insert(key).inserted
    }

    /// A break started: every key fires again on the next approach.
    public mutating func reset() { latched.removeAll() }
}
