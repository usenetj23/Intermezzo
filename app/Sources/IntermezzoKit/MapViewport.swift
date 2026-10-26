import CoreGraphics
import Foundation

// A window onto the world map in the plain (equirectangular) projection: one degree is the same number of
// points east-west and north-south. At zoom 1 the whole 360° fits the view's width. Pure geometry.

public struct MapViewport: Equatable, Sendable {
    public static let minZoom = 1.0
    /// About half a kilometre per point or finer in an 800-point-wide view.
    public static let maxZoom = 200.0
    private static let kilometresPerDegree = 111.32

    public var center: GeoPoint
    public var zoom: Double

    public init(center: GeoPoint = GeoPoint(latitude: 20, longitude: 10), zoom: Double = 1) {
        self.center = center
        self.zoom = min(max(zoom, Self.minZoom), Self.maxZoom)
    }

    private func pointsPerDegree(in size: CGSize) -> Double { max(size.width, 1) * zoom / 360 }

    public func point(for geo: GeoPoint, in size: CGSize) -> CGPoint {
        let scale = pointsPerDegree(in: size)
        return CGPoint(x: max(size.width, 1) / 2 + (geo.longitude - center.longitude) * scale,
                       y: max(size.height, 1) / 2 + (center.latitude - geo.latitude) * scale)
    }

    public func geo(at point: CGPoint, in size: CGSize) -> GeoPoint {
        let scale = pointsPerDegree(in: size)
        return GeoPoint(latitude: Self.clampedLatitude(center.latitude - (point.y - max(size.height, 1) / 2) / scale),
                        longitude: Self.wrapped(center.longitude + (point.x - max(size.width, 1) / 2) / scale))
    }

    /// Zooms so that the place under `anchor` stays under it.
    public func zoomed(by factor: Double, around anchor: CGPoint, in size: CGSize) -> MapViewport {
        let under = geo(at: anchor, in: size)
        var next = MapViewport(center: center, zoom: zoom * factor)
        let scale = next.pointsPerDegree(in: size)
        next.center = GeoPoint(
            latitude: Self.clampedLatitude(under.latitude + (anchor.y - max(size.height, 1) / 2) / scale),
            longitude: Self.wrapped(under.longitude - (anchor.x - max(size.width, 1) / 2) / scale))
        return next
    }

    /// Drags the map by `delta` points (the map follows the finger).
    public func panned(by delta: CGSize, in size: CGSize) -> MapViewport {
        let scale = pointsPerDegree(in: size)
        var next = self
        next.center = GeoPoint(latitude: Self.clampedLatitude(center.latitude + delta.height / scale),
                               longitude: Self.wrapped(center.longitude - delta.width / scale))
        return next
    }

    /// At the equator; east-west distances shrink toward the poles.
    public func kilometresPerPixel(in size: CGSize) -> Double {
        Self.kilometresPerDegree / pointsPerDegree(in: size)
    }

    private static func clampedLatitude(_ latitude: Double) -> Double { min(max(latitude, -90), 90) }

    private static func wrapped(_ longitude: Double) -> Double {
        var value = (longitude + 180).truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value - 180
    }
}
