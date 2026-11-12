import Foundation

// The brightness "equaliser" of the Light feature: a drawn day (how bright the screen is at each hour)
// and a drawn room (how much brighter or darker it gets for the light measured in the room).
//
//   level = clamp(day% / 100 × room% / 100, minimumLevel, 1)
//
// `day%` comes from the hourly bands (smoothly blended between hour centres), `room%` from the lux bands
// (blended on a log-lux axis, held flat beyond the first and last band). Without a sensor reading
// (no sensor, lid closed, room light off) `room%` is 100 and the day alone decides. The result is an
// absolute display brightness (0...1, as macOS and BetterDisplay count it), never below `minimumLevel`,
// so the screen can never go black.

/// Screen brightness for each of the 24 hours, in percent.
public struct BrightnessDayCurve: Equatable, Sendable {
    public static let bands = 24
    public static let step = 5.0
    public static let minPercent = 5.0
    public static let maxPercent = 100.0
    private static let range = minPercent...maxPercent

    /// A starting point: full brightness by day, gently lower in the evening and at night.
    public static let standard = BrightnessDayCurve(hourly: [
        40, 40, 40, 40, 40, 40, 60, 80,                       // 0-7
        100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, // 8-18
        90, 80, 65, 50, 40,                                    // 19-23
    ])

    public private(set) var hourly: [Double]

    public init(hourly: [Double]) {
        self.hourly = EqualizerBands.normalized(hourly, count: Self.bands, pad: Self.maxPercent, range: Self.range, step: Self.step)
    }

    static func snap(_ percent: Double) -> Double { EqualizerBands.snap(percent, range: range, step: step) }

    /// Percent at a moment of the day, `minute` in 0..<1440 (values outside wrap around).
    public func percent(atMinuteOfDay minute: Double) -> Double {
        EqualizerBands.dayValue(hourly, atMinuteOfDay: minute)
    }

    public mutating func set(hour: Int, percent: Double) {
        guard hourly.indices.contains(hour) else { return }
        hourly[hour] = Self.snap(percent)
    }

    public mutating func paint(fromBand a: Double, percent pa: Double, toBand b: Double, percent pb: Double) {
        hourly = EqualizerBands.painted(hourly, fromBand: a, value: pa, toBand: b, value: pb, snap: Self.snap)
    }

    public var encoded: String { EqualizerBands.encode(hourly) }

    public static func decode(_ text: String?) -> BrightnessDayCurve? {
        EqualizerBands.decode(text, count: bands).map { BrightnessDayCurve(hourly: $0) }
    }
}

/// How the room's light (lux) scales the hour's brightness: one band per illuminance, in percent.
public struct LuxBrightnessCurve: Equatable, Sendable {
    /// Dark room, dim lamp, lit room, bright office, by a window, daylight: half a decade apart.
    public static let luxPoints: [Double] = [10, 30, 100, 300, 1000, 3000]
    public static let step = 5.0
    public static let minPercent = 20.0
    /// Above 100 % a bright room can lift a dim hour (the result is still capped at full brightness).
    public static let maxPercent = 150.0
    private static let range = minPercent...maxPercent

    public static let standard = LuxBrightnessCurve(values: [60, 75, 90, 100, 115, 130])

    public private(set) var values: [Double]

    public init(values: [Double]) {
        self.values = EqualizerBands.normalized(values, count: Self.luxPoints.count, pad: 100, range: Self.range, step: Self.step)
    }

    static func snap(_ percent: Double) -> Double { EqualizerBands.snap(percent, range: range, step: step) }

    /// Where `lux` lies on the chart, in bands (0 at the first band, `count - 1` at the last), on a log axis.
    public static func position(lux: Double) -> Double {
        let logs = luxPoints.map(log10)
        guard let first = logs.first, let last = logs.last else { return 0 }
        let value = lux.isFinite ? log10(max(lux, 1)) : first
        if value <= first { return 0 }
        if value >= last { return Double(logs.count - 1) }
        guard let upper = logs.firstIndex(where: { $0 >= value }), upper > 0 else { return 0 }
        let lower = upper - 1
        return Double(lower) + (value - logs[lower]) / (logs[upper] - logs[lower])
    }

    /// Percent for a reading, blended between the neighbouring bands.
    public func percent(lux: Double) -> Double {
        let position = Self.position(lux: lux)
        let lower = min(Int(floor(position)), values.count - 1)
        let upper = min(lower + 1, values.count - 1)
        let t = position - Double(lower)
        return values[lower] + (values[upper] - values[lower]) * t
    }

    public mutating func set(band: Int, percent: Double) {
        guard values.indices.contains(band) else { return }
        values[band] = Self.snap(percent)
    }

    public mutating func paint(fromBand a: Double, percent pa: Double, toBand b: Double, percent pb: Double) {
        values = EqualizerBands.painted(values, fromBand: a, value: pa, toBand: b, value: pb, snap: Self.snap)
    }

    public var encoded: String { EqualizerBands.encode(values) }

    public static func decode(_ text: String?) -> LuxBrightnessCurve? {
        EqualizerBands.decode(text, count: luxPoints.count).map { LuxBrightnessCurve(values: $0) }
    }
}

public enum ScreenBrightness {
    /// The darkest the feature ever makes a screen (macOS's own slider goes to black; this never does).
    public static let minimumLevel = 0.05
    /// After the user moves the brightness by hand, that display is left alone this long.
    public static let manualHoldSeconds: TimeInterval = 3600

    /// Display brightness (minimumLevel...1) for a moment of the day and the room's light (nil = no reading).
    public static func level(minuteOfDay: Double, lux: Double?, day: BrightnessDayCurve, room: LuxBrightnessCurve) -> Double {
        let base = day.percent(atMinuteOfDay: minuteOfDay) / 100
        let roomFactor = lux.map { room.percent(lux: $0) / 100 } ?? 1
        return clamp(base * roomFactor)
    }

