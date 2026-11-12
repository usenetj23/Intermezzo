import XCTest
@testable import IntermezzoKit

final class EDIDInfoTests: XCTestCase {
    /// A base block for vendor DEL (0x10AC), product 0x4335, with one CTA extension.
    private func edid(hdrMaxCV: UInt8?) -> [UInt8] {
        var base = [UInt8](repeating: 0, count: 128)
        base[0...7] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        base[8] = 0x10; base[9] = 0xAC
        base[10] = 0x35; base[11] = 0x43
        base[126] = 1
        var cta = [UInt8](repeating: 0, count: 128)
        cta[0] = 0x02; cta[1] = 0x03
        var blocks: [UInt8] = [0x42, 0x10, 0x04]                  // video data block (tag 2, 2 bytes)
        if let cv = hdrMaxCV { blocks += [0xE6, 0x06, 0x05, 0x01, cv, 0x50, 0x00] }  // extended tag 6, length 6
        cta[2] = UInt8(4 + blocks.count)
        cta.replaceSubrange(4..<(4 + blocks.count), with: blocks)
        return base + cta
    }

    func testKeyFromTheBaseBlock() {
        XCTAssertEqual(EDIDInfo.key(edid(hdrMaxCV: nil)), MonitorKey(vendor: 0x10AC, model: 0x4335))
        XCTAssertNil(EDIDInfo.key([0, 1, 2]))
        XCTAssertNil(EDIDInfo.key([UInt8](repeating: 0, count: 128)))
    }

    func testMaxLuminanceFromHDRStaticMetadata() {
        // CV 96: 50 × 2^(96/32) = 400 nits
        XCTAssertEqual(EDIDInfo.maxLuminance(edid(hdrMaxCV: 96)) ?? 0, 400, accuracy: 1e-9)
        XCTAssertNil(EDIDInfo.maxLuminance(edid(hdrMaxCV: nil)))
        XCTAssertNil(EDIDInfo.maxLuminance(edid(hdrMaxCV: 0)), "0 means not given")
        XCTAssertNil(EDIDInfo.maxLuminance(Array(edid(hdrMaxCV: 96).prefix(128))), "no extension block")
        XCTAssertNil(EDIDInfo.maxLuminance([0x00, 0xFF]))
    }

    func testTruncatedExtensionDoesNotCrash() {
        let full = edid(hdrMaxCV: 96)
        for cut in 128..<full.count { _ = EDIDInfo.maxLuminance(Array(full.prefix(cut))) }
    }
}

