import Foundation

// Screen colour that follows the day: cool while the sun is up, warmer after sunset, warmest
// before sleep. Pure logic only; the app applies the result to the displays.

public enum ColorTemperature {
    /// Channel gains (0...1) that turn a 6500 K white point into one at `kelvin`.
    /// Uses Tanner Helland's blackbody fit; the input is limited to 1000...6500 K.
    public static func multipliers(kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let raw = channels(min(max(kelvin, 1000), 6500))
        let ref = channels(6500)
        return (min(1, raw.r / ref.r), min(1, raw.g / ref.g), min(1, raw.b / ref.b))
    }

    private static func channels(_ kelvin: Double) -> (r: Double, g: Double, b: Double) {
        let t = kelvin / 100
        let r = t <= 66 ? 255 : 329.698727446 * pow(t - 60, -0.1332047592)
        let g = t <= 66 ? 99.4708025861 * log(t) - 161.1195681661 : 288.1221695283 * pow(t - 60, -0.0755148492)
        let b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307)
        func clamp(_ v: Double) -> Double { min(255, max(0, v)) }
        return (clamp(r), clamp(g), clamp(b))
    }
}

public struct LightSettings: Equatable, Sendable {
    public static let minKelvin = 1000.0
    public static let maxKelvin = 6500.0

    public var dayK: Double
    public var sunsetK: Double
    public var bedtimeK: Double
    /// Minute of the day the user wakes up (0..<1440).
    public var wakeMinutes: Int
    /// Bedtime, counted from waking up.
    public var bedtimeAfterWakeMinutes: Int
    /// How long before bedtime the screen starts warming from the sunset to the bedtime colour.
    public var rampMinutes: Int
    /// How long after waking up the screen takes to cool back.
    public var wakeRampMinutes: Int
    /// Sun elevation (degrees) of full evening and of full day.
    public var twilightLow: Double
    public var twilightHigh: Double

    public init(dayK: Double, sunsetK: Double, bedtimeK: Double, wakeMinutes: Int, bedtimeAfterWakeMinutes: Int,
                rampMinutes: Int, wakeRampMinutes: Int, twilightLow: Double, twilightHigh: Double) {
        self.dayK = dayK
        self.sunsetK = sunsetK
        self.bedtimeK = bedtimeK
        self.wakeMinutes = wakeMinutes
        self.bedtimeAfterWakeMinutes = bedtimeAfterWakeMinutes
        self.rampMinutes = rampMinutes
        self.wakeRampMinutes = wakeRampMinutes
        self.twilightLow = twilightLow
        self.twilightHigh = twilightHigh
    }

    /// Values forced into a range where the schedule is well defined.
    public var sanitized: LightSettings {
        let day = min(max(dayK, Self.minKelvin), Self.maxKelvin)
        let sunset = min(max(sunsetK, Self.minKelvin), day)
        let bedtime = min(max(bedtimeK, Self.minKelvin), sunset)
        let low = twilightLow < twilightHigh ? twilightLow : -6
        let high = twilightLow < twilightHigh ? twilightHigh : 3
        return LightSettings(dayK: day, sunsetK: sunset, bedtimeK: bedtime,
                             wakeMinutes: ((wakeMinutes % 1440) + 1440) % 1440,
                             bedtimeAfterWakeMinutes: min(max(bedtimeAfterWakeMinutes, 240), 1380),
                             rampMinutes: min(max(rampMinutes, 15), 360),
                             wakeRampMinutes: min(max(wakeRampMinutes, 10), 240),
                             twilightLow: low, twilightHigh: high)
    }
}

/// Ready-made schedules. They are our own compromises, not medical prescriptions: the research
/// shows that bright, short-wavelength light in the evening delays the body clock, not which exact
/// kelvin value is right.
public enum LightProfile: String, CaseIterable, Sendable {
    case recommended, classic, farFromEquator, workingLate
    /// A hand-drawn day that follows the clock.
    case custom
    /// A hand-drawn day whose strength follows the Sun, the clouds and the room's light.
    case customSun

    /// Both hand-drawn profiles use the drawn curve.
    public var isCustom: Bool { self == .custom || self == .customSun }

