import AppKit
import SwiftUI

/// Holographic foil surface: a deep violet-graphite base, a slowly turning rainbow (conic) layer,
/// a second diagonal rainbow that drifts, a sheen band that sweeps across every few seconds and
/// fine foil grain. Core Animation only — the render server does the work, the app does none.
struct HoloFoilBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> HoloFoilNSView { HoloFoilNSView() }
    func updateNSView(_ v: HoloFoilNSView, context: Context) {}
}

final class HoloFoilNSView: NSView {
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
        if bounds.width > 20, bounds.size != builtSize { build() }
    }

    /// Core Animation strips animations from a layer that leaves the render tree (panel ordered out,
    /// card scrolled away), so the foil froze after a while. Rebuild whenever the view lands in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        builtSize = .zero
        needsLayout = true
    }

    private func slow(_ a: CAAnimation) {
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 24, preferred: 15)
        a.isRemovedOnCompletion = false
    }

    private func build() {
        guard let root = layer else { return }
        builtSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = bounds.width, h = bounds.height
        let big = max(w, h) * 2.2

        // 1. base: deep violet → graphite
        let base = CAGradientLayer()
        base.frame = bounds
        base.colors = [NSColor(red: 0.20, green: 0.15, blue: 0.30, alpha: 1).cgColor,
                       NSColor(red: 0.09, green: 0.10, blue: 0.18, alpha: 1).cgColor]
        root.addSublayer(base)

        // 2. rainbow, turning slowly
        let rainbow = CAGradientLayer()
        rainbow.type = .conic
        rainbow.bounds = CGRect(x: 0, y: 0, width: big, height: big)
        rainbow.position = CGPoint(x: w * 0.5, y: h * 0.5)
        rainbow.startPoint = CGPoint(x: 0.5, y: 0.5)
        rainbow.endPoint = CGPoint(x: 0.5, y: 1)
        let hues: [CGFloat] = [0.86, 0.72, 0.60, 0.50, 0.38, 0.14, 0.04, 0.86]
        rainbow.colors = hues.map { NSColor(hue: $0, saturation: 0.75, brightness: 1.0, alpha: 0.42).cgColor }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0; spin.toValue = 2 * Double.pi
        spin.duration = 70; spin.repeatCount = .infinity; slow(spin)
        rainbow.add(spin, forKey: "spin")
        root.addSublayer(rainbow)

        // 3. diagonal rainbow that drifts (gives the foil its "view-angle" colour shift)
        let drift = CAGradientLayer()
        drift.bounds = CGRect(x: 0, y: 0, width: big, height: big)      // edges stay far outside the panel
        drift.position = CGPoint(x: w * 0.5, y: h * 0.5)
        drift.colors = [NSColor(hue: 0.52, saturation: 0.8, brightness: 1, alpha: 0).cgColor,
                        NSColor(hue: 0.52, saturation: 0.8, brightness: 1, alpha: 0.30).cgColor,
                        NSColor(hue: 0.86, saturation: 0.7, brightness: 1, alpha: 0.30).cgColor,
                        NSColor(hue: 0.13, saturation: 0.8, brightness: 1, alpha: 0.26).cgColor,
                        NSColor(hue: 0.13, saturation: 0.8, brightness: 1, alpha: 0).cgColor]
        drift.locations = [0.30, 0.42, 0.50, 0.58, 0.70]               // bands only in the middle; clear elsewhere
        drift.startPoint = CGPoint(x: 0, y: 0); drift.endPoint = CGPoint(x: 1, y: 1)
        drift.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 5))
        let sway = CABasicAnimation(keyPath: "position")
        sway.fromValue = NSValue(point: CGPoint(x: w * 0.5 - w * 0.35, y: h * 0.5 - h * 0.3))
        sway.toValue = NSValue(point: CGPoint(x: w * 0.5 + w * 0.35, y: h * 0.5 + h * 0.3))
        sway.duration = 14; sway.autoreverses = true; sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut); slow(sway)
        drift.add(sway, forKey: "sway")
        root.addSublayer(drift)

        // 4. foil grain
        if let grain = SurfaceTexture.grain {
            let g = CALayer()
            g.frame = bounds
            g.backgroundColor = NSColor(patternImage: NSImage(cgImage: grain, size: NSSize(width: 128, height: 128))).cgColor
            g.opacity = 0.7
            root.addSublayer(g)
        }

        // 5. sheen band sweeping across, then resting
        let sheen = CAGradientLayer()
        sheen.bounds = CGRect(x: 0, y: 0, width: big, height: max(w, h) * 0.34)
        sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                        NSColor.white.withAlphaComponent(0.34).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        sheen.locations = [0, 0.5, 1]
        sheen.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 4))
        let sweep = CAKeyframeAnimation(keyPath: "position")
        let a = NSValue(point: CGPoint(x: -w * 0.4, y: h * 1.3))
        let b = NSValue(point: CGPoint(x: w * 1.4, y: -h * 0.3))
        sweep.values = [a, b, b]
        sweep.keyTimes = [0, 0.38, 1]
        sweep.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        sweep.duration = 9; sweep.repeatCount = .infinity; slow(sweep)
        sheen.position = CGPoint(x: -w * 0.4, y: h * 1.3)
        sheen.add(sweep, forKey: "sweep")
        root.addSublayer(sheen)
    }
}