final class BuiltInNitsTests: XCTestCase {
    func testSliderToLinearIsAPowerCurve() {
        XCTAssertEqual(BuiltInNits.linear(fromSlider: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(BuiltInNits.linear(fromSlider: 1), 1, accuracy: 1e-12)
        // measured on a MacBook Pro: slider 0.60 gave linear 0.278
        XCTAssertEqual(BuiltInNits.linear(fromSlider: 0.6), 0.278, accuracy: 0.01)
        XCTAssertEqual(BuiltInNits.linear(fromSlider: 2), 1, accuracy: 1e-12)
        XCTAssertEqual(BuiltInNits.linear(fromSlider: -1), 0, accuracy: 1e-12)
    }

    func testFixedPoint1616LittleEndian() {
        XCTAssertEqual(BuiltInNits.fixed1616([0x00, 0x00, 0x58, 0x02]) ?? 0, 600, accuracy: 1e-9)
        XCTAssertEqual(BuiltInNits.fixed1616([0x00, 0x80, 0xE8, 0x03]) ?? 0, 1000.5, accuracy: 1e-9)
        XCTAssertNil(BuiltInNits.fixed1616([0x01, 0x02]))
    }

    func testBacklightReadingIsPreferredAndHeadroomIsTakenOut() {
        let n = BuiltInNits.sdrNits(backlightMilliNits: 382_000, headroom: 1.2, linear: 0.3, slider: 0.6, maxNits: 600)
        XCTAssertEqual(n ?? 0, 382 / 1.2, accuracy: 1e-6)
        // no headroom known (or below 1): the backlight is the white
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 300_000, headroom: nil, linear: nil, slider: nil, maxNits: nil) ?? 0, 300, accuracy: 1e-9)
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 300_000, headroom: 0.5, linear: nil, slider: nil, maxNits: nil) ?? 0, 300, accuracy: 1e-9)
    }

    private let six: [UInt8] = [0x00, 0x00, 0x58, 0x02]       // 600 in 16.16
    private let thousand: [UInt8] = [0x00, 0x00, 0xE8, 0x03]  // 1000 in 16.16

    func testNominalIsTheBacklightsValueAndTheCeilingTheLargest() {
        // M5 Max: "backlight" 600 (macOS's Max SDR Luminance), "backlight-override" 1000 (outdoor ceiling)
        let limits = BuiltInNits.sdrLimits(backlight: six, declared: [thousand, six])
        XCTAssertEqual(limits, BuiltInNits.SDRLimits(nominal: 600, ceiling: 1000))
        // without the backlight's own value the smallest declared one is the nominal
        XCTAssertEqual(BuiltInNits.sdrLimits(backlight: nil, declared: [thousand, six]),
                       BuiltInNits.SDRLimits(nominal: 600, ceiling: 1000))
        // one value: nominal and ceiling are the same
        XCTAssertEqual(BuiltInNits.sdrLimits(backlight: six, declared: []), BuiltInNits.SDRLimits(nominal: 600, ceiling: 600))
        // unreadable or zero entries are ignored; nothing usable is nil
        XCTAssertEqual(BuiltInNits.sdrLimits(backlight: [0, 0, 0, 0], declared: [[0x01], six]),
                       BuiltInNits.SDRLimits(nominal: 600, ceiling: 600))
        XCTAssertNil(BuiltInNits.sdrLimits(backlight: nil, declared: []))
        XCTAssertNil(BuiltInNits.sdrLimits(backlight: [0, 0, 0, 0], declared: [[0, 0, 0, 0]]))
    }

    func testMeasuredNitsAreCutAtTheOutdoorCeilingNotAtTheNominal() {
        // a bright day: 900 nits of SDR white on a 600-nominal / 1000-ceiling panel stays 900
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 900_000, headroom: 1, linear: nil, slider: nil,
                                           maxNits: 600, ceiling: 1000) ?? 0, 900, accuracy: 1e-9)
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 1_400_000, headroom: 1, linear: nil, slider: nil,
                                           maxNits: 600, ceiling: 1000) ?? 0, 1000, accuracy: 1e-9)
        // the fallbacks use the nominal maximum
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: nil, headroom: nil, linear: 0.5, slider: nil,
                                           maxNits: 600, ceiling: 1000) ?? 0, 300, accuracy: 1e-9)
    }

    func testEffectiveMaximumRisesToTheCeilingInOutdoorMode() {
        let limits = BuiltInNits.SDRLimits(nominal: 600, ceiling: 1000)
        XCTAssertEqual(BuiltInNits.effectiveMax(limits, measuredNits: 400), 600)
        XCTAssertEqual(BuiltInNits.effectiveMax(limits, measuredNits: 600), 600)
        XCTAssertEqual(BuiltInNits.effectiveMax(limits, measuredNits: 750), 1000)
        XCTAssertEqual(BuiltInNits.effectiveMax(limits, measuredNits: nil), 600)
    }

    func testNeverAboveTheUserMaximum() {
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 1_500_000, headroom: 1, linear: nil, slider: nil, maxNits: 600) ?? 0, 600, accuracy: 1e-9)
    }

    func testFallsBackToLinearThenSlider() {
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: nil, headroom: nil, linear: 0.5, slider: 0.9, maxNits: 500) ?? 0, 250, accuracy: 1e-9)
        XCTAssertEqual(BuiltInNits.sdrNits(backlightMilliNits: 0, headroom: nil, linear: nil, slider: 1, maxNits: 500) ?? 0, 500, accuracy: 1e-9)
        XCTAssertNil(BuiltInNits.sdrNits(backlightMilliNits: nil, headroom: nil, linear: 0.5, slider: nil, maxNits: nil))
        XCTAssertNil(BuiltInNits.sdrNits(backlightMilliNits: .nan, headroom: nil, linear: nil, slider: nil, maxNits: 500))
    }
}

final class PeerBrightnessTests: XCTestCase {
    private let seen = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func profile(source: BrightnessSource? = nil, scale: Int? = nil, min: Int? = nil, max: Int? = nil,
                         maxNits: Int? = nil, untouched: Bool = false) -> MonitorProfile {
        MonitorProfile(name: "M", untouched: untouched, lastSeen: seen, brightnessSource: source, brightnessScale: scale,
                       brightnessMinPercent: min, brightnessMaxPercent: max, maxNits: maxNits)
    }

    private func resolve(builtIn: Bool = false, _ p: MonitorProfile?, automatic: Bool = false, eq: Double = 0.6,
                         nits: Double? = nil, detected: Double? = nil) -> PeerBrightness.Resolution {
        PeerBrightness.resolve(isBuiltIn: builtIn, profile: p, automatic: automatic, equalizerLevel: eq,
                               builtInNits: nits, detectedMaxNits: detected)
    }

