import Foundation

// The settings the AI assistant may change, and the checks every proposal of the model goes through.
// Only entries listed here can ever be written: paths, hotkeys, network names, places, folders and scripts
// are not in the catalog on purpose. The model's answer is untrusted text, so nothing in it is executed
// and a value outside its range is rejected, never trimmed to fit.

public struct SettingEntry: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case flag
        /// A whole number in `range`; `step` is only a hint for the prompt.
        case number(range: ClosedRange<Int>, step: Int)
        /// A whole number from a short list of allowed values.
        case numbers([Int])
        case minutesOfDay
        case choice([String])
    }

    public let key: String
    public let kind: Kind
    public let group: String
    public let descriptionPL: String
    public let descriptionEN: String
    /// What the app uses while the key is not stored.
    public let defaultValue: SettingValue

    public init(key: String, kind: Kind, group: String, descriptionPL: String, descriptionEN: String, defaultValue: SettingValue) {
        self.key = key
        self.kind = kind
        self.group = group
        self.descriptionPL = descriptionPL
        self.descriptionEN = descriptionEN
        self.defaultValue = defaultValue
    }
}

public enum SettingValue: Equatable, Sendable, Codable {
    case flag(Bool)
    case number(Int)
    case text(String)
}

public struct ProposedChange: Equatable, Sendable {
    public let key: String
    public let old: SettingValue?
    public let new: SettingValue
}

public struct SkippedChange: Equatable, Sendable {
    public let key: String
    public let reason: String
}

public struct SettingsProposal: Equatable, Sendable {
    public let changes: [ProposedChange]
    public let skipped: [SkippedChange]
    public let explanation: String?
}

public enum SettingsCatalog {
    private static func entry(_ key: String, _ kind: SettingEntry.Kind, _ group: String, _ pl: String, _ en: String,
                              _ value: SettingValue) -> SettingEntry {
        SettingEntry(key: key, kind: kind, group: group, descriptionPL: pl, descriptionEN: en, defaultValue: value)
    }

    public static let entries: [SettingEntry] = [
        entry("cycleMinutes", .number(range: 5...180, step: 5), "breaks",
              "Co ile minut pracy zaczyna się przerwa", "Minutes of work between breaks", .number(45)),
        entry("shortBreakSeconds", .number(range: BreakLengthLimits.shortAbsolute, step: 5), "breaks",
              "Długość krótkiej przerwy w sekundach", "Length of a short break in seconds", .number(300)),
        entry("longBreakSeconds", .number(range: BreakLengthLimits.longAbsolute, step: 30), "breaks",
              "Długość długiej przerwy w sekundach", "Length of a long break in seconds", .number(900)),
        entry("longBreakEvery", .number(range: 2...12, step: 1), "breaks",
              "Co którą przerwa jest długa", "Every how many breaks one is a long break", .number(4)),
        entry("playSound", .flag, "breaks", "Dźwięk przy przerwie", "Sound during a break", .flag(true)),
        entry("strictMode", .flag, "breaks", "Tryb surowy: pominięcie przerwy wymaga potwierdzenia",
              "Strict mode: skipping a break needs confirmation", .flag(false)),
        entry("pomodoroMode", .flag, "breaks", "Tryb Pomodoro", "Pomodoro mode", .flag(false)),
        entry("enforceWorkingHours", .flag, "work", "Przerwy tylko w godzinach pracy", "Breaks only during working hours", .flag(false)),
        entry("workStartMinutes", .minutesOfDay, "work", "Początek pracy, minuty od północy", "Start of work, minutes since midnight", .number(480)),
        entry("workEndMinutes", .minutesOfDay, "work", "Koniec pracy, minuty od północy", "End of work, minutes since midnight", .number(1080)),
        entry("workDaysMask", .number(range: 0...127, step: 1), "work",
              "Dni pracy jako maska bitów: poniedziałek 1, wtorek 2, środa 4, czwartek 8, piątek 16, sobota 32, niedziela 64 (pn–pt = 31)",
              "Working days as a bit mask: Monday 1, Tuesday 2, Wednesday 4, Thursday 8, Friday 16, Saturday 32, Sunday 64 (Mon–Fri = 31)",
              .number(31)),
        entry("meetingDetection", .flag, "detection", "Nie przerywaj w spotkaniach i rozmowach wideo",
              "Do not interrupt during meetings and video calls", .flag(true)),
        entry("videoDetection", .flag, "detection", "Nie przerywaj podczas oglądania wideo", "Do not interrupt while watching video", .flag(true)),
        entry("focusDetection", .flag, "detection", "Uwzględniaj tryb Skupienia macOS", "Respect the macOS Focus mode", .flag(false)),
        entry("idleDetection", .flag, "detection", "Wstrzymaj odliczanie, gdy nie ma aktywności", "Pause the timer when you are away", .flag(true)),
        entry("idleThresholdSeconds", .number(range: 60...900, step: 30), "detection",
              "Po ilu sekundach bezczynności uznać, że odszedłeś", "Seconds of inactivity before you count as away", .number(60)),
        entry("cursorCountdown", .flag, "reminders", "Odliczanie przy kursorze przed przerwą", "Countdown next to the cursor before a break", .flag(true)),
        entry("breakLeadPopup", .number(range: 10...300, step: 5), "reminders",
              "Ile sekund przed przerwą pokazać wyskakujące okno", "Seconds before a break to show the popup", .number(30)),
        entry("flashEnabled", .flag, "reminders", "Delikatny błysk ekranu jako przypomnienie", "Gentle screen flash as a reminder", .flag(false)),
        entry("flashIntervalMinutes", .numbers([5, 10, 15, 30]), "reminders",
              "Co ile minut błysk (5, 10, 15 lub 30)", "Minutes between flashes (5, 10, 15 or 30)", .number(10)),
        entry("lightEnabled", .flag, "light", "Barwa ekranu według pory dnia", "Screen colour by the time of day", .flag(false)),
        entry("lightProfile", .choice(["recommended", "classic", "farFromEquator", "workingLate"]), "light",
              "Profil barwy: recommended (zalecany), classic, farFromEquator (daleko od równika), workingLate (praca do późna)",
              "Colour profile: recommended, classic, farFromEquator, workingLate", .text("recommended")),
        entry("lightWakeMinutes", .minutesOfDay, "light", "Godzina wstawania dla Światła, minuty od północy",
              "Wake-up time for Light, minutes since midnight", .number(420)),
    ]

