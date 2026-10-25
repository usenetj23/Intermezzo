import AppKit
import SwiftUI
import IntermezzoKit

/// Main visual scheme shared by every popup surface: menu-bar panel, floating
/// chip, toast notifications and the Settings window.
enum SurfaceTheme: String, CaseIterable, Identifiable {
    case navy, glass, animated, frost, aluminium, inox, holo

    static let key = "surfaceTheme"
    static let tintKey = "surfaceTint"
    private static let migratedKey = "surfaceThemeGlassRenamed"
    var id: String { rawValue }

    /// The old "Glass" theme was renamed Navy and a truly translucent Glass added:
    /// whoever had "glass" selected keeps the look they chose.
    static func migrateStoredTheme() {
        let d = UserDefaults.standard
        if let value = SurfaceMigration.theme(stored: d.string(forKey: key), alreadyMigrated: d.bool(forKey: migratedKey)),
           value != d.string(forKey: key) {
            d.set(value, forKey: key)
        }
        d.set(true, forKey: migratedKey)
    }

    /// The colour the user picked for Navy and Glass; nil = never chosen.
    static var userTintHex: String? { UserDefaults.standard.string(forKey: tintKey) }
    static func tintGradient(hex: String?) -> (top: Color, bottom: Color) {
        let g = SurfaceTint.gradient(hex: hex)
        return (Color(red: g.top.red, green: g.top.green, blue: g.top.blue),
                Color(red: g.bottom.red, green: g.bottom.green, blue: g.bottom.blue))
    }

    static var current: SurfaceTheme {
        SurfaceTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .navy
    }

    var title: String {
        switch self {
        case .navy: return "Kolorowane"
        case .glass: return "Szkło"
        case .animated: return "Animowany"
        case .frost: return "Mrożone szkło"
        case .aluminium: return "Szczotkowane aluminium"
        case .inox: return "Stal nierdzewna (inox)"
        case .holo: return "Folia holograficzna"
        }
    }

    var subtitle: String {
        switch self {
        case .navy: return "Głęboki kolor w wybranym zabarwieniu"
        case .glass: return "Naprawdę przezroczyste, rozmywa pulpit"
        case .animated: return "Powoli dryfujące kolorowe plamy"
        case .frost: return "Mleczna szyba z ziarnem"
        case .aluminium: return "Grafitowy metal z włóknem"
        case .inox: return "Jasna stal z połyskiem"
        case .holo: return "Mieniąca się tęczowa folia"
        }
    }

    var isMetal: Bool { self == .aluminium || self == .inox }

    /// Opaque, textured surfaces (no behind-window blur).
    var isOpaque: Bool { isMetal || self == .holo || self == .animated }

    /// Behind-window blur is only worth its cost for the translucent themes.
    var usesBlur: Bool { !isOpaque }

    var blurMaterial: NSVisualEffectView.Material {
        switch self {
        case .frost: return .popover
        case .glass: return .underWindowBackground
        default: return .hudWindow
        }
    }

    /// Top → bottom base colours of the metal body.
    var metalColors: (NSColor, NSColor) {
        switch self {
        case .aluminium:
            return (NSColor(white: 0.36, alpha: 1), NSColor(white: 0.20, alpha: 1))
        case .inox:
            return (NSColor(red: 0.60, green: 0.63, blue: 0.67, alpha: 1),
                    NSColor(red: 0.34, green: 0.37, blue: 0.41, alpha: 1))
        default:
            return (.clear, .clear)
        }
    }

    /// Accent used for primary buttons on this surface.
    /// Built from one NSColor per theme: SwiftUI turns a tint into an NSColor for every switch it
    /// updates, and for a `Color(red:green:blue:)` that conversion allocates a colour that is never freed
    /// (a SwiftUI leak); a Color made from an NSColor hands back that same object.
    var accent: Color { Self.accentColors[self] ?? Color(nsColor: .controlAccentColor) }

    private static let accentColors: [SurfaceTheme: Color] = {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Color { Color(nsColor: NSColor(srgbRed: r, green: g, blue: b, alpha: 1)) }
        let green = c(0.36, 0.85, 0.63)
        return [.navy: green, .glass: green, .animated: c(0.50, 0.78, 1.0), .frost: c(0.55, 0.80, 0.95),
                .aluminium: c(0.98, 0.72, 0.30), .inox: c(0.30, 0.78, 0.85), .holo: c(0.62, 0.90, 1.0)]
    }()
}

// MARK: - Procedural textures (generated once, a few KB each)

