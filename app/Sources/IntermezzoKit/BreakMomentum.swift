import Foundation

/// Running "momentum" of recent breaks for the overlay chart. Absolute scale
/// (0 = red, 1 = green): a finished break lifts the line, a skipped one drops
/// it harder, and a longer break counts for more. A run of skipped breaks ends
/// in the red zone no matter what came before it.
public enum BreakMomentum {
    public struct Outcome: Equatable {
        public var skipped: Bool
        /// 1 = a regular short break; a long break weighs more.
        public var weight: Double
        /// How much of the full drop a skipped break causes: 1 for a skip, less for a postponement (+1 / +5).
        public var lossShare: Double
        public init(skipped: Bool, weight: Double = 1, lossShare: Double = 1) {
            self.skipped = skipped
            self.weight = weight
            self.lossShare = lossShare
        }
    }

    static let start = 0.6
    static let gain = 0.12
    static let loss = 0.2

    /// A postponement lowers the line only a little: more for +5 than for +1, never as much as a skip.
    public static func postponeShare(minutes: Int) -> Double {
        min(0.5, 0.15 + 0.05 * Double(max(0, minutes)))
    }

    /// Weight of a break relative to the short one, so a 15-minute break
    /// counts for more than a 5-minute one but never absurdly more.
    public static func weight(seconds: Int, shortSeconds: Int) -> Double {
        guard shortSeconds > 0 else { return 1 }
        return min(3, max(1, Double(seconds) / Double(shortSeconds)))
    }

    /// One level in 0...1 per break, oldest first. Needs at least two breaks.
    public static func levels(_ outcomes: [Outcome]) -> [Double] {
        guard outcomes.count >= 2 else { return [] }
        var level = start
        return outcomes.map { o in
            level += (o.skipped ? -loss * o.lossShare : gain) * o.weight
            level = min(1, max(0, level))
            return level
        }
    }
}
