import CoreGraphics

/// Geometry for one picture stretched across several screens (AppKit coordinates, y up).
public enum SpanLayout {
    public static func union(_ frames: [CGRect]) -> CGRect? {
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    /// How far to shift the union-sized picture so that `screen` shows its own part (SwiftUI offset, y down).
    public static func offset(of screen: CGRect, in union: CGRect) -> CGSize {
        CGSize(width: -(screen.minX - union.minX), height: -(union.maxY - screen.maxY))
    }
}
