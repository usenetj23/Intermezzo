import XCTest
@testable import IntermezzoKit

final class BreakActionStoreTests: XCTestCase {

    func testJSONRoundTrip() {
        var a = BreakActionItem()
        a.kind = .speakText
        a.when = .beforeDue
        a.offsetSeconds = 15
        a.speakText = "Za chwilę przerwa"
        var b = BreakActionItem()
        b.kind = .soundVolume
        b.volumeMode = "mute"
        b.when = .afterStart
        let items = [a, b]
        let data = BreakActionStore.encode(items)
        let decoded = BreakActionStore.decode(data)
        XCTAssertEqual(decoded, items)
    }

    func testDecodeGarbageIsNull() {
        XCTAssertNil(BreakActionStore.decode(Data([0xFF, 0xFE])))
        XCTAssertNil(BreakActionStore.decode(Data()))
        XCTAssertNil(BreakActionStore.decode(nil))
    }

    func testFullTimingPointSetRoundTrips() {
        // The full set of timing points must exist and survive JSON.
        let all: [BreakActionWhen] = [.beforeDue, .afterStart, .afterFadeIn,
                                       .beforeFadeOut, .beforeFinish, .afterFinish,
                                       .afterPostpone, .afterAnyEnd, .buttonClicked]
        XCTAssertEqual(Set(all.map { $0.rawValue }),
                     Set(BreakActionWhen.allCases.map { $0.rawValue }))
        var items: [BreakActionItem] = []
        for w in all {
            var it = BreakActionItem()
            it.when = w
            items.append(it)
        }
        let decoded = BreakActionStore.decode(BreakActionStore.encode(items))
        XCTAssertEqual(decoded, items)
    }

    func testFadeDurationIsSmallPositive() {
        XCTAssertGreaterThan(breakFadeDuration, 0)
        XCTAssertLessThanOrEqual(breakFadeDuration, 5)
    }
}
