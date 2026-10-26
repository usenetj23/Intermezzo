import XCTest
@testable import IntermezzoKit

final class WorldMapTests: XCTestCase {
    private func sample() -> WorldMap {
        WorldMap(land: [[GeoPoint(latitude: 50, longitude: 10), GeoPoint(latitude: 55, longitude: 20.1234),
                         GeoPoint(latitude: -10.5, longitude: -170)]],
                 borders: [[GeoPoint(latitude: 49, longitude: 14), GeoPoint(latitude: 51.0001, longitude: 15)]],
                 cities: [WorldMap.City(name: "Łódź", location: GeoPoint(latitude: 51.7592, longitude: 19.456), population: 700_000),
                          WorldMap.City(name: "Poznań", location: GeoPoint(latitude: 52.4069, longitude: 16.9299), population: 540_000)])
    }

    private func assertEqual(_ a: WorldMap, _ b: WorldMap, file: StaticString = #filePath, line: UInt = #line) {
        func flat(_ paths: [[GeoPoint]]) -> [Double] { paths.flatMap { $0.flatMap { [$0.latitude, $0.longitude] } } }
        XCTAssertEqual(a.land.map(\.count), b.land.map(\.count), file: file, line: line)
        XCTAssertEqual(a.borders.map(\.count), b.borders.map(\.count), file: file, line: line)
        for (x, y) in zip(flat(a.land) + flat(a.borders), flat(b.land) + flat(b.borders)) {
            XCTAssertEqual(x, y, accuracy: 1e-4, file: file, line: line)
        }
        XCTAssertEqual(a.cities.map(\.name), b.cities.map(\.name), file: file, line: line)
        XCTAssertEqual(a.cities.map(\.population), b.cities.map(\.population), file: file, line: line)
        for (x, y) in zip(a.cities, b.cities) {
            XCTAssertEqual(x.location.latitude, y.location.latitude, accuracy: 1e-4, file: file, line: line)
            XCTAssertEqual(x.location.longitude, y.location.longitude, accuracy: 1e-4, file: file, line: line)
        }
    }

    func testRoundTrip() throws {
        let back = try XCTUnwrap(WorldMap.decode(sample().encoded()))
        assertEqual(back, sample())
    }

    func testBadMagicVersionAndTruncatedGiveNil() {
        let good = sample().encoded()
        XCTAssertNil(WorldMap.decode(Data()))
        var badMagic = good
        badMagic[0] = 0x58
        XCTAssertNil(WorldMap.decode(badMagic))
        var badVersion = good
        badVersion[4] = 9
        XCTAssertNil(WorldMap.decode(badVersion))
        for cut in [5, 12, good.count / 2, good.count - 3, good.count - 1] {
            XCTAssertNil(WorldMap.decode(good.prefix(cut)), "cut at \(cut)")
        }
    }

    func testEmptyHasNothing() {
        XCTAssertTrue(WorldMap.empty.land.isEmpty)
        XCTAssertTrue(WorldMap.empty.borders.isEmpty)
        XCTAssertTrue(WorldMap.empty.cities.isEmpty)
    }

    func testCityVisibilityGrowsWithZoom() {
        XCTAssertGreaterThan(CityVisibility.minimumPopulation(zoom: 1), CityVisibility.minimumPopulation(zoom: 8))
        XCTAssertGreaterThan(CityVisibility.minimumPopulation(zoom: 8), CityVisibility.minimumPopulation(zoom: MapViewport.maxZoom))
        XCTAssertEqual(CityVisibility.minimumPopulation(zoom: 1), 5_000_000)
        XCTAssertEqual(CityVisibility.minimumPopulation(zoom: MapViewport.maxZoom), 5_000)
        // denser than a straight line in between: a mid-sized view already shows hundreds of thousands, not millions
        XCTAssertLessThan(CityVisibility.minimumPopulation(zoom: 8), 200_000)
    }

    /// The map that ships in the app (made by scripts/gen_world_map.py).
    func testBundledMapDecodes() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: app.appendingPathComponent("Support/worldmap/worldmap.bin"))
        let map = try XCTUnwrap(WorldMap.decode(data))
        XCTAssertGreaterThan(map.land.count, 100)
        XCTAssertGreaterThan(map.borders.count, 100)
        let names = Set(map.cities.map(\.name))
        XCTAssertFalse(names.isDisjoint(with: ["Warsaw", "Warszawa"]))
        XCTAssertFalse(names.isDisjoint(with: ["Lodz", "Łódź"]))
        XCTAssertFalse(names.isDisjoint(with: ["Poznan", "Poznań"]))
        XCTAssertTrue(names.contains("Węgrów"))
    }
}
