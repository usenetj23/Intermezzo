import Foundation

/// Optional working hours that differ by weekday (index 0 = Monday … 6 = Sunday);
/// days without an entry use the general window.
public struct WeekHours: Codable, Equatable {
    public struct Window: Codable, Equatable {
        public var start: Int
        public var end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }

        /// Minutes from midnight, end exclusive.
        public func contains(minute: Int) -> Bool { minute >= start && minute < end }
    }

    private var overrides: [Int: Window] = [:]

    public init() {}

    public func window(forDay day: Int, default fallback: Window) -> Window { overrides[day] ?? fallback }

    public func setting(_ window: Window, forDay day: Int) -> WeekHours {
        var next = self
        next.overrides[day] = window
        return next
    }

    public func clearing(day: Int) -> WeekHours {
        var next = self
        next.overrides[day] = nil
        return next
    }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

    public static func decode(_ data: Data?) -> WeekHours {
        data.flatMap { try? JSONDecoder().decode(WeekHours.self, from: $0) } ?? WeekHours()
    }
}
