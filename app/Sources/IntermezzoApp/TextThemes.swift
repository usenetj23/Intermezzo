import IntermezzoKit
import SwiftUI

// MARK: - "Text Theme": custom lines shown during a break.
//
// Sequential/random order, seconds per text or one-per-break, font,
// color, scale-to-fit percentage, vertical offset.

enum TextThemeKeys {
    static let enabled = "textThemeEnabled"
    static let items = "textThemeItems"          // JSON [String]
    static let random = "textThemeRandom"        // 0 = sequential, 1 = random
    static let seconds = "textThemeSeconds"      // 0 = one text per break
    static let font = "textThemeFont"            // default | serif | rounded | mono
    static let color = "textThemeColor"          // RRGGBB hex
    static let scale = "textThemeScale"          // 10...100 (% of screen)
    static let offset = "textThemeOffset"        // -50...50 (% vertical, +up)
}

/// Immutable view of the theme taken at break start.
struct TextThemeSnapshot: Equatable {
    var items: [String]
    var sequential: Bool
    var seconds: Int
    var fontDesign: String
    var colorHex: String
    var scalePercent: Int
    var offsetPercent: Int
    var seed: Int

    /// Nil when the feature is off or no usable texts are configured.
    static func fromDefaults(seed: Int) -> TextThemeSnapshot? {
        let d = UserDefaults.standard
        guard d.integer(forKey: TextThemeKeys.enabled) != 0 else { return nil }
        let items = loadTextThemeItems()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return nil }
        return TextThemeSnapshot(
            items: items,
            sequential: d.integer(forKey: TextThemeKeys.random) == 0,
            seconds: max(0, d.integer(forKey: TextThemeKeys.seconds)),
            fontDesign: d.string(forKey: TextThemeKeys.font) ?? "default",
            colorHex: d.string(forKey: TextThemeKeys.color) ?? "FFFFFF",
            scalePercent: min(100, max(10, d.integer(forKey: TextThemeKeys.scale))),
            offsetPercent: min(50, max(-50, d.integer(forKey: TextThemeKeys.offset))),
            seed: seed)
    }
}

// MARK: - Persistence (UserDefaults stores a JSON-encoded [String])

func loadTextThemeItems() -> [String] {
    guard let data = UserDefaults.standard.data(forKey: TextThemeKeys.items),
          let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
    return list
}

func saveTextThemeItems(_ items: [String]) {
    if let data = try? JSONEncoder().encode(items) {
        UserDefaults.standard.set(data, forKey: TextThemeKeys.items)
    }
}

/// Seeded sample content (equipment-free desk exercises), in the app's language at seeding time.
let deskExercisesSeed: [String] = [
    String(localized: "Wstań prosto i weź 5 powolnych, głębokich oddechów."),
    String(localized: "Unieś ramiona do uszu, przytrzymaj 5 s i opuść — powtórz 5 razy."),
    String(localized: "Przechyl głowę delikatnie do prawego ramienia, utrzymaj 15 s. Zmień stronę."),
    String(localized: "Spleć dłonie za plecami, wypchnij klatkę do przodu i oddychaj głęboko."),
    String(localized: "Przetocz barki do tyłu 10 razy, potem do przodu 10 razy."),
    String(localized: "Usiądź na krześle, skręć tułów w prawo, przytrzymaj 15 s. Zmień stronę."),
]

/// Ensures enabling the theme on an empty list seeds useful content.
func textThemeSeedIfEmpty() {
    if loadTextThemeItems().isEmpty {
        saveTextThemeItems(deskExercisesSeed)
    }
}

// MARK: - Font + color mapping

func textThemeFont(design: String, size: CGFloat) -> Font {
    switch design {
    case "serif":    return .system(size: size, weight: .medium, design: .serif)
    case "rounded":  return .system(size: size, weight: .medium, design: .rounded)
    case "mono":     return .system(size: size, weight: .medium, design: .monospaced)
    default:         return .system(size: size, weight: .medium)
    }
}

func colorFromHex(_ hex: String) -> Color {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = Int(s, radix: 16) else { return .white }
    return Color(red: Double((v >> 16) & 0xFF) / 255.0,
                 green: Double((v >> 8) & 0xFF) / 255.0,
                 blue: Double(v & 0xFF) / 255.0)
}

// MARK: - The rotating text shown on the break overlay

struct TextThemeRotator: View {
    let theme: TextThemeSnapshot
    let shownAt: Date
    let screenHeight: CGFloat

    /// Pacing floor: text that changes faster than ~12 s cannot be acted on
    /// (you cannot do an exercise while the instruction keeps flashing).
    private var paceSeconds: Double {
        theme.seconds > 0 ? max(12, Double(theme.seconds)) : 3600
    }

    var body: some View {
        TimelineView(.periodic(from: shownAt.addingTimeInterval(1),
                               by: paceSeconds)) { ctx in
            let elapsed = max(0, Int(ctx.date.timeIntervalSince(shownAt)))
            let tick = theme.seconds > 0
                ? elapsed / Int(paceSeconds) : 0
            let idx = textThemeIndex(seed: theme.seed, tick: tick,
                                     count: theme.items.count, random: !theme.sequential)
            Text(theme.items.indices.contains(idx) ? theme.items[idx] : "")
                .font(textThemeFont(design: theme.fontDesign, size: scaledFontSize))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex(theme.colorHex))
                .shadow(color: .black.opacity(0.7), radius: 0, x: 0, y: 2)
                .padding(.horizontal, 60)
                // Layout-space shift (padding), so the countdown ring always
                // stays clear of the text — an absolute offset used to allow
                // the two to overlap.
                .padding(.bottom, CGFloat(min(60, max(0, theme.offsetPercent))) * screenHeight / 200.0)
                .id(idx)
                .transition(.opacity)
        }
    }

    /// "Scale" = the text block occupies this percentage of the screen;
    /// map it to a clamped font size so long lines still fit and never
    /// collide with the ring.
    private var scaledFontSize: CGFloat {
        let raw = screenHeight * CGFloat(theme.scalePercent) / 100.0 / 8.0
        return min(64, max(16, raw))
    }
}
