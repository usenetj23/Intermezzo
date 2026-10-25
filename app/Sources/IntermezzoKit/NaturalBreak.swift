import Foundation

/// Time away from the computer that is recorded as a break of its own kind
/// (lunch, coffee, a walk), separate from the breaks the app asked for.
public enum NaturalBreak {
    /// Stored in `BreakRecord.kindRaw`. Old versions read an unknown value as a short break.
    public static let rawKind = "natural"

    static let smallestMinimumMinutes = 5
    /// Longer than this is the end of the day, not a break.
    static let longestSeconds: TimeInterval = 6 * 3600

    public static func shouldLog(awaySeconds: TimeInterval, minMinutes: Int) -> Bool {
        let minimum = TimeInterval(max(smallestMinimumMinutes, minMinutes) * 60)
        return awaySeconds >= minimum && awaySeconds <= longestSeconds
    }

    public enum Category: Equatable {
        case pause, meal, long

        public var title: String {
            switch self {
            case .pause: return kitL("Przerwa")
            case .meal: return kitL("Posiłek lub dłuższa przerwa")
            case .long: return kitL("Długa nieobecność")
            }
        }
    }

    public static func category(minutes: Int) -> Category {
        switch minutes {
        case ..<25: return .pause
        case 25..<90: return .meal
        default: return .long
        }
    }
}
