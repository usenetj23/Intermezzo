import XCTest
@testable import IntermezzoKit

final class BrightnessDayCurveTests: XCTestCase {
    private func flat(_ p: Double) -> BrightnessDayCurve { BrightnessDayCurve(hourly: Array(repeating: p, count: 24)) }

    func testBandsAreClampedSnappedAndPadded() {
        let c = BrightnessDayCurve(hourly: [0, 140, 42, 43])
        XCTAssertEqual(c.hourly.count, 24)
        XCTAssertEqual(Array(c.hourly.prefix(4)), [5, 100, 40, 45])
        XCTAssertEqual(c.hourly[10], 100)
        XCTAssertEqual(BrightnessDayCurve(hourly: Array(repeating: 50, count: 40)).hourly.count, 24)
    }

    func testValueAtABandCentreIsTheBandValueAndBlendsAcrossMidnight() {
        var c = flat(100)
        c.set(hour: 23, percent: 40)
        c.set(hour: 0, percent: 60)
        XCTAssertEqual(c.percent(atMinuteOfDay: 23 * 60 + 30), 40, accuracy: 1e-9)
        XCTAssertEqual(c.percent(atMinuteOfDay: 0), 50, accuracy: 1e-6)
        XCTAssertEqual(c.percent(atMinuteOfDay: 1440), c.percent(atMinuteOfDay: 0), accuracy: 1e-9)
    }

    func testStandardDayIsBrightByDayAndDimAtNight() {
        let c = BrightnessDayCurve.standard
        XCTAssertEqual(c.hourly[12], 100)
        XCTAssertLessThan(c.hourly[23], c.hourly[12])
        XCTAssertGreaterThanOrEqual(c.hourly.min() ?? 0, BrightnessDayCurve.minPercent)
    }

    func testPaintingFillsTheBandsBetweenTwoPoints() {
        var c = flat(100)
        c.paint(fromBand: 18.5, percent: 100, toBand: 22.5, percent: 40)
        XCTAssertEqual(c.hourly[18], 100)
        XCTAssertEqual(c.hourly[22], 40)
        for band in 19...21 { XCTAssertLessThan(c.hourly[band], c.hourly[band - 1], "band \(band)") }
        c.paint(fromBand: -5, percent: 10, toBand: 40, percent: 10)
        XCTAssertEqual(c.hourly.count, 24)
    }

    func testStorageRoundTrip() {
        var c = flat(100)
        c.set(hour: 22, percent: 35)
        XCTAssertEqual(BrightnessDayCurve.decode(c.encoded), c)
        XCTAssertNil(BrightnessDayCurve.decode(nil))
        XCTAssertNil(BrightnessDayCurve.decode("1,2,3"))
    }
}

final class LuxBrightnessCurveTests: XCTestCase {
    func testBandValuesAreReturnedAtTheirLux() {
        let c = LuxBrightnessCurve.standard
        for (i, lux) in LuxBrightnessCurve.luxPoints.enumerated() {
            XCTAssertEqual(c.percent(lux: lux), c.values[i], accuracy: 1e-9)
        }
    }

    func testInterpolatesOnALogAxisAndClampsAtTheEnds() {
        let c = LuxBrightnessCurve(values: [50, 100, 100, 100, 100, 100])
        // half way between 10 and 30 lx on a log axis is sqrt(300) ≈ 17.3 lx
        XCTAssertEqual(c.percent(lux: (10.0 * 30.0).squareRoot()), 75, accuracy: 1e-6)
        XCTAssertEqual(c.percent(lux: 0), 50, accuracy: 1e-9)
        XCTAssertEqual(c.percent(lux: -3), 50, accuracy: 1e-9)
        XCTAssertEqual(c.percent(lux: 1_000_000), 100, accuracy: 1e-9)
        XCTAssertEqual(c.percent(lux: .nan), 50, accuracy: 1e-9)
    }

    func testValuesAreClampedSnappedAndPadded() {
        let c = LuxBrightnessCurve(values: [1, 400, 62])
        XCTAssertEqual(c.values.count, LuxBrightnessCurve.luxPoints.count)
        XCTAssertEqual(Array(c.values.prefix(3)), [LuxBrightnessCurve.minPercent, LuxBrightnessCurve.maxPercent, 60])
        XCTAssertEqual(c.values[5], 100)
    }

