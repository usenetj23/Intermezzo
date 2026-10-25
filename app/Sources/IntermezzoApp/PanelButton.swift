import SwiftUI

/// Lightweight panel button: flat fill, hover/press feedback, no blur or shadow.
struct PanelButton: View {
    enum Kind { case primary, secondary, tile, ghost }

    let title: String
    var symbol: String?
    var kind: Kind = .secondary
    var tint: Color?
    var isEnabled = true
    /// Symbol only (title becomes the tooltip) — for tight footers.
    var iconOnly = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.surfaceTheme) private var theme

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .padding(.vertical, kind == .tile ? 9 : 10)
                .background(background, in: RoundedRectangle(cornerRadius: kind == .tile ? 12 : 14,
                                                             style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: kind == .tile ? 12 : 14, style: .continuous)
                        .stroke(stroke, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(iconOnly ? title : "")
    }

    @ViewBuilder private var label: some View {
        if iconOnly, let symbol {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
        } else if kind == .tile {
            VStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.primary.opacity(0.85))
        } else {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(kind == .primary ? Color.black.opacity(0.85) : Color.primary.opacity(0.9))
        }
    }

    private var background: Color {
        switch kind {
        case .primary:   return (tint ?? theme.accent).opacity(hovering ? 1.0 : 0.9)
        case .secondary: return Color.white.opacity(hovering ? 0.16 : 0.09)
        case .tile:      return Color.white.opacity(hovering ? 0.14 : 0.06)
        case .ghost:     return Color.white.opacity(hovering ? 0.08 : 0)
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary, .ghost: return .clear
        case .secondary, .tile: return Color.white.opacity(0.08)
        }
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
