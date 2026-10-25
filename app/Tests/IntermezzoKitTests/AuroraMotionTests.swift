import XCTest
@testable import IntermezzoKit

final class AuroraMotionTests: XCTestCase {
    func testThereAreSeveralBlobsWithDistinctColours() {
        XCTAssertGreaterThanOrEqual(AuroraMotion.blobs.count, 4)
        let colours = Set(AuroraMotion.blobs.map { "\($0.red),\($0.green),\($0.blue)" })
        XCTAssertEqual(colours.count, AuroraMotion.blobs.count)
    }

    func testBlobsStayInsideTheSurfaceAtAnyTime() {
        for i in AuroraMotion.blobs.indices {
            for t in stride(from: 0.0, through: 5000, by: 37.3) {
                let p = AuroraMotion.position(blob: i, time: t)
                XCTAssertTrue((-0.1...1.1).contains(p.x) && (-0.1...1.1).contains(p.y), "blob \(i) at \(t): \(p)")
            }
        }
    }

    func testBlobsActuallyMove() {
        let a = AuroraMotion.position(blob: 0, time: 0)
        let b = AuroraMotion.position(blob: 0, time: 20)
        XCTAssertNotEqual(a.x, b.x)
    }

    func testMotionIsSlow() {
        // A second later a blob has moved by only a few percent of the surface.
        let a = AuroraMotion.position(blob: 1, time: 100)
        let b = AuroraMotion.position(blob: 1, time: 101)
        XCTAssertLessThan(abs(a.x - b.x) + abs(a.y - b.y), 0.06)
    }

    func testSwingTimingMatchesTheSineAtTimeZero() {
        // An autoreversing c-a → c+a ease-in-out swing is ≈ c - a·cos(π·τ/D).
        for b in AuroraMotion.blobs {
            for (speed, phase) in [(b.speed.x, b.phase.x), (b.speed.y, b.phase.y)] {
                let t = AuroraMotion.swingTiming(speed: speed, phase: phase)
                XCTAssertEqual(t.halfPeriod, Double.pi / speed, accuracy: 1e-9)
                XCTAssertTrue((0..<(2 * t.halfPeriod)).contains(t.offset))
                XCTAssertEqual(-cos(Double.pi * t.offset / t.halfPeriod), sin(phase), accuracy: 1e-9)
            }
        }
    }

    func testUnknownBlobIndexIsHandled() {
        let p = AuroraMotion.position(blob: 99, time: 3)
        XCTAssertTrue((0...1).contains(p.x))
    }
}
