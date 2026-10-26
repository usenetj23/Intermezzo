import XCTest
@testable import IntermezzoKit

final class DayNightTests: XCTestCase {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testBandsByAltitude() {
        let expected: [(Double, Int)] = [(10, 0), (0.1, 0), (-0.1, 1), (-5.9, 1), (-6.1, 2), (-11.9, 2),
                                         (-12.1, 3), (-17.9, 3), (-18.1, 4), (-60, 4)]
        for (altitude, band) in expected {
            XCTAssertEqual(DayNight.darkness(sunAltitude: altitude), band, "\(altitude)")
        }
        XCTAssertEqual(DayNight.levels, 5)
    }

    func testNoonAtSubsolarPointIsDay() {
        let date = utc(2026, 6, 21, 12)
        let sub = DayNight.subsolarPoint(date: date)
        XCTAssertGreaterThan(Sun.position(date: date, latitude: sub.latitude, longitude: sub.longitude).altitudeDegrees, 85)
        XCTAssertEqual(DayNight.darkness(at: sub, date: date), 0)
    }

    func testSubsolarPointFollowsTheSeasons() {
        XCTAssertEqual(DayNight.subsolarPoint(date: utc(2026, 6, 21, 12)).latitude, 23.4, accuracy: 0.5)
        XCTAssertEqual(DayNight.subsolarPoint(date: utc(2026, 12, 21, 12)).latitude, -23.4, accuracy: 0.5)
    }

    func testAntipodeOfSubsolarPointIsNight() {
        let date = utc(2026, 3, 10, 7)
        let sub = DayNight.subsolarPoint(date: date)
        var lon = sub.longitude + 180
        if lon > 180 { lon -= 360 }
        XCTAssertEqual(DayNight.darkness(at: GeoPoint(latitude: -sub.latitude, longitude: lon), date: date), 4)
    }

    func testPolarNightAndMidnightSun() {
        XCTAssertEqual(DayNight.darkness(at: GeoPoint(latitude: 85, longitude: 0), date: utc(2026, 12, 21, 12)), 4)
        XCTAssertEqual(DayNight.darkness(at: GeoPoint(latitude: 80, longitude: 0), date: utc(2026, 6, 21, 0)), 0)
    }

    func testPrecomputedShaderMatchesTheSunPosition() {
        let date = utc(2026, 10, 26, 8)
        let shade = DayNight.shader(date: date)
        for lat in stride(from: -80.0, through: 80, by: 20) {
            for lon in stride(from: -180.0, through: 180, by: 30) {
                let expected = DayNight.darkness(sunAltitude: Sun.position(date: date, latitude: lat, longitude: lon).altitudeDegrees)
                XCTAssertEqual(shade(GeoPoint(latitude: lat, longitude: lon)), expected, "\(lat), \(lon)")
            }
        }
    }
}