    func testMarkerPositionFollowsTheLogAxis() {
        XCTAssertEqual(LuxBrightnessCurve.position(lux: 10), 0, accuracy: 1e-9)
        XCTAssertEqual(LuxBrightnessCurve.position(lux: 3000), 5, accuracy: 1e-9)
        XCTAssertEqual(LuxBrightnessCurve.position(lux: 100), 2, accuracy: 1e-9)
        XCTAssertEqual(LuxBrightnessCurve.position(lux: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(LuxBrightnessCurve.position(lux: 50_000), 5, accuracy: 1e-9)
    }

    func testStandardGetsBrighterWithTheRoom() {
        let v = LuxBrightnessCurve.standard.values
        for i in 1..<v.count { XCTAssertGreaterThanOrEqual(v[i], v[i - 1]) }
    }

    func testPaintingAndStorage() {
        var c = LuxBrightnessCurve.standard
        c.paint(fromBand: 0.5, percent: 30, toBand: 2.5, percent: 70)
        XCTAssertEqual(c.values[0], 30)
        XCTAssertEqual(c.values[2], 70)
        XCTAssertEqual(LuxBrightnessCurve.decode(c.encoded), c)
        XCTAssertNil(LuxBrightnessCurve.decode("1,2"))
        XCTAssertNil(LuxBrightnessCurve.decode(nil))
    }
}

final class ScreenBrightnessTests: XCTestCase {
    private let day = BrightnessDayCurve(hourly: Array(repeating: 80, count: 24))

    func testWithoutASensorTheHourDecides() {
        XCTAssertEqual(ScreenBrightness.level(minuteOfDay: 600, lux: nil, day: day, room: .standard), 0.8, accuracy: 1e-9)
    }

    func testTheRoomScalesTheHour() {
        let room = LuxBrightnessCurve(values: [50, 50, 50, 50, 50, 50])
        XCTAssertEqual(ScreenBrightness.level(minuteOfDay: 600, lux: 200, day: day, room: room), 0.4, accuracy: 1e-9)
    }

    func testNeverAboveFullOrBelowTheFloor() {
        let bright = LuxBrightnessCurve(values: Array(repeating: 150, count: 6))
        XCTAssertEqual(ScreenBrightness.level(minuteOfDay: 600, lux: 5000, day: day, room: bright), 1, accuracy: 1e-9)
        let dark = LuxBrightnessCurve(values: Array(repeating: 20, count: 6))
        let low = BrightnessDayCurve(hourly: Array(repeating: 5, count: 24))
        XCTAssertEqual(ScreenBrightness.level(minuteOfDay: 600, lux: 1, day: low, room: dark),
                       ScreenBrightness.minimumLevel, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(ScreenBrightness.minimumLevel, 0.05)
    }

    func testMinuteOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let t = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 21, minute: 15, second: 30))!
        XCTAssertEqual(ScreenBrightness.minuteOfDay(t, calendar: cal), 21 * 60 + 15.5, accuracy: 1e-9)
    }

    func testRampMovesAtMostOneStepAndLandsOnTheTarget() {
        XCTAssertEqual(ScreenBrightness.ramp(from: 0.5, to: 0.9, maxStep: 0.1), 0.6, accuracy: 1e-9)
        XCTAssertEqual(ScreenBrightness.ramp(from: 0.5, to: 0.2, maxStep: 0.1), 0.4, accuracy: 1e-9)
        XCTAssertEqual(ScreenBrightness.ramp(from: 0.5, to: 0.55, maxStep: 0.1), 0.55, accuracy: 1e-9)
        XCTAssertEqual(ScreenBrightness.ramp(from: 0.5, to: 0.9, maxStep: -1), 0.5, accuracy: 1e-9)
    }

