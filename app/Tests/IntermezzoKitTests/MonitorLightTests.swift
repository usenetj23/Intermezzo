import XCTest
@testable import IntermezzoKit

final class MonitorLightTests: XCTestCase {
    private let seen = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var recommended: LightSettings { LightProfile.recommended.settings(wakeMinutes: 6 * 60 + 30) }

    private func profile(warmestK: Double? = nil, dimPercent: Int? = nil, untouched: Bool = false) -> MonitorProfile {
        MonitorProfile(name: "Test", warmestK: warmestK, dimPercent: dimPercent, untouched: untouched, lastSeen: seen)
    }

    // MARK: key

    func testKeyIdIsStableHex() {
        XCTAssertEqual(MonitorKey(vendor: 0x10AC, model: 0xA0F3).id, "000010ac-0000a0f3")
    }

    func testKeyIdentifiable() {
        XCTAssertFalse(MonitorKey(vendor: 0, model: 5).isIdentifiable)
        XCTAssertFalse(MonitorKey(vendor: 5, model: 0).isIdentifiable)
        XCTAssertFalse(MonitorKey(vendor: 0xFFFF_FFFF, model: 5).isIdentifiable)
        XCTAssertFalse(MonitorKey(vendor: 5, model: 0xFFFF_FFFF).isIdentifiable)
        XCTAssertTrue(MonitorKey(vendor: 0x10AC, model: 0xA0F3).isIdentifiable)
    }

    func testKeyParsesItsOwnId() {
        let key = MonitorKey(vendor: 0x10AC, model: 0xA0F3)
        XCTAssertEqual(MonitorKey(id: key.id), key)
        XCTAssertNil(MonitorKey(id: "nonsense"))
        XCTAssertNil(MonitorKey(id: "000010ac-zzzz"))
    }

    // MARK: colour

    func testNoProfileKeepsGlobalKelvin() {
        XCTAssertEqual(MonitorLight.kelvin(global: 2000, profile: nil), 2000)
    }

    func testWarmestLimitRaisesOnlyWarmerThanLimit() {
        let p = profile(warmestK: 2700)
        XCTAssertEqual(MonitorLight.kelvin(global: 2000, profile: p), 2700)
        XCTAssertEqual(MonitorLight.kelvin(global: 4000, profile: p), 4000)
    }

    func testUntouchedIsNeutral() {
        XCTAssertEqual(MonitorLight.kelvin(global: 2000, profile: profile(untouched: true)), 6500)
        XCTAssertEqual(MonitorLight.kelvin(global: 2000, profile: profile(warmestK: 2700, untouched: true)), 6500)
    }

    func testWarmestOutOfRangeIsClamped() {
        XCTAssertEqual(MonitorLight.kelvin(global: 1500, profile: profile(warmestK: 100)), 1500)
        XCTAssertEqual(MonitorLight.kelvin(global: 2000, profile: profile(warmestK: 9000)), 6500)
        XCTAssertEqual(MonitorLight.clampedWarmest(100), 1000)
        XCTAssertEqual(MonitorLight.clampedWarmest(9000), 6500)
    }

    // MARK: dimming

    func testDimFactorWithoutProfileEqualsGlobal() {
        XCTAssertEqual(MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: nil),
                       EveningDimming.factor(kelvin: 1900, settings: recommended, maxDimPercent: 25))
    }

    func testProfilePercentOverridesGlobalAndIsOrdered() {
        let mild = MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 40, profile: profile(dimPercent: 10))
        let strong = MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 5, profile: profile(dimPercent: 25))
        XCTAssertGreaterThan(mild, strong)
        XCTAssertEqual(mild, EveningDimming.factor(kelvin: 1900, settings: recommended, maxDimPercent: 10))
    }

    func testUntouchedDimFactorIsOne() {
        XCTAssertEqual(MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25,
                                              profile: profile(untouched: true)), 1)
    }

    func testDimFactorIgnoresWarmestLimit() {
        let a = MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: profile(warmestK: 2700))
        let b = MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: profile(warmestK: 5000))
        XCTAssertEqual(a, b)
    }

    func testPercentIsClamped() {
        XCTAssertEqual(MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: profile(dimPercent: 0)), 1)
        XCTAssertEqual(MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: profile(dimPercent: -5)), 1)
        XCTAssertEqual(MonitorLight.dimFactor(kelvin: 1900, settings: recommended, globalPercent: 25, profile: profile(dimPercent: 90)),
                       EveningDimming.factor(kelvin: 1900, settings: recommended, maxDimPercent: EveningDimming.maxDimPercent))
        XCTAssertEqual(MonitorLight.clampedDimPercent(-5), 0)
        XCTAssertEqual(MonitorLight.clampedDimPercent(90), EveningDimming.maxDimPercent)
    }

    // MARK: storage

    func testHasOverrides() {
        XCTAssertFalse(profile().hasOverrides)
        XCTAssertFalse(profile(untouched: true).hasOverrides)
        XCTAssertTrue(profile(warmestK: 2700).hasOverrides)
        XCTAssertTrue(profile(dimPercent: 10).hasOverrides)
    }

    func testProfilesRoundTrip() {
        let key = MonitorKey(vendor: 0x10AC, model: 0xA0F3)
        let tv = MonitorKey(vendor: 0x1E6D, model: 0x0001)
        let stored = MonitorProfiles()
            .setting(profile(warmestK: 2700, dimPercent: 10), for: key)
            .setting(profile(untouched: true), for: tv)
        let back = MonitorProfiles.decode(stored.encoded())
        XCTAssertEqual(back, stored)
        XCTAssertEqual(back.profile(for: key)?.warmestK, 2700)
        XCTAssertEqual(back.profile(for: tv)?.untouched, true)
        XCTAssertNil(back.profile(for: tv)?.warmestK)
    }

    func testDecodeGarbageGivesEmpty() {
        XCTAssertEqual(MonitorProfiles.decode(Data("zzz".utf8)), MonitorProfiles())
        XCTAssertEqual(MonitorProfiles.decode(nil), MonitorProfiles())
    }

    func testOneMalformedEntryDoesNotLoseTheOthers() throws {
        let key = MonitorKey(vendor: 0x10AC, model: 0xA0F3)
        let good = MonitorProfiles().setting(profile(warmestK: 2700), for: key)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: good.encoded()) as? [String: Any])
        json["bad"] = ["name": "Broken", "dimPercent": "not a number"]
        let data = try JSONSerialization.data(withJSONObject: json)
        let back = MonitorProfiles.decode(data)
        XCTAssertEqual(back.profile(for: key)?.warmestK, 2700)
        XCTAssertEqual(back.items.count, 1)
    }

    func testChangesReturnCopies() {
        let key = MonitorKey(vendor: 1, model: 2)
        let original = MonitorProfiles()
        let added = original.setting(profile(), for: key)
        XCTAssertTrue(original.items.isEmpty)
        XCTAssertEqual(added.items.count, 1)
        let removed = added.removing(key)
        XCTAssertEqual(added.items.count, 1)
        XCTAssertTrue(removed.items.isEmpty)
    }
}
