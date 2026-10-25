import Foundation

/// What an `intermezzo://` address asks the app to do.
public enum AutomationCommand: Equatable, Sendable {
    case startShort, startLong
    case postpone(minutes: Int)
    case skip, pause, resume, reset, stopSound, flash, notify, openPanel, closePanel
    case button(title: String)
    case settings(pane: String?)
    case lightOn, lightOff
    case lightPause(minutes: Int)
    case awakeOn, awakeOff, awakeToggle
    case awakeFor(minutes: Int)
}

/// Reads the public automation addresses. The `debug` host is deliberately not handled here.
public enum AutomationURL {
    /// `host` is the first element after `intermezzo://`, `path` the rest.
    public static func parse(host: String?, path: [String]) -> AutomationCommand? {
        let next = path.first
        switch host?.lowercased() {
        case "break":
            switch next?.lowercased() {
            case "long", "normal", "lunchtime":
                return postponeIn(path) ?? .startLong
            case "micro", "short":
                return postponeIn(path) ?? .startShort
            default:
                return .startShort
            }
        case "short": return .startShort
        case "long": return .startLong
        case "postpone", "snooze", "delay": return .postpone(minutes: minutes(next, fallback: 5))
        case "skip": return .skip
        case "button":
            guard let raw = next, let title = raw.removingPercentEncoding, !title.isEmpty else { return nil }
            return .button(title: title)
        case "pause": return .pause
        case "resume": return .resume
        case "reset": return .reset
        case "stop-sound", "stopsound": return .stopSound
        case "flash": return .flash
        case "notify": return .notify
        case "panel": return .openPanel
        case "panel-close": return .closePanel
        case "settings": return .settings(pane: next)
        case "light":
            switch next?.lowercased() {
            case "on": return .lightOn
            case "off": return .lightOff
            case "pause": return .lightPause(minutes: minutes(path.count > 1 ? path[1] : nil, fallback: 60))
            default: return nil
            }
        case "awake":
            switch next?.lowercased() {
            case "on": return .awakeOn
            case "off": return .awakeOff
            case "toggle": return .awakeToggle
            case "for": return .awakeFor(minutes: minutes(path.count > 1 ? path[1] : nil, fallback: 60))
            default: return nil
            }
        default: return nil
        }
    }

    /// `break/<kind>/postpone/<time>`: the kind is not used, the next break is postponed.
    private static func postponeIn(_ path: [String]) -> AutomationCommand? {
        guard path.count >= 3, path[1] == "postpone" else { return nil }
        return .postpone(minutes: minutes(path[2], fallback: 5))
    }

    /// "90s", "5m", "2h", "1d"; a bare number means minutes. Never less than one minute.
    public static func minutes(_ raw: String?, fallback: Int) -> Int {
        guard let raw else { return fallback }
        if raw.hasSuffix("s"), let v = Double(raw.dropLast()) { return max(1, Int((v / 60).rounded())) }
        if raw.hasSuffix("m"), let v = Double(raw.dropLast()) { return max(1, Int(v)) }
        if raw.hasSuffix("h"), let v = Double(raw.dropLast()) { return max(1, Int(v * 60)) }
        if raw.hasSuffix("d"), let v = Double(raw.dropLast()) { return max(1, Int(v * 1440)) }
        if let v = Double(raw) { return max(1, Int(v)) }
        return fallback
    }
}

public struct AutomationURLEntry: Sendable {
    /// As shown after `intermezzo://`, with placeholders such as `<time>`.
    public let display: String
    /// A concrete address that parses to this command (used by tests and the copy button).
    public let example: String
    public let summary: String
}

public struct AutomationShortcut: Sendable {
    public let title: String
    /// The combination shipped as default, nil when the user has to record one.
    public let defaultCombo: String?
}