    public func settings(wakeMinutes: Int) -> LightSettings {
        switch self {
        case .recommended, .custom, .customSun:
            return LightSettings(dayK: 6500, sunsetK: 3400, bedtimeK: 1900, wakeMinutes: wakeMinutes,
                                 bedtimeAfterWakeMinutes: 990, rampMinutes: 120, wakeRampMinutes: 90,
                                 twilightLow: -6, twilightHigh: 3)
        case .classic:
            return LightSettings(dayK: 6500, sunsetK: 3400, bedtimeK: 3400, wakeMinutes: wakeMinutes,
                                 bedtimeAfterWakeMinutes: 990, rampMinutes: 60, wakeRampMinutes: 60,
                                 twilightLow: -6, twilightHigh: 3)
        case .farFromEquator:
            return LightSettings(dayK: 6500, sunsetK: 3500, bedtimeK: 2300, wakeMinutes: wakeMinutes,
                                 bedtimeAfterWakeMinutes: 990, rampMinutes: 180, wakeRampMinutes: 90,
                                 twilightLow: -4, twilightHigh: 6)
        case .workingLate:
            return LightSettings(dayK: 6500, sunsetK: 3400, bedtimeK: 2300, wakeMinutes: wakeMinutes,
                                 bedtimeAfterWakeMinutes: 1140, rampMinutes: 120, wakeRampMinutes: 90,
                                 twilightLow: -6, twilightHigh: 3)
        }
    }
}

public enum LightPhase: String, Sendable {
    case daytime, sunset, bedtime
}

public struct LightState: Equatable, Sendable {
    public let kelvin: Double
    public let phase: LightPhase
    public let sunElevation: Double

    public init(kelvin: Double, phase: LightPhase, sunElevation: Double) {
        self.kelvin = kelvin
        self.phase = phase
        self.sunElevation = sunElevation
    }
}

public struct SunEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case sunrise, sunset }
    public let kind: Kind
    public let date: Date
}

public enum LightSchedule {
    /// How far (degrees of sun elevation) a fully overcast sky moves the evening earlier.
    static let cloudShiftDegrees = 3.0

    public static func state(at date: Date, latitude: Double, longitude: Double, settings: LightSettings,
                             cloudCover: Double? = nil, calendar: Calendar = .current) -> LightState {
        let s = settings.sanitized
        let elevation = Sun.position(date: date, latitude: latitude, longitude: longitude).altitudeDegrees
        let cloud = min(max(cloudCover ?? 0, 0), 100) / 100
        let sun = smooth((elevation - cloud * cloudShiftDegrees - s.twilightLow) / (s.twilightHigh - s.twilightLow))
        let base = s.sunsetK + (s.dayK - s.sunsetK) * sun
        let night = nightWeight(at: date, settings: s, calendar: calendar)
        let kelvin = min(base, base + (s.bedtimeK - base) * night)
        let phase: LightPhase = night > 0.5 ? .bedtime : (sun < 0.5 ? .sunset : .daytime)
        return LightState(kelvin: kelvin, phase: phase, sunElevation: elevation)
    }

    /// 0 in the daytime, 1 from bedtime until waking up, smooth on both sides.
    static func nightWeight(at date: Date, settings s: LightSettings, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let minuteOfDay = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        var sinceWake = (minuteOfDay - Double(s.wakeMinutes)).truncatingRemainder(dividingBy: 1440)
        if sinceWake < 0 { sinceWake += 1440 }
        let bedtime = Double(s.bedtimeAfterWakeMinutes)
        let rampStart = bedtime - Double(s.rampMinutes)
        if sinceWake < Double(s.wakeRampMinutes) { return smooth(1 - sinceWake / Double(s.wakeRampMinutes)) }
        if sinceWake <= rampStart { return 0 }
        if sinceWake < bedtime { return smooth((sinceWake - rampStart) / Double(s.rampMinutes)) }
        return 1
    }

