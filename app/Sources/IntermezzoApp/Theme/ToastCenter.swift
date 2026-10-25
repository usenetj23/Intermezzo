import AppKit
import SwiftUI

struct ToastAction: Identifiable {
    let id = UUID()
    let title: String
    let handler: @MainActor () -> Void
}

/// In-app notification popups styled with the active `SurfaceTheme`.
/// One toast at a time (queued), top-right under the menu bar, auto-dismissed.
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    private struct Item {
        let title: String
        let body: String
        let symbol: String
        let actions: [ToastAction]
    }

    private static let width: CGFloat = 340
    private var queue: [Item] = []
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Extra space to keep clear below the menu bar (e.g. the floating chip).
    var topInset: () -> CGFloat = { 0 }

    func show(title: String, body: String, symbol: String = "bell.fill", actions: [ToastAction] = []) {
        let localizedActions = actions.map { ToastAction(title: L($0.title), handler: $0.handler) }
        queue.append(Item(title: L(title), body: L(body), symbol: symbol, actions: localizedActions))
        if panel == nil { presentNext() }
    }

    private func presentNext() {
        guard panel == nil, !queue.isEmpty else { return }
        let item = queue.removeFirst()
        let view = ToastView(title: item.title, text: item.body, symbol: item.symbol,
                             actions: item.actions) { [weak self] in self?.dismiss() }
        let height = SurfaceHost.fittingHeight(of: view, width: Self.width)
        let size = NSSize(width: Self.width, height: height)

        let panel = ToastPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.contentView = SurfaceHost.make(view, size: size, corner: 16)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let area = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        let target = NSPoint(x: area.maxX - size.width - 12,
                             y: area.maxY - size.height - 10 - topInset())
        panel.setFrameOrigin(NSPoint(x: target.x, y: target.y + 14))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(target)
        }
        self.panel = panel

        let seconds = item.actions.isEmpty ? max(4.0, 2.0 + Double(item.body.count) / 18) : 12
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.presentNext()
            }
        })
    }
}

private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

struct ToastView: View {
    let title: String
    let text: String
    let symbol: String
    let actions: [ToastAction]
    let onDismiss: () -> Void

    @Environment(\.surfaceTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(actions) { action in
                            PanelButton(title: action.title, kind: .secondary) {
                                action.handler()
                                onDismiss()
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if actions.isEmpty { onDismiss() } }
    }
}
