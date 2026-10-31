import Foundation
import IntermezzoKit

/// The one answer to "where am I" for the Light schedule, the weather on the break screen and the sun in its
/// picture: the place typed in Light settings, else the Mac's own position, else the time zone's city.
/// (The work place of the work zone is a different thing and has its own setting.)
enum PlaceResolver {
    nonisolated(unsafe) private static var zoneCache: (zone: String, point: GeoPoint?)?

    static func resolve(defaults: UserDefaults = .standard) -> (point: GeoPoint, source: PlaceSource)? {
        func coordinate(_ key: String) -> Double? {
            if let v = defaults.object(forKey: key) as? Double { return v }
            if let s = defaults.string(forKey: key), let v = Double(s) { return v }
            return nil
        }
        var fix: GeoPoint?
        if let lat = coordinate(GlassKeys.lat), let lon = coordinate(GlassKeys.lon) {
            fix = GeoPoint(latitude: lat, longitude: lon)
        }
        let zone = TimeZone.current.identifier
        if zoneCache?.zone != zone {
            let table = (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) ?? ""
            zoneCache = (zone, LightLocation.fromZoneTab(zoneID: zone, table: table))
        }
        return PlaceChoice.pick(manual: defaults.string(forKey: LightKeys.manualLocation),
                                macFix: fix, timeZoneCity: zoneCache?.point)
    }
}
