import AppKit
import SwiftUI

/// "Hold to skip" as a real NSView. The previous SwiftUI DragGesture lived
/// inside a window that is never key and drew a TimelineView at 15 fps even
/// when idle; clicks landed only on parts of the capsule. Here the whole
/// rectangle is the hit area, the first click is accepted without activating
/// the window, and the timer runs only while the button is held.
struct HoldToSkipButton: NSViewRepresentable {
    let duration: TimeInterval
    let onSkip: () -> Void

    func makeNSView(context: Context) -> HoldButtonView {
        HoldButtonView(duration: duration, onSkip: onSkip)
    }

    func updateNSView(_ view: HoldButtonView, context: Context) {
        view.onSkip = onSkip
    }
}

final class HoldButtonView: NSView {
    static let size = NSSize(width: 170, height: 44)

    var onSkip: () -> Void
    private let duration: TimeInterval
    private var holdStart: Date?
    private var timer: Timer?
    private var fired = false
    private var progress: CGFloat = 0 {
        didSet { if progress != oldValue { needsDisplay = true } }
    }

    init(duration: TimeInterval, onSkip: @escaping () -> Void) {
        self.duration = duration
        self.onSkip = onSkip
        super.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var intrinsicContentSize: NSSize { Self.size }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        fired = false
        holdStart = Date()
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    override func mouseUp(with event: NSEvent) { release() }

    override func viewDidMoveToWindow() {
        if window == nil { release() }
    }

    private func step() {
        guard let start = holdStart else { return }
        progress = min(1, CGFloat(Date().timeIntervalSince(start) / duration))
        if progress >= 1, !fired {
            fired = true
            release()
            onSkip()
        }
    }

    private func release() {
        timer?.invalidate()
        timer = nil
        holdStart = nil
        progress = 0
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                 xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.10).setFill()
        shape.fill()
        if progress > 0 {
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor.systemRed.withAlphaComponent(0.55).setFill()
            NSRect(x: 0, y: 0, width: bounds.width * progress, height: bounds.height).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.white.withAlphaComponent(0.25).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let base = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 15) } ?? base
        let text = NSAttributedString(
            string: progress < 1 ? String(localized: "Hold to skip") : String(localized: "Skip!"),
            attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
        let s = text.size()
        text.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2))
    }
}
