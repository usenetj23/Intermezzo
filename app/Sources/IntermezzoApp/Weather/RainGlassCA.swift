import AppKit
import SwiftUI

// Rain on a window pane, Core Animation edition.
//
// Look (after the raindrop-fx reference): a cool, steamy pane over the blurred
// desktop, a fine film of condensation (thousands of micro-droplets baked into
// ONE image), larger lens-like drops that sit, creep and slide in stop-and-go
// jerks leaving a clear wet trail that slowly fogs over again.
//
// Cost: the app draws nothing per frame. Drops are sprite layers, motion is
// CAKeyframeAnimation on the render server, and only a 1–2 s timer on the main
// thread spawns an occasional slide. (The previous CoreGraphics simulation
// cost 50–100% CPU and ~500 MB; this one ~2% CPU.)

struct RainGlassCARepresentable: NSViewRepresentable {
    let intensity: Double
    let storm: Bool
    var windKmh: Double

    func makeNSView(context: Context) -> RainGlassCAView {
        let v = RainGlassCAView()
        v.intensity = intensity
        v.storm = storm
        v.windKmh = windKmh
        return v
    }

    func updateNSView(_ v: RainGlassCAView, context: Context) {
        v.windKmh = windKmh
    }
}

final class RainGlassCAView: NSView {
    var intensity = 1.0
    var storm = false
    var windKmh = 0.0

    private var builtSize = CGSize.zero
    private var dropLayers: [CALayer] = []
    private var sliding = Set<ObjectIdentifier>()
    private var spawnTimer: Timer?
    private var flashTimer: Timer?
    private let flash = CALayer()
    private var rng = SystemRandomNumberGenerator()

