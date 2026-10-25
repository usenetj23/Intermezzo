import AppKit
import SwiftUI

/// Snow with real six-armed crystals in three depth layers (far: small, sharp, slow;
/// mid: crystals; near: large soft bokeh flakes, fast) — GPU particle emitters, no
/// per-frame work in the app.
struct SnowCARepresentable: NSViewRepresentable {
    var windKmh: Double
    func makeNSView(context: Context) -> SnowNSView {
        let v = SnowNSView()
        v.windKmh = windKmh
        return v
    }
    func updateNSView(_ v: SnowNSView, context: Context) {
        if v.windKmh != windKmh { v.windKmh = windKmh }
    }
}

final class SnowNSView: NSView {
    var windKmh = 0.0 { didSet { if windKmh != oldValue { configure(force: true) } } }
    private var configuredSize = CGSize.zero

    private static let crystals: [CGImage] = (0..<3).compactMap { makeCrystal(variant: $0) }
    private static let bokeh: CGImage? = makeBokeh()
    private static let dot: CGImage? = makeDot()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        configure()
    }

    /// Three depth layers, populated evenly at t = 0 (each sprite has a random phase).
    private func configure(force: Bool = false) {
        guard bounds.width > 100, bounds.height > 100, let root = layer else { return }
        guard force || bounds.size != configuredSize else { return }
        configuredSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let area = bounds.width * bounds.height
        let drift = CGFloat(windKmh) * 1.2
        var rng = SystemRandomNumberGenerator()
        func add(count: Int, _ make: () -> FallingSprites.Spec?) {
            for _ in 0..<min(count, 700) {
                guard let spec = make() else { continue }
                root.addSublayer(FallingSprites.layer(spec, in: bounds, rng: &rng))
            }
        }
        // far: tiny soft dots, slow
        if let dot = Self.dot {
            add(count: Int(area / 5200)) {
                let d = CGFloat.random(in: 3...7)
                return .init(image: dot, size: CGSize(width: d, height: d),
                             speed: CGFloat.random(in: 24...46), drift: drift * 0.5,
                             alpha: Float.random(in: 0.35...0.7), sway: 6)
            }
        }
        // mid: six-armed crystals
        if !Self.crystals.isEmpty {
            add(count: Int(area / 17000)) {
                let d = CGFloat.random(in: 12...30)
                return .init(image: Self.crystals.randomElement()!, size: CGSize(width: d, height: d),
                             speed: CGFloat.random(in: 44...86), drift: drift,
                             alpha: Float.random(in: 0.7...0.95),
                             spin: CGFloat.random(in: -40...40), sway: 22)
            }
        }
        // near: big soft bokeh flakes, fast
        if let bokeh = Self.bokeh {
            add(count: Int(area / 85000)) {
                let d = CGFloat.random(in: 46...110)
                return .init(image: bokeh, size: CGSize(width: d, height: d),
                             speed: CGFloat.random(in: 95...150), drift: drift * 1.6,
                             alpha: Float.random(in: 0.18...0.34), sway: 30)
            }
        }
    }

    // MARK: Sprites (generated once)

    /// Six-armed dendrite with side branches and a soft glow underneath.
    private static func makeCrystal(variant: Int) -> CGImage? {
        let n = 128
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let c = CGPoint(x: 64, y: 64)
        ctx.translateBy(x: c.x, y: c.y)
        ctx.setLineCap(.round)
        let branches: [[(CGFloat, CGFloat)]] = [      // (position along arm 0…1, branch length)
            [(0.42, 0.34), (0.68, 0.24)],
            [(0.30, 0.22), (0.55, 0.36), (0.78, 0.18)],
            [(0.50, 0.40), (0.75, 0.22)],
        ]
        func arms(width: CGFloat, alpha: CGFloat) {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: alpha))
            ctx.setLineWidth(width)
            for k in 0..<6 {
                ctx.saveGState()
                ctx.rotate(by: CGFloat(k) * .pi / 3)
                ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: 56, y: 0))
                for (pos, len) in branches[variant % branches.count] {
                    let p = CGPoint(x: 56 * pos, y: 0)
                    for s in [CGFloat(1), -1] {
                        ctx.move(to: p)
                        ctx.addLine(to: CGPoint(x: p.x + cos(.pi / 3) * 56 * len, y: s * sin(.pi / 3) * 56 * len))
                    }
                }
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        arms(width: 7, alpha: 0.16)      // glow
        arms(width: 2.6, alpha: 0.95)    // crisp ice
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fillEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        return ctx.makeImage()
    }

    private static func makeBokeh() -> CGImage? {
        let n = 128
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0.38),
                                          CGColor(gray: 1, alpha: 0.0)] as CFArray,
                                 locations: [0, 0.78, 1]) else { return nil }
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                               endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
        return ctx.makeImage()
    }

    private static func makeDot() -> CGImage? {
        let n = 32
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                                 locations: [0.3, 1]) else { return nil }
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                               endCenter: CGPoint(x: 16, y: 16), endRadius: 15, options: [])
        return ctx.makeImage()
    }
}