    /// The next time the sun crosses the horizon (−0.833°, refraction included), within 36 hours.
    public static func nextSunEvent(after date: Date, latitude: Double, longitude: Double) -> SunEvent? {
        func altitude(_ d: Date) -> Double {
            Sun.position(date: d, latitude: latitude, longitude: longitude).altitudeDegrees + 0.833
        }
        let step: TimeInterval = 300
        var previousDate = date
        var previous = altitude(date)
        for _ in 0..<(36 * 12) {
            let next = previousDate.addingTimeInterval(step)
            let value = altitude(next)
            if (previous < 0) != (value < 0) {
                let fraction = abs(previous) / (abs(previous) + abs(value))
                return SunEvent(kind: value >= 0 ? .sunrise : .sunset,
                                date: previousDate.addingTimeInterval(step * fraction))
            }
            previousDate = next
            previous = value
        }
        return nil
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

public struct GeoPoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LightLocation {
    /// "52.4, 22" (decimal point; the comma separates the two numbers).
    public static func parse(_ text: String) -> GeoPoint? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    /// The reference city of a time zone from /usr/share/zoneinfo/zone.tab (ISO 6709 coordinates).
    public static func fromZoneTab(zoneID: String, table: String) -> GeoPoint? {
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, columns[2] == zoneID else { continue }
            return iso6709(String(columns[1]))
        }
        return nil
    }

    private static func iso6709(_ text: String) -> GeoPoint? {
        let chars = Array(text)
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        func value(_ part: ArraySlice<Character>, degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = part.dropFirst()
            guard digits.allSatisfy(\.isNumber), digits.count >= degreeDigits + 2 else { return nil }
            let d = Double(String(digits.prefix(degreeDigits))) ?? 0
            let rest = digits.dropFirst(degreeDigits)
            let m = Double(String(rest.prefix(2))) ?? 0
            let sec = rest.count >= 4 ? Double(String(rest.dropFirst(2).prefix(2))) ?? 0 : 0
            return (sign == "-" ? -1 : 1) * (d + m / 60 + sec / 3600)
        }
        guard let lat = value(chars[..<split], degreeDigits: 2),
              let lon = value(chars[split...], degreeDigits: 3) else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }
}

// MARK: - Leaving a display neutral

public struct DisplayFrame: Equatable, Sendable {
    public let id: UInt32
    /// In the global display space (top-left origin), like window bounds.
    public let bounds: CGRect
    public init(id: UInt32, bounds: CGRect) {
        self.id = id
        self.bounds = bounds
    }
}

/// The active window of the frontmost app.
public struct FrontWindow: Equatable, Sendable {
    /// Every name the app is known by (display name, executable name).
    public let appNames: [String]
    public let bounds: CGRect
    public init(appNames: [String], bounds: CGRect) {
        self.appNames = appNames
        self.bounds = bounds
    }
}

public enum LightExclusion {
    /// Displays that must show the system colours: the one the active window is on, when that app is on
    /// the exclusion list or the window fills the whole display (a film, a game, a full-screen app).
    public static func displaysToLeaveNeutral(front: FrontWindow?, displays: [DisplayFrame],
                                              excludedApps: [String], skipFullscreen: Bool) -> Set<UInt32> {
        guard let front, let display = display(of: front.bounds, in: displays) else { return [] }
        if KeepAwakeApps.firstMatch(wanted: excludedApps, running: front.appNames) != nil { return [display.id] }
        if skipFullscreen, covers(front.bounds, display.bounds) { return [display.id] }
        return []
    }

    /// The display the window mostly lies on.
    static func display(of window: CGRect, in displays: [DisplayFrame]) -> DisplayFrame? {
        var best: DisplayFrame?
        var bestArea: CGFloat = 0
        for display in displays {
            let overlap = display.bounds.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                best = display
                bestArea = area
            }
        }
        return best
    }

    static func covers(_ window: CGRect, _ display: CGRect) -> Bool {
        let leftOK = window.minX <= display.minX + 1
        let topOK = window.minY <= display.minY + 1
        let rightOK = window.maxX >= display.maxX - 1
        let bottomOK = window.maxY >= display.maxY - 1
        return leftOK && topOK && rightOK && bottomOK
    }
}
