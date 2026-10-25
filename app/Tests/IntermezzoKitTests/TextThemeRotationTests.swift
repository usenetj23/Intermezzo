import XCTest
@testable import IntermezzoKit

final class TextThemeRotationTests: XCTestCase {

    func testSequentialWrapsAroundAndStaysInBounds() {
        XCTAssertEqual(textThemeIndex(seed: 0, tick: 0, count: 3, random: false), 0)
        XCTAssertEqual(textThemeIndex(seed: 0, tick: 1, count: 3, random: false), 1)
        XCTAssertEqual(textThemeIndex(seed: 0, tick: 3, count: 3, random: false), 0)
        XCTAssertEqual(textThemeIndex(seed: 2, tick: 2, count: 3, random: false), 1)
    }

    func testSequentialAcrossBreaksContinuesSequence() {
        // seed = completed-break count; one text per break (tick always 0)
        // must show a different entry each break, cycling.
        var seen: [Int] = []
        for breakNo in 0..<6 { seen.append(textThemeIndex(seed: breakNo, tick: 0, count: 3, random: false)) }
        XCTAssertEqual(seen, [0, 1, 2, 0, 1, 2])
    }

    func testRandomIsDeterministicPerSeedTickAndInBounds() {
        let a = textThemeIndex(seed: 7, tick: 2, count: 5, random: true)
        let b = textThemeIndex(seed: 7, tick: 2, count: 5, random: true)
        XCTAssertEqual(a, b, "same inputs must produce same selection")
        for seed in 0..<40 {
            for tick in 0..<8 {
                let idx = textThemeIndex(seed: seed, tick: tick, count: 5, random: true)
                XCTAssertTrue((0..<5).contains(idx), "index \(idx) out of bounds")
            }
        }
    }

    func testRandomActuallyVaries() {
        var seen = Set<Int>()
        for tick in 0..<40 { seen.insert(textThemeIndex(seed: 13, tick: tick, count: 6, random: true)) }
        XCTAssertGreaterThanOrEqual(seen.count, 4, "random selection must cover most entries")
    }

    func testEmptyCountSafe() {
        XCTAssertEqual(textThemeIndex(seed: 5, tick: 5, count: 0, random: false), 0)
        XCTAssertEqual(textThemeIndex(seed: 5, tick: 5, count: 0, random: true), 0)
    }
}
