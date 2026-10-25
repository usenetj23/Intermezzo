import Foundation

/// Reminder-only mode: a due break never takes the screen. The first nudge is gentle;
/// while it stays ignored, every `repeatEvery` seconds the nudge gets stronger.
public struct ReminderEscalation: Equatable {
    public enum Step: Equatable {
        case gentle
        case stronger(level: Int)
    }

    private var lastStep: Date?
    public private(set) var level = 0

    public init() {}

    public mutating func reset() {
        lastStep = nil
        level = 0
    }

    /// The nudge to give now, or nil when it is not time yet.
    public mutating func advance(now: Date, repeatEvery: TimeInterval) -> Step? {
        guard let last = lastStep else {
            lastStep = now
            level = 0
            return .gentle
        }
        guard now.timeIntervalSince(last) >= repeatEvery else { return nil }
        lastStep = now
        level += 1
        return .stronger(level: level)
    }

    /// Edge-glow strength 0...1 once the reminder was ignored at least once; nil before.
    public var glowProgress: Double? {
        level == 0 ? nil : min(1, 0.4 + 0.2 * Double(level))
    }
}
