import Foundation
import IntermezzoKit

/// A break of its own length that is live right now (meal, statutory break). Main thread only;
/// `currentConfig()` applies it so the engine, ring and overlay all agree on the length.
enum CustomBreak {
    nonisolated(unsafe) static var active: (label: String, seconds: Int)?
}

/// User choices about how firmly and in what tone breaks are shown.
/// Defaults reproduce the behaviour from before these options existed.
enum BreakStyleSettings {
    static let strictnessKey = "strictness"
    static let motivationKey = "motivationStyle"
    static let softBreakKey = "softBreak"
    static let edgeGlowKey = "edgeGlowWarning"
    private static let budgetKey = "snoozeBudget"

    static var strictness: Strictness { Strictness(stored: UserDefaults.standard.string(forKey: strictnessKey)) }
    static var motivation: MotivationStyle { MotivationStyle(stored: UserDefaults.standard.string(forKey: motivationKey)) }
    /// Click-through overlay: the break never captures the mouse.
    static var softBreak: Bool { UserDefaults.standard.integer(forKey: softBreakKey) != 0 }

    /// Warning glow along the screen edges before a break.
    static var edgeGlow: Bool { UserDefaults.standard.integer(forKey: edgeGlowKey) != 0 }

    static var policy: OverlayPolicy { strictness.policy }

    /// nil = unlimited.
    static func snoozesLeft(now: Date = Date()) -> Int? {
        let budget = SnoozeBudget.decode(UserDefaults.standard.data(forKey: budgetKey))
        return budget.remaining(limit: policy.snoozeLimit, on: now, calendar: .current)
    }

    static func consumeSnooze(now: Date = Date()) {
        let budget = SnoozeBudget.decode(UserDefaults.standard.data(forKey: budgetKey))
        UserDefaults.standard.set(budget.consuming(now: now, calendar: .current).encoded(), forKey: budgetKey)
    }
}
