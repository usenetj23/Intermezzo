import Foundation

// Day and night on the world map: the bands of twilight by the Sun's height, like the shading on a
// world clock. Pure logic; the map view draws the result.

public enum DayNight {
    /// Day, civil, nautical and astronomical twilight, night.
    public static let levels = 5

    /// 0 = day, 1 = civil twilight (down to −6°), 2 = nautical (−12°), 3 = astronomical (−18°), 4 = night.
    public static func darkness(sunAltitude: Double) -> Int {
        if sunAltitude >= 0 { return 0 }
        if sunAltitude >= -6 { return 1 }
        if sunAltitude >= -12 { return 2 }
        if sunAltitude >= -18 { return 3 }
        return 4
    }

    public static func darkness(at geo: GeoPoint, date: Date) -> Int {
        shader(date: date)(geo)
    }

    /// `darkness(at:date:)` for many places at one moment: the Sun's place is worked out once.
    public static func shader(date: Date) -> (GeoPoint) -> Int {
        let rad = Double.pi / 180
        let sun = Sun.equatorial(date: date)
        let sinDeclination = sin(sun.declination), cosDeclination = cos(sun.declination)
        return { geo in
            let hourAngle = (geo.longitude + sun.greenwichSiderealDegrees) * rad - sun.rightAscension
            let lat = geo.latitude * rad
            let sinAltitude = sin(lat) * sinDeclination + cos(lat) * cosDeclination * cos(hourAngle)
            return darkness(sunAltitude: asin(min(max(sinAltitude, -1), 1)) / rad)
        }
    }

    /// The place where the Sun stands straight overhead.
    public static func subsolarPoint(date: Date) -> GeoPoint {
        let sun = Sun.equatorial(date: date)
        var longitude = (sun.rightAscension * 180 / Double.pi - sun.greenwichSiderealDegrees)
            .truncatingRemainder(dividingBy: 360)
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return GeoPoint(latitude: sun.declination * 180 / Double.pi, longitude: longitude)
    }
}
