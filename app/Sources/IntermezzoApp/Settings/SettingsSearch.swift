import SwiftUI

/// One searchable setting: where it lives and the label it carries there (the same literal the row uses,
/// so it is shown in the current language). `words` are extra search terms in either language.
struct SettingsSearchEntry: Identifiable {
    let pane: SettingsPane
    let anchor: String?
    let key: String
    let words: String
    /// Lives in a section that only shows with all settings on.
    let expert: Bool
    var id: String { pane.rawValue + "|" + key }

    init(_ pane: SettingsPane, _ key: String, anchor: String? = nil, words: String = "", expert: Bool = false) {
        self.pane = pane
        self.anchor = anchor
        self.key = key
        self.words = words
        self.expert = expert
    }

    var title: String { L(key) }
}

enum SettingsSearch {
    /// Hand-kept list of the settings people look for. Rows with an anchor are scrolled to and flashed;
    /// the others open their pane.
    static let entries: [SettingsSearchEntry] = [
        // General
        .init(.general, "Launch when Mac starts", words: "autostart login uruchamiaj start systemu"),
        .init(.general, "Start timer automatically on app launch"),
        .init(.general, "Show countdown text in menu bar", words: "status bar pasek menu licznik"),
        .init(.general, "Pokaż licznik także na ekranie z notchem", words: "notch"),
        .init(.general, "Koloruj ikonę w pasku menu według stanu timera", words: "kolor icon"),
        .init(.general, "Detect inactivity", words: "idle bezczynność nieaktywność"),
        .init(.general, "Zapisuj dłuższą nieobecność jako przerwę naturalną", words: "natural break"),
        .init(.general, "Enable working hours", anchor: "hours", words: "godziny pracy harmonogram schedule"),
        .init(.general, "Różne godziny w poszczególne dni", anchor: "hours", words: "dni tygodnia weekdays"),
        .init(.general, "Holiday guard: no breaks on days with events matching", anchor: "holiday", words: "święta urlop"),
        .init(.general, "Vacation mode — pause everything for N days", anchor: "vacation", words: "urlop wakacje"),
        .init(.general, "Meeting detection: pause when Zoom/Teams/Webex is on", anchor: "meeting", words: "spotkanie teams zoom mikrofon"),
        .init(.general, "Video detection: pause when watching video", anchor: "video", words: "wideo film"),
        .init(.general, "Focus: pause while Focus / Do Not Disturb is on", anchor: "focus", words: "skupienie nie przeszkadzać dnd"),
        .init(.general, "Focus oznaczony jako „praca” liczy się do strefy pracy", anchor: "focus", words: "tryb skupienia full disk"),
        .init(.general, "Calendar: breaks also run during matching events (added to working hours)", anchor: "zone-calendar", words: "kalendarz strefa pracy"),
        .init(.general, "VPN: active only while a VPN from the list is connected", anchor: "zone-vpn", words: "wireguard strefa pracy"),
        .init(.general, "Wi-Fi: active only while connected to a network from the list", anchor: "zone-wifi", words: "sieć strefa pracy"),
        .init(.general, "Location: active only within radius of a saved place", anchor: "zone-geo", words: "lokalizacja geofence miejsce strefa pracy"),
        .init(.general, "Keyboard Shortcuts", words: "skróty klawiatura hotkey"),
        // Status
        .init(.status, "Wstrzymaj timer", anchor: "pause", words: "pauza pause"),
        // Work log
        .init(.workLog, "Sieć przewodowa (LAN, stacja dokująca)", anchor: "lan", words: "lan karta sieciowa praca"),
        // Breaks
        .init(.breaks, "Focus Duration", words: "czas pracy długość"),
        .init(.breaks, "Short Break", words: "krótka przerwa"),
        .init(.breaks, "Long Break", words: "długa przerwa"),
        .init(.breaks, "Play sound at break start", words: "dźwięk sound"),
        .init(.breaks, "Wstrzymuj wideo i muzykę na czas przerwy", words: "media muzyka"),
        .init(.breaks, "Countdown popup next to cursor", words: "popup kursor"),
        .init(.breaks, "Hide Skip button in reminder (strict)", words: "pomiń skip"),
        .init(.breaks, "Strict mode (skip needs confirmation)", words: "tryb ścisły"),
        .init(.breaks, "Break Actions", words: "akcje"),
        .init(.breaks, "Break Scripts", words: "skrypty"),
        // Focus / Pomodoro
        .init(.focus, "Enable Pomodoro mode", words: "pomodoro"),
        // About
        .init(.about, "Kopiuj diagnostykę", words: "diagnostics diagnostyka raport zgłoszenie błąd bug github issue schowek clipboard"),
        // Light
        .init(.light, "Dostosowuj barwę ekranu do pory dnia", words: "night shift true tone"),
        .init(.light, "Lampy w pokoju (dom i reszta miejsc)", words: "lamp light room"),
        .init(.light, "Lampy w pracy", words: "lamp work"),
        .init(.light, "Nie zmieniaj barw w aplikacjach pełnoekranowych", words: "fullscreen"),
        .init(.light, "Przyciemniaj monitory wieczorem (sprzętowo)", words: "betterdisplay ddc"),
        // Appearance
        .init(.appearance, "Powierzchnia", words: "motyw theme skin szkło glass"),
        .init(.appearance, "Powiadomienia", words: "notifications"),
        .init(.appearance, "Pływająca pastylka", words: "pill"),
        .init(.appearance, "Pory roku", words: "liście pogoda seasons"),
        // Advanced
        .init(.advanced, "Natural Break", anchor: "idle", words: "event monitor input monitoring"),
        .init(.advanced, "Permissions", words: "uprawnienia full disk access dostęp do dysku kalendarz lokalizacja"),
        .init(.advanced, "Ukryj przyciski (pokusa do pomijania)", words: "hide buttons"),
        .init(.advanced, "Nie pozwól uśpić Maca podczas przerwy", words: "sleep"),
        .init(.advanced, "Alarmuj o drugiej kopii Intermezzo", words: "duplicate"),
    ]