enum SurfaceTexture {
    /// Horizontal brushed-metal fibres on a transparent 512×128 tile that wraps
    /// seamlessly in both directions.
    static let brushed: CGImage? = makeBrushed(seed: 0xB2A5_1F3C_77D1_0042, density: 700, maxAlpha: 0.055)
    static let brushedFine: CGImage? = makeBrushed(seed: 0x9E37_79B9_7F4A_7C15, density: 1000, maxAlpha: 0.035)
    /// Fine monochrome grain for frosted glass.
    static let grain: CGImage? = makeGrain()
    private static func makeBrushed(seed: UInt64, density: Int, maxAlpha: CGFloat) -> CGImage? {
        let w = 512, h = 128
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var state = seed
        func rnd() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
        }
        ctx.setLineCap(.butt)
        for _ in 0..<density {
            let y = rnd() * CGFloat(h)
            let x = rnd() * CGFloat(w)
            let len = 20 + rnd() * 220
            let light = rnd() > 0.45
            let alpha = 0.02 + rnd() * maxAlpha
            ctx.setStrokeColor(CGColor(gray: light ? 1 : 0, alpha: alpha))
            ctx.setLineWidth(0.5 + rnd() * 0.8)
            // Draw three copies so streaks wrap around the tile edges.
            for dx in [-CGFloat(w), 0, CGFloat(w)] {
                ctx.move(to: CGPoint(x: x + dx, y: y))
                ctx.addLine(to: CGPoint(x: x + dx + len, y: y))
            }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    private static func makeGrain() -> CGImage? {
        let n = 128
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func rnd() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
        }
        for _ in 0..<2600 {
            ctx.setFillColor(CGColor(gray: rnd() > 0.5 ? 1 : 0, alpha: 0.03 + rnd() * 0.07))
            ctx.fill(CGRect(x: rnd() * CGFloat(n), y: rnd() * CGFloat(n), width: 1, height: 1))
        }
        return ctx.makeImage()
    }
}

// MARK: - SwiftUI background

/// Themed panel body. Translucent themes sit on a real behind-window blur
/// (provided by `SurfaceHost`); metals are opaque textures with a diagonal
/// anisotropic sheen and a bevelled edge.
struct SurfaceBackground: View {
    let theme: SurfaceTheme
    var corner: CGFloat = 18
    /// Passed in (not read inside) so a parent that observes the setting redraws when it changes.
    var tintHex: String? = SurfaceTheme.userTintHex

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            switch theme {
            case .navy:
                let tint = SurfaceTheme.tintGradient(hex: tintHex)
                shape.fill(LinearGradient(colors: [tint.top.opacity(0.62), tint.bottom.opacity(0.62)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear],
                                          startPoint: .top, endPoint: .center))
            case .glass:
                // Nearly clear: the blur behind the window does the work; only a hairline sheen on top.
                if let hex = tintHex, let c = SurfaceTint.rgb(fromHex: hex) {
                    shape.fill(Color(red: c.red, green: c.green, blue: c.blue).opacity(0.16))
                }
                shape.fill(Color.white.opacity(0.015))
                shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear, .white.opacity(0.04)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            case .frost:
                shape.fill(Color.white.opacity(0.17))
                tile(SurfaceTexture.grain, opacity: 1)
            case .holo:
                HoloFoilBackground().clipShape(shape)
            case .animated:
                AuroraBackground().clipShape(shape)
            case .aluminium, .inox:
                let (top, bottom) = theme.metalColors
                shape.fill(LinearGradient(colors: [Color(nsColor: top), Color(nsColor: bottom)],
                                          startPoint: .top, endPoint: .bottom))
                tile(SurfaceTexture.brushed, opacity: 1)
                tile(SurfaceTexture.brushedFine, opacity: 0.8)
                // Anisotropic highlight band across the brushed grain.
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0), location: 0.0),
                            .init(color: .white.opacity(theme == .inox ? 0.34 : 0.18), location: 0.22),
                            .init(color: .white.opacity(0), location: 0.42),
                            .init(color: .white.opacity(theme == .inox ? 0.16 : 0.07), location: 0.78),
                            .init(color: .white.opacity(0), location: 1.0)],
                    startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 1, y: 0.7)))
            }
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(theme.isOpaque ? (theme == .holo ? 0.50 : (theme == .animated ? 0.30 : 0.55)) : 0.32),
                                        .white.opacity(0.04),
                                        .black.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
    }

    @ViewBuilder
    private func tile(_ image: CGImage?, opacity: Double) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

// MARK: - AppKit host

/// Wraps SwiftUI content in a themed, rounded container (optionally on a
/// behind-window blur). Used for the panel and toast windows.
@MainActor
enum SurfaceHost {
    static func make<V: View>(_ content: V, size: NSSize, corner: CGFloat = 18) -> NSView {
        let theme = SurfaceTheme.current
        let frame = NSRect(origin: .zero, size: size)

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = corner
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        if theme.usesBlur {
            let blur = NSVisualEffectView(frame: frame)
            blur.material = theme.blurMaterial
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            container.addSubview(blur)
        }

        let root = ZStack { SurfaceBackground(theme: theme, corner: corner); content }
            .environment(\.colorScheme, .dark)
            .environment(\.surfaceTheme, theme)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        return container
    }

    /// Fitting height of `content` laid out at `width`.
    static func fittingHeight<V: View>(of content: V, width: CGFloat) -> CGFloat {
        let probe = NSHostingView(rootView: content.frame(width: width).environment(\.colorScheme, .dark))
        return ceil(probe.fittingSize.height)
    }
}

private struct SurfaceThemeKey: EnvironmentKey {
    static let defaultValue: SurfaceTheme = .navy
}

extension EnvironmentValues {
    var surfaceTheme: SurfaceTheme {
        get { self[SurfaceThemeKey.self] }
        set { self[SurfaceThemeKey.self] = newValue }
    }
}

// MARK: - Translucent window support (Glass)

/// Real behind-window blur as a SwiftUI background.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Makes the hosting window see-through for the Glass theme and opaque again for the others.
struct WindowTranslucency: NSViewRepresentable {
    let translucent: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = !translucent
            window.backgroundColor = translucent ? .clear : .windowBackgroundColor
        }
    }
}
