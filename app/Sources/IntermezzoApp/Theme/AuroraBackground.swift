import AppKit
import IntermezzoKit
import SwiftUI

/// Animated surface: soft colour blobs drifting over a dark base, so white text stays readable.
/// Core Animation layers, like the holo foil: the render server moves the blobs, so the app spends
/// no CPU per frame. The former SwiftUI TimelineView re-laid out the whole hosting window 15 times
/// a second (~14% CPU with the Settings window open). Stands still under Reduce Motion.
struct AuroraBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> AuroraNSView { AuroraNSView() }
    func updateNSView(_ v: AuroraNSView, context: Context) {}
}

final class AuroraNSView: NSView {
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
        if bounds.width > 2, bounds.size != builtSize { build() }
    }

    /// Core Animation strips animations from a layer that leaves the render tree, so rebuild
    /// whenever the view lands in a window (same fix as the holo foil).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        builtSize = .zero
        needsLayout = true
    }

    private func build() {
        guard let root = layer else { return }
        builtSize = bounds.size
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let w = bounds.width, h = bounds.height
        let longSide = max(w, h)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let base = CALayer()
        base.frame = bounds
        base.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1).cgColor
        root.addSublayer(base)

        for (i, blob) in AuroraMotion.blobs.enumerated() {
            let colour = NSColor(red: blob.red, green: blob.green, blue: blob.blue, alpha: 1)
            let side = longSide * blob.radius * 2
            let g = CAGradientLayer()
            g.type = .radial
            g.colors = [colour.withAlphaComponent(0.62).cgColor, colour.withAlphaComponent(0).cgColor]
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            // Unit coordinates are y-down; the layer tree is y-up.
            let still = AuroraMotion.position(blob: i, time: 0)
            g.position = CGPoint(x: still.x * w, y: (1 - still.y) * h)
            if !reduceMotion {
                g.add(swing("position.x", centre: blob.centre.x * w, amplitude: blob.amplitude.x * w,
                            speed: blob.speed.x, phase: blob.phase.x), forKey: "x")
                g.add(swing("position.y", centre: (1 - blob.centre.y) * h, amplitude: -blob.amplitude.y * h,
                            speed: blob.speed.y, phase: blob.phase.y), forKey: "y")
            }
            root.addSublayer(g)
        }

        // Light veil on top, like the frosted tiles of the reference.
        let veil = CAGradientLayer()
        veil.frame = bounds
        veil.colors = [NSColor.white.withAlphaComponent(0.07).cgColor, NSColor.clear.cgColor]
        veil.startPoint = CGPoint(x: 0.5, y: 1)
        veil.endPoint = CGPoint(x: 0.5, y: 0.5)
        root.addSublayer(veil)
    }

    /// `centre + amplitude·sin(speed·t + phase)` as an ease-in-out swing (see `AuroraMotion.swingTiming`).
    private func swing(_ keyPath: String, centre: CGFloat, amplitude: CGFloat,
                       speed: Double, phase: Double) -> CABasicAnimation {
        let timing = AuroraMotion.swingTiming(speed: speed, phase: phase)
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = centre - amplitude
        a.toValue = centre + amplitude
        a.duration = timing.halfPeriod
        a.timeOffset = timing.offset
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 24, preferred: 15)
        return a
    }
}
