import XCTest
@testable import IntermezzoKit

final class SurfaceTintTests: XCTestCase {
    func testValidHexParsesToUnitRGB() throws {
        let c = try XCTUnwrap(SurfaceTint.rgb(fromHex: "#FF8000"))
        XCTAssertEqual(c.red, 1, accuracy: 0.001)
        XCTAssertEqual(c.green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(c.blue, 0, accuracy: 0.001)
        XCTAssertNotNil(SurfaceTint.rgb(fromHex: "1c2638"))
    }

    func testInvalidHexIsRejected() {
        XCTAssertNil(SurfaceTint.rgb(fromHex: ""))
        XCTAssertNil(SurfaceTint.rgb(fromHex: "12345"))
        XCTAssertNil(SurfaceTint.rgb(fromHex: "GGGGGG"))
    }

    func testBadStoredValueFallsBackToTheDefaultNavy() {
        XCTAssertEqual(SurfaceTint.resolved(hex: "zzz"), SurfaceTint.resolved(hex: SurfaceTint.defaultHex))
        XCTAssertEqual(SurfaceTint.resolved(hex: nil), SurfaceTint.resolved(hex: SurfaceTint.defaultHex))
    }

    func testBottomOfTheGradientIsDarkerThanTheTop() {
        let g = SurfaceTint.gradient(hex: "3366CC")
        XCTAssertLessThan(g.bottom.red, g.top.red)
        XCTAssertLessThan(g.bottom.green, g.top.green)
        XCTAssertLessThan(g.bottom.blue, g.top.blue)
    }

    func testHexRoundTrip() {
        XCTAssertEqual(SurfaceTint.hex(red: 1, green: 0.5, blue: 0), "FF8000")
        XCTAssertEqual(SurfaceTint.hex(red: 2, green: -1, blue: 0), "FF0000")   // clamped
    }

    // MARK: migration of the stored theme

    func testOldGlassBecomesNavyExactlyOnce() {
        XCTAssertEqual(SurfaceMigration.theme(stored: "glass", alreadyMigrated: false), "navy")
        XCTAssertEqual(SurfaceMigration.theme(stored: "glass", alreadyMigrated: true), "glass")
    }

    func testRemovedCarbonThemeFallsBackToNavy() {
        XCTAssertEqual(SurfaceMigration.theme(stored: "carbon", alreadyMigrated: true), "navy")
        XCTAssertEqual(SurfaceMigration.theme(stored: "carbon", alreadyMigrated: false), "navy")
    }

    func testOtherThemesAndEmptyValuesAreUntouched() {
        XCTAssertEqual(SurfaceMigration.theme(stored: "frost", alreadyMigrated: false), "frost")
        XCTAssertNil(SurfaceMigration.theme(stored: nil, alreadyMigrated: false))
    }
}
