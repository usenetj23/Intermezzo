import XCTest
@testable import IntermezzoKit

final class RhythmSettingsBackupTests: XCTestCase {
    private var suite = ""
    private var d: UserDefaults!

    override func setUp() {
        suite = "rhythm-backup-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    private typealias B = RhythmSettingsBackup

    func testCaptureChangeRestoreReturnsExactValues() {
        d.set(45, forKey: B.cycleMinutesKey)
        d.set(420, forKey: B.shortBreakSecondsKey)
        B.begin(in: d)
        d.set(25, forKey: B.cycleMinutesKey)
        d.set(300, forKey: B.shortBreakSecondsKey)
        XCTAssertEqual(B.end(in: d), .restored)
        XCTAssertEqual(d.integer(forKey: B.cycleMinutesKey), 45)
        XCTAssertEqual(d.integer(forKey: B.shortBreakSecondsKey), 420)
        XCTAssertFalse(B.hasBackup(in: d))
    }

    func testAbsentKeysAreRemovedOnRestore() {
        B.begin(in: d)
        d.set(50, forKey: B.cycleMinutesKey)
        d.set(600, forKey: B.shortBreakSecondsKey)
        B.end(in: d)
        XCTAssertNil(d.object(forKey: B.cycleMinutesKey))
        XCTAssertNil(d.object(forKey: B.shortBreakSecondsKey))
    }

    func testStartWithExistingBackupRestoresOriginalFirstAndKeepsIt() {
        d.set(45, forKey: B.cycleMinutesKey)
        d.set(420, forKey: B.shortBreakSecondsKey)
        B.begin(in: d)
        d.set(25, forKey: B.cycleMinutesKey)            // arm-applied values
        d.set(300, forKey: B.shortBreakSecondsKey)
        XCTAssertEqual(B.begin(in: d), .restoredLeftover)   // second start, e.g. after a lost experiment blob
        XCTAssertEqual(B.load(from: d), B(cycleMinutes: 45, shortBreakSeconds: 420))
        XCTAssertEqual(d.integer(forKey: B.cycleMinutesKey), 45)
    }

    func testDoubleStartDoesNotOverwriteOriginal() {
        d.set(45, forKey: B.cycleMinutesKey)
        B.begin(in: d)
        d.set(25, forKey: B.cycleMinutesKey)
        B.begin(in: d)
        B.begin(in: d)
        XCTAssertEqual(B.load(from: d)?.cycleMinutes, 45)
        B.end(in: d)
        XCTAssertEqual(d.integer(forKey: B.cycleMinutesKey), 45)
    }

    func testCorruptBackupIsNotDeletedOnEnd() {
        let junk = Data("not json".utf8)
        d.set(junk, forKey: B.backupKey)
        d.set(25, forKey: B.cycleMinutesKey)
        XCTAssertEqual(B.end(in: d), .undecodableKept)
        XCTAssertEqual(d.data(forKey: B.backupKey), junk)
        XCTAssertEqual(d.integer(forKey: B.cycleMinutesKey), 25)
    }

    func testCorruptBackupIsParkedOnBegin() {
        let junk = Data("not json".utf8)
        d.set(junk, forKey: B.backupKey)
        XCTAssertEqual(B.begin(in: d), .parkedCorrupt)
        XCTAssertEqual(d.data(forKey: B.corruptKey), junk)
        XCTAssertNotNil(B.load(from: d))
    }

    func testBackupDecodesTolerantly() throws {
        let b = try JSONDecoder().decode(B.self, from: Data("{}".utf8))
        XCTAssertNil(b.cycleMinutes)
    }
}
