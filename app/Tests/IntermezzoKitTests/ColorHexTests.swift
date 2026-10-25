import XCTest
@testable import IntermezzoKit

final class ColorHexTests: XCTestCase {
    func testParsesWithAndWithoutHash() throws {
        let a = try XCTUnwrap(ColorHex.components("#FF8000"))
        XCTAssertEqual(a.r, 1, accuracy: 0.001)
        XCTAssertEqual(a.g, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(a.b, 0, accuracy: 0.001)
        XCTAssertNotNil(ColorHex.components("5ad9a0"))
    }

    func testRejectsMalformed() {
        XCTAssertNil(ColorHex.components("#12345"))
        XCTAssertNil(ColorHex.components("zzzzzz"))
        XCTAssertNil(ColorHex.components(""))
    }

    func testRoundTripAndClamping() {
        XCTAssertEqual(ColorHex.string(r: 1, g: 0.5, b: 0), "#FF8000")
        XCTAssertEqual(ColorHex.string(r: 2, g: -1, b: 0), "#FF0000")
        let c = ColorHex.components("#5AD9A0")!
        XCTAssertEqual(ColorHex.string(r: c.r, g: c.g, b: c.b), "#5AD9A0")
    }
}

final class ColorHexStrictTests: XCTestCase {
    func testRejectsSignedAndLoneHash() {
        XCTAssertNil(ColorHex.components("+12345"))
        XCTAssertNil(ColorHex.components("-12345"))
        XCTAssertNil(ColorHex.components("#"))
    }

    func testLowercaseAndWhitespace() {
        let c = ColorHex.components("  #5ad9a0 \n")!
        XCTAssertEqual(ColorHex.string(r: c.r, g: c.g, b: c.b), "#5AD9A0")
    }
}
