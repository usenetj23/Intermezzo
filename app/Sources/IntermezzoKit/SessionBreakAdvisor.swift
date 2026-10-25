import Foundation

/// What the break screen should offer after the session that just ended.
public enum SessionAdvice: Equatable {
    case category(ExerciseCategory)
    case outdoors
    case rotation
}

/// Rule-of-thumb matching of break content to the finished work session.
/// Every threshold below is a named heuristic chosen for variety, not a
/// measurement or a health claim; rule order matters (first match wins).
public enum SessionBreakAdvisor {
    /// Heuristic: this many logged interruptions in one session counts as a restless one.
    public static let interruptionThreshold = 3
    /// Heuristic: share of the session with input activity counted as "intense".
    public static let activeShareThreshold = 0.8
    /// Heuristic: continuous screen minutes that count as a long stretch.
    public static let screenMinutesThreshold = 50
    /// Heuristic: session length (minutes) counted as a long sit.
    public static let longSessionMinutes = 45

    // Heuristic bounds for "pleasant enough to step outside".
    static let outdoorsTemperatureRange: ClosedRange<Double> = 0...30
    static let outdoorsMaxUV = 8.0

    public static func advise(last: PomodoroRecord?, continuousScreenMinutes: Int,
                              outdoorsWeather: Bool, kind: BreakKind) -> SessionAdvice {
        guard let last else { return .rotation }
        if last.internalInterruptions + last.externalInterruptions >= interruptionThreshold {
            return .category(.breathing)
        }
        if last.actualSeconds > 0,
           Double(last.activeSeconds) / Double(last.actualSeconds) >= activeShareThreshold,
           continuousScreenMinutes >= screenMinutesThreshold {
            return .category(.eyes)
        }
        if kind == .long && outdoorsWeather { return .outdoors }
        if last.actualSeconds >= longSessionMinutes * 60 { return .category(.legs) }
        return .rotation
    }

    /// Whether the weather is suitable for suggesting a trip outside: clear sky,
    /// moderate temperature, no extreme UV. Rain, storm, snow and fog never qualify.
    public static func isOutdoorsWeather(effect: WeatherEffect, uvIndex: Double?,
                                         temperatureC: Double) -> Bool {
        effect == .clear
            && outdoorsTemperatureRange.contains(temperatureC)
            && (uvIndex ?? 0) < outdoorsMaxUV
    }
}

extension PomodoroLedger {
    /// The last record, only if it ended within `seconds` of `now` (either side).
    /// Anything older, or dated in the future beyond the window, is not "the
    /// session that just finished" and yields nil.
    public func justFinished(at now: Date, within seconds: TimeInterval = 5) -> PomodoroRecord? {
        guard let last = records.last, abs(last.date.timeIntervalSince(now)) <= seconds else { return nil }
        return last
    }
}

extension SessionBreakAdvisor {
    /// Chooses a library exercise for a category advice; nil when nothing
    /// matches (the caller then keeps the regular rotation).
    public static func pickExercise(category: ExerciseCategory, kind: BreakKind,
                                    from exercises: [LibraryExercise]) -> LibraryExercise? {
        exercises.filter { $0.category == category && (kind == .long ? $0.long : $0.short) }.randomElement()
    }
}
