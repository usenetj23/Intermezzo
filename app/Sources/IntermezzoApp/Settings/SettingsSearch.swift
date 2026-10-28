import SwiftUI

/// One searchable setting: where it lives and the label it carries there (the same literal the row uses,
/// so it is shown in the current language). `words` are extra search terms in either language.
struct SettingsSearchEntry: Identifiable {
    let pane: SettingsPane
    let anchor: String?
    let key: String
    let words: String
    var id: String { pane.rawValue + "|" + key }

    init(_ pane: SettingsPane, _ key: String, anchor: String? = nil, words: String = "") {
        self.pane = pane
        self.anchor = anchor
        self.key = key
        self.words = words
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
        return entries.filter { entry in
            guard showAll || !entry.pane.isExpert else { return false }
            let hay = fold([entry.title, entry.key, L(entry.pane.title), entry.words].joined(separator: " "))
            return terms.allSatisfy { hay.contains($0) }
        }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "ł", with: "l")
    }
}

/// Sidebar results: one row per match, with the pane it lives in.
struct SettingsSearchResults: View {
    let query: String
    let showAll: Bool
    let open: (SettingsSearchEntry) -> Void

    var body: some View {
        let found = SettingsSearch.results(for: query, showAll: showAll)
        if found.isEmpty {
            Text("Brak wyników")
                .foregroundStyle(.secondary)
        } else {
            ForEach(found) { entry in
                Button { open(entry) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).lineLimit(2)
                        Label(LocalizedStringKey(entry.pane.title), systemImage: entry.pane.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
