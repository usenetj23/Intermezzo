import XCTest
@testable import IntermezzoKit

final class SpanLayoutTests: XCTestCase {
    private let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let right = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    func testUnionCoversAllScreens() {
        XCTAssertEqual(SpanLayout.union([left, right]), CGRect(x: 0, y: 0, width: 4480, height: 1440))
        XCTAssertNil(SpanLayout.union([]))
    }

    func testLeftmostScreenShowsTheStartOfTheImage() {
        let u = SpanLayout.union([left, right])!
        XCTAssertEqual(SpanLayout.offset(of: left, in: u).width, 0)
    }

    func testSecondScreenIsShiftedByItsDistanceFromTheLeftEdge() {
        let u = SpanLayout.union([left, right])!
        XCTAssertEqual(SpanLayout.offset(of: right, in: u).width, -1920)
    }

    func testVerticalOffsetMeasuresFromTheUnionTop() {
        let u = SpanLayout.union([left, right])!      // top = 1440 (AppKit y-up)
        XCTAssertEqual(SpanLayout.offset(of: left, in: u).height, -360)
        XCTAssertEqual(SpanLayout.offset(of: right, in: u).height, 0)
    }
}
