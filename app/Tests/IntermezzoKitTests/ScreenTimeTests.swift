import XCTest
@testable import IntermezzoKit

final class ScreenTimeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "ScreenTimeTests")!
        defaults.removePersistentDomain(forName: "ScreenTimeTests")
    }

    private func day(_ d: Int, _ h: Int = 9) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = d; c.hour = h
        return cal.date(from: c)!
    }

    func testAccumulatesWithinADay() {
        let s = ScreenTimeStore(defaults: defaults, calendar: cal)
        _ = s.add(seconds: 600, now: day(23))
        _ = s.add(seconds: 300, now: day(23, 11))
        XCTAssertEqual(s.seconds(now: day(23, 12)), 900)
    }

    func testResetsOnANewDay() {
        let s = ScreenTimeStore(defaults: defaults, calendar: cal)
        _ = s.add(seconds: 3600, now: day(23))
        XCTAssertEqual(s.seconds(now: day(24)), 0)
        _ = s.add(seconds: 10, now: day(24))
        XCTAssertEqual(s.seconds(now: day(24)), 10)
    }

    func testLimitAlertFiresOncePerDay() {
        let s = ScreenTimeStore(defaults: defaults, calendar: cal)
        XCTAssertFalse(s.add(seconds: ScreenTimeStore.dailyLimit - 1, now: day(23)))
        XCTAssertTrue(s.add(seconds: 1, now: day(23)))        // crosses the limit
        XCTAssertFalse(s.add(seconds: 600, now: day(23)))     // already alerted today
        XCTAssertFalse(s.add(seconds: ScreenTimeStore.dailyLimit - 1, now: day(24)))
        XCTAssertTrue(s.add(seconds: 1, now: day(24)))        // new day, alert again
    }

    func testFormatting() {
        XCTAssertEqual(ScreenTimeStore.format(seconds: 0), "0 min")
        XCTAssertEqual(ScreenTimeStore.format(seconds: 59 * 60), "59 min")
        XCTAssertEqual(ScreenTimeStore.format(seconds: 2 * 3600 + 14 * 60), "2 h 14 min")
    }
}