    private static let dropSprite: CGImage? = makeDropSprite()
    private static let trailSprite: CGImage? = makeTrailSprite()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// Effect layers are decoration: they must never take mouse events from the
    /// break controls beneath/above them (SwiftUI's allowsHitTesting does not
    /// make an embedded NSView transparent to AppKit hit-testing).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.width > 200, bounds.size != builtSize { build() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        spawnTimer?.invalidate(); spawnTimer = nil
        flashTimer?.invalidate(); flashTimer = nil
        guard window != nil else { return }
        scheduleSpawn()
        if storm { scheduleFlash() }
    }

    // MARK: Scene

    private func build() {
        guard let root = layer else { return }
        builtSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        dropLayers.removeAll()
        sliding.removeAll()
        let w = bounds.width, h = bounds.height

        // Cool, steamy pane.
        let veil = CAGradientLayer()
        veil.frame = bounds
        veil.colors = [NSColor(red: 0.66, green: 0.77, blue: 0.90, alpha: 0.30).cgColor,
                       NSColor(red: 0.34, green: 0.45, blue: 0.58, alpha: 0.20).cgColor,
                       NSColor(red: 0.18, green: 0.25, blue: 0.34, alpha: 0.22).cgColor]
        veil.locations = [0, 0.55, 1]
        root.addSublayer(veil)

        // Condensation film: one half-resolution image, stretched.
        let mist = CALayer()
        mist.frame = bounds
        mist.contents = Self.makeMist(width: Int(w / 2), height: Int(h / 2), intensity: intensity)
        mist.contentsGravity = .resize
        root.addSublayer(mist)

        // Edge vignette keeps the centre readable.
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.frame = bounds
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.30).cgColor]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.0, y: 1.0)
        root.addSublayer(vignette)

        // Resting drops, mostly small with a few big ones.
        let count = Int(34 * intensity * (storm ? 1.3 : 1))
        for _ in 0..<count {
            let layer = makeDrop(in: bounds)
            root.addSublayer(layer)
            dropLayers.append(layer)
        }

        flash.frame = bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
    }

    private func makeDrop(in rect: CGRect) -> CALayer {
        // Size distribution: lots of small, a few large.
        let t = CGFloat.random(in: 0...1, using: &rng)
        let diameter = 5 + pow(t, 2.2) * 26
        let layer = CALayer()
        layer.contents = Self.dropSprite
        layer.contentsGravity = .resize
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter * 1.18)
        layer.position = CGPoint(x: CGFloat.random(in: 0...rect.width, using: &rng),
                                 y: CGFloat.random(in: rect.height * 0.08...rect.height, using: &rng))
        layer.opacity = Float(0.75 + 0.25 * t)
        return layer
    }

    // MARK: Motion

    private func scheduleSpawn() {
        let base = storm ? 1.1 : 2.2
        let interval = base / max(0.5, intensity)
        spawnTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.spawnSlide() }
        }
        RunLoop.main.add(spawnTimer!, forMode: .common)
    }

    private func spawnSlide() {
        guard window?.isVisible == true, let root = layer, !dropLayers.isEmpty else { return }
        // Only big enough drops are heavy enough to run.
        let candidates = dropLayers.filter { $0.bounds.width > 11 && !sliding.contains(ObjectIdentifier($0)) }
        guard let drop = candidates.randomElement() else { return }
        sliding.insert(ObjectIdentifier(drop))

        let start = drop.position
        let travel = CGFloat.random(in: 120...(bounds.height * 0.55), using: &rng)
        let drift = CGFloat(windKmh) * 0.006 * travel
        let duration = Double.random(in: 4.5...9.5, using: &rng) * (storm ? 0.6 : 1)

        // Stop-and-go: 4–6 jerks separated by pauses.
        let steps = Int.random(in: 4...6, using: &rng)
        var weights = (0..<steps).map { _ in CGFloat.random(in: 0.5...1.6, using: &rng) }
        let sum = weights.reduce(0, +)
        weights = weights.map { $0 / sum }
        var yValues: [CGFloat] = [start.y]
        var xValues: [CGFloat] = [start.x]
        var times: [NSNumber] = [0]
        var tf: [CAMediaTimingFunction] = []
        var acc: CGFloat = 0
        for (i, wgt) in weights.enumerated() {
            acc += wgt
            let phase = Double(i) / Double(steps)
            let moveEnd = phase + 0.55 / Double(steps)                      // slide…
            let holdEnd = Double(i + 1) / Double(steps)                     // …then pause
            let y = max(0, start.y - travel * acc)
            let x = start.x + drift * acc + CGFloat.random(in: -2...2, using: &rng)
            yValues += [y, y]; xValues += [x, x]
            times += [NSNumber(value: moveEnd), NSNumber(value: holdEnd)]
            tf += [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear)]
        }
        let totalTravel = travel * acc

        // Wet trail: grows behind the drop, then fogs over.
        let trail = CALayer()
        trail.contents = Self.trailSprite
        trail.contentsGravity = .resize
        trail.anchorPoint = CGPoint(x: 0.5, y: 1)
        trail.position = CGPoint(x: start.x, y: start.y)
        trail.bounds = CGRect(x: 0, y: 0, width: max(4, drop.bounds.width * 0.85), height: 0)
        root.insertSublayer(trail, below: drop)

        let moveY = CAKeyframeAnimation(keyPath: "position.y")
        moveY.values = yValues; moveY.keyTimes = times; moveY.timingFunctions = tf
        let moveX = CAKeyframeAnimation(keyPath: "position.x")
        moveX.values = xValues; moveX.keyTimes = times; moveX.timingFunctions = tf
        let grow = CAKeyframeAnimation(keyPath: "bounds.size.height")
        grow.values = yValues.map { start.y - $0 }; grow.keyTimes = times; grow.timingFunctions = tf
        let shift = CAKeyframeAnimation(keyPath: "position.x")
        shift.values = xValues; shift.keyTimes = times; shift.timingFunctions = tf

        for a in [moveY, moveX, grow, shift] {
            a.duration = duration
            a.isRemovedOnCompletion = false
            a.fillMode = .forwards
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak drop, weak trail] in
            MainActor.assumeIsolated {
                guard let self, let drop else { return }
                // Commit the final model values, then let the trail fog over.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                drop.removeAllAnimations()
                drop.position = CGPoint(x: xValues.last ?? start.x, y: yValues.last ?? start.y)
                CATransaction.commit()
                self.sliding.remove(ObjectIdentifier(drop))
                if let trail {
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(7)
                    CATransaction.setCompletionBlock { trail.removeFromSuperlayer() }
                    trail.opacity = 0
                    CATransaction.commit()
                }
            }
        }
        drop.add(moveY, forKey: "y")
        drop.add(moveX, forKey: "x")
        trail.add(grow, forKey: "grow")
        trail.add(shift, forKey: "shift")
        _ = totalTravel
        CATransaction.commit()
    }

    private func scheduleFlash() {
        let delay = Double.random(in: 6...14, using: &rng)
        flashTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isVisible == true else { return }
                let a = CAKeyframeAnimation(keyPath: "opacity")
                a.values = [0, 0.42, 0.08, 0.30, 0]
                a.keyTimes = [0, 0.08, 0.22, 0.34, 1]
                a.duration = 0.7
                self.flash.add(a, forKey: "flash")
                self.scheduleFlash()
            }
        }
        RunLoop.main.add(flashTimer!, forMode: .common)
    }

    // MARK: Sprites

    private static func makeMist(width w: Int, height h: Int, intensity: Double) -> CGImage? {
        guard w > 20, h > 20,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var state: UInt64 = 0xD1B5_4A32_D192_ED03
        func rnd() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
        }
        let fw = CGFloat(w), fh = CGFloat(h)
        let n = Int(Double(w * h) / 150.0 * min(1.3, intensity))
        for _ in 0..<n {
            let r = 0.5 + rnd() * rnd() * 2.2
            let x = rnd() * fw
            // denser toward the top, like condensation on a real pane
            let y = fh - rnd() * rnd() * fh
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.10 + rnd() * 0.08))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.45 + rnd() * 0.45))
            ctx.fillEllipse(in: CGRect(x: x - r * 0.55, y: y - r * 0.75, width: r * 0.8, height: r * 0.7))
        }
        return ctx.makeImage()
    }

    /// Glass bead: dark rim, faint cool body, bright caustic crescent at the
    /// bottom (light focused through the drop) and a small specular glint.
    private static func makeDropSprite() -> CGImage? {
        let n = 128
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGPoint(x: 64, y: 64), r: CGFloat = 60
        let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        // cool body, darker toward the rim
        if let body = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.75, green: 0.86, blue: 1, alpha: 0.10),
                                                           CGColor(red: 0.05, green: 0.08, blue: 0.14, alpha: 0.38)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(body, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
        }
        // caustic crescent (bottom)
        if let caustic = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.65),
                                                              CGColor(gray: 1, alpha: 0)] as CFArray,
                                    locations: [0, 1]) {
            ctx.drawRadialGradient(caustic, startCenter: CGPoint(x: 64, y: 12), startRadius: 0,
                                   endCenter: CGPoint(x: 64, y: 12), endRadius: 62, options: [])
        }
        ctx.restoreGState()

        // rim: dark outside, light inside along the lower edge
        ctx.setLineWidth(4)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.38))
        ctx.strokeEllipse(in: circle.insetBy(dx: 2, dy: 2))
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: n, height: 56))
        ctx.setLineWidth(2)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
        ctx.strokeEllipse(in: circle.insetBy(dx: 6, dy: 6))
        ctx.restoreGState()

        // specular glint, upper left
        if let glint = CGGradient(colorsSpace: cs, colors: [CGColor(gray: 1, alpha: 0.95),
                                                            CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 1]) {
            ctx.drawRadialGradient(glint, startCenter: CGPoint(x: 42, y: 92), startRadius: 0,
                                   endCenter: CGPoint(x: 42, y: 92), endRadius: 15, options: [])
        }
        return ctx.makeImage()
    }

    /// Clear wet streak: soft-edged vertical band, brightest along the centre.
    private static func makeTrailSprite() -> CGImage? {
        let w = 16, h = 64
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Rows run top (y = h, start of the slide) → bottom (y = 0, at the drop):
        // the streak is faint where the drop began and strongest right behind it.
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        for row in 0..<h {
            let t = CGFloat(row) / CGFloat(h - 1)                    // 0 = bottom (drop) … 1 = top
            let strength = pow(1 - t, 1.6) * 0.30
            guard strength > 0.004, let g = CGGradient(
                colorsSpace: cs,
                colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: strength),
                         CGColor(gray: 1, alpha: 0)] as CFArray,
                locations: [0, 0.5, 1]) else { continue }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: row, width: w, height: 1))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(w), y: 0), options: [])
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
