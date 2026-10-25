import XCTest
@testable import IntermezzoKit

final class AmbientLightTests: XCTestCase {
    private let settings = LightProfile.recommended.settings(wakeMinutes: 390)

    func testMedianIgnoresOneOddReading() {
        XCTAssertEqual(AmbientLight.smoothed([54, 54, 5000, 53, 54]), 54)
        XCTAssertEqual(AmbientLight.smoothed([10, 20]), 15)
        XCTAssertNil(AmbientLight.smoothed([]))
        XCTAssertNil(AmbientLight.smoothed([-1, .nan]))
    }

    func testBrightnessScale() {
        XCTAssertEqual(AmbientLight.brightness(lux: 5), 0)
        XCTAssertEqual(AmbientLight.brightness(lux: 100), 0, accuracy: 1e-9)
        XCTAssertEqual(AmbientLight.brightness(lux: 1500), 1, accuracy: 1e-9)
        XCTAssertEqual(AmbientLight.brightness(lux: 50000), 1)
        XCTAssertLessThan(AmbientLight.brightness(lux: 100), AmbientLight.brightness(lux: 300))
    }

    func testDaytimeColourIsNotChangedByTheRoom() {
        for lux in [0.0, 54, 500, 20000] {
            XCTAssertEqual(AmbientLight.adjustedKelvin(6500, lux: lux, settings: settings, roomLampK: nil), 6500, accuracy: 1e-9)
        }
    }

    func testEveningWarmingIsFullInADarkRoomAndWeakerInABrightOne() {
        let dark = AmbientLight.adjustedKelvin(1900, lux: 54, settings: settings, roomLampK: nil)
        let bright = AmbientLight.adjustedKelvin(1900, lux: 1500, settings: settings, roomLampK: nil)
        XCTAssertEqual(dark, 1900, accuracy: 1e-9)
        XCTAssertGreaterThan(bright, dark)
        XCTAssertEqual(bright, 6500 - 4600 * 0.6, accuracy: 1e-6)
    }

    func testLampColourKeepsTheEveningScreenCloseToTheRoom() {
        // 2700 K lamps, a lit room: the screen is not left at 3400 K.. but never cooler than lamp + 500 K
        XCTAssertEqual(AmbientLight.adjustedKelvin(3400, lux: 150, settings: settings, roomLampK: 2700), 3200, accuracy: 1e-9)
        // a dark room: lamps are off, so the lamp colour does not apply
        XCTAssertEqual(AmbientLight.adjustedKelvin(3400, lux: 10, settings: settings, roomLampK: 2700), 3400, accuracy: 1e-9)
        // 54 lx is still a dark room: full warming
        // cool lamps do not make the screen cooler than the schedule
        XCTAssertEqual(AmbientLight.adjustedKelvin(3400, lux: 150, settings: settings, roomLampK: 5500),
                       AmbientLight.adjustedKelvin(3400, lux: 150, settings: settings, roomLampK: nil), accuracy: 1e-9)
    }

    func testResultStaysInRange() {
        for kelvin in stride(from: 1000.0, through: 6500, by: 500) {
            for lux in [0.0, 40, 400, 5000] {
                let k = AmbientLight.adjustedKelvin(kelvin, lux: lux, settings: settings, roomLampK: 1000)
                XCTAssertGreaterThanOrEqual(k, 1000)
                XCTAssertLessThanOrEqual(k, 6500)
            }
        }
    }

    func testDimmingFadesOutInBrightRooms() {
        XCTAssertEqual(AmbientLight.scaledDimFactor(0.8, lux: 54), 0.8, accuracy: 1e-9)
        XCTAssertEqual(AmbientLight.scaledDimFactor(0.8, lux: 2500), 1, accuracy: 1e-9)
        XCTAssertEqual(AmbientLight.scaledDimFactor(0.8, lux: nil), 0.8)
        let mid = AmbientLight.scaledDimFactor(0.8, lux: 180)
        XCTAssertGreaterThan(mid, 0.8)
        XCTAssertLessThan(mid, 1)
    }

    func testPresetsAddEachAppOnce() {
        let preset = LightExclusionPresets.all[0]
        let once = LightExclusionPresets.adding(preset, to: "Pixelmator Pro.app, Safari")
        XCTAssertEqual(KeepAwakeApps.list(fromCommaText: once).filter { KeepAwakeApps.normalized($0) == "pixelmator pro" }.count, 1)
        XCTAssertTrue(once.contains("Safari"))
        XCTAssertEqual(LightExclusionPresets.adding(preset, to: once), once)
        XCTAssertEqual(Set(LightExclusionPresets.all.map(\.id)).count, LightExclusionPresets.all.count)
    }
}
