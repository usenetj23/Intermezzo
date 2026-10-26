import SwiftUI
import SwiftData
import AppKit
import IntermezzoKit

extension Notification.Name {
    static let openMessage = Notification.Name("IntermezzoOpenMessage")
    static let openSettingsPane = Notification.Name("IntermezzoOpenSettingsPane")
}

/// `rawValue` stays the legacy English id: Messages deep-link into panes by it.
enum SettingsPane: String, Identifiable, CaseIterable {
    case status = "Status"
    case statistics = "Statistics"
    case workLog = "Work log"
    case breaks = "Breaks"
    case general = "General"
    case focus = "Focus mode"
    case rules = "Rules"
    case clockOut = "Clock Out"
    case flash = "Flash Reminder"
    case light = "Light"
    case awake = "Awake"
    case messages = "Messages"
    case exercises = "Exercises"
    case gallery = "Script Gallery"
    case appearance = "Appearance"
    case sync = "Sync"
    case advanced = "Advanced"
    case ai = "AI"
    case about = "About"
    var id: String { rawValue }

    /// Set by `intermezzo://settings/<pane>` before the window exists; taken when it appears.
    @MainActor static var pending: SettingsPane?

    /// `workLog`, `work-log` or the legacy id ("Work log"), case-insensitive.
    init?(link: String) {
        let key = link.lowercased().filter { $0.isLetter }
        guard let pane = Self.allCases.first(where: {
            String(describing: $0).lowercased() == key || $0.rawValue.lowercased().filter(\.isLetter) == key
        }) else { return nil }
        self = pane
    }

    var title: String {
        switch self {
        case .status: return "Status"
        case .statistics: return "Statystyki"
        case .workLog: return "Rejestr pracy"
        case .breaks: return "Przerwy"
        case .general: return "Ogólne"
        case .focus: return "Skupienie"
        case .rules: return "Reguły"
        case .clockOut: return "Koniec dnia"
        case .flash: return "Przypomnienie błyskiem"
        case .light: return "Światło"
        case .awake: return "Czuwanie"
        case .messages: return "Wiadomości"
        case .exercises: return "Ćwiczenia"
        case .gallery: return "Galeria skryptów"
        case .appearance: return "Wygląd"
        case .sync: return "Synchronizacja i kopia"
        case .advanced: return "Zaawansowane"
        case .ai: return "AI"
        case .about: return "O aplikacji"
        }
    }

    var subtitle: String {
        switch self {
        case .status: return "Odliczanie na żywo, uprawnienia i stan paska menu"
        case .statistics: return "Historia przerw, passa i eksport"
        case .workLog: return "Godziny w pracy, nadgodziny i eksport do rozliczeń"
        case .breaks: return "Długość, rytm, dźwięk i akcje przerw"
        case .general: return "Godziny pracy, wykrywanie kontekstu, skróty"
        case .focus: return "Tryb Pomodoro i blokady"
        case .rules: return "Kiedy odkładać lub pomijać przerwy"
        case .clockOut: return "Wieczorne przypomnienie o zakończeniu pracy"
        case .flash: return "Dyskretny błysk przypominający o postawie"
        case .light: return "Barwa ekranu według pory dnia i godziny snu"
        case .awake: return "Nie pozwól Macowi zasnąć, gdy pracuje"
        case .messages: return "Porady i artykuły wyświetlane w przerwach"
        case .exercises: return "Ćwiczenia przypisane do przerw"
        case .gallery: return "Gotowe i własne reguły-skrypty"
        case .appearance: return "Motyw, powiadomienia i wygląd ekranu przerwy"
        case .sync: return "Ustawienia i historia na Twoich Macach i w chmurze"
        case .advanced: return "Wykrywanie nieaktywności, blokady, diagnostyka"
        case .ai: return "Asystent ustawień, autor skryptów i podsumowanie tygodnia"
        case .about: return "Wersja i informacje"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "gauge.with.dots.needle.67percent"
        case .statistics: return "chart.bar.xaxis"
        case .workLog: return "clock.badge.checkmark"
        case .breaks: return "timer"
        case .general: return "gearshape"
        case .focus: return "brain.head.profile"
        case .rules: return "line.3.horizontal.decrease.circle"
        case .clockOut: return "moon.zzz"
        case .flash: return "bolt"
        case .light: return "sun.max"
        case .awake: return "cup.and.saucer"
        case .messages: return "envelope"
        case .exercises: return "figure.cooldown"
        case .gallery: return "scroll"
        case .appearance: return "paintpalette"
        case .sync: return "arrow.triangle.2.circlepath"
        case .advanced: return "slider.horizontal.below.rectangle"
        case .ai: return "sparkles"
        case .about: return "info.circle"
        }
    }

    /// Panes for tuning and automation; hidden while the sidebar shows basic settings only.
    var isExpert: Bool { [.rules, .flash, .gallery, .ai, .advanced].contains(self) }

    static let groups: [(title: String, panes: [SettingsPane])] = [
        ("Przegląd", [.status, .statistics, .workLog]),
        ("Rytm pracy", [.breaks, .general, .focus, .rules, .clockOut, .flash, .light, .awake]),
        ("Treść", [.messages, .exercises, .gallery]),
        ("Aplikacja", [.appearance, .sync, .ai, .advanced, .about]),
    ]
}

