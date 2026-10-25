import AppKit
import SwiftUI
import IntermezzoKit

/// Sun, photographic style — all Core Animation layers, no per-frame drawing:
/// soft crepuscular beams (conic gradient with random bands, radially masked and
/// slowly counter-rotating), halo + bloom + hot core, anamorphic streak, lens-flare
/// ghosts on the sun→centre axis, and dust motes drifting through the light.
/// Position and colour come from the real sun (azimuth/altitude for the saved location).
final class SunSkyNSView: NSView {
    private var builtSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.width > 200, bounds.size != builtSize { build() }
    }

    // MARK: Sprites

    private static let softDisc: CGImage? = radialImage(size: 64, stops: [(0, 1), (1, 0)])
    private static let hexagon: CGImage? = {
        let n = 128
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let c = CGPoint(x: 64, y: 64)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3
            let p = CGPoint(x: c.x + cos(a) * 58, y: c.y + sin(a) * 58)
            i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
        }
        ctx.closePath()
        ctx.fillPath()
        return ctx.makeImage()
    }()

    /// White radial sprite; `stops` are (location, alpha).
    private static func radialImage(size n: Int, stops: [(CGFloat, CGFloat)]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: stops.map { CGColor(gray: 1, alpha: $0.1) } as CFArray,
                                 locations: stops.map { $0.0 }) else { return nil }
        let c = CGPoint(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(n) / 2, options: [])
        return ctx.makeImage()
    }

    // MARK: Layers

    private func radial(_ colors: [NSColor], _ locations: [NSNumber], size: CGFloat, at p: CGPoint) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.colors = colors.map(\.cgColor)
        g.locations = locations
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        g.position = p
        return g
    }

    private func slow(_ a: CAAnimation) {
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: 12, preferred: 8)
    }

    private func build() {
        guard let root = layer else { return }
        builtSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = bounds.width, h = bounds.height

        // Real sun position for the saved location (fallback: top-right).
        let d = UserDefaults.standard
        var altitude = 45.0
        var sun = CGPoint(x: w * 0.82, y: h * 0.86)
        if let lat = d.object(forKey: GlassKeys.lat) as? Double,
           let lon = d.object(forKey: GlassKeys.lon) as? Double {
            let p = Sun.position(date: Date(), latitude: lat, longitude: lon)
            altitude = p.altitudeDegrees
            let fx = 0.08 + (min(270, max(90, p.azimuthDegrees)) - 90) / 180 * 0.84
            let fyTop = max(0.07, 0.80 - max(0, min(60, altitude)) / 60 * 0.73)
            sun = CGPoint(x: w * fx, y: h * (1 - fyTop))
        }
        let night = altitude < -2
        let warm: NSColor = night ? NSColor(red: 0.62, green: 0.72, blue: 1.0, alpha: 1)
            : altitude < 8 ? NSColor(red: 1.0, green: 0.42, blue: 0.16, alpha: 1)
            : altitude < 22 ? NSColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
            : altitude < 40 ? NSColor(red: 1.0, green: 0.82, blue: 0.48, alpha: 1)
            : NSColor(red: 1.0, green: 0.92, blue: 0.70, alpha: 1)
        func tint(_ a: CGFloat, mix white: CGFloat = 0) -> NSColor {
            warm.blended(withFraction: white, of: .white)!.withAlphaComponent(a)
        }
        let dim: CGFloat = night ? 0.45 : 1

        // Atmospheric wash from the sun's side.
        let wash = CAGradientLayer()
        wash.frame = bounds
        wash.colors = [tint(0.16 * dim).cgColor, tint(0.05 * dim).cgColor, NSColor.clear.cgColor]
        wash.locations = [0, 0.5, 1]
        wash.startPoint = CGPoint(x: sun.x / w, y: sun.y / h)
        wash.endPoint = CGPoint(x: sun.x / w < 0.5 ? 1 : 0, y: 0)
        root.addSublayer(wash)

        // Wide halo (breathes very slowly).
        let halo = radial([tint(0.26 * dim), tint(0.09 * dim), tint(0)], [0, 0.22, 1], size: 1700, at: sun)
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.82; breathe.toValue = 1.0; breathe.duration = 7
        breathe.autoreverses = true; breathe.repeatCount = .infinity; slow(breathe)
        halo.add(breathe, forKey: "breathe")
        root.addSublayer(halo)

        if !night {
            // Crepuscular beams: two conic layers of random soft bands, radially masked.
            var seed: UInt64 = 0xA17E_55ED_2026
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
            }
            let beams = CALayer()
            beams.bounds = CGRect(x: 0, y: 0, width: 2200, height: 2200)
            beams.position = sun
            let mask = CAGradientLayer()
            mask.type = .radial
            mask.frame = beams.bounds
            mask.colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
            mask.locations = [0, 0.35, 1]
            mask.startPoint = CGPoint(x: 0.5, y: 0.5); mask.endPoint = CGPoint(x: 1, y: 1)
            beams.mask = mask
            for (i, period) in [420.0, -270.0].enumerated() {
                let conic = CAGradientLayer()
                conic.type = .conic
                conic.frame = beams.bounds
                conic.startPoint = CGPoint(x: 0.5, y: 0.5)
                conic.endPoint = CGPoint(x: 0.5, y: 1)
                let n = 84
                var alphas = (0..<n).map { _ in pow(rnd(), 2.4) * (i == 0 ? 0.20 : 0.13) }
                alphas[n - 1] = alphas[0]                                 // seamless wrap
                conic.colors = alphas.map { tint($0, mix: 0.35).cgColor }
                conic.locations = (0..<n).map { NSNumber(value: Double($0) / Double(n - 1)) }
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = 2 * Double.pi * (period < 0 ? -1 : 1)
                spin.duration = abs(period); spin.repeatCount = .infinity; slow(spin)
                conic.add(spin, forKey: "spin")
                beams.addSublayer(conic)
            }
            root.addSublayer(beams)
        }

        // Bloom + hot core.
        root.addSublayer(radial([tint(night ? 0.35 : 0.70, mix: 0.5), tint(night ? 0.14 : 0.30), tint(0)],
                                [0, 0.28, 1], size: night ? 360 : 640, at: sun))
        root.addSublayer(radial([NSColor.white.withAlphaComponent(night ? 0.8 : 1.0),
                                 tint(night ? 0.5 : 0.9, mix: 0.6), tint(0)],
                                [0, 0.30, 1], size: night ? 70 : 130, at: sun))

        guard !night else { return }

        // Anamorphic streak.
        let streak = CAGradientLayer()
        streak.colors = [NSColor.clear.cgColor, tint(0.55, mix: 0.7).cgColor, NSColor.clear.cgColor]
        streak.locations = [0, 0.5, 1]
        streak.startPoint = CGPoint(x: 0, y: 0.5); streak.endPoint = CGPoint(x: 1, y: 0.5)
        streak.bounds = CGRect(x: 0, y: 0, width: 1300, height: 6)
        streak.cornerRadius = 3
        streak.position = sun
        root.addSublayer(streak)

        // Lens-flare ghosts along the sun → centre axis.
        let centre = CGPoint(x: w / 2, y: h / 2)
        let axis = CGPoint(x: centre.x - sun.x, y: centre.y - sun.y)
        let ghosts: [(CGFloat, CGFloat, NSColor)] = [
            (0.55, 90, NSColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)),
            (0.95, 170, NSColor(red: 1.0, green: 0.62, blue: 0.30, alpha: 1)),
            (1.35, 60, NSColor(red: 0.95, green: 0.45, blue: 0.85, alpha: 1)),
            (1.85, 230, NSColor(red: 0.50, green: 1.0, blue: 0.70, alpha: 1)),
        ]
        for (k, size, color) in ghosts {
            let p = CGPoint(x: sun.x + axis.x * k, y: sun.y + axis.y * k)
            root.addSublayer(radial([color.withAlphaComponent(0), color.withAlphaComponent(0.03),
                                     color.withAlphaComponent(0.16), color.withAlphaComponent(0)],
                                    [0, 0.55, 0.86, 1], size: size, at: p))
        }
        let hex = CALayer()
        hex.contents = Self.hexagon
        hex.bounds = CGRect(x: 0, y: 0, width: 74, height: 74)
        hex.position = CGPoint(x: sun.x + axis.x * 1.15, y: sun.y + axis.y * 1.15)
        hex.opacity = 0.10
        hex.backgroundColor = nil
        hex.contentsGravity = .resize
        root.addSublayer(hex)

        // Dust motes drifting in the light.
        let motes = CAEmitterLayer()
        motes.frame = bounds
        motes.emitterShape = .rectangle
        motes.emitterMode = .volume
        // Only in the lit cone around the sun, not across the whole frame.
        motes.emitterPosition = CGPoint(x: (sun.x * 2 + w / 2) / 3, y: (sun.y * 2 + h / 2) / 3)
        motes.emitterSize = CGSize(width: w * 0.55, height: h * 0.55)
        let cell = CAEmitterCell()
        cell.contents = Self.softDisc
        cell.birthRate = 3.2
        cell.lifetime = 22
        cell.velocity = 6
        cell.velocityRange = 5
        cell.emissionRange = 2 * .pi
        cell.scale = 0.065
        cell.scaleRange = 0.05
        cell.alphaRange = 0.35
        cell.color = tint(0.38, mix: 0.6).cgColor
        motes.emitterCells = [cell]
        motes.timeOffset = 22
        root.addSublayer(motes)
    }
}
