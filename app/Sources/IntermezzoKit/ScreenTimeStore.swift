import Foundation

/// Active screen time per calendar day, with a once-per-day limit alert.
/// (A daily average above ~4 h is named a risk factor for digital eye strain
/// in the Kaur 2022 review; this measures only time this Mac was in use.)
public final class ScreenTimeStore {
    public static let dailyLimit = 4 * 3600

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let dayKey = "screenTimeDay"
    private let secondsKey = "screenTimeSeconds"
    private let alertedKey = "screenTimeAlerted"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    private func stamp(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func rollIfNewDay(_ now: Date) {
        let today = stamp(now)
        if defaults.string(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: secondsKey)
            defaults.set(false, forKey: alertedKey)
        }
    }

    public func seconds(now: Date) -> Int {
        rollIfNewDay(now)
        return defaults.integer(forKey: secondsKey)
    }

    /// Adds active seconds; returns true exactly once per day, when the limit is crossed.
    @discardableResult
    public func add(seconds: Int, now: Date) -> Bool {
        rollIfNewDay(now)
        let total = defaults.integer(forKey: secondsKey) + seconds
        defaults.set(total, forKey: secondsKey)
        if total >= Self.dailyLimit, !defaults.bool(forKey: alertedKey) {
            defaults.set(true, forKey: alertedKey)
            return true
        }
        return false
    }

    public static func format(seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }
}
