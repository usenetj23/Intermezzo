import XCTest
@testable import IntermezzoKit

final class KeepAwakeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let safety = KeepAwakeSafety(batteryFloorPercent: 20, stopOnLowPowerMode: true, stopOnThermal: true)
    private func power(battery: Int? = 80, onBattery: Bool = true, lowPower: Bool = false,
                       thermal: ThermalLevel = .nominal) -> PowerConditions {
        PowerConditions(onBattery: onBattery, batteryPercent: battery, lowPowerMode: lowPower, thermal: thermal)
    }

    func testHoldsWithoutEndUntilStopped() {
        let r = KeepAwakePolicy.manual(request: KeepAwakeRequest(level: .system, until: nil), safety: safety,
                                       power: power(), now: now)
        XCTAssertEqual(r, .hold(.system))
    }

    func testNoRequestReleasesWithoutReason() {
        XCTAssertEqual(KeepAwakePolicy.manual(request: nil, safety: safety, power: power(), now: now), .release(nil))
    }

    func testTimerEnds() {
        let request = KeepAwakeRequest(level: .systemAndDisplay, until: now.addingTimeInterval(600))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(), now: now), .hold(.systemAndDisplay))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(),
                                              now: now.addingTimeInterval(600)), .release(.timerEnded))
    }

    func testBatteryFloorOnlyOnBattery() {
        let request = KeepAwakeRequest(level: .system, until: nil)
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(battery: 20), now: now), .release(.batteryLow))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(battery: 21), now: now), .hold(.system))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(battery: 5, onBattery: false), now: now), .hold(.system))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request,
                                              safety: KeepAwakeSafety(batteryFloorPercent: 0, stopOnLowPowerMode: false, stopOnThermal: false),
                                              power: power(battery: 3), now: now), .hold(.system))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(battery: nil), now: now), .hold(.system))
    }

    func testLowPowerModeAndThermal() {
        let request = KeepAwakeRequest(level: .system, until: nil)
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(lowPower: true), now: now), .release(.lowPowerMode))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(onBattery: false, lowPower: true), now: now), .hold(.system))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(thermal: .fair), now: now), .hold(.system))
        XCTAssertEqual(KeepAwakePolicy.manual(request: request, safety: safety, power: power(thermal: .serious), now: now), .release(.thermal))
    }

    func testStopReasonPriority() {
        let request = KeepAwakeRequest(level: .system, until: now)
        let r = KeepAwakePolicy.manual(request: request, safety: safety,
                                       power: power(battery: 5, lowPower: true, thermal: .critical), now: now)
        XCTAssertEqual(r, .release(.timerEnded))
        let r2 = KeepAwakePolicy.manual(request: KeepAwakeRequest(level: .system, until: nil), safety: safety,
                                        power: power(battery: 5, lowPower: true, thermal: .critical), now: now)
        XCTAssertEqual(r2, .release(.thermal))
    }

    func testAutomaticHoldsHonourSafetyButHaveNoTimer() {
        XCTAssertEqual(KeepAwakePolicy.automatic(wanted: .system, safety: safety, power: power()), .system)
        XCTAssertNil(KeepAwakePolicy.automatic(wanted: .system, safety: safety, power: power(battery: 10)))
        XCTAssertNil(KeepAwakePolicy.automatic(wanted: nil, safety: safety, power: power()))
    }

    func testCombineTakesTheStrongest() {
        XCTAssertNil(KeepAwakePolicy.combine([]))
        XCTAssertEqual(KeepAwakePolicy.combine([.system]), .system)
        XCTAssertEqual(KeepAwakePolicy.combine([.system, .systemAndDisplay, .system]), .systemAndDisplay)
    }

    func testDurations() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let t = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 14, minute: 20))!
        XCTAssertEqual(KeepAwakeDuration.minutes(30).end(from: t, calendar: cal), t.addingTimeInterval(1800))
        XCTAssertNil(KeepAwakeDuration.indefinitely.end(from: t, calendar: cal))
        let untilFive = KeepAwakeDuration.untilHour(17).end(from: t, calendar: cal)!
        XCTAssertEqual(cal.component(.hour, from: untilFive), 17)
        XCTAssertEqual(cal.component(.minute, from: untilFive), 0)
        // the hour has passed today: tomorrow
        let untilNine = KeepAwakeDuration.untilHour(9).end(from: t, calendar: cal)!
        XCTAssertEqual(cal.component(.day, from: untilNine), 26)
    }

    func testNextWholeHours() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let t = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 14, minute: 20))!
        XCTAssertEqual(KeepAwakeDuration.nextWholeHours(count: 3, from: t, calendar: cal), [15, 16, 17])
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 22, minute: 5))!
        XCTAssertEqual(KeepAwakeDuration.nextWholeHours(count: 3, from: late, calendar: cal), [23, 0, 1])
    }

    func testParsesPmsetAssertions() {
        let text = """
        2026-10-25 09:00:00 +0200
        Assertion status system-wide:
           PreventUserIdleSystemSleep     1
        Listed by owning process:
           pid 421(coreaudiod): [0x000000010000abcd] 01:02:03 PreventUserIdleSystemSleep named: "com.apple.audio.context1.preventuseridlesleep"
           \tTimeout will fire in 600 secs Action=TimeoutActionRelease
           pid 77(caffeinate): [0x000000010000ef01] 00:00:09 PreventUserIdleDisplaySleep named: "caffeinate command-line tool"
        Kernel Assertions: 0x4=USB
        """
        let list = PmsetAssertions.parse(text)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].process, "coreaudiod")
        XCTAssertEqual(list[0].pid, 421)
        XCTAssertEqual(list[1].type, "PreventUserIdleDisplaySleep")
        XCTAssertEqual(list[1].reason, "caffeinate command-line tool")
        XCTAssertEqual(PmsetAssertions.parse("nothing here").count, 0)
        XCTAssertEqual(PmsetAssertions.parse(text, excluding: 77).map(\.process), ["coreaudiod"])
    }
}

final class KeepAwakeAppsTests: XCTestCase {
    func testMatchesIgnoringCaseAndExtension() {
        XCTAssertEqual(KeepAwakeApps.firstMatch(wanted: ["OBS", "Zoom.app"], running: ["Finder", "zoom.us", "zoom"]), "Zoom.app")
        XCTAssertEqual(KeepAwakeApps.firstMatch(wanted: ["obs64.exe"], running: ["OBS64"]), "obs64.exe")
        XCTAssertNil(KeepAwakeApps.firstMatch(wanted: ["Slack"], running: ["Finder"]))
        XCTAssertNil(KeepAwakeApps.firstMatch(wanted: [], running: ["Finder"]))
    }

    func testParsesCommaText() {
        XCTAssertEqual(KeepAwakeApps.list(fromCommaText: " OBS , ,Xcode,"), ["OBS", "Xcode"])
    }
}
