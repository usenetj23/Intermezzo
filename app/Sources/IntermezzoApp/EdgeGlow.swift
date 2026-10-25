import AppKit

/// Click-through glow along the screen edges that warns about an approaching break
/// and shifts from amber to red as it nears. Never takes mouse or keyboard input.
@MainActor
final class EdgeGlowController {
    private var windows: [NSWindow] = []
    private static let thickness: CGFloat = 70

    /// `progress` 0...1 inside the warning window; nil hides the glow.
    func update(progress: Double?) {
        guard let progress else { hide(); return }
        if windows.isEmpty { build() }
        let color = NSColor(hue: 0.11 * (1 - progress), saturation: 0.9, brightness: 1, alpha: 1)
        let alpha = Float(0.35 + 0.4 * progress)
        for window in windows {
            window.contentView?.layer?.sublayers?.forEach { layer in
                guard let g = layer as? CAGradientLayer else { return }
                g.colors = [color.withAlphaComponent(CGFloat(alpha)).cgColor, color.withAlphaComponent(0).cgColor]
            }
        }
    }

    func hide() {
        guard !windows.isEmpty else { return }
        let dying = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            dying.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { dying.forEach { $0.orderOut(nil); $0.close() } }
        })
    }

    private func build() {
        for screen in NSScreen.screens where screen.frame.width > 200 {
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let size = screen.frame.size, t = Self.thickness
            // start/end points run from the edge inwards
            let edges: [(CGRect, CGPoint, CGPoint)] = [
                (CGRect(x: 0, y: size.height - t, width: size.width, height: t), CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)),
                (CGRect(x: 0, y: 0, width: size.width, height: t), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
                (CGRect(x: 0, y: 0, width: t, height: size.height), CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
                (CGRect(x: size.width - t, y: 0, width: t, height: size.height), CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)),
            ]
            for (frame, start, end) in edges {
                let g = CAGradientLayer()
                g.frame = frame
                g.startPoint = start
                g.endPoint = end
                view.layer?.addSublayer(g)
            }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.55
            pulse.toValue = 1
            pulse.duration = 1.1
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            view.layer?.add(pulse, forKey: "pulse")
            window.contentView = view
            window.alphaValue = 0
            window.orderFront(nil)
            window.animator().alphaValue = 1
            windows.append(window)
        }
    }
}