    public static func entry(for key: String) -> SettingEntry? { entries.first { $0.key == key } }

    /// The values the catalog's keys have now; a key that is not stored shows the app's default.
    public static func current(in d: UserDefaults) -> [String: SettingValue] {
        var values: [String: SettingValue] = [:]
        for entry in entries {
            guard d.object(forKey: entry.key) != nil else { values[entry.key] = entry.defaultValue; continue }
            switch entry.kind {
            case .flag: values[entry.key] = .flag(d.bool(forKey: entry.key))
            case .number, .numbers, .minutesOfDay: values[entry.key] = .number(d.integer(forKey: entry.key))
            case .choice: values[entry.key] = .text(d.string(forKey: entry.key) ?? "")
            }
        }
        return values
    }

    /// Writes the changes with the types the app stores them in. Keys outside the catalog are ignored.
    public static func apply(_ changes: [ProposedChange], to d: UserDefaults) {
        for change in changes where entry(for: change.key) != nil {
            switch change.new {
            case .flag(let value): d.set(value, forKey: change.key)
            case .number(let value): d.set(value, forKey: change.key)
            case .text(let value): d.set(value, forKey: change.key)
            }
        }
    }
}

public enum SettingsAssistant {
    private static let maxItems = 200

    // MARK: Prompt

    public static func prompt(request: String, current: [String: SettingValue], language: String) -> AIRequest {
        let polish = language == "pl"
        let lines = SettingsCatalog.entries.map { entry -> String in
            let value = current[entry.key] ?? entry.defaultValue
            return "- \(entry.key) (\(kindText(entry.kind))): \(polish ? entry.descriptionPL : entry.descriptionEN). Current: \(valueText(value))"
        }
        let system = """
        You configure a break reminder app for macOS. The user describes how the app should work; you answer \
        with the settings to change.
        Rules:
        - Answer with a single JSON object and nothing else: {"changes":[{"key":"<key>","value":<value>}],"explanation":"<one or two short sentences>"}.
        - Use only the keys listed below, with a value of the stated type and inside the stated range. Never invent keys.
        - Change only what the request needs. If nothing fits, return an empty "changes" list and say why in "explanation".
        - Do not give medical or health advice.
        - Write "explanation" in \(polish ? "Polish" : "English").
        """
        let user = (["Settings you may change:"] + lines + ["", "Request: \(request)"]).joined(separator: "\n")
        return AIRequest(system: system, user: user, jsonSchema: schema)
    }

