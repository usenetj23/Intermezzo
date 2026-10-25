import XCTest
@testable import IntermezzoKit

final class BreakPresetTests: XCTestCase {
    func testPresetsHaveUniqueIDsAndSources() {
        let ids = BreakPreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for p in BreakPreset.all {
            XCTAssertFalse(p.title.isEmpty)
            XCTAssertFalse(p.summary.isEmpty)
            XCTAssertFalse(p.source.isEmpty)
        }
    }

    func testPresetValuesAreWithinEngineBounds() {
        for p in BreakPreset.all {
            XCTAssertGreaterThanOrEqual(p.cycleMinutes, 1, p.id)
            XCTAssertGreaterThanOrEqual(p.shortBreakSeconds, 10, p.id)
            XCTAssertGreaterThanOrEqual(p.longBreakSeconds, 60, p.id)
            XCTAssertGreaterThanOrEqual(p.longBreakEvery, 2, p.id)
        }
    }

    func testTwentyTwentyTwentyPreset() {
        let p = BreakPreset.all.first { $0.id == "20-20-20" }
        XCTAssertEqual(p?.cycleMinutes, 20)
        XCTAssertEqual(p?.shortBreakSeconds, 20)
    }

    func testPolishRegulationPresetIsFiveMinutesPerHour() {
        let p = BreakPreset.all.first { $0.id == "bhp-5-60" }
        XCTAssertEqual(p?.cycleMinutes, 60)
        XCTAssertEqual(p?.shortBreakSeconds, 300)
    }

    func testMatchingFindsActivePreset() {
        let p = BreakPreset.all[0]
        XCTAssertEqual(BreakPreset.matching(cycleMinutes: p.cycleMinutes,
                                            shortSeconds: p.shortBreakSeconds,
                                            longSeconds: p.longBreakSeconds,
                                            longEvery: p.longBreakEvery)?.id, p.id)
        XCTAssertNil(BreakPreset.matching(cycleMinutes: 37, shortSeconds: 41, longSeconds: 99, longEvery: 7))
    }
}
