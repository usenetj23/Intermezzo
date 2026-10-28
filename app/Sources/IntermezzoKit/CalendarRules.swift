import Foundation

/// One rule for which calendar events count as work: which calendar, which titles, which kinds of event.
public struct CalendarRule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var enabled = true
    /// nil = every calendar.
    public var calendarID: String?
    /// Shown while the calendar cannot be found (renamed, removed, another account).
    public var calendarName = ""
    /// Comma-separated fragments of the title, any one is enough; empty = any title.
    public var keywords = ""
    /// Only events that show you as busy (not "free").
    public var onlyBusy = true
    public var skipAllDay = true
    /// Skip events whose invitation you declined.
    public var skipDeclined = true

    public init(enabled: Bool = true, calendarID: String? = nil, calendarName: String = "", keywords: String = "",
                onlyBusy: Bool = true, skipAllDay: Bool = true, skipDeclined: Bool = true) {
        self.enabled = enabled
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.keywords = keywords
        self.onlyBusy = onlyBusy
        self.skipAllDay = skipAllDay
        self.skipDeclined = skipDeclined
    }
}

/// What a rule needs to know about one event (the app fills it from EventKit).
public struct CalendarEventInfo: Equatable, Sendable {
    public var calendarID: String
    public var title: String
    public var isAllDay: Bool
    /// Availability is anything but "free".
    public var isBusy: Bool
    public var isDeclined: Bool

    public init(calendarID: String, title: String, isAllDay: Bool, isBusy: Bool, isDeclined: Bool) {
        self.calendarID = calendarID
        self.title = title
        self.isAllDay = isAllDay
        self.isBusy = isBusy
        self.isDeclined = isDeclined
    }
}

public enum CalendarRules {
    /// "a, B ,c" -> ["a", "b", "c"]
    public static func keywords(from text: String) -> [String] {
        text.lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func matches(_ rule: CalendarRule, _ event: CalendarEventInfo) -> Bool {
        guard rule.enabled else { return false }
        if let id = rule.calendarID, id != event.calendarID { return false }
        if rule.onlyBusy, !event.isBusy { return false }
        if rule.skipAllDay, event.isAllDay { return false }
        if rule.skipDeclined, event.isDeclined { return false }
        let words = keywords(from: rule.keywords)
        if words.isEmpty { return true }
        let title = event.title.lowercased()
        return words.contains { title.contains($0) }
    }

    public static func firstMatch(_ rules: [CalendarRule], _ event: CalendarEventInfo) -> CalendarRule? {
        rules.first { matches($0, event) }
    }

    /// The rule that reproduces the old single keyword list: every calendar, any kind of event.
    public static func legacy(keywords: String) -> CalendarRule {
        CalendarRule(keywords: keywords, onlyBusy: false, skipAllDay: false, skipDeclined: false)
    }

    public static func decode(_ data: Data?) -> [CalendarRule] {
        data.flatMap { try? JSONDecoder().decode([CalendarRule].self, from: $0) } ?? []
    }

    public static func encode(_ rules: [CalendarRule]) -> Data {
        (try? JSONEncoder().encode(rules)) ?? Data()
    }
}
