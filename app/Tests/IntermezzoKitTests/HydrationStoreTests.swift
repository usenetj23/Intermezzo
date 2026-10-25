import XCTest
@testable import IntermezzoKit

final class HydrationStoreTests: XCTestCase {
    var defaults: UserDefaults!
    let suite = "HydrationStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testRecordAndTodaySummary() {
        let now = Date()
        HydrationStore.record(kind: "woda", ml: 250, now: now, defaults)
        HydrationStore.record(kind: "kawa", ml: 150, now: now, defaults)
        HydrationStore.record(kind: "woda", ml: 200, now: now, defaults)
        let s = HydrationStore.todaySummary(now: now, defaults)
        XCTAssertEqual(s.totalMl, 600)
        XCTAssertEqual(s.byKind.first?.0, "woda")
        XCTAssertEqual(s.byKind.first?.1, 450)
    }

    func testOldEntriesPrunedFromSummary() {
        let now = Date()
        HydrationStore.record(kind: "sok", ml: 300,
                              now: now.addingTimeInterval(-40 * 86_400), defaults)
        HydrationStore.record(kind: "woda", ml: 100, now: now, defaults)
        let s = HydrationStore.todaySummary(now: now, defaults)
        XCTAssertEqual(s.totalMl, 100)
    }

    func testJSONRoundTripWithNewFields() {
        var item = BreakActionItem()
        item.kind = .logDrink
        item.drinkKind = "herbata"
        item.amountMl = 500
        let decoded = BreakActionStore.decode(BreakActionStore.encode([item]))
        XCTAssertEqual(decoded?.first?.kind, .logDrink)
        XCTAssertEqual(decoded?.first?.drinkKind, "herbata")
        XCTAssertEqual(decoded?.first?.amountMl, 500)
    }
}
