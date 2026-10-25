import XCTest
@testable import IntermezzoKit

final class BetterDisplayTests: XCTestCase {
    func testRequestJSONHasTheDocumentedShape() throws {
        let json = BetterDisplayProtocol.requestJSON(uuid: "U-1", command: "get",
                                                     parameters: [("displayID", "3"), ("brightness", nil)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["uuid"] as? String, "U-1")
        XCTAssertEqual(object["commands"] as? [String], ["get"])
        let params = try XCTUnwrap(object["parameters"] as? [String: Any])
        XCTAssertEqual(params["displayID"] as? String, "3")
        XCTAssertTrue(params["brightness"] is NSNull)
    }

    func testDecodesResponses() {
        let r = BetterDisplayProtocol.decodeResponse(#"{"result":true,"payload":"0.912","uuid":"A"}"#)
        XCTAssertEqual(r, BetterDisplayResponse(uuid: "A", result: true, payload: "0.912"))
        XCTAssertEqual(BetterDisplayProtocol.number(r?.payload), 0.912)
        XCTAssertEqual(BetterDisplayProtocol.decodeResponse(#"{"result":false}"#)?.result, false)
        XCTAssertNil(BetterDisplayProtocol.decodeResponse("nonsense"))
        XCTAssertNil(BetterDisplayProtocol.number("off"))
    }

    func testParsesTheRealIdentifiersAnswer() {
        let payload = """
        {\n  "UUID" : "AC8B",\n  "deviceType" : "Display",\n  "displayID" : "3",\n  "name" : "DELL P2725HE"\n},{\n  "UUID" : "37D8",\n  "deviceType" : "Display",\n  "displayID" : "1",\n  "name" : "Built-in Display"\n},{\n  "deviceType" : "VirtualScreen",\n  "displayID" : "9",\n  "name" : "Dummy"\n}
        """
        XCTAssertEqual(BetterDisplayProtocol.parseDevices(payload: payload),
                       [BetterDisplayDevice(displayID: 3, name: "DELL P2725HE"),
                        BetterDisplayDevice(displayID: 1, name: "Built-in Display")])
        XCTAssertEqual(BetterDisplayProtocol.parseDevices(payload: "").count, 0)
        XCTAssertEqual(BetterDisplayProtocol.parseDevices(payload: "garbage").count, 0)
    }

    private let settings = LightProfile.recommended.settings(wakeMinutes: 390)

    func testNoDimmingInTheDaytime() {
        XCTAssertEqual(EveningDimming.factor(kelvin: 6500, settings: settings, maxDimPercent: 30), 1, accuracy: 1e-9)
    }

    func testDimsAsTheScreenWarms() {
        let evening = EveningDimming.factor(kelvin: 3400, settings: settings, maxDimPercent: 30)
        let bed = EveningDimming.factor(kelvin: 1900, settings: settings, maxDimPercent: 30)
        XCTAssertLessThan(evening, 1)
        XCTAssertGreaterThan(evening, bed)
        XCTAssertEqual(bed, 0.7, accuracy: 1e-9)
    }

    func testNeverBelowTheFloorOrTheLimit() {
        XCTAssertGreaterThanOrEqual(EveningDimming.factor(kelvin: 1000, settings: settings, maxDimPercent: 90), 0.5)
        XCTAssertEqual(EveningDimming.factor(kelvin: 1900, settings: settings, maxDimPercent: 0), 1, accuracy: 1e-9)
    }

    func testDetectsManualChangesAndSmallSteps() {
        XCTAssertFalse(EveningDimming.userChanged(current: 0.71, lastSet: 0.70))
        XCTAssertTrue(EveningDimming.userChanged(current: 0.9, lastSet: 0.7))
        XCTAssertTrue(EveningDimming.needsUpdate(target: 0.7, lastSet: nil))
        XCTAssertFalse(EveningDimming.needsUpdate(target: 0.71, lastSet: 0.70))
        XCTAssertTrue(EveningDimming.needsUpdate(target: 0.67, lastSet: 0.70))
    }

    func testFindsDisplaysThatFollowTheOneJustSet() {
        let before = [3: 0.912, 4: 0.912, 1: 0.666]
        // set 4 to 0.73: display 3 followed, the built-in did not
        XCTAssertEqual(BetterDisplayLinks.followers(leader: 4, wanted: 0.73, before: before,
                                                    after: [3: 0.73, 1: 0.666]), [3])
        XCTAssertTrue(BetterDisplayLinks.followers(leader: 4, wanted: 0.73, before: before, after: [3: 0.912, 1: 0.666]).isEmpty)
        // a display that moved somewhere else is not a follower
        XCTAssertTrue(BetterDisplayLinks.followers(leader: 4, wanted: 0.73, before: before, after: [1: 0.5]).isEmpty)
        // already at the wanted value before: nothing moved, so nothing is learnt
        XCTAssertTrue(BetterDisplayLinks.followers(leader: 4, wanted: 0.73, before: [3: 0.73], after: [3: 0.73]).isEmpty)
    }

    func testOldSavedStateStillDecodes() {
        let old = Data(#"{"originalBrightness":{"3":0.9},"lastSetBrightness":{"3":0.7},"trueToneWasOn":true}"#.utf8)
        let state = BetterDisplayState.decode(old)
        XCTAssertEqual(state.originalBrightness["3"], 0.9)
        XCTAssertTrue(state.trueToneWasOn)
        XCTAssertTrue(state.followerOf.isEmpty)
        XCTAssertTrue(state.disabledGroups.isEmpty)
    }

    func testUnlinkingGivesFollowersTheirLeadersValues() {
        var state = BetterDisplayState()
        state.originalBrightness = ["4": 0.912, "1": 0.666]
        state.lastSetBrightness = ["4": 0.73, "1": 0.533]
        state.followerOf = ["3": "4"]
        state.unlinkFollowers()
        XCTAssertEqual(state.originalBrightness["3"], 0.912)
        XCTAssertEqual(state.lastSetBrightness["3"], 0.73)
        XCTAssertTrue(state.followerOf.isEmpty)
    }

    func testAGroupLeftOffKeepsTheStateAlive() {
        var state = BetterDisplayState()
        state.disabledGroups = ["DeskPair"]
        XCTAssertFalse(state.isEmpty)
    }

    func testParsesGroupNames() {
        let payload = "{\n \"deviceType\" : \"DisplayGroup\",\n \"name\" : \"DeskPair\",\n \"tagID\" : \"-1001\"\n}"
        XCTAssertEqual(BetterDisplayProtocol.parseGroupNames(payload: payload), ["DeskPair"])
        XCTAssertTrue(BetterDisplayProtocol.parseGroupNames(payload: "").isEmpty)
    }

    func testStateRoundTrips() {
        var state = BetterDisplayState()
        XCTAssertTrue(state.isEmpty)
        state.originalBrightness["3"] = 0.9
        state.lastSetBrightness["3"] = 0.7
        state.trueToneWasOn = true
        state.followerOf = ["3": "4"]
        XCTAssertFalse(state.isEmpty)
        XCTAssertEqual(BetterDisplayState.decode(state.encoded()), state)
        XCTAssertTrue(BetterDisplayState.decode(nil).isEmpty)
        XCTAssertTrue(BetterDisplayState.decode(Data("junk".utf8)).isEmpty)
    }
}