    public static var schema: String {
        let keys = SettingsCatalog.entries.map { "\"\($0.key)\"" }.joined(separator: ",")
        return #"{"type":"object","properties":{"changes":{"type":"array","items":{"type":"object","properties":{"key":{"type":"string","enum":["# + keys + #"]},"value":{"type":["boolean","integer","string"]}},"required":["key","value"]}},"explanation":{"type":"string"}},"required":["changes"]}"#
    }

    private static func kindText(_ kind: SettingEntry.Kind) -> String {
        switch kind {
        case .flag: return "true or false"
        case .number(let range, let step): return "integer \(range.lowerBound) to \(range.upperBound), steps of \(step)"
        case .numbers(let values): return "one of " + values.map(String.init).joined(separator: ", ")
        case .minutesOfDay: return "integer 0 to 1439"
        case .choice(let values): return "one of " + values.map { "\"\($0)\"" }.joined(separator: ", ")
        }
    }

    private static func valueText(_ value: SettingValue) -> String {
        switch value {
        case .flag(let on): return on ? "true" : "false"
        case .number(let n): return String(n)
        case .text(let s): return "\"\(s)\""
        }
    }

    // MARK: Answer

    /// What the model's text proposes. Anything that is not a change to a catalog key with a fitting value
    /// is skipped with a reason; unreadable text gives an empty proposal.
    public static func parse(_ text: String, current: [String: SettingValue]) -> SettingsProposal {
        guard let data = JSONExtract.firstJSON(in: text), let root = try? JSONSerialization.jsonObject(with: data) else {
            return SettingsProposal(changes: [], skipped: [], explanation: nil)
        }
        let items: [Any]
        var explanation: String?
        if let object = root as? [String: Any] {
            items = object["changes"] as? [Any] ?? []
            explanation = (object["explanation"] as? String).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)) }
        } else {
            items = root as? [Any] ?? []
        }
        var order: [String] = []
        var accepted: [String: SettingValue] = [:]
        var skipped: [SkippedChange] = []
        var seen: [String: Int] = [:]
        func skip(_ key: String, _ reason: String) {
            if !skipped.contains(where: { $0.key == key }) { skipped.append(SkippedChange(key: key, reason: reason)) }
        }
        for item in items.prefix(maxItems) {
            guard let dict = item as? [String: Any], let key = dict["key"] as? String, let raw = dict["value"] else { continue }
            seen[key, default: 0] += 1
            guard let entry = SettingsCatalog.entry(for: key) else { skip(key, kitL("nieznane ustawienie")); continue }
            guard let value = validated(raw, for: entry) else { skip(key, kitL("wartość nie pasuje")); continue }
            if accepted[key] == nil { order.append(key) }
            accepted[key] = value
        }
        // A key the model gave twice is not guessed at: neither value is proposed.
        for (key, count) in seen where count > 1 && accepted[key] != nil {
            accepted[key] = nil
            skip(key, kitL("ustawienie powtórzone w odpowiedzi"))
        }
        // Settings that only make sense together are checked as the app would see them after the change.
        func effective(_ key: String) -> SettingValue? { accepted[key] ?? current[key] ?? SettingsCatalog.entry(for: key)?.defaultValue }
        func number(_ key: String) -> Int? { if case .number(let n)? = effective(key) { return n } else { return nil } }
        func flag(_ key: String) -> Bool { if case .flag(let on)? = effective(key) { return on } else { return false } }
        let rules: [(keys: [String], violated: Bool, reason: String)] = [
            (["shortBreakSeconds", "longBreakSeconds"], (number("shortBreakSeconds") ?? 0) > (number("longBreakSeconds") ?? Int.max),
             kitL("krótka przerwa byłaby dłuższa niż długa")),
            (["workStartMinutes", "workEndMinutes"], (number("workStartMinutes") ?? 0) >= (number("workEndMinutes") ?? Int.max),
             kitL("początek pracy nie byłby przed jej końcem")),
            (["workDaysMask", "enforceWorkingHours"], number("workDaysMask") == 0 && flag("enforceWorkingHours"),
             kitL("godziny pracy bez żadnego dnia pracy wyłączyłyby przerwy")),
        ]
        for rule in rules where rule.violated {
            for key in rule.keys where accepted[key] != nil {
                accepted[key] = nil
                skip(key, rule.reason)
            }
        }
        let changes = order.compactMap { key -> ProposedChange? in
            guard let new = accepted[key] else { return nil }
            let old = current[key] ?? SettingsCatalog.entry(for: key)?.defaultValue
            return new == old ? nil : ProposedChange(key: key, old: old, new: new)
        }
        return SettingsProposal(changes: changes, skipped: skipped, explanation: explanation)
    }

    /// The value in the type the entry needs, or nil when it does not fit.
    static func validated(_ raw: Any, for entry: SettingEntry) -> SettingValue? {
        let number = raw as? NSNumber
        let isBool = number.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        func whole() -> Int? {
            guard let number, !isBool, number.doubleValue == number.doubleValue.rounded(), abs(number.doubleValue) < 1e9 else { return nil }
            return number.intValue
        }
        switch entry.kind {
        case .flag:
            return isBool ? .flag(number!.boolValue) : nil
        case .number(let range, _):
            return whole().flatMap { range.contains($0) ? .number($0) : nil }
        case .numbers(let values):
            return whole().flatMap { values.contains($0) ? .number($0) : nil }
        case .minutesOfDay:
            return whole().flatMap { (0...1439).contains($0) ? .number($0) : nil }
        case .choice(let values):
            return (raw as? String).flatMap { values.contains($0) ? .text($0) : nil }
        }
    }

    static func validated(_ value: SettingValue, for entry: SettingEntry) -> SettingValue? {
        switch value {
        case .flag(let on): return validated(on as Any, for: entry)
        case .number(let n): return validated(n as Any, for: entry)
        case .text(let s): return validated(s as Any, for: entry)
        }
    }
}

