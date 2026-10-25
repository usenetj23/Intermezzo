import Foundation

public struct SunPosition: Equatable {
    /// Degrees clockwise from north (90 = east, 180 = south, 270 = west).
    public let azimuthDegrees: Double
    /// Degrees above the horizon; negative = below.
    public let altitudeDegrees: Double
}

/// Low-precision solar position (≈0.01°, plenty for a decorative sky).
public enum Sun {
    public static func position(date: Date, latitude: Double, longitude: Double) -> SunPosition {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let n = jd - 2_451_545.0

        let meanLongitude = normalize(280.460 + 0.9856474 * n)
        let meanAnomaly = normalize(357.528 + 0.9856003 * n) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))

        let gmst = normalize(280.46061837 + 360.98564736629 * n)
        let hourAngle = (normalize(gmst + longitude) * rad) - rightAscension

        let lat = latitude * rad
        let altitude = asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle))
        let azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(lat) - tan(declination) * cos(lat))

        return SunPosition(azimuthDegrees: normalize(azimuth / rad + 180),
                           altitudeDegrees: altitude / rad)
    }

    private static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
