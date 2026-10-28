import Foundation

/// A small repeating nudge (water, blinking, posture) on its own interval.
public struct MicroReminder: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var intervalMinutes: Int
    public var symbol: String = "bell.fill"
    public var enabled: Bool = true

    public init(title: String, intervalMinutes: Int, symbol: String = "bell.fill", enabled: Bool = true) {
        self.title = title
        self.intervalMinutes = intervalMinutes
        self.symbol = symbol
        self.enabled = enabled
    }

    /// Suggestions offered in Settings; the user turns them on.
    public static let presets: [MicroReminder] = [
        MicroReminder(title: kitL("Drink some water"), intervalMinutes: 60, symbol: "drop.fill", enabled: false),
        MicroReminder(title: kitL("Blink a few times"), intervalMinutes: 20, symbol: "eye", enabled: false),
        MicroReminder(title: kitL("Check your posture"), intervalMinutes: 30, symbol: "figure.stand", enabled: false),
    ]

    public static func encodeList(_ list: [MicroReminder]) -> Data { (try? JSONEncoder().encode(list)) ?? Data() }
    public static func decodeList(_ data: Data?) -> [MicroReminder] {
        data.flatMap { try? JSONDecoder().decode([MicroReminder].self, from: $0) } ?? []
    }
}

/// A break at a fixed time of day on chosen weekdays (Calendar weekday numbers, 1 = Sunday).
public struct ScheduledBreak: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var label: String
    public var minuteOfDay: Int
    public var weekdays: Set<Int>
    public var isLong: Bool
    public var enabled: Bool = true
    /// A break of its own length (meal, statutory break); nil = the regular short or long break.
    public var customMinutes: Int?
    /// Offer the break in a notification instead of starting it by itself.
    public var askFirst: Bool = false

    public init(label: String, minuteOfDay: Int, weekdays: Set<Int>, isLong: Bool, enabled: Bool = true,
                customMinutes: Int? = nil, askFirst: Bool = false) {
        self.label = label
        self.minuteOfDay = minuteOfDay
        self.weekdays = weekdays
        self.isLong = isLong
        self.enabled = enabled
        self.customMinutes = customMinutes
        self.askFirst = askFirst
    }

    // Lists saved before custom lengths existed lack the new keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        minuteOfDay = try c.decode(Int.self, forKey: .minuteOfDay)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        isLong = try c.decode(Bool.self, forKey: .isLong)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        customMinutes = try c.decodeIfPresent(Int.self, forKey: .customMinutes)
        askFirst = try c.decodeIfPresent(Bool.self, forKey: .askFirst) ?? false
    }

    private static let workdays: Set<Int> = [2, 3, 4, 5, 6]

    /// Meal suggestions offered in Settings.
    public static let mealPresets: [ScheduledBreak] = [
        ScheduledBreak(label: kitL("Śniadanie"), minuteOfDay: 9 * 60, weekdays: workdays, isLong: false, customMinutes: 15),
        ScheduledBreak(label: kitL("Obiad"), minuteOfDay: 12 * 60 + 30, weekdays: workdays, isLong: false, customMinutes: 30),
        ScheduledBreak(label: kitL("Kolacja"), minuteOfDay: 18 * 60, weekdays: workdays, isLong: false, customMinutes: 30),
    ]

    public static func encodeList(_ list: [ScheduledBreak]) -> Data { (try? JSONEncoder().encode(list)) ?? Data() }
    public static func decodeList(_ data: Data?) -> [ScheduledBreak] {
        data.flatMap { try? JSONDecoder().decode([ScheduledBreak].self, from: $0) } ?? []
    }
}

public enum ReminderSchedule {
    /// A scheduled break still fires this long after its minute (the app may have been busy or asleep).
    static let catchUpSeconds: TimeInterval = 2 * 60

    /// Reminders whose interval has passed since they were last shown (or since `since`).
    public static func dueMicro(_ reminders: [MicroReminder], lastShown: [UUID: Date],
                                since: Date, now: Date) -> [MicroReminder] {
        reminders.filter { r in
            guard r.enabled, r.intervalMinutes > 0 else { return false }
            let last = lastShown[r.id] ?? since
            return now.timeIntervalSince(last) >= TimeInterval(r.intervalMinutes * 60)
        }
    }

    /// A meal break (own length) owns the window `minuteOfDay ..< minuteOfDay + customMinutes`.
    /// It starts when the regular timer runs out inside that window; if none does, at the window's end.
    static func window(of b: ScheduledBreak, startOfDay: Date) -> (start: Date, end: Date)? {
        guard let minutes = b.customMinutes else { return nil }
        let start = startOfDay.addingTimeInterval(TimeInterval(b.minuteOfDay * 60))
        return (start, start.addingTimeInterval(TimeInterval(max(1, minutes) * 60)))
    }

    /// The meal break whose window contains `now` and has not started today yet.
    public static func mealInWindow(_ items: [ScheduledBreak], lastFired: [UUID: Date],
                                    now: Date, calendar: Calendar) -> ScheduledBreak? {
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        return items.first { b in
            guard b.enabled, b.weekdays.contains(weekday),
                  let w = window(of: b, startOfDay: startOfDay), now >= w.start, now < w.end else { return false }
            if let fired = lastFired[b.id], calendar.isDate(fired, inSameDayAs: now) { return false }
            return true
        }
    }

    public static func dueScheduled(_ items: [ScheduledBreak], lastFired: [UUID: Date],
                                    now: Date, calendar: Calendar) -> [ScheduledBreak] {
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)
        return items.filter { b in
            guard b.enabled, b.weekdays.contains(weekday) else { return false }
            // Meal breaks wait for the regular timer; this is their fallback at the window's end.
            let target = window(of: b, startOfDay: startOfDay)?.end
                ?? startOfDay.addingTimeInterval(TimeInterval(b.minuteOfDay * 60))
            let late = now.timeIntervalSince(target)
            guard late >= 0, late < catchUpSeconds else { return false }
            if let fired = lastFired[b.id], calendar.isDate(fired, inSameDayAs: now) { return false }
            return true
        }
    }
}
