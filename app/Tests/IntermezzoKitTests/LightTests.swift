import XCTest
@testable import IntermezzoKit

final class LightTests: XCTestCase {
    private var warsaw: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, calendar: Calendar? = nil) -> Date {
        let cal = calendar ?? warsaw
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private let lat = 52.2, lon = 21.0
    private var recommended: LightSettings { LightProfile.recommended.settings(wakeMinutes: 6 * 60 + 30) }

    // MARK: colour

    func testSixtyFiveHundredIsNeutral() {
        let m = ColorTemperature.multipliers(kelvin: 6500)
        XCTAssertEqual(m.r, 1, accuracy: 0.001)
        XCTAssertEqual(m.g, 1, accuracy: 0.001)
        XCTAssertEqual(m.b, 1, accuracy: 0.001)
    }

    func testWarmerMeansLessBlueThenLessGreen() {
        var previous = ColorTemperature.multipliers(kelvin: 6500)
        for k in stride(from: 6000.0, through: 1000.0, by: -250) {
            let m = ColorTemperature.multipliers(kelvin: k)
            XCTAssertEqual(m.r, 1, accuracy: 0.001, "red stays full at \(k)")
            XCTAssertLessThanOrEqual(m.b, previous.b + 1e-9, "blue at \(k)")
            XCTAssertLessThanOrEqual(m.g, previous.g + 1e-9, "green at \(k)")
            previous = m
        }
        let candle = ColorTemperature.multipliers(kelvin: 1900)
        XCTAssertLessThan(candle.b, 0.35)
        XCTAssertGreaterThan(candle.g, 0.5)
    }

    func testMultipliersAreClamped() {
        let low = ColorTemperature.multipliers(kelvin: 100)
        XCTAssertEqual(low.b, ColorTemperature.multipliers(kelvin: 1000).b, accuracy: 1e-9)
        let high = ColorTemperature.multipliers(kelvin: 20000)
        XCTAssertEqual(high.r, 1, accuracy: 1e-9)
        XCTAssertEqual(high.g, 1, accuracy: 1e-9)
        XCTAssertEqual(high.b, 1, accuracy: 1e-9)
    }

    // MARK: schedule

    func testNoonIsDaytimeAndMidnightIsBedtime() {
        let noon = LightSchedule.state(at: date(2026, 6, 21, 13), latitude: lat, longitude: lon,
                                       settings: recommended, calendar: warsaw)
        XCTAssertEqual(noon.kelvin, 6500, accuracy: 1)
        XCTAssertEqual(noon.phase, .daytime)
        let night = LightSchedule.state(at: date(2026, 6, 21, 2), latitude: lat, longitude: lon,
                                        settings: recommended, calendar: warsaw)
        XCTAssertEqual(night.kelvin, 1900, accuracy: 1)
        XCTAssertEqual(night.phase, .bedtime)
    }

    func testEveningAfterSunsetIsWarmerThanDaytimeButNotYetBedtime() {
        let evening = LightSchedule.state(at: date(2026, 12, 21, 18), latitude: lat, longitude: lon,
                                          settings: recommended, calendar: warsaw)
        XCTAssertEqual(evening.kelvin, 3400, accuracy: 1)
        XCTAssertEqual(evening.phase, .sunset)
    }

    func testNeverOutsideTheConfiguredRange() {
        let s = recommended
        var t = date(2026, 3, 29, 0)
        for _ in 0..<(48 * 60) {
            let k = LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: s, calendar: warsaw).kelvin
            XCTAssertGreaterThanOrEqual(k, s.bedtimeK - 0.001)
            XCTAssertLessThanOrEqual(k, s.dayK + 0.001)
            t = t.addingTimeInterval(60)
        }
    }

    func testNoJumpsAcrossTheDayIncludingDaylightSavingChange() {
        for start in [date(2026, 6, 21, 0), date(2026, 3, 29, 0), date(2026, 10, 25, 0)] {
            var t = start
            var previous = LightSchedule.state(at: t, latitude: lat, longitude: lon,
                                               settings: recommended, calendar: warsaw).kelvin
            for _ in 0..<(26 * 60) {
                t = t.addingTimeInterval(60)
                let k = LightSchedule.state(at: t, latitude: lat, longitude: lon,
                                            settings: recommended, calendar: warsaw).kelvin
                XCTAssertLessThan(abs(k - previous), 100, "jump at \(t)")
                previous = k
            }
        }
    }

    func testWakeTimeCoolsTheScreenGradually() {
        let s = recommended
        let before = LightSchedule.state(at: date(2026, 6, 21, 6, 0), latitude: lat, longitude: lon, settings: s, calendar: warsaw).kelvin
        let during = LightSchedule.state(at: date(2026, 6, 21, 7, 15), latitude: lat, longitude: lon, settings: s, calendar: warsaw).kelvin
        let after = LightSchedule.state(at: date(2026, 6, 21, 9, 0), latitude: lat, longitude: lon, settings: s, calendar: warsaw).kelvin
        XCTAssertEqual(before, 1900, accuracy: 1)
        XCTAssertGreaterThan(during, before)
        XCTAssertLessThan(during, after)
        XCTAssertEqual(after, 6500, accuracy: 1)
    }

    func testCloudsStartTheEveningEarlier() {
        let t = date(2026, 9, 21, 18, 40)
        let clear = LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: recommended, cloudCover: 0, calendar: warsaw).kelvin
        let cloudy = LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: recommended, cloudCover: 100, calendar: warsaw).kelvin
        XCTAssertLessThan(cloudy, clear)
        XCTAssertEqual(LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: recommended, cloudCover: nil, calendar: warsaw).kelvin, clear, accuracy: 0.001)
    }

    func testPolarSummerAndWinterStayInRange() {
        for (lat, month) in [(69.6, 6), (69.6, 12)] {
            let k = LightSchedule.state(at: date(2026, month, 21, 12), latitude: lat, longitude: 19.0, settings: recommended, calendar: warsaw).kelvin
            XCTAssertGreaterThanOrEqual(k, 1900)
            XCTAssertLessThanOrEqual(k, 6500)
        }
        // polar night: the sun stays below the horizon, so noon is only as bright as twilight
        let polarNoon = LightSchedule.state(at: date(2026, 12, 21, 12), latitude: 69.6, longitude: 19.0,
                                            settings: recommended, calendar: warsaw)
        XCTAssertLessThan(polarNoon.kelvin, 5200)
        XCTAssertGreaterThanOrEqual(polarNoon.kelvin, 3400)
    }

    func testWorkingLateKeepsTheEveningLongerThanRecommended() {
        let late = LightProfile.workingLate.settings(wakeMinutes: 390)
        let t = date(2026, 6, 21, 23, 30)
        XCTAssertGreaterThan(LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: late, calendar: warsaw).kelvin,
                             LightSchedule.state(at: t, latitude: lat, longitude: lon, settings: recommended, calendar: warsaw).kelvin)
    }

    func testProfilesAreOrderedAndInRange() {
        for profile in LightProfile.allCases where !profile.isCustom {
            let s = profile.settings(wakeMinutes: 420)
            XCTAssertGreaterThanOrEqual(s.bedtimeK, LightSettings.minKelvin, "\(profile)")
            XCTAssertLessThanOrEqual(s.bedtimeK, s.sunsetK, "\(profile)")
            XCTAssertLessThanOrEqual(s.sunsetK, s.dayK, "\(profile)")
            XCTAssertLessThan(s.bedtimeAfterWakeMinutes, 1440, "\(profile)")
        }
    }

    func testSanitizedKeepsOrderAndRange() {
        let bad = LightSettings(dayK: 9000, sunsetK: 7000, bedtimeK: 200, wakeMinutes: 5000, bedtimeAfterWakeMinutes: 9000,
                                rampMinutes: 0, wakeRampMinutes: -5, twilightLow: 10, twilightHigh: -10).sanitized
        XCTAssertEqual(bad.dayK, LightSettings.maxKelvin)
        XCTAssertLessThanOrEqual(bad.sunsetK, bad.dayK)
        XCTAssertGreaterThanOrEqual(bad.bedtimeK, LightSettings.minKelvin)
        XCTAssertTrue((0..<1440).contains(bad.wakeMinutes))
        XCTAssertLessThan(bad.bedtimeAfterWakeMinutes, 1440)
        XCTAssertGreaterThan(bad.rampMinutes, 0)
        XCTAssertLessThan(bad.twilightLow, bad.twilightHigh)
    }

    // MARK: sun events

    func testNextSunEventIsSunsetInTheAfternoonAndSunriseAtNight() {
        let afternoon = LightSchedule.nextSunEvent(after: date(2026, 6, 21, 13), latitude: lat, longitude: lon)
        XCTAssertEqual(afternoon?.kind, .sunset)
        let hour = warsaw.component(.hour, from: afternoon!.date)
        XCTAssertTrue((20...21).contains(hour), "sunset hour \(hour)")
        let night = LightSchedule.nextSunEvent(after: date(2026, 6, 21, 1), latitude: lat, longitude: lon)
        XCTAssertEqual(night?.kind, .sunrise)
        XCTAssertNil(LightSchedule.nextSunEvent(after: date(2026, 12, 21, 12), latitude: 80, longitude: 0))
    }

    // MARK: location

    func testParsesManualCoordinates() {
        XCTAssertEqual(LightLocation.parse("52.4,22")?.latitude, 52.4)
        XCTAssertEqual(LightLocation.parse(" 52.4 , 22.0 ")?.longitude, 22.0)
        XCTAssertEqual(LightLocation.parse("-33,151")?.latitude, -33)
        XCTAssertNil(LightLocation.parse("52,4, 22,0"))
        XCTAssertNil(LightLocation.parse("91, 0"))
        XCTAssertNil(LightLocation.parse("12, 181"))
        XCTAssertNil(LightLocation.parse("abc"))
    }

    func testReadsTimeZoneTable() {
        let tab = "# comment\nPL\t+5215+02100\tEurope/Warsaw\nAR\t-3436-05827\tAmerica/Argentina/Buenos_Aires\nUS\t+404251-0740023\tAmerica/New_York\n"
        let pl = LightLocation.fromZoneTab(zoneID: "Europe/Warsaw", table: tab)
        XCTAssertEqual(pl!.latitude, 52.25, accuracy: 0.01)
        XCTAssertEqual(pl!.longitude, 21.0, accuracy: 0.01)
        let ar = LightLocation.fromZoneTab(zoneID: "America/Argentina/Buenos_Aires", table: tab)
        XCTAssertEqual(ar!.latitude, -34.6, accuracy: 0.05)
        XCTAssertEqual(ar!.longitude, -58.45, accuracy: 0.05)
        let ny = LightLocation.fromZoneTab(zoneID: "America/New_York", table: tab)
        XCTAssertEqual(ny!.latitude, 40.714, accuracy: 0.01)
        XCTAssertEqual(ny!.longitude, -74.006, accuracy: 0.01)
        XCTAssertNil(LightLocation.fromZoneTab(zoneID: "Mars/Olympus", table: tab))
    }
}

