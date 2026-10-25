import SwiftUI
import AppKit
import IntermezzoKit

/// Appearance: surface theme (shared by panel, toasts, chip, this window),
/// notification style, floating chip mode, the look of the break screen
/// (glass, own texts, slideshow, YouTube) and weather scene previews.
struct AppearancePane: View {
    @AppStorage(SurfaceTheme.key) private var themeRaw = SurfaceTheme.navy.rawValue
    @AppStorage(SurfaceTheme.tintKey) private var tintHex = ""
    @AppStorage("notifyStyle") private var notifyStyle = "toast"
    @AppStorage("chipMode") private var chipMode = "auto"
    @AppStorage("weatherTips") private var weatherTips = true
    @AppStorage("seasonFX") private var seasonFX = "auto"
    @Environment(\.surfaceTheme) private var theme

    private var tintBinding: Binding<Color> {
        Binding(
            get: {
                let c = SurfaceTint.resolved(hex: tintHex.isEmpty ? nil : tintHex)
                return Color(red: c.red, green: c.green, blue: c.blue)
            },
            set: { color in
                guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
                tintHex = SurfaceTint.hex(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent)
            })
    }

    private var previews: [(String, String, String)] { [
        ("clear", String(localized: "Słońce"), "sun.max.fill"), ("cloudy", String(localized: "Chmury"), "cloud.fill"),
        ("rain", String(localized: "Deszcz"), "cloud.rain.fill"), ("storm", String(localized: "Burza"), "cloud.bolt.rain.fill"),
        ("snow", String(localized: "Śnieg"), "snowflake"), ("fog", String(localized: "Mgła"), "cloud.fog.fill"),
    ] }

    var body: some View {
        Form {
            LanguageSection()
            Section("Powierzchnia") {
                Text("Wspólny motyw dla panelu paska menu, powiadomień, pastylki i tego okna.")
                    .settingsNote()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(SurfaceTheme.allCases) { t in
                        ThemeCard(theme: t, tintHex: tintHex.isEmpty ? nil : tintHex, selected: t.rawValue == themeRaw) { themeRaw = t.rawValue }
                    }
                }
                .padding(.vertical, 4)
                if theme == .navy || theme == .glass {
                    Group {
                        HStack {
                            ColorPicker(theme == .navy ? "Kolor" : "Zabarwienie szkła", selection: tintBinding, supportsOpacity: false)
                            if !tintHex.isEmpty {
                                Button("Przywróć domyślny") { tintHex = "" }.controlSize(.small)
                            }
                        }
                        Text(theme == .navy
                             ? "Odcień całego okna, panelu i powiadomień. Dół jest zawsze ciemniejszy."
                             : "Szkło jest przezroczyste i rozmywa to, co leży za oknem. Bez wybranego koloru nie jest zabarwione.")
                            .settingsNote()
                    }
                    .expertOnly()
                }
            }

            Section("Powiadomienia") {
                Picker("Styl", selection: $notifyStyle) {
                    Text("Własne okienko (motyw)").tag("toast")
                    Text("Centrum powiadomień macOS").tag("system")
                    Text("Oba").tag("both")
                }
                Button("Wyślij testowe powiadomienie") {
                    AppDelegate.shared?.coordinator.sendTestNotification()
                }
                .controlSize(.small)
            }

            Section("Pływająca pastylka") {
                Picker("Pokazuj", selection: $chipMode) {
                    Text("Tylko gdy macOS schowa ikonę (auto)").tag("auto")
                    Text("Zawsze").tag("always")
                    Text("Nigdy").tag("never")
                }
                Text("Pastylka z odliczaniem; przeciągnij ją, gdzie chcesz. Ratuje widoczność timera, gdy pasek menu jest pełny.")
                    .settingsNote()
            }
            .expertOnly()

            BreakGlassSection()
            BreakTextThemeSection()
            BreakImageThemeSection()
            BreakYouTubeSection()

            Section("Pory roku") {
                Picker("Liście i płatki", selection: $seasonFX) {
                    Text("Automatycznie (jesienią liście, wiosną płatki)").tag("auto")
                    Text("Wyłączone").tag("off")
                }
                Text("Zależą od pory roku, nie od pogody: spadają też w słoneczny październik. Nie pojawiają się w deszczu, burzy i śniegu.")
                    .settingsNote()
            }
            .expertOnly()

            Section("Podgląd scen pogodowych") {
                Toggle("Podpowiedzi zależne od pogody (co trzecia przerwa)", isOn: $weatherTips)
                Text("Pokazuje wybrany efekt na 8 sekund. Podgląd nie blokuje myszki i nie jest przerwą.")
                    .settingsNote()
                HStack(spacing: 8) {
                    ForEach(previews, id: \.0) { effect, label, symbol in
                        PanelButton(title: label, symbol: symbol, kind: .tile) {
                            if let e = WeatherEffect(rawValue: effect) {
                                WeatherController.shared.debugForce(effect: e, windKmh: 12)
                                AppDelegate.shared?.coordinator.previewWeatherScene()
                            }
                        }
                    }
                }
            }
            .expertOnly()
        }
        .formStyle(.grouped)
    }
}

private struct ThemeCard: View {
    let theme: SurfaceTheme
    let tintHex: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.34),
                                            Color(red: 0.08, green: 0.09, blue: 0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    SurfaceBackground(theme: theme, corner: 12, tintHex: tintHex)
                        .padding(10)
                    HStack(spacing: 8) {
                        Circle().fill(theme.accent).frame(width: 12, height: 12)
                        Text("0:42").font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .frame(height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .environment(\.colorScheme, .dark)
                VStack(alignment: .leading, spacing: 1) {
                    Text(LocalizedStringKey(theme.title)).font(.system(size: 13, weight: .semibold))
                    Text(LocalizedStringKey(theme.subtitle)).settingsNote()
                }
            }
            .padding(8)
            .background(Color.white.opacity(selected ? 0.07 : 0.03),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? theme.accent : Color.white.opacity(0.10),
                            lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
