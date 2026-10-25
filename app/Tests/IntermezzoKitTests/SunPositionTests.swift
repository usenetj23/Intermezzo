import XCTest
@testable import IntermezzoKit

final class SunPositionTests: XCTestCase {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    func testEquinoxNoonAtEquatorIsNearZenith() {
        let p = Sun.position(date: utc(2026, 3, 20, 12), latitude: 0, longitude: 0)
        XCTAssertGreaterThan(p.altitudeDegrees, 84)
    }

    func testWarsawSolarNoonMidsummer() {
        // Solar noon in Warsaw ≈ 10:36 UTC; max altitude = 90 - 52.23 + 23.44 ≈ 61.2°
        let p = Sun.position(date: utc(2026, 6, 21, 10, 36), latitude: 52.23, longitude: 21.01)
        XCTAssertEqual(p.altitudeDegrees, 61.2, accuracy: 1.5)
        XCTAssertEqual(p.azimuthDegrees, 180, accuracy: 6)
    }

    func testMorningSunIsInTheEast() {
        let p = Sun.position(date: utc(2026, 6, 21, 5), latitude: 52.23, longitude: 21.01)
        XCTAssertGreaterThan(p.altitudeDegrees, 0)
        XCTAssertTrue((50...110).contains(p.azimuthDegrees), "azimuth \(p.azimuthDegrees)")
    }

    func testAfternoonSunIsInTheWest() {
        let p = Sun.position(date: utc(2026, 6, 21, 16), latitude: 52.23, longitude: 21.01)
        XCTAssertTrue((250...310).contains(p.azimuthDegrees), "azimuth \(p.azimuthDegrees)")
    }

    func testMidnightWinterIsBelowHorizon() {
        let p = Sun.position(date: utc(2026, 12, 21, 23), latitude: 52.23, longitude: 21.01)
        XCTAssertLessThan(p.altitudeDegrees, 0)
    }
}
