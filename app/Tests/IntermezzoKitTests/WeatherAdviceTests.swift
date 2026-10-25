import XCTest
@testable import IntermezzoKit

final class WeatherAdviceTests: XCTestCase {
    func testSunnyWithHighUVSuggestsGoingOutside() {
        let tip = WeatherAdvice.tip(effect: .clear, uvIndex: 5, temperatureC: 20)
        XCTAssertTrue(tip?.contains("na zewnątrz") == true)
        XCTAssertTrue(tip?.contains("UV") == true)
    }

    func testSunnyWithoutUVStillGivesATip() {
        XCTAssertNotNil(WeatherAdvice.tip(effect: .clear, uvIndex: nil, temperatureC: 15))
    }

    func testFreezingSunnyDoesNotSendYouOutside() {
        let tip = WeatherAdvice.tip(effect: .clear, uvIndex: 4, temperatureC: -12)
        XCTAssertFalse(tip?.contains("na zewnątrz") == true)
    }

    func testRainAndStormSuggestIndoorStretching() {
        XCTAssertTrue(WeatherAdvice.tip(effect: .rain, uvIndex: nil, temperatureC: 10)?.contains("w pomieszczeniu") == true)
        XCTAssertTrue(WeatherAdvice.tip(effect: .storm, uvIndex: nil, temperatureC: 10)?.contains("w pomieszczeniu") == true)
    }

    func testCloudyAndNoneHaveNoTip() {
        XCTAssertNil(WeatherAdvice.tip(effect: .cloudy, uvIndex: nil, temperatureC: 10))
        XCTAssertNil(WeatherAdvice.tip(effect: .none, uvIndex: nil, temperatureC: 10))
    }
}
