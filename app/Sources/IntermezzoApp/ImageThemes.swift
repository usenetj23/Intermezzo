import AppKit
import IntermezzoKit
import SwiftUI

// MARK: - "Image Theme": personal photos shown during a break.
//
// Sequential or random order, timed crossfade, seconds per image or
// one-per-break, Fit / Fill / Percent scaling.

enum ImageThemeKeys {
    static let enabled = "imageThemeEnabled"
    static let items = "imageThemeItems"                 // JSON [String] file paths
    static let random = "imageThemeRandom"               // 0 = sequential, 1 = random
    static let seconds = "imageThemeSeconds"             // 0 = one image per break
    static let transition = "imageThemeTransition"       // "none" | "crossfade"
    static let crossfade = "imageThemeCrossfadeSeconds"  // seconds, 0 = none
    static let scale = "imageThemeScale"                 // "fit" | "fill" | "percent"
    static let scalePercent = "imageThemeScalePercent"   // 10...100
    static let span = "imageThemeSpan"                   // 1 = one picture across all screens (Fill only)
}

/// Immutable view of the image theme taken at break start. Images are
/// preloaded so the overlay never blocks on disk I/O mid-break.
@MainActor
struct ImageThemeSnapshot {
    var images: [NSImage]
    var sequential: Bool
    var seconds: Int
    var crossfade: Double
    var scaleMode: String
    var scalePercent: Int
    var seed: Int
    var span = false

    /// Nil when the feature is off or no images could be loaded.
    static func fromDefaults(seed: Int) -> ImageThemeSnapshot? {
        let d = UserDefaults.standard
        guard d.integer(forKey: ImageThemeKeys.enabled) != 0 else { return nil }
        var loaded: [NSImage] = []
        for path in loadImageThemeItems() {
            let expanded = (path as NSString).expandingTildeInPath
            if let img = NSImage(contentsOfFile: expanded) { loaded.append(img) }
        }
        guard !loaded.isEmpty else { return nil }
        let crossfade = d.string(forKey: ImageThemeKeys.transition) == "none"
            ? 0.0
            : min(5.0, max(0.0, Double(d.integer(forKey: ImageThemeKeys.crossfade))))
        return ImageThemeSnapshot(
            images: loaded,
            sequential: d.integer(forKey: ImageThemeKeys.random) == 0,
            seconds: max(0, d.integer(forKey: ImageThemeKeys.seconds)),
            crossfade: crossfade,
            scaleMode: d.string(forKey: ImageThemeKeys.scale) ?? "fill",
            scalePercent: min(100, max(10, d.integer(forKey: ImageThemeKeys.scalePercent))),
            seed: seed,
            span: d.integer(forKey: ImageThemeKeys.span) != 0)
    }
}

// MARK: - Persistence (UserDefaults stores a JSON-encoded [String] of paths)

func loadImageThemeItems() -> [String] {
    guard let data = UserDefaults.standard.data(forKey: ImageThemeKeys.items),
          let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return list
}

func saveImageThemeItems(_ items: [String]) {
    if let data = try? JSONEncoder().encode(items) {
        UserDefaults.standard.set(data, forKey: ImageThemeKeys.items)
    }
}

// MARK: - The crossfading slideshow shown on the break overlay

struct ImageThemeSlides: View {
    let theme: ImageThemeSnapshot
    let shownAt: Date
    var screenFrame: NSRect = .zero

    var body: some View {
        GeometryReader { geo in
            TimelineView(.periodic(from: shownAt.addingTimeInterval(1),
                                   by: theme.seconds > 0 ? Double(theme.seconds) : 3600)) { ctx in
                let elapsed = max(0, Int(ctx.date.timeIntervalSince(shownAt)))
                let tick = theme.seconds > 0 ? elapsed / max(1, theme.seconds) : 0
                let idx = textThemeIndex(seed: theme.seed, tick: tick,
                                         count: theme.images.count, random: !theme.sequential)
                ZStack {
                    ForEach(theme.images.indices, id: \.self) { i in
                        slideView(theme.images[i], geo: geo)
                            .opacity(i == idx ? 1 : 0)
                    }
                }
                .animation(.easeInOut(duration: max(0.01, theme.crossfade)), value: idx)
            }
        }
    }

    @ViewBuilder
    private func slideView(_ image: NSImage, geo: GeometryProxy) -> some View {
        switch theme.scaleMode {
        case "percent":
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width * CGFloat(theme.scalePercent) / 100.0,
                       height: geo.size.height * CGFloat(theme.scalePercent) / 100.0)
        case "fit":
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(24)
        default: // fill
            if theme.span, screenFrame.width > 0,
               let union = SpanLayout.union(NSScreen.screens.map(\.frame)), NSScreen.screens.count > 1 {
                let shift = SpanLayout.offset(of: screenFrame, in: union)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: union.width, height: union.height)
                    .clipped()
                    .offset(x: shift.width, y: shift.height)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
            } else {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
            }
        }
    }
}
