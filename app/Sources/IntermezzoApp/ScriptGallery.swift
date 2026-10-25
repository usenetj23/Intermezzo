import Foundation
import IntermezzoKit

// MARK: - Script Gallery (fully local)
//
// A built-in catalog of ready-made AppleScript rules. "Install" writes the
// script into our Application Scripts folder and (optionally) adds it as a
// disabled-until-you-enable rule. No downloads, no network: every script is
// written from scratch and ships inside the app.

/// Comments and names written into the scripts, in the app's language (read once per launch).
private enum ScriptText {
    static let t1 = L("Spotkanie FaceTime")
    static let t2 = L("FaceTime otwarty i na pierwszym planie, albo ma aktywne okno rozmowy")
    static let t3 = L("Wideokonferencja")
    static let t4 = L("Gra Valve / Steam")
    static let t5 = L("Czytanie dokumentu")
    static let t6 = L("Prezentacja")
    static let t7 = L("Zdalna sesja")
    static let t8 = L("ktoś ogląda Twój ekran (usługa macOS działa tylko podczas połączenia)")
    static let t9 = L("Nagrywanie ekranu")
    static let t10 = L("Spotkanie w przeglądarce")
    static let t11 = L("Rozmowa głosowa")
    static let t12 = L("Sesja w terminalu")
    static let t13 = L("Praca twórcza")
    static let t14 = L("Gry spoza Steama")
    static let t15 = L("Duplikowanie ekranu")
    static let t16 = L("Długi build / render")
    static let t17 = L("Pora obiadu")
    static let t18 = L("Zwróć true, gdy warunek jest spełniony (wtedy reguła działa), w przeciwnym razie false.")
    static let t19 = L("Nastawy: linie „property nazwa : wartość” na początku (lista tekstów, liczba, true/false, tekst).")
}

struct GalleryScript: Identifiable {
    let id: String
    let title: String
    let summary: String
    /// Suggested outcome when installing as a rule.
    let outcomeNote: String
    let source: String
}

