import XCTest
@testable import IntermezzoKit

final class MapViewportTests: XCTestCase {
    private let size = CGSize(width: 800, height: 400)

    private let samples = [
        GeoPoint(latitude: 52.4, longitude: 22), GeoPoint(latitude: 0, longitude: 0),
        GeoPoint(latitude: -33.9, longitude: 151.2), GeoPoint(latitude: 89, longitude: 179),
        GeoPoint(latitude: -89, longitude: -179), GeoPoint(latitude: 40.7, longitude: -74),
    ]

    func testProjectRoundTrip() {
        for zoom in [1.0, 3.5, 40] {
            let view = MapViewport(center: GeoPoint(latitude: 30, longitude: 10), zoom: zoom)
            for p in samples {
                let back = view.geo(at: view.point(for: p, in: size), in: size)
                XCTAssertEqual(back.latitude, p.latitude, accuracy: 1e-6)
                XCTAssertEqual(back.longitude, p.longitude, accuracy: 1e-6)
            }
        }
    }

    func testZoomKeepsAnchorPointFixed() {
        let view = MapViewport(center: GeoPoint(latitude: 20, longitude: 10), zoom: 2)
        let anchor = CGPoint(x: 600, y: 120)
        let before = view.geo(at: anchor, in: size)
        let after = view.zoomed(by: 4, around: anchor, in: size)
        XCTAssertEqual(after.zoom, 8, accuracy: 1e-9)
        let still = after.geo(at: anchor, in: size)
        XCTAssertEqual(still.latitude, before.latitude, accuracy: 1e-6)
        XCTAssertEqual(still.longitude, before.longitude, accuracy: 1e-6)
    }

    func testZoomIsClamped() {
        let view = MapViewport()
        let middle = CGPoint(x: 400, y: 200)
        XCTAssertEqual(view.zoomed(by: 1e9, around: middle, in: size).zoom, MapViewport.maxZoom)
        XCTAssertEqual(view.zoomed(by: 1e-9, around: middle, in: size).zoom, MapViewport.minZoom)
    }

    func testPanClampsLatitudeAndWrapsLongitude() {
        let view = MapViewport(center: GeoPoint(latitude: 80, longitude: 170), zoom: 4)
        let up = view.panned(by: CGSize(width: 0, height: 100_000), in: size)
        XCTAssertGreaterThanOrEqual(up.center.latitude, -90)
        XCTAssertLessThanOrEqual(up.center.latitude, 90)
        let sideways = view.panned(by: CGSize(width: -100_000, height: 0), in: size)
        XCTAssertGreaterThanOrEqual(sideways.center.longitude, -180)
        XCTAssertLessThanOrEqual(sideways.center.longitude, 180)
    }

    func testKilometresPerPixelScalesWithZoom() {
        let one = MapViewport(zoom: 1).kilometresPerPixel(in: size)
        let two = MapViewport(zoom: 2).kilometresPerPixel(in: size)
        XCTAssertEqual(one, 111.32 * 360 / 800, accuracy: 0.5)
        XCTAssertEqual(two, one / 2, accuracy: one * 0.01)
    }

    func testTinySizeDoesNotCrash() {
        let view = MapViewport()
        for tiny in [CGSize(width: 0, height: 0), CGSize(width: 1, height: 1)] {
            let p = view.point(for: GeoPoint(latitude: 10, longitude: 10), in: tiny)
            XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            let g = view.geo(at: CGPoint(x: 0, y: 0), in: tiny)
            XCTAssertTrue(g.latitude.isFinite && g.longitude.isFinite)
            XCTAssertTrue(view.kilometresPerPixel(in: tiny).isFinite)
            XCTAssertTrue(view.zoomed(by: 2, around: .zero, in: tiny).zoom.isFinite)
        }
    }
}
