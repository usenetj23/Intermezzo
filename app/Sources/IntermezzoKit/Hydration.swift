import Foundation

// MARK: - Hydration registry
//
// Tiny local log: every "Water"-style button press (or any timed action of
// kind .logDrink) records "N ml of <drink>". Kept as JSON in UserDefaults,
// pruned to the last 30 days. The app additionally pushes the amount to
// Apple Health (waterConsumption) when HealthKit is available and the user
// has authorized it — Garmin/MyFitnessPal live in the cloud and are not
// touched locally.

public struct HydrationEntry: Codable, Equatable {
    public var date: Date
    public var kind: String   // "woda" | "herbata" | "kawa" | "sok" | "inne"
    public var ml: Int

    public init(date: Date, kind: String, ml: Int) {
        self.date = date
        self.kind = kind
        self.ml = ml
    }
}

public enum HydrationStore {
    public static let storageKey = "hydrationLog"
    public static let drinkKinds = ["woda", "herbata", "kawa", "sok", "inne"]

    public static func load(_ defaults: UserDefaults = .standard) -> [HydrationEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([HydrationEntry].self, from: data)
        else { return [] }
        return entries
    }

    private static func save(_ entries: [HydrationEntry],
                             _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Record a drink; keeps only the last 30 days.
    public static func record(kind: String, ml: Int, now: Date = Date(),
                              _ defaults: UserDefaults = .standard) {
        var entries = load(defaults)
        entries.append(HydrationEntry(date: now, kind: kind, ml: max(1, ml)))
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        entries.removeAll { $0.date < cutoff }
        save(entries, defaults)
    }

    /// Total ml today + breakdown per drink kind.
    public static func todaySummary(now: Date = Date(),
                                     _ defaults: UserDefaults = .standard)
        -> (totalMl: Int, byKind: [(String, Int)]) {
        let cal = Calendar.current
        let entries = load(defaults).filter { cal.isDate($0.date, inSameDayAs: now) }
        var total = 0
        var per: [String: Int] = [:]
        for e in entries {
            total += e.ml
            per[e.kind, default: 0] += e.ml
        }
        let sorted = per.sorted { $0.value > $1.value }
        return (total, sorted)
    }
}
