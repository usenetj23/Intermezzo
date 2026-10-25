import Foundation

/// "Natural seam" gate: when a break is due while the user is still typing,
/// hold it back until a short pause in input — but never longer than
/// `maxDelay` from the FIRST moment the break was due in this cycle.
///
/// Pure value type: every clock value is passed in, nothing reads `Date()`.
/// Call `reset()` once a break starts (or the cycle is paused / reset) so the
/// remembered first-due moment never carries over into the next cycle.
public struct SeamGate: Equatable, Sendable {
    /// Upper bound of the hold, measured from the first due moment.
    public var maxDelay: TimeInterval = 180
    /// Input-free seconds that count as a "seam" (a pause in typing).
    public var quietSeconds: TimeInterval = 4
    /// First moment the break was due in the current cycle (nil = not due yet).
    public private(set) var firstDue: Date?
    /// Latched once the gate lets the break through (seam found or limit
    /// reached): typing again a second later must not re-hold this break.
    public private(set) var released = false

    public init(maxDelay: TimeInterval = 180, quietSeconds: TimeInterval = 4) {
        self.maxDelay = maxDelay
        self.quietSeconds = quietSeconds
    }

    /// True when the due break should be held back a little longer.
    /// - Parameters:
    ///   - dueAt: the engine's current break deadline.
    ///   - now: current time.
    ///   - secondsSinceInput: seconds since the last keyboard/mouse event.
    public mutating func shouldHold(dueAt: Date, now: Date, secondsSinceInput: TimeInterval) -> Bool {
        // Anchor at the earlier of "due" and "now" so the window can only be
        // shorter, never longer, than `maxDelay`. A clock that jumped
        // backwards past the anchor re-anchors instead of stretching the hold.
        let anchor: Date
        if let remembered = firstDue, now >= remembered {
            anchor = remembered
        } else {
            anchor = min(dueAt, now)
            firstDue = anchor
        }
        guard !released else { return false }
        let typing = secondsSinceInput < quietSeconds
        let withinLimit = now.timeIntervalSince(anchor) < maxDelay
        if typing && withinLimit { return true }
        released = true
        return false
    }

    /// Forget the first-due moment (a break started or the cycle restarted).
    public mutating func reset() {
        firstDue = nil
        released = false
    }
}
