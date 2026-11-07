import XCTest
@testable import IntermezzoKit

final class AutomationStateTests: XCTestCase {
    private func state(_ configure: (inout AutomationState) -> Void = { _ in }) -> AutomationState {
        var s = AutomationState()
        s.timer = "running"
        configure(&s)
        return s
    }

    // MARK: State

    func testJSONRoundTripKeepsEveryField() {
        var s = state {
            $0.appVersion = "1.43.0"
            $0.pauseReasons = ["inMeeting"]
            $0.nextBreakAt = Date(timeIntervalSince1970: 1_800_000_000)
            $0.inWorkZone = true
            $0.workZoneSources = ["vpn", "lan"]
            $0.focusModes = ["Praca"]
            $0.lightKelvin = 4200
            $0.updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        }
        s.keepAwake = true
        let back = AutomationState.decode(s.jsonData())
        XCTAssertEqual(back, s)
    }

    func testJSONUsesReadableKeysAndISODates() {
        let text = state { $0.nextBreakAt = Date(timeIntervalSince1970: 0) }.jsonString()
        XCTAssertTrue(text.contains("\"timer\" : \"running\""))
        XCTAssertTrue(text.contains("1970-01-01T00:00:00Z"))
    }

    func testARefreshedStampAloneIsNotAChange() {
        var a = state(), b = state()
        a.updatedAt = Date(timeIntervalSince1970: 1)
        b.updatedAt = Date(timeIntervalSince1970: 99)
        XCTAssertTrue(a.sameContent(as: b))
        b.away = true
        XCTAssertFalse(a.sameContent(as: b))
    }

    // MARK: Events

    func testEventsFollowTheChangesBetweenTwoStates() {
        let base = state { $0.inWorkZone = false }
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.timer = "paused"; $0.inWorkZone = false }), [.timerPaused])
        XCTAssertEqual(AutomationEvent.diff(from: state { $0.timer = "paused" }, to: base), [.timerResumed])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = true }), [.zoneEntered])
        XCTAssertEqual(AutomationEvent.diff(from: state { $0.inWorkZone = true }, to: base), [.zoneLeft])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = false; $0.inMeeting = true }), [.meetingBegan])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = false; $0.focusActive = true }), [.focusOn])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = false; $0.away = true }), [.awayBegan])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = false; $0.screenLocked = true }), [.screenLocked])
        XCTAssertEqual(AutomationEvent.diff(from: base, to: state { $0.inWorkZone = false; $0.vpnConnected = true }), [.vpnConnected])
    }

    func testNoChangeAndAnUnknownZoneGiveNoEvents() {
        XCTAssertTrue(AutomationEvent.diff(from: state(), to: state()).isEmpty)
        // The zone becoming known or unknown (a source switched on or off) is not entering or leaving it.
        XCTAssertTrue(AutomationEvent.diff(from: state(), to: state { $0.inWorkZone = true }).isEmpty)
        XCTAssertTrue(AutomationEvent.diff(from: state { $0.inWorkZone = false }, to: state()).isEmpty)
    }

    func testBreakEventsHaveNoTriggerAndTheOthersMapToABreakActionTrigger() {
        for event in AutomationEvent.allCases {
            switch event {
            case .breakBegan, .breakCompleted, .breakSkipped, .breakPostponed: XCTAssertNil(event.trigger)
            default: XCTAssertEqual(event.trigger?.isEventTrigger, true, event.rawValue)
            }
        }
        XCTAssertFalse(BreakActionWhen.afterStart.isEventTrigger)
        XCTAssertFalse(BreakActionWhen.buttonClicked.isEventTrigger)
    }

    // MARK: Conditions

    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testNoConditionsAlwaysAllow() {
        XCTAssertTrue(ActionConditions().allows(state: nil, lastRun: nil, now: now))
        XCTAssertTrue(ActionConditions().allows(state: state(), lastRun: now, now: now))
    }

    func testZoneMeetingAndLockConditions() {
        var inside = ActionConditions(); inside.zone = .inside
        XCTAssertTrue(inside.allows(state: state { $0.inWorkZone = true }, lastRun: nil, now: now))
        XCTAssertFalse(inside.allows(state: state { $0.inWorkZone = false }, lastRun: nil, now: now))
        XCTAssertFalse(inside.allows(state: state(), lastRun: nil, now: now))          // zone unknown
        var outside = ActionConditions(); outside.zone = .outside
        XCTAssertTrue(outside.allows(state: state { $0.inWorkZone = false }, lastRun: nil, now: now))
        XCTAssertFalse(outside.allows(state: state { $0.inWorkZone = true }, lastRun: nil, now: now))
        var quiet = ActionConditions(); quiet.notInMeeting = true; quiet.screenUnlocked = true
        XCTAssertTrue(quiet.allows(state: state(), lastRun: nil, now: now))
        XCTAssertFalse(quiet.allows(state: state { $0.inMeeting = true }, lastRun: nil, now: now))
        XCTAssertFalse(quiet.allows(state: state { $0.screenLocked = true }, lastRun: nil, now: now))
        XCTAssertFalse(quiet.allows(state: nil, lastRun: nil, now: now))                 // needs a state
    }

    func testCooldownCountsFromTheLastRun() {
        var c = ActionConditions(); c.cooldownSeconds = 60
        XCTAssertTrue(c.allows(state: nil, lastRun: nil, now: now))
        XCTAssertFalse(c.allows(state: nil, lastRun: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(c.allows(state: nil, lastRun: now.addingTimeInterval(-61), now: now))
    }

    func testConditionsSurviveEncodingAndOldJSONGetsNone() throws {
        var item = BreakActionItem()
        item.kind = .runShortcut
        item.shortcutName = "Focus Work"
        item.when = .zoneEntered
        item.conditions.zone = .inside
        item.conditions.cooldownSeconds = 120
        let data = BreakActionStore.encode([item])!
        let back = BreakActionStore.decode(data)!
        XCTAssertEqual(back, [item])
        // An action saved by an older version has none of the new fields.
        let old = Data(#"[{"kind":"notification","when":"afterStart","enabled":true}]"#.utf8)
        let decoded = BreakActionStore.decode(old)!
        XCTAssertTrue(decoded[0].conditions.isDefault)
        XCTAssertEqual(decoded[0].shortcutName, "")
    }

    // MARK: Address

    func testOnlyANonWebCallbackIsAccepted() {
        func callback(_ text: String) -> URL? { AutomationURL.stateCallback(in: URL(string: text)!) }
        XCTAssertEqual(callback("intermezzo://state?x-success=shortcuts://run-shortcut")?.scheme, "shortcuts")
        XCTAssertNil(callback("intermezzo://state?x-success=https://example.com/collect"))
        XCTAssertNil(callback("intermezzo://state?x-success=file:///etc/passwd"))
        XCTAssertNil(callback("intermezzo://state"))
        XCTAssertNil(callback("intermezzo://state?x-success=not%20a%20url"))
    }

    func testTheStateIsAddedToTheCallback() {
        let url = AutomationURL.callbackURL(URL(string: "shortcuts://x-callback-url/run-shortcut?name=Mine")!, state: "{\"a\":1}")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Mine")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "{\"a\":1}")
    }

    func testTheStateAddressParses() {
        XCTAssertEqual(AutomationURL.parse(host: "state", path: []), .state)
    }
}
