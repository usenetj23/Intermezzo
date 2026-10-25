import XCTest
@testable import IntermezzoKit

final class CustomLightCurveTests: XCTestCase {
    private func flat(_ k: Double) -> CustomLightCurve { CustomLightCurve(hourly: Array(repeating: k, count: 24)) }

    func testBandsAreClampedSnappedAndPadded() {
        let c = CustomLightCurve(hourly: [200, 9000, 3449, 3451])
        XCTAssertEqual(c.hourly.count, 24)
        XCTAssertEqual(Array(c.hourly.prefix(4)), [1000, 6500, 3400, 3500])
        XCTAssertEqual(c.hourly[10], 6500)
        XCTAssertEqual(CustomLightCurve(hourly: Array(repeating: 3000, count: 40)).hourly.count, 24)
    }

    func testValueAtABandCentreIsTheBandValue() {
        var c = flat(6500)
        c.set(hour: 20, kelvin: 2700)
        XCTAssertEqual(c.kelvin(atMinuteOfDay: 20 * 60 + 30), 2700, accuracy: 1e-9)
        XCTAssertEqual(c.kelvin(atMinuteOfDay: 10 * 60 + 30), 6500, accuracy: 1e-9)
    }

    func testBlendsSmoothlyBetweenBandsAndWrapsMidnight() {
        var c = flat(6500)
        c.set(hour: 23, kelvin: 2000)
        c.set(hour: 0, kelvin: 3000)
        // between the middles of 23:xx and 0:xx, i.e. at midnight: half way
        XCTAssertEqual(c.kelvin(atMinuteOfDay: 0), 2500, accuracy: 1e-6)
        XCTAssertEqual(c.kelvin(atMinuteOfDay: 1440), c.kelvin(atMinuteOfDay: 0), accuracy: 1e-9)
        XCTAssertEqual(c.kelvin(atMinuteOfDay: -60), c.kelvin(atMinuteOfDay: 1380), accuracy: 1e-9)
        // monotone between two bands
        var previous = c.kelvin(atMinuteOfDay: 22 * 60 + 30)
        for step in 1...60 {
            let k = c.kelvin(atMinuteOfDay: 22 * 60 + 30 + Double(step))
            XCTAssertLessThanOrEqual(k, previous + 1e-9)
            previous = k
        }
    }

    func testNoJumpsAlongTheDay() {
        var c = flat(6500)
        for hour in 18..<24 { c.set(hour: hour, kelvin: 1900) }
        var previous = c.kelvin(atMinuteOfDay: 0)
        for minute in 1..<1440 {
            let k = c.kelvin(atMinuteOfDay: Double(minute))
            XCTAssertLessThan(abs(k - previous), 200, "minute \(minute)")
            previous = k
        }
    }

    func testPaintingFillsTheBandsBetweenTwoPoints() {
        var c = flat(6500)
        c.paint(fromBand: 4.5, kelvin: 6500, toBand: 9.5, kelvin: 2500)
        XCTAssertEqual(c.hourly[4], 6500)
        XCTAssertEqual(c.hourly[9], 2500)
        for band in 5...8 { XCTAssertLessThan(c.hourly[band], c.hourly[band - 1], "band \(band)") }
        XCTAssertEqual(c.hourly[10], 6500)
        // right to left works the same
        var d = flat(6500)
        d.paint(fromBand: 9.5, kelvin: 2500, toBand: 4.5, kelvin: 6500)
        XCTAssertEqual(c, d)
        // a single point
        var e = flat(6500)
        e.paint(fromBand: 12.2, kelvin: 4000, toBand: 12.2, kelvin: 4000)
        XCTAssertEqual(e.hourly[12], 4000)
        // outside the day is ignored
        e.paint(fromBand: -3, kelvin: 1000, toBand: 30, kelvin: 1000)
        XCTAssertEqual(e.hourly.count, 24)
    }

    func testStorageRoundTrip() {
        var c = flat(6500)
        c.set(hour: 22, kelvin: 1900)
        XCTAssertEqual(CustomLightCurve.decode(c.encoded), c)
        XCTAssertNil(CustomLightCurve.decode(nil))
        XCTAssertNil(CustomLightCurve.decode("1,2,3"))
        XCTAssertNil(CustomLightCurve.decode("a,b"))
    }