    func testGoals() {
        XCTAssertNil(DisplayBrightnessGoal.original.wanted(original: 0.7))
        XCTAssertNil(DisplayBrightnessGoal.factor(1).wanted(original: 0.7))
        XCTAssertEqual(DisplayBrightnessGoal.factor(0.5).wanted(original: 0.8) ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(DisplayBrightnessGoal.level(1).wanted(original: 0.3) ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(DisplayBrightnessGoal.level(0).wanted(original: 0.3) ?? -1, ScreenBrightness.minimumLevel, accuracy: 1e-9)
        XCTAssertTrue(DisplayBrightnessGoal.level(0.6).drives)
        XCTAssertTrue(DisplayBrightnessGoal.factor(0.6).drives)
        XCTAssertFalse(DisplayBrightnessGoal.factor(1).drives)
        XCTAssertFalse(DisplayBrightnessGoal.original.drives)
    }

    func testHoldAfterAManualChange() {
        let now = Date()
        XCTAssertTrue(ScreenBrightness.holding(since: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(ScreenBrightness.holding(since: now.addingTimeInterval(-ScreenBrightness.manualHoldSeconds - 1), now: now))
        XCTAssertFalse(ScreenBrightness.holding(since: nil, now: now))
    }
}

final class SyncPolicyBrightnessTests: XCTestCase {
    func testBrightnessSettingsSyncButTheSavedOriginalStaysOnThisMac() {
        XCTAssertTrue(SyncPolicy.isSynced(key: "lightBrightnessEQ"))
        XCTAssertTrue(SyncPolicy.isSynced(key: "lightBrightnessCurve"))
        XCTAssertTrue(SyncPolicy.isSynced(key: "lightLuxCurve"))
        XCTAssertTrue(SyncPolicy.isSynced(key: "lightBrightnessAuto"))
        // per-display settings (incl. typed max nits) live in the monitor profiles, which stay on this Mac
        XCTAssertFalse(SyncPolicy.isSynced(key: "lightMonitors"))
        XCTAssertFalse(SyncPolicy.isSynced(key: "lightBuiltInOriginal"))
    }
}

final class ManualHoldTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var recent: Date { now.addingTimeInterval(-60) }
    private var old: Date { now.addingTimeInterval(-ScreenBrightness.manualHoldSeconds - 1) }

    func testAnEqualizerHoldSurvivesAnExceptionAPauseOrAPreview() {
        // an exception, a pause or a preview turn the goal into "original" for a while: the hold must stay
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: recent, goal: .original, now: now), .keep)
        // and when the equaliser drives again, the hold still keeps its hands off
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: recent, goal: .level(0.5), now: now), .keep)
    }

    func testAnEqualizerHoldEndsAfterTheHoldTime() {
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: old, goal: .level(0.5), now: now), .drop)
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: old, goal: .original, now: now), .drop)
    }

    func testAnEqualizerHoldEndsWhenTheEqualizerIsOff() {
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: recent, goal: .factor(0.8), now: now), .drop)
    }

    func testAnEveningHoldLastsUntilTheEveningEnds() {
        XCTAssertEqual(ManualHold.decision(kind: .evening, since: old, goal: .factor(0.8), now: now), .keep)
        XCTAssertEqual(ManualHold.decision(kind: .evening, since: recent, goal: .factor(1), now: now), .drop)
        XCTAssertEqual(ManualHold.decision(kind: .evening, since: recent, goal: .original, now: now), .drop)
        XCTAssertEqual(ManualHold.decision(kind: .evening, since: recent, goal: .level(0.5), now: now), .drop)
    }

    func testAnotherMechanismOwnsTheDisplay() {
        XCTAssertNil(DisplayBrightnessGoal.elsewhere.wanted(original: 0.7))
        XCTAssertFalse(DisplayBrightnessGoal.elsewhere.drives)
        XCTAssertEqual(ManualHold.decision(kind: .equalizer, since: recent, goal: .elsewhere, now: now), .drop)
    }
}

final class SavedBrightnessTests: XCTestCase {
    func testOldFormatIsJustTheOriginal() {
        XCTAssertEqual(SavedBrightness(plist: 0.62), SavedBrightness(original: 0.62, lastSet: nil))
    }

    func testRoundTripWithLastSet() {
        let saved = SavedBrightness(original: 0.7, lastSet: 0.45)
        XCTAssertEqual(SavedBrightness(plist: saved.plist), saved)
        XCTAssertEqual(SavedBrightness(plist: SavedBrightness(original: 0.7, lastSet: nil).plist)?.lastSet, nil)
    }

    func testUnreadableValuesAreNothing() {
        XCTAssertNil(SavedBrightness(plist: nil))
        XCTAssertNil(SavedBrightness(plist: "x"))
        XCTAssertNil(SavedBrightness(plist: ["lastSet": 0.4]))
        XCTAssertNil(SavedBrightness(plist: Double.nan))
    }

    func testRestoreAfterARestartOnlyWhenTheUserDidNotTouchIt() {
        let saved = SavedBrightness(original: 0.8, lastSet: 0.4)
        XCTAssertTrue(saved.mayRestore(current: 0.41))
        XCTAssertFalse(saved.mayRestore(current: 0.7))
        XCTAssertTrue(SavedBrightness(original: 0.8, lastSet: nil).mayRestore(current: 0.1))
    }
}

