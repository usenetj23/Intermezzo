import Foundation

/// Time away from the computer counted as a break that was due anyway.
public enum AwayCredit {
    /// The break an absence counts as, or nil when it was too short for the next planned one.
    /// - At least as long as the long break: a long break, even if a short one was next.
    /// - Otherwise at least as long as the next break, when that one is short.
    public static func kind(awaySeconds: TimeInterval, nextKind: BreakKind, config: BreakConfig) -> BreakKind? {
        if awaySeconds >= config.breakDuration(for: .long) { return .long }
        if nextKind == .short, awaySeconds >= config.breakDuration(for: .short) { return .short }
        return nil
    }
}

/// When no input counts as having been away. Reading, watching or thinking looks the same as leaving the desk, so
/// without a sign of leaving (the screen locked, asleep or on the screen saver) only a long stretch without input
/// counts. Anything shorter just stops the timer, and the time before it stopped is given back.
public enum AwayPolicy {
    public static func isRealAbsence(idleSeconds: TimeInterval, confirmed: Bool, unconfirmedSeconds: TimeInterval) -> Bool {
        confirmed || idleSeconds >= unconfirmedSeconds
    }
}