    public static func clamp(_ level: Double) -> Double {
        guard level.isFinite else { return 1 }
        return min(max(level, minimumLevel), 1)
    }

    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
    }

    /// One step from `current` toward `target`, no larger than `maxStep` (so the screen never jumps).
    public static func ramp(from current: Double, to target: Double, maxStep: Double) -> Double {
        let step = max(maxStep, 0)
        return current + min(max(target - current, -step), step)
    }

    /// A manual change made at `since` still keeps the feature's hands off.
    public static func holding(since: Date?, now: Date) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) < manualHoldSeconds
    }
}

/// What a display's brightness should be, as the BetterDisplay pass and the built-in display see it.
public enum DisplayBrightnessGoal: Equatable, Sendable {
    /// Leave it at (or give back) the brightness it had before the feature touched it.
    case original
    /// Evening dimming: a share of the original brightness (1 = no dimming).
    case factor(Double)
    /// The brightness equaliser: an absolute level.
    case level(Double)
    /// Another mechanism owns this display (the built-in screen through DisplayServices): forget what was
    /// remembered for it, without writing anything.
    case elsewhere

    /// The brightness to set, or nil when the original one is wanted.
    public func wanted(original: Double) -> Double? {
        switch self {
        case .original, .elsewhere: return nil
        case .factor(let f): return f >= 0.995 ? nil : original * f
        case .level(let l): return ScreenBrightness.clamp(l)
        }
    }

    /// The feature is actively driving this display (it is not just giving it back).
    public var drives: Bool {
        switch self {
        case .original, .elsewhere: return false
        case .factor(let f): return f < 0.995
        case .level: return true
        }
    }
}

/// What to do with a display left alone after the user changed its brightness by hand.
public enum ManualHold {
    public enum Kind: Equatable, Sendable {
        /// Evening dimming: hands off until the evening ends.
        case evening
        /// Brightness equaliser: hands off for `ScreenBrightness.manualHoldSeconds`, whatever happens meanwhile
        /// (an exception, a pause or a preview must not cut the hold short).
        case equalizer
    }

    public enum Decision: Equatable, Sendable {
        /// Still hands off: keep the hold and do not touch the display.
        case keep
        /// The hold is over: forget it and drive the display again.
        case drop
    }

    public static func decision(kind: Kind, since: Date, goal: DisplayBrightnessGoal, now: Date) -> Decision {
        switch kind {
        case .evening:
            if case .factor = goal, goal.drives { return .keep }
            return .drop
        case .equalizer:
            switch goal {
            case .level, .original: return ScreenBrightness.holding(since: since, now: now) ? .keep : .drop
            case .factor, .elsewhere: return .drop
            }
        }
    }
}

/// The built-in screen's brightness from before the equaliser, kept across restarts with the value the
/// equaliser set last. Stored as a property-list dictionary; an older version stored just the number.
public struct SavedBrightness: Equatable, Sendable {
    public let original: Double
    public let lastSet: Double?

    public init(original: Double, lastSet: Double?) {
        self.original = original
        self.lastSet = lastSet
    }

    public init?(plist: Any?) {
        if let number = plist as? Double {
            guard number.isFinite else { return nil }
            self.init(original: number, lastSet: nil)
            return
        }
        guard let dictionary = plist as? [String: Any], let original = dictionary["original"] as? Double,
              original.isFinite else { return nil }
        self.init(original: original, lastSet: (dictionary["lastSet"] as? Double).flatMap { $0.isFinite ? $0 : nil })
    }

    public var plist: [String: Double] {
        var result = ["original": original]
        if let lastSet { result["lastSet"] = lastSet }
        return result
    }

    /// Giving the original back is right only when the screen still shows what the equaliser set
    /// (someone who moved it by hand meanwhile keeps their value).
    public func mayRestore(current: Double) -> Bool {
        guard let lastSet else { return true }
        return !EveningDimming.userChanged(current: current, lastSet: lastSet)
    }
}

/// Passing the built-in screen between the evening dimming (BetterDisplay) and the equaliser (DisplayServices)
/// without losing its real original brightness: only one of them drives it at a time, and the one that lets
/// go hands its original to the one that takes over.
public enum BrightnessHandover {
    /// The original the letting-go side hands over: none after a manual change (the user owns the value then).
    /// `takerLastSet`: what the taking side wrote already (its glide may have started): that is no manual change.
    public static func originalToHandOver(original: Double?, lastSet: Double?, current: Double,
                                          takerLastSet: Double? = nil) -> Double? {
        guard let original, original.isFinite else { return nil }
        if let taker = takerLastSet, !EveningDimming.userChanged(current: current, lastSet: taker) { return original }
        if let lastSet, EveningDimming.userChanged(current: current, lastSet: lastSet) { return nil }
        return original
    }

    /// A handed-over original is older than what the taker read itself (that may be already dimmed), so it wins.
    public static func adopted(own: Double?, handedOver: Double?) -> Double? {
        if let handedOver, handedOver.isFinite { return handedOver }
        return own
    }

    /// The equaliser keeps the built-in screen (the dimming must leave it alone) while it is active, still has
    /// an original to give back, or is gliding back to it.
    public static func keepsBuiltIn(equalizerActive: Bool, hasOriginal: Bool, restoring: Bool) -> Bool {
        equalizerActive || hasOriginal || restoring
    }

    /// With no last value (after a wake-up) the current reading becomes it, so the next manual change is
    /// recognised and a restore after a restart is checked against something real.
    public static func lastSetAfterCheck(lastSet: Double?, current: Double) -> Double {
        lastSet ?? current
    }
}
