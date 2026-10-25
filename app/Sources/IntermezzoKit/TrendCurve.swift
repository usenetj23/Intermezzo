import Foundation

/// Smooth line through the trend points that never overshoots them nor folds back.
/// Catmull-Rom on unevenly spaced points (real break times) bulged past the neighbours and
/// looped where a short step followed a long one; a monotone cubic (Fritsch–Butland tangents,
/// control points at thirds of each step) keeps every piece between its two points.
public enum TrendCurve {
    public struct Controls: Equatable, Sendable {
        public let c1x, c1y, c2x, c2y: Double
    }

    /// Bezier controls for each piece i (from point i to point i + 1).
    public static func controls(xs: [Double], ys: [Double]) -> [Controls] {
        let n = min(xs.count, ys.count)
        guard n >= 2 else { return [] }
        let h = (0..<(n - 1)).map { max(xs[$0 + 1] - xs[$0], 1e-9) }
        let d = (0..<(n - 1)).map { (ys[$0 + 1] - ys[$0]) / h[$0] }
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for k in 1..<(n - 1) {
            let d0 = d[k - 1], d1 = d[k]
            guard d0 * d1 > 0 else { continue }      // a peak or a flat step: level tangent
            let h0 = h[k - 1], h1 = h[k]
            m[k] = 3 * (h0 + h1) / ((2 * h1 + h0) / d0 + (h1 + 2 * h0) / d1)
        }
        return (0..<(n - 1)).map { i in
            let third = h[i] / 3
            return Controls(c1x: xs[i] + third, c1y: ys[i] + m[i] * third,
                            c2x: xs[i + 1] - third, c2y: ys[i + 1] - m[i + 1] * third)
        }
    }
}