struct SettingsView: View {
    @State private var selection: SettingsPane? = .status
    @State private var openMessageID: String?
    @AppStorage(SettingsLevel.key) private var showAll = false
    @AppStorage(SurfaceTheme.key) private var themeRaw = SurfaceTheme.navy.rawValue
    @AppStorage(SurfaceTheme.tintKey) private var tintHex = ""

    private var theme: SurfaceTheme { SurfaceTheme(rawValue: themeRaw) ?? .navy }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SettingsPane.groups, id: \.title) { group in
                    Section(LocalizedStringKey(group.title)) {
                        ForEach(group.panes.filter { showAll || !$0.isExpert }) { pane in
                            NavigationLink(value: pane) {
                                Label(LocalizedStringKey(pane.title), systemImage: pane.symbol)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { SettingsLevelPicker() }
            .background(SettingsBackdrop(theme: theme, tintHex: tintHex.isEmpty ? nil : tintHex))
            .onChange(of: showAll) { _, all in
                // Leaving an expert pane that just disappeared from the sidebar.
                if !all, selection?.isExpert == true { selection = .status }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            let pane = selection ?? .status
            VStack(spacing: 0) {
                PaneHeader(pane: pane, accent: theme.accent)
                content(for: pane)
                    .scrollContentBackground(.hidden)
            }
            .background(SettingsBackdrop(theme: theme, tintHex: tintHex.isEmpty ? nil : tintHex))
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        // Not a fixed frame: a rigid width/height clipped labels and the
        // sidebar list. min + ideal keeps a comfortable default and lets the
        // window resize freely.
        .frame(minWidth: 820, idealWidth: 900, minHeight: 580, idealHeight: 680)
        .environment(\.surfaceTheme, theme)
        .background(WindowTranslucency(translucent: theme == .glass))
        .preferredColorScheme(.dark)
        .tint(theme.accent)
        .onAppear {
            if let pane = SettingsPane.pending { selection = pane; SettingsPane.pending = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPane)) { _ in
            if let pane = SettingsPane.pending { selection = pane; SettingsPane.pending = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMessage)) { note in
            // A tip tapped on the break screen: show the article now that
            // the break is over.
            if let id = note.object as? String {
                openMessageID = id
                selection = .messages
            }
        }
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .status: StatusPane()
        case .general: GeneralPane()
        case .rules: RulesPane()
        case .messages: MessagesPane(openMessageID: $openMessageID, selection: $selection)
        case .breaks: BreaksPane()
        case .focus: FocusPane()
        case .flash: FlashPane()
        case .light: LightPane()
        case .awake: AwakePane()
        case .exercises: ExercisesPane()
        case .clockOut: ClockOutPane()
        case .statistics: StatisticsPane()
        case .workLog: WorkLogPane()
        case .gallery: ScriptGalleryPane()
        case .appearance: AppearancePane()
        case .sync: SyncPane()
        case .advanced: AdvancedPane()
        case .ai: AIPane()
        case .about: AboutPane()
        }
    }
}

/// Title strip of a settings page: accent icon tile, name, one-line purpose.
struct PaneHeader: View {
    let pane: SettingsPane
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pane.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 38, height: 38)
                .background(accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(pane.title))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(LocalizedStringKey(pane.subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.12), .white.opacity(0.0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
    }
}

/// Window background that follows the chosen surface (glass → deep blue-grey
/// gradient, frost → light veil with grain, metals → brushed texture).
struct SettingsBackdrop: View {
    let theme: SurfaceTheme
    var tintHex: String?

    var body: some View {
        ZStack {
            if theme != .glass { Color(red: 0.07, green: 0.08, blue: 0.10) }
            switch theme {
            case .navy:
                let tint = SurfaceTheme.tintGradient(hex: tintHex)
                LinearGradient(colors: [tint.top, tint.bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .glass:
                // The window itself is translucent (see WindowTranslucency); this only
                // adds the blur of the desktop behind it and an optional tint.
                BehindWindowBlur()
                if let hex = tintHex, let c = SurfaceTint.rgb(fromHex: hex) {
                    Color(red: c.red, green: c.green, blue: c.blue).opacity(0.18)
                }
            case .frost:
                LinearGradient(colors: [Color(white: 0.30), Color(white: 0.17)],
                               startPoint: .top, endPoint: .bottom)
                tile(SurfaceTexture.grain)
            case .animated, .aluminium, .inox, .holo:
                SurfaceBackground(theme: theme, corner: 0)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func tile(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1).resizable(resizingMode: .tile)
        }
    }
}

/// Sheets open in their own window and do not inherit the Settings look: give them the same backdrop,
/// theme environment and accent.
private struct ThemedSheet: ViewModifier {
    @AppStorage(SurfaceTheme.key) private var themeRaw = SurfaceTheme.navy.rawValue
    @AppStorage(SurfaceTheme.tintKey) private var tintHex = ""

    func body(content: Content) -> some View {
        let theme = SurfaceTheme(rawValue: themeRaw) ?? .navy
        content
            .scrollContentBackground(.hidden)
            .background(SettingsBackdrop(theme: theme, tintHex: tintHex.isEmpty ? nil : tintHex))
            .environment(\.surfaceTheme, theme)
            .tint(theme.accent)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func themedSheet() -> some View { modifier(ThemedSheet()) }
}
