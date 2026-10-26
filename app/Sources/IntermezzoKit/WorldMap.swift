import Foundation

// The world map the location picker draws: coastlines, borders and the larger cities, read from the one
// small file the app ships (made by scripts/gen_world_map.py from Natural Earth, public domain).
//
// File layout, little endian: "WMAP", UInt8 version (1), UInt32 land paths, UInt32 border paths, the
// paths (UInt32 count, then Int32 latitude and longitude pairs in 1e-4 degrees), UInt32 cities, the cities
// (Int32 latitude, Int32 longitude, UInt32 population, UInt8 name length, UTF-8 name).

public struct WorldMap: Equatable, Sendable {
    public struct City: Equatable, Sendable {
        public let name: String
        public let location: GeoPoint
        public let population: Int

        public init(name: String, location: GeoPoint, population: Int) {
            self.name = name
            self.location = location
            self.population = population
        }
    }

    public let land: [[GeoPoint]]
    public let borders: [[GeoPoint]]
    public let cities: [City]

    public static let empty = WorldMap(land: [], borders: [], cities: [])
    private static let magic = Array("WMAP".utf8)
    private static let version: UInt8 = 1
    private static let unit = 10_000.0

    public init(land: [[GeoPoint]], borders: [[GeoPoint]], cities: [City]) {
        self.land = land
        self.borders = borders
        self.cities = cities
    }

    // MARK: Writing

    public func encoded() -> Data {
        var out = Data(Self.magic)
        out.append(Self.version)
        append(UInt32(land.count), to: &out)
        append(UInt32(borders.count), to: &out)
        for path in land + borders {
            append(UInt32(path.count), to: &out)
            for point in path { appendPoint(point, to: &out) }
        }
        append(UInt32(cities.count), to: &out)
        for city in cities {
            appendPoint(city.location, to: &out)
            append(UInt32(max(city.population, 0)), to: &out)
            var name = city.name
            while name.utf8.count > 255 { name.removeLast() }
            out.append(UInt8(name.utf8.count))
            out.append(contentsOf: name.utf8)
        }
        return out
    }

    private func append(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendPoint(_ point: GeoPoint, to data: inout Data) {
        for value in [point.latitude, point.longitude] {
            withUnsafeBytes(of: Int32((value * Self.unit).rounded()).littleEndian) { data.append(contentsOf: $0) }
        }
    }

    // MARK: Reading

    /// nil when the data is not a map of this version or is cut short.
    public static func decode(_ data: Data) -> WorldMap? {
        var reader = Reader(bytes: [UInt8](data))
        guard reader.take(4) == magic, reader.byte() == version,
              let landCount = reader.uint32(), let borderCount = reader.uint32() else { return nil }
        var paths: [[GeoPoint]] = []
        for _ in 0..<(Int(landCount) + Int(borderCount)) {
            guard let count = reader.uint32(), reader.remaining >= Int(count) * 8 else { return nil }
            var path: [GeoPoint] = []
            path.reserveCapacity(Int(count))
            for _ in 0..<count {
                guard let point = reader.point() else { return nil }
                path.append(point)
            }
            paths.append(path)
        }
        guard let cityCount = reader.uint32() else { return nil }
        var cities: [City] = []
        for _ in 0..<cityCount {
            guard let location = reader.point(), let population = reader.uint32(), let length = reader.byte(),
                  let name = reader.take(Int(length)) else { return nil }
            cities.append(City(name: String(decoding: name, as: UTF8.self), location: location, population: Int(population)))
        }
        guard reader.remaining == 0 else { return nil }
        return WorldMap(land: Array(paths.prefix(Int(landCount))), borders: Array(paths.dropFirst(Int(landCount))), cities: cities)
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var remaining: Int { bytes.count - offset }

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, remaining >= count else { return nil }
            defer { offset += count }
            return Array(bytes[offset..<offset + count])
        }

        mutating func byte() -> UInt8? { take(1)?.first }

        mutating func uint32() -> UInt32? {
            take(4).map { $0.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) } }
        }

        mutating func point() -> GeoPoint? {
            guard let lat = uint32(), let lon = uint32() else { return nil }
            return GeoPoint(latitude: Double(Int32(bitPattern: lat)) / WorldMap.unit,
                            longitude: Double(Int32(bitPattern: lon)) / WorldMap.unit)
        }
    }
}

public enum CityVisibility {
    private static let largest = 5_000_000.0
    private static let smallest = 5_000.0
    /// Below 1 the curve bends toward the close zooms, so a mid-sized view already names plenty of towns.
    private static let bend = 0.7

    /// How big a city has to be to get a name at this zoom: only the giants on the whole world, more and more
    /// towns as the map is brought closer.
    public static func minimumPopulation(zoom: Double) -> Int {
        let progress = pow(min(max(log2(max(zoom, MapViewport.minZoom)) / log2(MapViewport.maxZoom), 0), 1), bend)
        return Int((largest * pow(smallest / largest, progress)).rounded())
    }
}