/// The single list of everything that can be triggered from outside the app. The Messages article,
/// the Settings section and the tests all read it, so a command cannot be added without a description.
public enum AutomationCatalog {
    public static var urls: [AutomationURLEntry] { [
        AutomationURLEntry(display: "break/short", example: "break/short",
                           summary: kitL("Rozpoczyna krótką przerwę teraz (także: short, break/micro)")),
        AutomationURLEntry(display: "break/long", example: "break/long",
                           summary: kitL("Rozpoczyna długą przerwę teraz (także: long, break/normal, break/lunchtime)")),
        AutomationURLEntry(display: "postpone/<time>", example: "postpone/10m",
                           summary: kitL("Odracza najbliższą przerwę; bez czasu o 5 min (także: snooze, delay)")),
        AutomationURLEntry(display: "break/short/postpone/<time>", example: "break/short/postpone/2m",
                           summary: kitL("To samo co postpone; rodzaj przerwy w adresie jest dziś pomijany")),
        AutomationURLEntry(display: "skip", example: "skip",
                           summary: kitL("Pomija bieżącą lub najbliższą przerwę")),
        AutomationURLEntry(display: "pause", example: "pause",
                           summary: kitL("Wstrzymuje timer przerw do wznowienia")),
        AutomationURLEntry(display: "resume", example: "resume",
                           summary: kitL("Wznawia timer przerw")),
        AutomationURLEntry(display: "reset", example: "reset",
                           summary: kitL("Zeruje cykl i liczy do następnej przerwy od nowa")),
        AutomationURLEntry(display: "stop-sound", example: "stop-sound",
                           summary: kitL("Zatrzymuje dźwięk przerwy lub muzykę relaksacyjną (także: stopSound)")),
        AutomationURLEntry(display: "button/<title>", example: "button/Water",
                           summary: kitL("Uruchamia akcje przypisane do przycisku o tym tytule, np. Water zapisuje szklankę wody")),
        AutomationURLEntry(display: "flash", example: "flash",
                           summary: kitL("Pokazuje przypomnienie błyskiem ekranu")),
        AutomationURLEntry(display: "notify", example: "notify",
                           summary: kitL("Wysyła testowe powiadomienie")),
        AutomationURLEntry(display: "panel", example: "panel",
                           summary: kitL("Otwiera panel z paska menu")),
        AutomationURLEntry(display: "panel-close", example: "panel-close",
                           summary: kitL("Zamyka panel z paska menu")),
        AutomationURLEntry(display: "settings/<panel>", example: "settings/workLog",
                           summary: kitL("Otwiera Ustawienia; panel jest opcjonalny, np. workLog, sync, gallery, appearance")),
        AutomationURLEntry(display: "light/on", example: "light/on",
                           summary: kitL("Włącza dopasowanie barwy ekranu do pory dnia")),
        AutomationURLEntry(display: "light/off", example: "light/off",
                           summary: kitL("Wyłącza dopasowanie barwy i przywraca kolory systemu (awaryjne wyłączenie)")),
        AutomationURLEntry(display: "light/pause/<time>", example: "light/pause/1h",
                           summary: kitL("Wstrzymuje zmianę barwy na podany czas; bez czasu na godzinę")),
        AutomationURLEntry(display: "awake/on", example: "awake/on",
                           summary: kitL("Włącza czuwanie: Mac nie zaśnie do wyłączenia")),
        AutomationURLEntry(display: "awake/for/<time>", example: "awake/for/2h",
                           summary: kitL("Czuwanie na podany czas, potem Mac może zasnąć")),
        AutomationURLEntry(display: "awake/off", example: "awake/off",
                           summary: kitL("Wyłącza czuwanie")),
        AutomationURLEntry(display: "awake/toggle", example: "awake/toggle",
                           summary: kitL("Przełącza czuwanie")),
    ] }

    public static var shortcuts: [AutomationShortcut] { [
        AutomationShortcut(title: kitL("Krótka przerwa teraz"), defaultCombo: "⌃⌥B"),
        AutomationShortcut(title: kitL("Długa przerwa teraz"), defaultCombo: "⌃⌥L"),
        AutomationShortcut(title: kitL("Pomiń przerwę"), defaultCombo: "⌃⌥S"),
        AutomationShortcut(title: kitL("Wstrzymaj lub wznów timer"), defaultCombo: "⌃⌥P"),
        AutomationShortcut(title: kitL("Odrocz najbliższą przerwę"), defaultCombo: nil),
        AutomationShortcut(title: kitL("Wstrzymaj wszystko na stałe"), defaultCombo: nil),
        AutomationShortcut(title: kitL("Wznów wszystkie przerwy"), defaultCombo: nil),
        AutomationShortcut(title: kitL("Zresetuj przerwy"), defaultCombo: nil),
        AutomationShortcut(title: kitL("Zatrzymaj dźwięk"), defaultCombo: nil),
    ] }

    /// The body of the Messages article (and the text next to the Settings list).
    public static func explanation() -> String {
        var lines: [String] = []
        lines.append(kitL("Globalne skróty działają w każdej aplikacji. Cztery mają domyślne kombinacje, resztę nagrasz w Ustawieniach → Ogólne:"))
        for s in shortcuts {
            lines.append("• \(s.title)" + (s.defaultCombo.map { " — \($0)" } ?? ""))
        }
        lines.append("")
        lines.append(kitL("Adresy intermezzo:// uruchomisz z Skrótów, skryptów, crona albo terminala (open \"intermezzo://break/long\"):"))
        for u in urls {
            lines.append("• intermezzo://\(u.display) — \(u.summary)")
        }
        lines.append("")
        lines.append(kitL("Czas to liczba z jednostką s, m, h lub d (90s, 5m, 2h, 1d); sama liczba oznacza minuty."))
        return lines.joined(separator: "\n")
    }
}
