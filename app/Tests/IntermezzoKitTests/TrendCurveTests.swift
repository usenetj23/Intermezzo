import XCTest
@testable import IntermezzoKit

final class TrendCurveTests: XCTestCase {
    func testControlsStayWithinEachStep() {
        // Uneven spacing: a long step then a short one, the case that looped before.
        let xs: [Double] = [0, 300, 320, 340, 600]
        let ys: [Double] = [80, 40, 20, 20, 60]
        let c = TrendCurve.controls(xs: xs, ys: ys)
        XCTAssertEqual(c.count, 4)
        for i in 0..<c.count {
            XCTAssertTrue((xs[i]...xs[i + 1]).contains(c[i].c1x))
            XCTAssertTrue((xs[i]...xs[i + 1]).contains(c[i].c2x))
            XCTAssertLessThan(c[i].c1x, c[i].c2x)
            let lo = min(ys[i], ys[i + 1]), hi = max(ys[i], ys[i + 1])
            XCTAssertTrue((lo...hi).contains(c[i].c1y), "piece \(i) c1 overshoots")
            XCTAssertTrue((lo...hi).contains(c[i].c2y), "piece \(i) c2 overshoots")
        }
    }

    func testPeakGetsLevelTangent() {
        let c = TrendCurve.controls(xs: [0, 10, 20], ys: [0, 10, 0])
        XCTAssertEqual(c[0].c2y, 10, accuracy: 1e-9)
        XCTAssertEqual(c[1].c1y, 10, accuracy: 1e-9)
    }

    func testTooFewPoints() {
        XCTAssertTrue(TrendCurve.controls(xs: [1], ys: [1]).isEmpty)
    }
}
