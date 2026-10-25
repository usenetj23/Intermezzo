import Foundation

/// A hand-drawn day: the screen colour for each of the 24 hours, like the bands of an equaliser.
/// Between the middles of two hours the colour blends smoothly, so there are no steps.
public struct CustomLightCurve: Equatable, Sendable {
    public static let bands = 24
    /// Dragging snaps to this many kelvin.
    public static let step = 100.0

    public private(set) var hourly: [Double]

    public init(hourly: [Double]) {
        var values = hourly.prefix(Self.bands).map { Self.snap($0) }
        while values.count < Self.bands { values.append(LightSettings.maxKelvin) }
        self.hourly = values
    }

    static func snap(_ kelvin: Double) -> Double {
        let clamped = min(max(kelvin, LightSettings.minKelvin), LightSettings.maxKelvin)
        return (clamped / step).rounded() * step
    }

    public var warmest: Double { hourly.min() ?? LightSettings.minKelvin }
    public var coolest: Double { hourly.max() ?? LightSettings.maxKelvin }

    /// Colour at a moment of the day, `minute` in 0..<1440 (values outside wrap around).
    public func kelvin(atMinuteOfDay minute: Double) -> Double {
        var m = minute.truncatingRemainder(dividingBy: 1440)
        if m < 0 { m += 1440 }
        let position = (m - 30) / 60               // band centres are at h:30
        let lower = Int(floor(position))
        let fraction = position - Double(lower)
        let a = hourly[((lower % Self.bands) + Self.bands) % Self.bands]
        let b = hourly[(((lower + 1) % Self.bands) + Self.bands) % Self.bands]
        let t = fraction * fraction * (3 - 2 * fraction)
        return a + (b - a) * t
    }

    public mutating func set(hour: Int, kelvin: Double) {
        guard (0..<Self.bands).contains(hour) else { return }
        hourly[hour] = Self.snap(kelvin)
    }

    /// A drag from one point to another sets every band in between on a straight line, so that a fast
    /// stroke leaves no gaps. Positions are in bands (0..<24, fractions allowed).
    public mutating func paint(fromBand a: Double, kelvin ka: Double, toBand b: Double, kelvin kb: Double) {
        let first = Int(floor(min(a, b))), last = Int(floor(max(a, b)))
        for band in first...last where (0..<Self.bands).contains(band) {
            let t = abs(b - a) < 1e-9 ? 1 : (Double(band) + 0.5 - a) / (b - a)
            let k = ka + (kb - ka) * min(max(t, 0), 1)
            set(hour: band, kelvin: k)
        }
    }

    // MARK: Storage ("6500,6500,…")

    public var encoded: String { hourly.map { String(Int($0)) }.joined(separator: ",") }

    public static func decode(_ text: String?) -> CustomLightCurve? {
        guard let text else { return nil }
        let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == bands else { return nil }
        return CustomLightCurve(hourly: numbers)
    }

    /// A starting point: what a profile does at the middle of each hour on `date`.
    public static func sampled(settings: LightSettings, latitude: Double, longitude: Double, date: Date,
                               calendar: Calendar = .current) -> CustomLightCurve {
        let start = calendar.startOfDay(for: date)
        let values = (0..<bands).map { hour -> Double in
            let moment = calendar.date(byAdding: .minute, value: hour * 60 + 30, to: start) ?? start
            return LightSchedule.state(at: moment, latitude: latitude, longitude: longitude,
                                       settings: settings, calendar: calendar).kelvin
        }
        return CustomLightCurve(hourly: values)
    }

    /// The settings the rest of the app needs from a curve (the warmest and coolest point).
    /// `sunDriven`: the cool end is the neutral 6500 K, because daytime is left to the Sun.
    public func lightSettings(wakeMinutes: Int, sunDriven: Bool = false) -> LightSettings {
        var s = LightProfile.recommended.settings(wakeMinutes: wakeMinutes)
        s.dayK = sunDriven ? LightSettings.maxKelvin : coolest
        s.bedtimeK = warmest
        s.sunsetK = (coolest + warmest) / 2
        return s.sanitized
    }
}

extension LightSchedule {
    /// The state for a hand-drawn day: only the clock decides (the Sun's height is still reported).
    public static func state(at date: Date, latitude: Double, longitude: Double, curve: CustomLightCurve,
                             calendar: Calendar = .current) -> LightState {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        let kelvin = curve.kelvin(atMinuteOfDay: minute)
        let span = max(curve.coolest - curve.warmest, 1)
        let warmth = (curve.coolest - kelvin) / span
        let phase: LightPhase = warmth < 0.2 ? .daytime : (warmth < 0.75 ? .sunset : .bedtime)
        let elevation = Sun.position(date: date, latitude: latitude, longitude: longitude).altitudeDegrees
        return LightState(kelvin: kelvin, phase: phase, sunElevation: elevation)
    }

    /// A hand-drawn day whose strength follows the Sun: the curve says how warm each hour may get, and
    /// the Sun (with clouds) says how much of it applies. Daylight is neutral; once the Sun is low the
    /// drawn colour fades in; around bedtime the clock keeps it applied even where the Sun never sets.
    public static func sunDrivenState(at date: Date, latitude: Double, longitude: Double, curve: CustomLightCurve,
                                      settings: LightSettings, cloudCover: Double? = nil,
                                      calendar: Calendar = .current) -> LightState {
        let s = settings.sanitized
        let elevation = Sun.position(date: date, latitude: latitude, longitude: longitude).altitudeDegrees
        let cloud = min(max(cloudCover ?? 0, 0), 100) / 100
        let sun = smoothStep((elevation - cloud * cloudShiftDegrees - s.twilightLow) / (s.twilightHigh - s.twilightLow))
        let night = nightWeight(at: date, settings: s, calendar: calendar)
        let activation = max(1 - sun, night)
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        let neutral = LightSettings.maxKelvin
        let kelvin = neutral + (min(curve.kelvin(atMinuteOfDay: minute), neutral) - neutral) * activation
        let phase: LightPhase = activation < 0.2 ? .daytime : (night > 0.5 ? .bedtime : .sunset)
        return LightState(kelvin: kelvin, phase: phase, sunElevation: elevation)
    }

    fileprivate static func smoothStep(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