    func testLimitsAndScale() {
        XCTAssertEqual(PeerBrightness.limited(0.6, profile: nil), 0.6, accuracy: 1e-9)
        XCTAssertEqual(PeerBrightness.limited(0.6, profile: profile(scale: 50)), 0.3, accuracy: 1e-9)
        XCTAssertEqual(PeerBrightness.limited(0.6, profile: profile(max: 40)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(PeerBrightness.limited(0.1, profile: profile(min: 30)), 0.3, accuracy: 1e-9)
        XCTAssertEqual(PeerBrightness.limited(0.9, profile: profile(scale: 200)), 1, accuracy: 1e-9)
        // a minimum above the maximum gives way to the maximum; never below the global floor
        XCTAssertEqual(PeerBrightness.limited(0.9, profile: profile(min: 80, max: 50)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PeerBrightness.limited(0.01, profile: profile(min: 0)), ScreenBrightness.minimumLevel, accuracy: 1e-9)
    }

    func testEqualizerForEveryDisplayWithoutAutomatic() {
        XCTAssertEqual(resolve(nil), .init(goal: .level(0.6), kind: .equalizer))
        XCTAssertEqual(resolve(builtIn: true, nil), .init(goal: .level(0.6), kind: .equalizer))
    }

    func testLeftAloneAndOff() {
        XCTAssertEqual(resolve(profile(untouched: true), automatic: true, nits: 300), .init(goal: .original, kind: .untouched))
        XCTAssertEqual(resolve(profile(source: .off)), .init(goal: .original, kind: .off))
        XCTAssertEqual(resolve(builtIn: true, profile(source: .off)), .init(goal: .original, kind: .off))
    }

    func testAutomaticLeavesTheBuiltInToApple() {
        XCTAssertEqual(resolve(builtIn: true, nil, automatic: true, nits: 300), .init(goal: .original, kind: .apple))
        XCTAssertEqual(resolve(builtIn: true, profile(source: .equalizer), automatic: true, nits: 300),
                       .init(goal: .original, kind: .apple))
    }

    func testExternalFollowsTheBuiltInNits() {
        // 300 nits on the built-in, a 400-nit monitor: 75 %
        XCTAssertEqual(resolve(nil, automatic: true, nits: 300, detected: 400),
                       .init(goal: .level(0.75), kind: .followsBuiltIn(nits: 300)))
        // the hand-entered maximum wins over the EDID
        XCTAssertEqual(resolve(profile(maxNits: 600), automatic: true, nits: 300, detected: 400).goal, .level(0.5))
        // nothing known: the default maximum
        XCTAssertEqual(resolve(nil, automatic: true, nits: 175).goal, .level(175 / PeerBrightness.defaultExternalMaxNits))
        // brighter than the monitor can go: full; own limits still apply
        XCTAssertEqual(resolve(nil, automatic: true, nits: 900, detected: 400).goal, .level(1))
        XCTAssertEqual(resolve(profile(max: 80), automatic: true, nits: 900, detected: 400).goal, .level(0.8))
    }

    func testExternalCanStayOnTheEqualizer() {
        XCTAssertEqual(resolve(profile(source: .equalizer), automatic: true, nits: 300, detected: 400),
                       .init(goal: .level(0.6), kind: .equalizer))
    }

    func testWithoutAReferenceTheEqualizerTakesOver() {
        XCTAssertEqual(resolve(nil, automatic: true, nits: nil, detected: 400), .init(goal: .level(0.6), kind: .equalizer))
        XCTAssertEqual(resolve(nil, automatic: true, nits: 0, detected: 400).kind, .equalizer)
    }
}

final class MonitorProfileBrightnessTests: XCTestCase {
    func testOldProfilesStillDecode() {
        let json = #"{"000010ac-00004335":{"name":"DELL","untouched":false,"lastSeen":"2026-01-01T00:00:00Z","dimPercent":20}}"#
        let profiles = MonitorProfiles.decode(Data(json.utf8))
        let p = profiles.profile(for: MonitorKey(vendor: 0x10AC, model: 0x4335))
        XCTAssertEqual(p?.dimPercent, 20)
        XCTAssertNil(p?.brightnessSource)
        XCTAssertNil(p?.maxNits)
    }

    func testUnknownSourceFallsBackToAutomaticInsteadOfLosingTheProfile() {
        let json = #"{"000010ac-00004335":{"name":"DELL","untouched":false,"lastSeen":"2026-01-01T00:00:00Z","brightnessSource":"future"}}"#
        let p = MonitorProfiles.decode(Data(json.utf8)).profile(for: MonitorKey(vendor: 0x10AC, model: 0x4335))
        XCTAssertEqual(p?.brightnessSource, .automatic)
    }

    func testRoundTripWithBrightnessSettings() {
        let key = MonitorKey(vendor: 1, model: 2)
        let p = MonitorProfile(name: "X", lastSeen: Date(timeIntervalSince1970: 1_800_000_000), brightnessSource: .equalizer,
                               brightnessScale: 90, brightnessMinPercent: 20, brightnessMaxPercent: 80, maxNits: 450)
        let decoded = MonitorProfiles.decode(MonitorProfiles().setting(p, for: key).encoded()).profile(for: key)
        XCTAssertEqual(decoded, p)
        XCTAssertTrue(p.hasOverrides)
    }

    func testSanitizedBrightnessKeepsValuesInRange() {
        var p = MonitorProfile(name: "X", lastSeen: Date(), brightnessScale: 900, brightnessMinPercent: -5,
                               brightnessMaxPercent: 400, maxNits: 5)
        p = MonitorLight.sanitizedBrightness(p)
        XCTAssertEqual(p.brightnessScale, PeerBrightness.scaleRange.upperBound)
        XCTAssertEqual(p.brightnessMinPercent, PeerBrightness.percentRange.lowerBound)
        XCTAssertEqual(p.brightnessMaxPercent, PeerBrightness.percentRange.upperBound)
        XCTAssertEqual(p.maxNits, PeerBrightness.nitsRange.lowerBound)
    }
}
