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
