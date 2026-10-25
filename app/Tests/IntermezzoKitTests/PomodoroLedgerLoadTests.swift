import XCTest
@testable import IntermezzoKit

final class PomodoroLedgerLoadTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "ledger-load-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testValidBlobLoadsAndParksNothing() throws {
        let ledger = PomodoroLedger().addingTask(title: "t", estimate: 2)
        let data = try JSONEncoder().encode(ledger)
        let result = PomodoroLedger.load(data, parkingCorruptIn: defaults)
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.ledger.tasks.map(\.title), ["t"])
        XCTAssertNil(defaults.data(forKey: PomodoroLedger.corruptKey))
    }

    func testMissingOrEmptyBlobIsAFreshLedger() {
        XCTAssertEqual(PomodoroLedger.load(nil, parkingCorruptIn: defaults).outcome, .empty)
        XCTAssertEqual(PomodoroLedger.load(Data(), parkingCorruptIn: defaults).outcome, .empty)
        XCTAssertNil(defaults.data(forKey: PomodoroLedger.corruptKey))
    }

    func testUndecodableBlobIsParkedRaw() {
        let junk = Data("{not json".utf8)
        let result = PomodoroLedger.load(junk, parkingCorruptIn: defaults)
        XCTAssertEqual(result.outcome, .parkedCorrupt)
        XCTAssertTrue(result.ledger.tasks.isEmpty)
        XCTAssertEqual(defaults.data(forKey: PomodoroLedger.corruptKey), junk)
    }

    func testExistingCorruptSlotIsNotClobbered() {
        let first = Data("first".utf8)
        _ = PomodoroLedger.load(first, parkingCorruptIn: defaults)
        let result = PomodoroLedger.load(Data("second".utf8), parkingCorruptIn: defaults)
        XCTAssertEqual(result.outcome, .corruptSlotTaken)
        XCTAssertEqual(defaults.data(forKey: PomodoroLedger.corruptKey), first)
    }
}