    func testSamplingAProfileGivesAUsableStart() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let c = CustomLightCurve.sampled(settings: LightProfile.recommended.settings(wakeMinutes: 390),
                                         latitude: 52.2, longitude: 21.0, date: day, calendar: cal)
        XCTAssertEqual(c.hourly[13], 6500)
        XCTAssertEqual(c.hourly[2], 1900)
        XCTAssertEqual(c.coolest, 6500)
        XCTAssertEqual(c.warmest, 1900)
    }

    func testStateFollowsTheClockOnly() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        var c = flat(6500)
        for hour in 21..<24 { c.set(hour: hour, kelvin: 2000) }
        let noon = cal.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        let late = cal.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 22, minute: 30))!
        let a = LightSchedule.state(at: noon, latitude: 52.2, longitude: 21, curve: c, calendar: cal)
        let b = LightSchedule.state(at: late, latitude: 52.2, longitude: 21, curve: c, calendar: cal)
        XCTAssertEqual(a.kelvin, 6500, accuracy: 1e-9)
        XCTAssertEqual(a.phase, .daytime)
        XCTAssertEqual(b.kelvin, 2000, accuracy: 1e-9)
        XCTAssertEqual(b.phase, .bedtime)
    }

    func testSettingsFromACurveSpanItsRange() {
        var c = flat(6500)
        c.set(hour: 3, kelvin: 2200)
        c.set(hour: 15, kelvin: 5000)
        for hour in [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23] { c.set(hour: hour, kelvin: 4000) }
        let s = c.lightSettings(wakeMinutes: 390)
        XCTAssertEqual(s.dayK, 5000)
        XCTAssertEqual(s.bedtimeK, 2200)
        XCTAssertLessThanOrEqual(s.sunsetK, s.dayK)
        XCTAssertGreaterThanOrEqual(s.sunsetK, s.bedtimeK)
    }
}

final class SunDrivenCurveTests: XCTestCase {
    private var warsaw: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private let lat = 52.2, lon = 21.0
    private let settings = LightProfile.recommended.settings(wakeMinutes: 390)

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        warsaw.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// Warm all evening and night (18:00-06:00), neutral by day.
    private var drawn: CustomLightCurve {
        var c = CustomLightCurve(hourly: Array(repeating: 6500, count: 24))
        for hour in 0..<6 { c.set(hour: hour, kelvin: 2200) }
        for hour in 18..<24 { c.set(hour: hour, kelvin: 2200) }
        return c
    }

    private func state(_ t: Date, cloud: Double? = nil, curve: CustomLightCurve? = nil, lat: Double? = nil) -> LightState {
        LightSchedule.sunDrivenState(at: t, latitude: lat ?? self.lat, longitude: lon, curve: curve ?? drawn,
                                     settings: settings, cloudCover: cloud, calendar: warsaw)
    }

    func testDaylightIsNeutralWhateverIsDrawnForThatHour() {
        var c = drawn
        c.set(hour: 13, kelvin: 2000)             // drawn warm at 13:00, but the Sun is high
        XCTAssertEqual(state(date(2026, 6, 21, 13), curve: c).kelvin, 6500, accuracy: 1e-6)
    }

    func testAfterSunsetTheDrawnColourApplies() {
        let s = state(date(2026, 12, 21, 19))     // dark by 19:00 in December
        XCTAssertEqual(s.kelvin, 2200, accuracy: 60)
        XCTAssertNotEqual(s.phase, .daytime)
    }

    func testTheDrawnEveningStartsWithTheSunNotWithTheClock() {
        // the same drawn 18:00 warmth: in June (sun still high) nothing happens, in December it is dark
        XCTAssertGreaterThan(state(date(2026, 6, 21, 18, 30)).kelvin, 6000)
        XCTAssertLessThan(state(date(2026, 12, 21, 18, 30)).kelvin, 2600)
    }

    func testCloudsLetTheDrawnColourInSooner() {
        let t = date(2026, 9, 21, 18, 40)
        XCTAssertLessThan(state(t, cloud: 100).kelvin, state(t, cloud: 0).kelvin)
    }

    func testMidnightSunStillWarmsAroundBedtime() {
        // 69.6°N in June: the Sun never sets, yet 23:30 follows the drawn colour through the bedtime clock
        XCTAssertLessThan(state(date(2026, 6, 21, 23, 30), lat: 69.6).kelvin, 2600)
        XCTAssertEqual(state(date(2026, 6, 21, 12), lat: 69.6).kelvin, 6500, accuracy: 1e-6)
    }

    func testNoJumpsAcrossTheDay() {
        for start in [date(2026, 6, 21, 0), date(2026, 12, 21, 0), date(2026, 3, 29, 0)] {
            var t = start
            var previous = state(t).kelvin
            for _ in 0..<(26 * 60) {
                t = t.addingTimeInterval(60)
                let k = state(t).kelvin
                XCTAssertLessThan(abs(k - previous), 120, "jump at \(t)")
                previous = k
            }
        }
    }

    func testNeverCoolerThanNeutralOrWarmerThanDrawn() {
        var t = date(2026, 10, 25, 0)
        for _ in 0..<(24 * 6) {
            let k = state(t).kelvin
            XCTAssertLessThanOrEqual(k, 6500 + 1e-9)
            XCTAssertGreaterThanOrEqual(k, 2200 - 1e-9)
            t = t.addingTimeInterval(600)
        }
    }

    func testProfileFlagsAndSettings() {
        XCTAssertTrue(LightProfile.custom.isCustom)
        XCTAssertTrue(LightProfile.customSun.isCustom)
        XCTAssertFalse(LightProfile.recommended.isCustom)
        let sunSettings = drawn.lightSettings(wakeMinutes: 390, sunDriven: true)
        XCTAssertEqual(sunSettings.dayK, 6500)
        XCTAssertEqual(sunSettings.bedtimeK, 2200)
    }
}