enum ScriptGallery {
    /// Where installed scripts live.
    static var scriptsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Scripts/com.automit.Intermezzo/Rules", isDirectory: true)
    }

    static func installedPath(for script: GalleryScript) -> URL {
        scriptsDir.appendingPathComponent("\(script.id).applescript")
    }

    static func isInstalled(_ script: GalleryScript) -> Bool {
        FileManager.default.fileExists(atPath: installedPath(for: script).path)
    }

    @discardableResult
    static func install(_ script: GalleryScript) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
            try script.source.write(to: installedPath(for: script), atomically: true, encoding: .utf8)
            return true
        } catch {
            Trace.log("gallery install failed \(script.id): \(error)")
            return false
        }
    }

    /// What the "install" button should do with the rule it creates. Defaults to postponing.
    static func suggestedOutcome(for script: GalleryScript) -> BreakRuleOutcome {
        switch script.id {
        case "ValveGame", "GameLaunchers", "PresenterMode", "MirroredDisplay": return .autoSkip
        case "LunchHour": return .treatAsNaturalBreak
        case "LongBuild": return .suggestBreak
        default: return .postpone
        }
    }

    // The catalog. Every script answers "is this condition true right now?"
    static let catalog: [GalleryScript] = [
        GalleryScript(
            id: "FacetimeMeeting",
            title: "Spotkanie FaceTime",
            summary: "Wykrywa, gdy aktywnie prowadzisz lub odbierasz rozmowę FaceTime. Przerwa zostanie odroczona do końca spotkania.",
            outcomeNote: "Zalecane: odroczony lub pomijany automatycznie.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t1)
            tell application "System Events"
                set p to every process whose name is "FaceTime"
                if (count of p) is 0 then return false
            end tell
            -- \(ScriptText.t2)
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            return frontName is "FaceTime"
            """),
        GalleryScript(
            id: "VideoConference",
            title: "Wideokonferencja (Zoom / Teams / Webex)",
            summary: "Sprawdza, czy któryś klient wideokonferencji ma otwarte aktywne okno. Nie pomija przerw tylko dlatego, że aplikacja działa w tle.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t3)
            property clients : {"zoom.us", "Microsoft Teams", "Teams", "webex"}
            tell application "System Events"
                repeat with c in clients
                    set p to every process whose name is c
                    repeat with proc in p
                        try
                            if (count of windows of proc) > 0 and visible of proc then return true
                        end try
                    end repeat
                end repeat
            end tell
            return false
            """),
        GalleryScript(
            id: "ValveGame",
            title: "Gra Valve / Steam",
            summary: "Gry Steam nie zawsze są wykrywalne jak zwykłe aplikacje. Ten skrypt sprawdza proces gry lub Big Picture. Przerwa w środku rajdu? Nigdy.",
            outcomeNote: "Zalecane: pomijaj automatycznie podczas grania.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t4)
            property games : {"Dota 2", "cs2", "csgo"}
            tell application "System Events"
                if (exists process "Steam") and (visible of process "Steam") then
                    if (count of windows of process "Steam") > 0 then return true
                end if
                repeat with n in games
                    if (exists process (n as text)) then return true
                end repeat
            end tell
            return false
            """),
        GalleryScript(
            id: "ReadingDoc",
            title: "Czytasz PDF lub e-book",
            summary: "Podgląd/Skim/App Books na pierwszym planie: wpatrujesz się w ekran, ale nie ruszasz myszką — Intermezzo nie powinien traktować tego jako naturalnej przerwy, a przerwy oddelegować na po przeczytaniu rozdziału.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t5)
            property apps : {"Preview", "Skim", "Books"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            return apps contains frontName
            """),
        GalleryScript(
            id: "PresenterMode",
            title: "Prezentacja (Keynote / PowerPoint slideshow)",
            summary: "Wykrywa tryb slajdów Keynote lub PowerPointa — publiczność patrzy na Ciebie, nie na Twój nadgarstek. Przerwa poczeka do końca prezentacji.",
            outcomeNote: "Zalecane: pomijaj automatycznie.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t6)
            tell application "System Events"
                if (exists process "Keynote") then
                    try
                        set docState to value of attribute "AXSlideshowRunning" of application process "Keynote"
                        if docState is true then return true
                    end try
                end if
                if (exists process "Microsoft PowerPoint") then
                    set p to first process whose frontmost is true
                    if name of p is "Microsoft PowerPoint" then return true
                end if
            end tell
            return false
            """),
        GalleryScript(
            id: "RemoteSession",
            title: "Zdalna sesja / pomoc zdalna",
            summary: "TeamViewer, AnyDesk, Parsec, Jump Desktop, Windows App lub udostępnianie ekranu macOS na pierwszym planie. Przerwa nie wskoczy w środek sesji u klienta ani cudzej pomocy.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t7)
            property clients : {"TeamViewer", "AnyDesk", "Parsec", "Jump Desktop", "Microsoft Remote Desktop", "Windows App", "RustDesk", "Screen Sharing", "DeskVNCViewer"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
                if clients contains frontName then return true
            end tell
            -- \(ScriptText.t8)
            try
                set n to do shell script "pgrep -x screensharingd | wc -l | tr -d ' '"
                if (n as integer) > 0 then return true
            end try
            return false
            """),
        GalleryScript(
            id: "ScreenRecording",
            title: "Nagrywanie ekranu / streaming",
            summary: "OBS, ScreenFlow, Loom, Screen Studio, CleanShot lub nagranie ekranu w QuickTime ma otwarte okno. Wykrywa narzędzie, nie sam fakt nagrywania, więc przy otwartym OBS bez nagrywania też zadziała.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t9)
            property tools : {"OBS", "ScreenFlow", "Loom", "Screen Studio", "CleanShot X"}
            tell application "System Events"
                repeat with n in tools
                    if exists process (n as text) then
                        try
                            if (count of windows of process (n as text)) > 0 then return true
                        end try
                    end if
                end repeat
                if exists process "QuickTime Player" then
                    try
                        repeat with w in windows of process "QuickTime Player"
                            set t to name of w
                            if t contains "Screen Recording" or t contains "Nagranie ekranu" then return true
                        end repeat
                    end try
                end if
            end tell
            return false
            """),
        GalleryScript(
            id: "BrowserMeeting",
            title: "Spotkanie w przeglądarce (Meet / Teams / Whereby)",
            summary: "Okno przeglądarki z tytułem spotkania: Google Meet, Microsoft Teams, Whereby, Jitsi, Webex lub Zoom w przeglądarce. Wideo w kartach nie jest wykrywane przez aplikacje desktopowe, dlatego osobna reguła. Wymaga uprawnienia Ułatwień dostępu.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t10)
            property browsers : {"Safari", "Google Chrome", "Arc", "Firefox", "Microsoft Edge", "Brave Browser"}
            property markers : {"Meet -", "meet.google.com", "Microsoft Teams", "Whereby", "Zoom Meeting", "Jitsi", "Webex"}
            tell application "System Events"
                repeat with b in browsers
                    if exists process (b as text) then
                        try
                            repeat with w in windows of process (b as text)
                                set t to name of w
                                repeat with m in markers
                                    if t contains (m as text) then return true
                                end repeat
                            end repeat
                        end try
                    end if
                end repeat
            end tell
            return false
            """),
        GalleryScript(
            id: "ChatHuddle",
            title: "Rozmowa głosowa w Slacku / Discordzie",
            summary: "Okno huddle Slacka albo połączenie głosowe na Discordzie. Rozmowa jest wtedy ważniejsza niż przypomnienie o przerwie. Wymaga uprawnienia Ułatwień dostępu.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t11)
            property apps : {"Slack", "Discord"}
            property markers : {"Huddle", "Voice Connected", "Połączono"}
            tell application "System Events"
                repeat with n in apps
                    if exists process (n as text) then
                        try
                            repeat with w in windows of process (n as text)
                                set t to name of w
                                repeat with m in markers
                                    if t contains (m as text) then return true
                                end repeat
                            end repeat
                        end try
                    end if
                end repeat
            end tell
            return false
            """),
        GalleryScript(
            id: "TerminalSession",
            title: "Sesja w terminalu (ssh / vim / htop)",
            summary: "Terminal na pierwszym planie, a w systemie działa żywy ssh, mosh, vim, nvim lub htop. Chroni długie sesje zdalne i edycję, której nie chcesz przerywać w pół zdania.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t12)
            property terminals : {"Terminal", "iTerm2", "Ghostty", "Warp", "kitty", "Alacritty", "WezTerm"}
            property procs : {"ssh", "mosh-client", "vim", "nvim", "htop"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            if terminals does not contain frontName then return false
            repeat with n in procs
                try
                    do shell script "pgrep -x " & quoted form of (n as text) & " >/dev/null"
                    return true
                end try
            end repeat
            return false
            """),
        GalleryScript(
            id: "CreativeFlow",
            title: "Praca twórcza (DAW / montaż / 3D)",
            summary: "Logic, GarageBand, Ableton, Pro Tools, Cubase, Reaper, Final Cut, Premiere, DaVinci Resolve lub Blender na pierwszym planie. Wejście w stan flow trudno odbudować po przerwie w środku nagrania lub renderu.",
            outcomeNote: "Zalecane: odroczenie przerwy.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t13)
            property apps : {"Logic", "GarageBand", "Ableton", "Pro Tools", "Cubase", "REAPER", "Final Cut", "Premiere", "DaVinci", "Blender"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            repeat with n in apps
                if frontName contains (n as text) then return true
            end repeat
            return false
            """),
        GalleryScript(
            id: "GameLaunchers",
            title: "Gra spoza Steama (Epic / Battle.net / GOG / Minecraft)",
            summary: "Launchery i gry, które nie są Steamem: Epic, Battle.net, GOG Galaxy, Heroic, CrossOver, Whisky, RetroArch, Minecraft. Uzupełnia regułę „Gra Valve / Steam”.",
            outcomeNote: "Zalecane: pomijaj automatycznie podczas grania.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t14)
            property apps : {"Epic Games", "Battle.net", "GOG", "Heroic", "CrossOver", "Whisky", "RetroArch", "Minecraft"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            repeat with n in apps
                if frontName contains (n as text) then return true
            end repeat
            return false
            """),
        GalleryScript(
            id: "MirroredDisplay",
            title: "Rzutnik / duplikowanie ekranu",
            summary: "Gdy ekran jest powielony na projektorze lub telewizorze (Mirror: On), to prawie na pewno ktoś na niego patrzy. Przerwa na cały ekran na czyjejś prezentacji byłaby niezręczna.",
            outcomeNote: "Zalecane: pomijaj automatycznie.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t15)
            try
                set n to do shell script "system_profiler SPDisplaysDataType | grep -c 'Mirror: On'"
                if (n as integer) > 0 then return true
            end try
            return false
            """),
        GalleryScript(
            id: "LongBuild",
            title: "Długi build / render (dobra pora na przerwę)",
            summary: "Działa xcodebuild, swift-build, cargo, gradle, mvn, ninja, ffmpeg lub HandBrake. Podczas czekania i tak nie masz nic do roboty, więc Intermezzo zaproponuje przerwę — dopiero gdy zadanie trwa dłużej niż ustawiony czas (domyślnie 2 min), a od ostatniej przerwy minęło co najmniej 10 minut pracy.",
            outcomeNote: "Wynik: zaproponuj przerwę teraz (nie odkłada, tylko podpowiada).",
            source: """
            -- Intermezzo Rule: \(ScriptText.t16)
            property procs : {"xcodebuild", "swift-build", "cargo", "gradle", "mvn", "ninja", "ffmpeg", "HandBrakeCLI"}
            repeat with n in procs
                try
                    do shell script "pgrep -x " & quoted form of (n as text) & " >/dev/null"
                    return true
                end try
            end repeat
            return false
            """),
        GalleryScript(
            id: "LunchHour",
            title: "Pora obiadu (12:00–13:00)",
            summary: "W godzinach obiadu przerwy nie są potrzebne: i tak odchodzisz od komputera. Traktuje tę godzinę jak naturalną przerwę. Godziny zmienisz w edytorze skryptu.",
            outcomeNote: "Zalecane: traktuj jako naturalną przerwę.",
            source: """
            -- Intermezzo Rule: \(ScriptText.t17)
            property fromHour : 12
            property toHour : 13
            set h to hours of (current date)
            return h is greater than or equal to fromHour and h is less than toHour
            """),
    ]
}

// MARK: - Editing and the user's own scripts

/// A rule script the user created in the editor (any file in `scriptsDir` that is not a gallery script).
struct CustomScript: Identifiable, Hashable {
    let url: URL
    let name: String
    var id: String { url.path }
}

/// Starting points for a new script in the editor.
struct ScriptTemplate: Identifiable {
    let id: String
    let title: String
    let body: String
}

extension ScriptGallery {
    /// Labels for the property names the gallery scripts and templates use.
    static let settingLabels: [String: String] = [
        "apps": "Aplikacje",
        "clients": "Aplikacje do rozmów i pulpitu zdalnego",
        "games": "Procesy gier",
        "tools": "Narzędzia",
        "browsers": "Przeglądarki",
        "markers": "Tytuł okna zawiera",
        "terminals": "Terminale",
        "procs": "Procesy",
        "fromHour": "Od godziny",
        "toHour": "Do godziny",
    ]

    static let templates: [ScriptTemplate] = [
        ScriptTemplate(id: "frontApp", title: "Aplikacja na pierwszym planie", body: """
            property apps : {"Safari"}
            tell application "System Events"
                set frontName to name of first process whose frontmost is true
            end tell
            return apps contains frontName
            """),
        ScriptTemplate(id: "windowTitle", title: "Tytuł okna zawiera tekst", body: """
            property apps : {"Safari", "Google Chrome"}
            property markers : {"Meet -"}
            tell application "System Events"
                repeat with b in apps
                    if exists process (b as text) then
                        try
                            repeat with w in windows of process (b as text)
                                set t to name of w
                                repeat with m in markers
                                    if t contains (m as text) then return true
                                end repeat
                            end repeat
                        end try
                    end if
                end repeat
            end tell
            return false
            """),
        ScriptTemplate(id: "process", title: "Działa proces", body: """
            property procs : {"ffmpeg"}
            repeat with n in procs
                try
                    do shell script "pgrep -x " & quoted form of (n as text) & " >/dev/null"
                    return true
                end try
            end repeat
            return false
            """),
        ScriptTemplate(id: "hours", title: "Przedział godzin", body: """
            property fromHour : 12
            property toHour : 13
            set h to hours of (current date)
            return h is greater than or equal to fromHour and h is less than toHour
            """),
        ScriptTemplate(id: "empty", title: "Pusty skrypt", body: """
            -- \(ScriptText.t18)
            -- \(ScriptText.t19)
            return false
            """),
    ]

    static func source(for template: ScriptTemplate, name: String) -> String {
        ScriptSettings.withRuleName(name, in: template.body)
    }

    static func customScripts() -> [CustomScript] {
        let galleryIDs = Set(catalog.map(\.id))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: scriptsDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "applescript" && !galleryIDs.contains($0.deletingPathExtension().lastPathComponent) }
            .map { url in
                let source = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return CustomScript(url: url, name: ScriptSettings.ruleName(in: source) ?? url.deletingPathExtension().lastPathComponent)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A free file URL for a new script named `name`.
    static func newScriptURL(named name: String) -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: scriptsDir, includingPropertiesForKeys: nil)) ?? []
        let taken = Set(files.map { $0.deletingPathExtension().lastPathComponent }).union(catalog.map(\.id))
        let stem = ScriptSettings.uniqueSlug(ScriptSettings.fileSlug(name), taken: taken)
        return scriptsDir.appendingPathComponent("\(stem).applescript")
    }

    @discardableResult
    static func write(_ source: String, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            Trace.log("script save failed \(url.lastPathComponent): \(error)")
            return false
        }
    }

    /// Adds a script rule for `path` unless one exists already.
    static func addRule(path: String, outcome: BreakRuleOutcome, store: BreakRuleStore = BreakRuleStore()) {
        var rules = store.load()
        guard !rules.contains(where: { $0.kind == .script && $0.text == path }) else { return }
        var rule = BreakRule()
        rule.kind = .script
        rule.text = path
        rule.outcome = outcome
        rule.postponeMinutes = 5
        if outcome == .suggestBreak { rule.sustainSeconds = 120 }
        rule.enabled = true
        rules.append(rule)
        store.save(rules)
    }

    /// Deletes a script file (own or installed from the gallery) and the rules that run it.
    static func remove(_ url: URL, store: BreakRuleStore = BreakRuleStore()) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Trace.log("script remove failed \(url.lastPathComponent): \(error)")
        }
        store.save(store.load().filter { !($0.kind == .script && $0.text == url.path) })
    }
}
