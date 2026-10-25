import XCTest
@testable import IntermezzoKit

final class SuggestBreakTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testOffersOnlyAfterTheConditionHeldLongEnough() {
        var g = SuggestBreakGate(sustainSeconds: 60, cooldownSeconds: 1800, minWorkedSeconds: 0)
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0))
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(59)))
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(60)))
    }

    func testConditionDroppingResetsTheSustainTimer() {
        var g = SuggestBreakGate(sustainSeconds: 60, cooldownSeconds: 1800, minWorkedSeconds: 0)
        _ = g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0)
        _ = g.shouldOffer(conditionMet: false, workedSeconds: 3600, now: t0.addingTimeInterval(40))
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(50)))
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(100)))
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(110)))
    }

    func testCooldownPreventsRepeatOffers() {
        var g = SuggestBreakGate(sustainSeconds: 0, cooldownSeconds: 1800, minWorkedSeconds: 0)
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0))
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(1799)))
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(1800)))
    }

    func testCooldownAlsoCoversAConditionThatFlipsOffAndOn() {
        var g = SuggestBreakGate(sustainSeconds: 0, cooldownSeconds: 1800, minWorkedSeconds: 0)
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0))
        _ = g.shouldOffer(conditionMet: false, workedSeconds: 3600, now: t0.addingTimeInterval(100))
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 3600, now: t0.addingTimeInterval(200)))
    }

    func testNeverOffersRightAfterABreak() {
        var g = SuggestBreakGate(sustainSeconds: 0, cooldownSeconds: 0, minWorkedSeconds: 600)
        XCTAssertFalse(g.shouldOffer(conditionMet: true, workedSeconds: 120, now: t0))
        XCTAssertTrue(g.shouldOffer(conditionMet: true, workedSeconds: 600, now: t0.addingTimeInterval(480)),
                      "once enough has been worked the held condition must be enough")
    }

    // MARK: rule model

    func testOldRulesWithoutNewFieldsStillDecode() throws {
        let legacy = """
        [{"id":"7B6C3C1E-0000-4000-8000-000000000001","enabled":true,"kind":"script",
          "text":"/tmp/a.applescript","inverted":false,"outcome":"postpone","postponeMinutes":9}]
        """.data(using: .utf8)!
        let rules = try JSONDecoder().decode([BreakRule].self, from: legacy)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].postponeMinutes, 9)
        XCTAssertEqual(rules[0].sustainSeconds, 60)
        XCTAssertEqual(rules[0].cooldownMinutes, 30)
    }

    func testSuggestOutcomeRoundTrips() {
        let store = BreakRuleStore(defaults: UserDefaults(suiteName: "SuggestBreakTests")!)
        var r = BreakRule()
        r.outcome = .suggestBreak
        r.sustainSeconds = 120
        r.cooldownMinutes = 45
        XCTAssertTrue(store.save([r]))
        let back = store.load()
        XCTAssertEqual(back.first?.outcome, .suggestBreak)
        XCTAssertEqual(back.first?.sustainSeconds, 120)
        XCTAssertEqual(back.first?.cooldownMinutes, 45)
        UserDefaults(suiteName: "SuggestBreakTests")!.removePersistentDomain(forName: "SuggestBreakTests")
    }

    func testDisplayNameUsesScriptFileName() {
        var r = BreakRule()
        r.kind = .script
        r.text = "/Users/x/Library/Application Scripts/com.automit.Intermezzo/Rules/LongBuild.applescript"
        XCTAssertEqual(r.displayName, "LongBuild")
        r.kind = .appOpen
        r.text = "Xcode"
        XCTAssertTrue(r.displayName.contains("Xcode"))
    }
}