final class LightExclusionTests: XCTestCase {
    private let left = DisplayFrame(id: 1, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let right = DisplayFrame(id: 2, bounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440))

    private func front(_ names: [String], _ rect: CGRect) -> FrontWindow { FrontWindow(appNames: names, bounds: rect) }

    func testExcludedAppLeavesOnlyItsDisplayNeutral() {
        let w = front(["Pixelmator Pro", "Pixelmator Pro"], CGRect(x: 2100, y: 100, width: 1000, height: 800))
        XCTAssertEqual(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right],
                                                             excludedApps: ["pixelmator pro.app"], skipFullscreen: false), [2])
    }

    func testOtherAppIsLeftTinted() {
        let w = front(["Safari"], CGRect(x: 100, y: 100, width: 900, height: 700))
        XCTAssertTrue(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right],
                                                            excludedApps: ["Final Cut Pro"], skipFullscreen: false).isEmpty)
    }

    func testFullScreenWindowLeavesItsDisplayNeutralOnlyWhenAsked() {
        let w = front(["IINA"], left.bounds)
        XCTAssertEqual(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right], excludedApps: [], skipFullscreen: true), [1])
        XCTAssertTrue(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right], excludedApps: [], skipFullscreen: false).isEmpty)
    }

    func testNearlyFullWindowIsNotFullScreen() {
        let w = front(["Safari"], CGRect(x: 0, y: 25, width: 1920, height: 1055))
        XCTAssertTrue(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right], excludedApps: [], skipFullscreen: true).isEmpty)
    }

    func testWindowOnTwoDisplaysCountsForTheLargerPart() {
        let w = front(["Final Cut Pro"], CGRect(x: 1800, y: 0, width: 1200, height: 900))
        XCTAssertEqual(LightExclusion.displaysToLeaveNeutral(front: w, displays: [left, right],
                                                             excludedApps: ["Final Cut Pro"], skipFullscreen: false), [2])
    }

    func testNoWindowOrNoDisplayMeansNothingToDo() {
        XCTAssertTrue(LightExclusion.displaysToLeaveNeutral(front: nil, displays: [left], excludedApps: ["x"], skipFullscreen: true).isEmpty)
        let off = front(["x"], CGRect(x: 9000, y: 9000, width: 100, height: 100))
        XCTAssertTrue(LightExclusion.displaysToLeaveNeutral(front: off, displays: [left], excludedApps: ["x"], skipFullscreen: true).isEmpty)
    }
}
