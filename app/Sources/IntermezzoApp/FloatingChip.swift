import AppKit
import Combine
import SwiftUI

/// Whether macOS has "parked" our NSStatusItem. On a notched MacBook with a
/// full menu bar the system gives overflow items a zero-height window at the
/// origin instead of a slot, so the icon is simply not there.
@MainActor
final class MenuBarHealth: ObservableObject {
    static let shared = MenuBarHealth()
    @Published private(set) var parked = false

    func set(parked: Bool) {
        if self.parked != parked { self.parked = parked }
    }
}

/// Click target that also drags the window; a click without movement fires `onClick`.
private final class ChipBackground: NSView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = window.frame.origin
        window.performDrag(with: event)
        if window.frame.origin == start { onClick?() } else { onMoved?() }
    }
}

/// Fallback countdown pill, shown only while the status item is parked.
/// Idle cost when hidden: none (no window ordered in, no updates applied).
@MainActor
final class FloatingChip {
    private static let originKey = "floatingChipOrigin"
    private static let height: CGFloat = 26

    private let panel: NSPanel
    private let background: ChipBackground
    private let blur = NSVisualEffectView()
    private let surface = NSHostingView(rootView: AnyView(EmptyView()))
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    var onClick: (() -> Void)? {
        get { background.onClick }
        set { background.onClick = newValue }
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    init() {
        background = ChipBackground(frame: NSRect(x: 0, y: 0, width: 74, height: Self.height))
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.height / 2
        background.layer?.masksToBounds = true
        blur.blendingMode = .behindWindow
        blur.state = .active
        for v in [blur, surface] {
            v.frame = background.bounds
            v.autoresizingMask = [.width, .height]
            background.addSubview(v)
        }

        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .labelColor
        icon.frame = NSRect(x: 9, y: 5, width: 16, height: 16)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        background.addSubview(icon)
        background.addSubview(label)

        panel = NSPanel(contentRect: background.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.contentView = background
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        background.onMoved = { [weak self] in self?.saveOrigin() }
    }

    /// Re-skin to the current `SurfaceTheme` (cheap; only runs when shown).
    /// The symbol currently on the icon, so an unchanged one is not rebuilt every second.
    private var shownSymbol: String?

    private func applyTheme() {
        let theme = SurfaceTheme.current
        blur.isHidden = !theme.usesBlur
        blur.material = theme.blurMaterial
        surface.rootView = AnyView(SurfaceBackground(theme: theme, corner: Self.height / 2)
            .environment(\.colorScheme, .dark))
    }

    func show(text: String, symbol: String) {
        applyTheme()
        apply(text: text, symbol: symbol)
        if !panel.isVisible {
            panel.setFrameOrigin(restoredOrigin())
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// No-op unless visible, so the 1 Hz countdown costs nothing in the normal case.
    func update(text: String, symbol: String) {
        guard panel.isVisible else { return }
        apply(text: text, symbol: symbol)
    }

    private func apply(text: String, symbol: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if label.stringValue != trimmed {
            label.stringValue = trimmed
            label.sizeToFit()
            let width = 9 + 16 + 6 + label.frame.width + 12
            var frame = panel.frame
            // Digits of a countdown rarely change the width; skip the window resize when they don't.
            if abs(frame.width - width) > 0.5 {
                frame.size = NSSize(width: width, height: Self.height)
                panel.setFrame(frame, display: false)
                background.frame = NSRect(origin: .zero, size: frame.size)
            }
            label.frame.origin = NSPoint(x: 31, y: (Self.height - label.frame.height) / 2)
        }
        if symbol != shownSymbol {
            shownSymbol = symbol
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Intermezzo")
        }
    }

    /// Where the pill sits: last dragged spot if still on a screen, otherwise
    /// the top-right corner just under the menu bar of the main display.
    private func restoredOrigin() -> NSPoint {
        if let raw = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], raw.count == 2 {
            let p = NSPoint(x: raw[0], y: raw[1])
            if NSScreen.screens.contains(where: { $0.frame.contains(p) }) { return p }
        }
        let area = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSPoint(x: area.maxX - panel.frame.width - 12,
                       y: area.maxY - Self.height - 8)
    }

    private func saveOrigin() {
        let o = panel.frame.origin
        UserDefaults.standard.set([o.x, o.y], forKey: Self.originKey)
    }
}
