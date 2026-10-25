import Foundation

/// Bounds for the two break lengths, in seconds: a short break may never be set
/// longer than the long one, and the long one never shorter than the short one.
public enum BreakLengthLimits {
    public static let shortAbsolute: ClosedRange<Int> = 10...600
    public static let longAbsolute: ClosedRange<Int> = 60...3600

    public static func shortRange(longSeconds: Int) -> ClosedRange<Int> {
        shortAbsolute.lowerBound...max(shortAbsolute.lowerBound + 10, min(shortAbsolute.upperBound, longSeconds))
    }

    public static func longRange(shortSeconds: Int) -> ClosedRange<Int> {
        min(longAbsolute.upperBound - 30, max(longAbsolute.lowerBound, shortSeconds))...longAbsolute.upperBound
    }

    /// Repairs stored values that break the rule (the short one is kept, the long one is raised).
    public static func reconciled(short: Int, long: Int) -> (short: Int, long: Int) {
        let s = min(shortAbsolute.upperBound, max(shortAbsolute.lowerBound, short))
        let l = min(longAbsolute.upperBound, max(longAbsolute.lowerBound, long, s))
        return (s, l)
    }
}
