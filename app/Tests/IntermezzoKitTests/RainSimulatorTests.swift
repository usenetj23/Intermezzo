import XCTest
@testable import IntermezzoKit

final class RainSimulatorTests: XCTestCase {
    private func run(_ sim: inout RainSimulator, seconds: Float, dt: Float = 1.0 / 30.0) {
        var t: Float = 0
        while t < seconds { sim.step(dt: dt); t += dt }
    }

    func testSpawnsDropsUpToTheLimit() {
        var sim = RainSimulator(width: 1800, height: 1169, intensity: 1, storm: false, seed: 7)
        run(&sim, seconds: 30)
        XCTAssertGreaterThan(sim.drops.count, 5)
        XCTAssertLessThanOrEqual(sim.drops.count, sim.dropLimit)
    }

    func testStormHasMoreDropsThanRain() {
        let calm = RainSimulator(width: 1800, height: 1169, intensity: 1, storm: false, seed: 1)
        let storm = RainSimulator(width: 1800, height: 1169, intensity: 1, storm: true, seed: 1)
        XCTAssertGreaterThan(storm.dropLimit, calm.dropLimit)
    }

    func testIsDeterministicForASeed() {
        var a = RainSimulator(width: 1000, height: 700, intensity: 1, storm: false, seed: 42)
        var b = RainSimulator(width: 1000, height: 700, intensity: 1, storm: false, seed: 42)
        run(&a, seconds: 12); run(&b, seconds: 12)
        XCTAssertEqual(a.drops.map(\.x), b.drops.map(\.x))
        XCTAssertEqual(a.drops.map(\.y), b.drops.map(\.y))
    }

    func testSlidingDropsLeaveTrailAndWipeTheMist() {
        var sim = RainSimulator(width: 1800, height: 1169, intensity: 1, storm: true, seed: 3)
        var sawTrail = false, sawEraser = false
        for _ in 0..<(30 * 40) {
            sim.step(dt: 1.0 / 30.0)
            sawTrail = sawTrail || !sim.trail.isEmpty
            sawEraser = sawEraser || !sim.erasers.isEmpty
        }
        XCTAssertTrue(sawTrail, "no trail droplets were left behind")
        XCTAssertTrue(sawEraser, "no mist was wiped")
    }

    func testDropsBelowTheScreenAreRemoved() {
        var sim = RainSimulator(width: 800, height: 600, intensity: 0, storm: false, seed: 5)
        sim.inject(RainDrop(id: 999, x: 100, y: 900, r: 8))
        sim.step(dt: 1.0 / 30.0)
        XCTAssertFalse(sim.drops.contains { $0.id == 999 })
    }

    func testFastDropWipesAContinuousPath() {
        var sim = RainSimulator(width: 800, height: 1200, intensity: 0, storm: false, seed: 5)
        var d = RainDrop(id: 1, x: 300, y: 100, r: 8)
        d.sliding = true
        d.vy = 2000
        sim.inject(d)
        sim.step(dt: 0.05)
        let ys = sim.erasers.map(\.y).sorted()
        XCTAssertGreaterThanOrEqual(ys.count, 4, "one stamp per frame leaves beads, not a streak")
        for (a, b) in zip(ys, ys.dropFirst()) {
            XCTAssertLessThanOrEqual(b - a, 4, "gap between wipe stamps must stay well under a drop radius (8)")
        }
    }

    func testSlidingDropLosesMassAndLeavesAFiniteTrail() {
        var sim = RainSimulator(width: 800, height: 6000, intensity: 0, storm: false, seed: 5)
        var d = RainDrop(id: 1, x: 300, y: 50, r: 9)
        d.sliding = true
        sim.inject(d)
        var travelled: Float = 0, lastY: Float = 50
        for _ in 0..<(30 * 60) {
            sim.step(dt: 1.0 / 30.0)
            if let cur = sim.drops.first(where: { $0.id == 1 }) { travelled += cur.y - lastY; lastY = cur.y }
        }
        // Below the slip threshold (r < 7) a drop stays put as an ordinary small drop.
        let remaining = sim.drops.first { $0.id == 1 }
        XCTAssertLessThan(remaining?.r ?? 0, 7.5, "the drop must have lost most of its mass")
        XCTAssertFalse(remaining?.sliding ?? false, "a small drop no longer runs")
        XCTAssertLessThan(travelled, 3000, "an evaporating drop leaves a bounded streak")
    }

    func testOverlappingDropsMergeAndConserveMass() {
        var sim = RainSimulator(width: 800, height: 600, intensity: 0, storm: false, seed: 2)
        sim.inject(RainDrop(id: 1, x: 200, y: 200, r: 8))
        sim.inject(RainDrop(id: 2, x: 204, y: 203, r: 6))
        sim.step(dt: 1.0 / 60.0)
        XCTAssertEqual(sim.drops.count, 1)
        let r = sim.drops[0].r
        XCTAssertEqual(r * r, 8 * 8 + 6 * 6, accuracy: 3, "area (mass) is conserved by a merge")
    }

    func testDropsWipeMicroDropletsOnTheirPath() {
        var sim = RainSimulator(width: 400, height: 400, intensity: 0, storm: false, seed: 4)
        var d = RainDrop(id: 1, x: 200, y: 100, r: 9)
        d.sliding = true
        d.vy = 200
        sim.inject(d)
        let before = sim.micro.filter { abs($0.x - 200) < 9 && $0.y > 100 && $0.y < 160 && $0.radius > 0.2 }.count
        for _ in 0..<20 { sim.step(dt: 1.0 / 30.0) }
        let after = sim.micro.filter { abs($0.x - 200) < 5 && $0.y > 105 && $0.y < 160 && $0.radius > 0.2 }.count
        XCTAssertLessThanOrEqual(after, max(0, before / 2), "rain on the glass must be wiped where a drop slid")
    }

    func testHugeTimeStepStaysFinite() {
        var sim = RainSimulator(width: 800, height: 600, intensity: 1, storm: true, seed: 9)
        sim.step(dt: 5)
        sim.step(dt: 0)
        for d in sim.drops {
            XCTAssertTrue(d.x.isFinite && d.y.isFinite && d.r.isFinite)
        }
    }

    func testMicroDropletsExistAndGrowFromNothing() {
        var sim = RainSimulator(width: 1800, height: 1169, intensity: 1, storm: false, seed: 11)
        XCTAssertGreaterThan(sim.micro.count, 200)
        sim.step(dt: 0.2)
        XCTAssertTrue(sim.micro.allSatisfy { $0.radius >= 0 && $0.radius <= $0.target + 0.001 })
    }
}
