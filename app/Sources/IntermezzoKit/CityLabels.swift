import CoreGraphics
import Foundation

// Which city names the map shows: the biggest first, as many as fit without touching each other.

public enum CityLabels {
    public struct Placed: Equatable, Sendable {
        public let city: WorldMap.City
        public let point: CGPoint
        public let labelRect: CGRect
    }

    private static let dotRadius = 3.0
    private static let gap = 4.0
    private static let spacing = 2.0

    public static func place(cities: [WorldMap.City], viewport: MapViewport, size: CGSize,
                             labelSize: (String) -> CGSize, maximum: Int = 150) -> [Placed] {
        let window = CGRect(origin: .zero, size: size)
        let minimum = CityVisibility.minimumPopulation(zoom: viewport.zoom)
        var placed: [Placed] = []
        var taken: [CGRect] = []
        for city in biggestFirst(cities) {
            if city.population < minimum || placed.count >= maximum { break }
            guard let point = onScreen(city, viewport, size, window) else { continue }
            let text = labelSize(city.name)
            let label = CGRect(x: point.x + dotRadius + gap, y: point.y - text.height / 2, width: text.width, height: text.height)
            let dot = CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            guard window.contains(label),
                  !taken.contains(where: { $0.insetBy(dx: -spacing, dy: -spacing).intersects(label) || $0.intersects(dot) })
            else { continue }
            placed.append(Placed(city: city, point: point, labelRect: label))
            taken += [label, dot]
        }
        return placed
    }

    /// The map keeps its cities biggest first, so this is a single cheap pass over them every frame.
    private static func biggestFirst(_ cities: [WorldMap.City]) -> [WorldMap.City] {
        zip(cities, cities.dropFirst()).allSatisfy { $0.population >= $1.population }
            ? cities : cities.sorted { $0.population > $1.population }
    }

    /// The city's place in the window, trying the map's neighbouring copies across the date line.
    private static func onScreen(_ city: WorldMap.City, _ viewport: MapViewport, _ size: CGSize, _ window: CGRect) -> CGPoint? {
        for shift in [0.0, 360, -360] {
            let location = GeoPoint(latitude: city.location.latitude, longitude: city.location.longitude + shift)
            let point = viewport.point(for: location, in: size)
            if window.contains(point) { return point }
        }
        return nil
    }
}
