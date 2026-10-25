import Foundation

/// Slowly drifting colour blobs for the animated surface. Pure maths: the view only draws.
public enum AuroraMotion {
    public struct Blob: Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
        /// Radius as a fraction of the surface's longer side.
        public let radius: Double
        public let centre: (x: Double, y: Double)
        public let amplitude: (x: Double, y: Double)
        /// Radians per second.
        public let speed: (x: Double, y: Double)
        public let phase: (x: Double, y: Double)

        public static func == (l: Blob, r: Blob) -> Bool {
            l.red == r.red && l.green == r.green && l.blue == r.blue && l.radius == r.radius
        }
    }

    public static let blobs: [Blob] = [
        Blob(red: 0.20, green: 0.55, blue: 1.00, radius: 0.75, centre: (0.70, 0.25), amplitude: (0.25, 0.20), speed: (0.050, 0.037), phase: (0.0, 1.0)),
        Blob(red: 1.00, green: 0.72, blue: 0.33, radius: 0.70, centre: (0.30, 0.80), amplitude: (0.28, 0.15), speed: (0.041, 0.057), phase: (2.0, 0.5)),
        Blob(red: 1.00, green: 0.38, blue: 0.45, radius: 0.55, centre: (0.10, 0.45), amplitude: (0.15, 0.30), speed: (0.063, 0.044), phase: (4.0, 3.0)),
        Blob(red: 0.62, green: 0.52, blue: 0.95, radius: 0.60, centre: (0.60, 0.70), amplitude: (0.30, 0.22), speed: (0.035, 0.052), phase: (1.0, 5.0)),
        Blob(red: 0.45, green: 0.85, blue: 1.00, radius: 0.50, centre: (0.90, 0.85), amplitude: (0.12, 0.12), speed: (0.058, 0.040), phase: (3.0, 2.0)),
    ]

    /// `c + a·sin(speed·t + phase)` as an autoreversing Core Animation swing from c-a to c+a:
    /// one leg lasts `halfPeriod`, and `offset` (the animation's timeOffset) starts it at the sine's phase.
    public static func swingTiming(speed: Double, phase: Double) -> (halfPeriod: Double, offset: Double) {
        let halfPeriod = Double.pi / speed
        let raw = (phase + Double.pi / 2) / speed
        let offset = raw.truncatingRemainder(dividingBy: 2 * halfPeriod)
        return (halfPeriod, offset < 0 ? offset + 2 * halfPeriod : offset)
    }

    /// Centre of a blob in unit coordinates (0...1, y down) at `time` seconds.
    public static func position(blob index: Int, time: Double) -> (x: Double, y: Double) {
        guard blobs.indices.contains(index) else { return (0.5, 0.5) }
        let b = blobs[index]
        return (b.centre.x + b.amplitude.x * sin(time * b.speed.x + b.phase.x),
                b.centre.y + b.amplitude.y * sin(time * b.speed.y + b.phase.y))
    }
}