    /// Entries whose label, pane name or extra words contain every typed word (diacritics and case ignored).
    static func results(for query: String, showAll: Bool) -> [SettingsSearchEntry] {
        let terms = fold(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var hits: [(entry: SettingsSearchEntry, inTitle: Bool)] = []
        for entry in all {
            guard showAll || !(entry.pane.isExpert || entry.expert) else { continue }
            let title = fold(entry.title + " " + entry.key)
            let hay = title + " " + fold([L(entry.pane.title), entry.words].joined(separator: " "))
            if terms.allSatisfy({ hay.contains($0) }) {
                hits.append((entry, terms.allSatisfy { title.contains($0) }))
            }
        }
        // Matches in the label itself first, then the ones found through the pane name or extra words.
        return hits.filter(\.inTitle).map(\.entry) + hits.filter { !$0.inTitle }.map(\.entry)
    }

    /// Hand-kept entries (extra words, rows with old anchors), then the generated index, then the permissions;
    /// the first entry for a pane and label wins.
    static let all: [SettingsSearchEntry] = {
        var seen = Set<String>()
        return (entries + generated + permissionEntries).filter { seen.insert($0.id).inserted }
    }()

    /// One row per permission, found by its name or by what it is for.
    static var permissionEntries: [SettingsSearchEntry] {
        PermissionKind.allCases.map {
            SettingsSearchEntry(.advanced, $0.title, anchor: "perm-\($0.rawValue)",
                                words: L($0.usedFor) + " " + $0.usedFor, expert: false)
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ł", with: "l")
    }
}

/// Search box pinned above the sidebar list, like the one in System Settings.
struct SettingsSearchField: View {
    @Binding var query: String
    let showAll: Bool
    let open: (SettingsSearchEntry) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Szukaj w ustawieniach", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    if let first = SettingsSearch.results(for: query, showAll: showAll).first { open(first) }
                }
                .onExitCommand { query = ""; focused = false }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(focused ? 0.9 : 0), lineWidth: 2))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Drop-down of matches under the search box: one row per setting, with the pane it lives in.
struct SettingsSearchResults: View {
    let query: String
    let showAll: Bool
    let open: (SettingsSearchEntry) -> Void

    var body: some View {
        let found = SettingsSearch.results(for: query, showAll: showAll)
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if found.isEmpty {
                    Text("Brak wyników")
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                ForEach(found) { entry in
                    Button { open(entry) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.pane.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.8))
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title).lineLimit(2).multilineTextAlignment(.leading)
                                Text(LocalizedStringKey(entry.pane.title))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(maxHeight: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
