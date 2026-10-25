import XCTest
@testable import IntermezzoKit

final class BreakRuleStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: BreakRuleStore.storageKey)
    }

    func testRuleRoundTripAllFields() {
        let store = BreakRuleStore()
        var rule = BreakRule()
        rule.kind = .script
        rule.text = "/tmp/x.applescript"
        rule.inverted = true
        rule.outcome = .autoSkip
        rule.postponeMinutes = 7
        store.add(rule)

        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].kind, .script)
        XCTAssertEqual(loaded[0].text, "/tmp/x.applescript")
        XCTAssertTrue(loaded[0].inverted)
        XCTAssertEqual(loaded[0].outcome, .autoSkip)
        XCTAssertEqual(loaded[0].postponeMinutes, 7)
        XCTAssertTrue(loaded[0].enabled)
    }

    func testUpdateAndRemove() {
        let store = BreakRuleStore()
        var rule = BreakRule()
        rule.kind = .focusActive
        store.add(rule)
        rule.enabled = false
        store.update(rule)
        XCTAssertEqual(store.load().first?.enabled, false)

        store.remove(id: rule.id)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testEveryKindEncodes() {
        for kind in BreakRuleKind.allCases {
            var rule = BreakRule()
            rule.kind = kind
            let data = try? JSONEncoder().encode(rule)
            XCTAssertNotNil(data, "encode \(kind.rawValue)")
            let back = data.flatMap { try? JSONDecoder().decode(BreakRule.self, from: $0) }
            XCTAssertEqual(back?.kind, kind)
            if kind.needsText { XCTAssertTrue(kind.needsText) }
        }
    }
}
