import Foundation

/// A critically damped spring toward a moving target: the value starts slowly, speeds up and settles
/// without overshoot, and a new target in mid-way keeps the speed (no jerk). Used for the screen colour.
public enum SmoothDamp {
    /// One step of `dt` seconds. `smoothTime` is roughly the time to cover most of the distance.
    public static func step(value: Double, target: Double, velocity: inout Double,
                            smoothTime: Double, dt: Double) -> Double {
        let time = max(smoothTime, 0.0001)
        let omega = 2 / time
        let x = omega * dt
        let decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = value - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * decay
        var next = target + (change + temp) * decay
        // Never run past the target (a large step could).
        if (target - value > 0) == (next > target) && next != target { next = target; velocity = 0 }
        return next
    }

    /// Close enough to stop: within `distance` of the target and nearly at rest.
    public static func settled(value: Double, target: Double, velocity: Double,
                               distance: Double = 1, speed: Double = 2) -> Bool {
        abs(target - value) <= distance && abs(velocity) <= speed
    }
}
