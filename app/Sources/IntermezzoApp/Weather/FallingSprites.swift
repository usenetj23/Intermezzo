import AppKit

/// Falling sprites as plain layers with looping animations — deterministic and cheap:
/// every sprite has its own random phase (`timeOffset`), so the sky is evenly populated
/// from the first frame, and all motion runs in the render server (no app work per frame).
/// (CAEmitterLayer could not be pre-run or burst reliably on this macOS.)
enum FallingSprites {
    struct Spec {
        let image: CGImage
        let size: CGSize          // points
        let speed: CGFloat        // fall speed, px/s
        let drift: CGFloat        // horizontal px/s (wind)
        let alpha: Float
        var spin: CGFloat = 0     // degrees/s (sign = direction), 0 = none
        var sway: CGFloat = 0     // ± px of lazy side-to-side motion
    }

    @MainActor
    static func layer(_ s: Spec, in bounds: CGRect, rng: inout SystemRandomNumberGenerator) -> CALayer {
        let margin = max(s.size.width, s.size.height) + 20
        let x0 = CGFloat.random(in: -80...(bounds.width + 80), using: &rng)
        let fall = bounds.height + 2 * margin
        let duration = Double(fall / max(s.speed, 1))

        let l = CALayer()
        l.contents = s.image
        l.contentsGravity = .resize
        l.bounds = CGRect(origin: .zero, size: s.size)
        l.opacity = s.alpha
        l.position = CGPoint(x: x0, y: bounds.height + margin)

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: CGPoint(x: x0, y: bounds.height + margin))
        move.toValue = NSValue(point: CGPoint(x: x0 + s.drift * CGFloat(duration), y: -margin))
        move.duration = duration
        move.repeatCount = .infinity
        move.timeOffset = Double.random(in: 0...duration, using: &rng)
        move.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 40, preferred: 30)
        l.add(move, forKey: "fall")

        if s.sway > 0 {
            let sway = CABasicAnimation(keyPath: "transform.translation.x")
            sway.fromValue = -s.sway; sway.toValue = s.sway
            sway.duration = Double.random(in: 2.0...4.6, using: &rng)
            sway.autoreverses = true; sway.repeatCount = .infinity
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sway.timeOffset = Double.random(in: 0...4, using: &rng)
            sway.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 40, preferred: 30)
            l.add(sway, forKey: "sway")
        }
        if s.spin != 0 {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = (s.spin < 0 ? -1.0 : 1.0) * 2 * Double.pi
            spin.duration = 360 / Double(abs(s.spin))
            spin.repeatCount = .infinity
            spin.timeOffset = Double.random(in: 0...spin.duration, using: &rng)
            spin.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 20)
            l.add(spin, forKey: "spin")
        }
        return l
    }
}
