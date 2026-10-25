import XCTest
@testable import IntermezzoKit

final class WeatherCodesTests: XCTestCase {
    func testWMOMapping() {
        XCTAssertEqual(WeatherEffect.from(wmoCode: 0), .clear)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 2), .cloudy)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 45), .fog)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 61), .rain)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 82), .rain)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 75), .snow)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 96), .storm)
        XCTAssertEqual(WeatherEffect.from(wmoCode: 999), .none)
    }
}