final class EqualizerBandsSafetyTests: XCTestCase {
    func testNonFiniteInputsDoNotCrash() {
        let c = BrightnessDayCurve.standard
        XCTAssertTrue(c.percent(atMinuteOfDay: .nan).isFinite)
        XCTAssertTrue(c.percent(atMinuteOfDay: .infinity).isFinite)
        var d = c
        d.paint(fromBand: -1e300, percent: 50, toBand: 1e300, percent: 50)
        XCTAssertEqual(d.hourly, Array(repeating: 50, count: 24))
        d.paint(fromBand: .nan, percent: 10, toBand: 3, percent: 10)
        XCTAssertEqual(d.hourly[3], 50)
    }

    func testBrightnessSourceToleratesANonTextValue() throws {
        let json = #"{"000010ac-00004335":{"name":"DELL","untouched":false,"lastSeen":"2026-01-01T00:00:00Z","brightnessSource":7}}"#
        let p = MonitorProfiles.decode(Data(json.utf8)).profile(for: MonitorKey(vendor: 0x10AC, model: 0x4335))
        XCTAssertEqual(p?.brightnessSource, .automatic)
    }
}

final class BrightnessHandoverTests: XCTestCase {
    func testTheDimmingsOriginalIsHandedOverWhenTheScreenStillShowsWhatWasSet() {
        // the evening dimming took the screen from 0.8 to 0.6; the equaliser takes over
        XCTAssertEqual(BrightnessHandover.originalToHandOver(original: 0.8, lastSet: 0.6, current: 0.61), 0.8)
        XCTAssertEqual(BrightnessHandover.originalToHandOver(original: 0.8, lastSet: nil, current: 0.3), 0.8)
    }

    func testNothingIsHandedOverAfterAManualChangeOrWithoutAnOriginal() {
        XCTAssertNil(BrightnessHandover.originalToHandOver(original: 0.8, lastSet: 0.6, current: 0.9))
        XCTAssertNil(BrightnessHandover.originalToHandOver(original: nil, lastSet: 0.6, current: 0.6))
    }

    func testTheTakersOwnGlideIsNotAManualChange() {
        // the equaliser already moved the screen from 0.6 to 0.5 before the dimming let go
        XCTAssertEqual(BrightnessHandover.originalToHandOver(original: 0.8, lastSet: 0.6, current: 0.5, takerLastSet: 0.5), 0.8)
        XCTAssertNil(BrightnessHandover.originalToHandOver(original: 0.8, lastSet: 0.6, current: 0.9, takerLastSet: 0.5))
    }

    func testAHandedOverOriginalWinsOverWhatTheTakerReadItself() {
        // the equaliser read 0.6 (already dimmed) as its original; the dimming's 0.8 is the real one
        XCTAssertEqual(BrightnessHandover.adopted(own: 0.6, handedOver: 0.8), 0.8)
        XCTAssertEqual(BrightnessHandover.adopted(own: nil, handedOver: 0.8), 0.8)
        XCTAssertEqual(BrightnessHandover.adopted(own: 0.6, handedOver: nil), 0.6)
        XCTAssertNil(BrightnessHandover.adopted(own: nil, handedOver: .nan))
    }

    func testTheEqualizerKeepsTheBuiltInWhileItStillHasSomethingToGiveBack() {
        XCTAssertTrue(BrightnessHandover.keepsBuiltIn(equalizerActive: true, hasOriginal: false, restoring: false))
        XCTAssertTrue(BrightnessHandover.keepsBuiltIn(equalizerActive: false, hasOriginal: true, restoring: false))
        XCTAssertTrue(BrightnessHandover.keepsBuiltIn(equalizerActive: false, hasOriginal: false, restoring: true))
        XCTAssertFalse(BrightnessHandover.keepsBuiltIn(equalizerActive: false, hasOriginal: false, restoring: false))
    }

    func testAfterAWakeTheFirstReadingBecomesTheLastValueSet() {
        // no last value (woke up): the current reading is taken, no manual change is assumed
        XCTAssertEqual(BrightnessHandover.lastSetAfterCheck(lastSet: nil, current: 0.42), 0.42)
        XCTAssertEqual(BrightnessHandover.lastSetAfterCheck(lastSet: 0.5, current: 0.42), 0.5)
    }
}
