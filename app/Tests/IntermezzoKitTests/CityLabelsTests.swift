import XCTest
@testable import IntermezzoKit

final class CityLabelsTests: XCTestCase {
    private let size = CGSize(width: 800, height: 400)

    private func city(_ name: String, _ lat: Double, _ lon: Double, _ population: Int) -> WorldMap.City {
        WorldMap.City(name: name, location: GeoPoint(latitude: lat, longitude: lon), population: population)
    }

    private func labelSize(_ text: String) -> CGSize { CGSize(width: Double(text.count) * 7, height: 12) }

    private func place(_ cities: [WorldMap.City], _ view: MapViewport = MapViewport(), maximum: Int = 60) -> [CityLabels.Placed] {
        CityLabels.place(cities: cities, viewport: view, size: size, labelSize: labelSize, maximum: maximum)
    }

    func testBiggerCityWinsOverlap() {
        let placed = place([city("Small", 10, 10, 9_000_000), city("Big", 10, 10, 20_000_000)])
        XCTAssertEqual(placed.map(\.city.name), ["Big"])
    }

    func testLabelsDoNotOverlap() {
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let cities = (0..<200).map { city("City\($0)", -60 + next() * 120, -170 + next() * 340, 6_000_000 + $0) }
        let rects = place(cities, MapViewport(center: GeoPoint(latitude: 0, longitude: 0), zoom: 1)).map(\.labelRect)
        XCTAssertFalse(rects.isEmpty)
        for i in rects.indices {
            for j in rects.indices where j > i { XCTAssertFalse(rects[i].intersects(rects[j]), "\(i) and \(j)") }
        }
    }

    func testSmallCitiesAppearOnlyWhenZoomedIn() {
        let small = city("Smallville", 51.7, 19.4, 60_000)
        XCTAssertTrue(place([small]).isEmpty)
        let close = MapViewport(center: small.location, zoom: MapViewport.maxZoom)
        XCTAssertEqual(place([small], close).map(\.city.name), ["Smallville"])
    }

    func testSmallTownsAppearOnlyAtTheClosestZoom() {
        let town = city("Węgrów", 52.4, 22.0, 12_000)
        XCTAssertTrue(place([town], MapViewport(center: town.location, zoom: 8)).isEmpty)
        XCTAssertEqual(place([town], MapViewport(center: town.location, zoom: MapViewport.maxZoom)).map(\.city.name), ["Węgrów"])
    }

    func testBigCitiesWinWhateverTheInputOrder() {
        let cities = [city("Tiny", 10, 10, 6_000), city("Huge", 10, 10.1, 9_000_000)]
        let view = MapViewport(center: GeoPoint(latitude: 10, longitude: 10), zoom: MapViewport.maxZoom)
        XCTAssertEqual(place(cities, view).map(\.city.name).first, "Huge")
        XCTAssertEqual(place(cities.reversed(), view).map(\.city.name).first, "Huge")
    }

    func testOffscreenAndClippedLabelsAreDropped() {
        let view = MapViewport(center: GeoPoint(latitude: 0, longitude: 0), zoom: 1)
        let offscreen = city("Away", 0, 150, 9_000_000)
        let zoomed = MapViewport(center: GeoPoint(latitude: 0, longitude: 0), zoom: 8)
        XCTAssertTrue(place([offscreen], zoomed).isEmpty)
        // a point 3 pt from the right edge: its label would stick out of the window
        let edgeLongitude = view.geo(at: CGPoint(x: 797, y: 200), in: size).longitude
        XCTAssertTrue(place([city("Edge", 0, edgeLongitude, 9_000_000)], view).isEmpty)
    }

    func testMaximumIsRespected() {
        let cities = (0..<30).map { city("C\($0)", Double($0) * 2 - 30, Double($0) * 10 - 150, 8_000_000 + $0) }
        XCTAssertLessThanOrEqual(place(cities, maximum: 5).count, 5)
    }
}