// MARK: - Undo

/// The values the assistant is about to change, so that they can be put back exactly.
/// A `nil` value means the key was not stored; restoring removes it again.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public let takenAt: Date
    public let values: [String: SettingValue?]

    public init(takenAt: Date, values: [String: SettingValue?]) {
        self.takenAt = takenAt
        self.values = values
    }

    public static func capture(keys: [String], from d: UserDefaults, now: Date) -> SettingsSnapshot {
        var values: [String: SettingValue?] = [:]
        for key in keys {
            if let object = d.object(forKey: key) {
                if let number = object as? NSNumber {
                    values[key] = CFGetTypeID(number) == CFBooleanGetTypeID() ? .flag(number.boolValue) : .number(number.intValue)
                } else if let text = object as? String {
                    values[key] = .text(text)
                } else {
                    values[key] = .some(nil)
                }
            } else {
                values[key] = .some(nil)
            }
        }
        return SettingsSnapshot(takenAt: now, values: values)
    }

    public func restore(into d: UserDefaults) {
        for (key, value) in values {
            switch value {
            case .flag(let on)?: d.set(on, forKey: key)
            case .number(let n)?: d.set(n, forKey: key)
            case .text(let s)?: d.set(s, forKey: key)
            case nil: d.removeObject(forKey: key)
            }
        }
    }
}

/// The last few snapshots, newest last, kept in UserDefaults on this Mac.
public enum SettingsHistory {
    public static let key = "aiAssistantUndo"
    public static let limit = 5

    private static func load(from d: UserDefaults) -> [SettingsSnapshot] {
        guard let data = d.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SettingsSnapshot].self, from: data)) ?? []
    }

    private static func save(_ snapshots: [SettingsSnapshot], to d: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshots) { d.set(data, forKey: key) }
    }

    public static func count(in d: UserDefaults) -> Int { load(from: d).count }

    public static func push(_ snapshot: SettingsSnapshot, to d: UserDefaults) {
        save(Array((load(from: d) + [snapshot]).suffix(limit)), to: d)
    }

    public static func popLast(from d: UserDefaults) -> SettingsSnapshot? {
        var snapshots = load(from: d)
        guard let last = snapshots.popLast() else { return nil }
        save(snapshots, to: d)
        return last
    }
}
