import Foundation

// MARK: - Rules
//
// If a rule's condition matches when a break is due, the break is skipped
// or postponed instead of firing. Conditions cover frontmost/open apps
// (with is/isn't reversal), calendar text, fullscreen / screensaver /
// display sleep, Focus, meeting & video contexts, and AppleScript hooks.

public enum BreakRuleKind: String, Codable, CaseIterable, Identifiable {
    case frontmostApp
    case appOpen
    case calendarText
    case fullscreen
    case screensaver
    case displayAsleep
    case focusActive
    case meetingActive
    case videoActive
    case script

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .frontmostApp: return "Aplikacja z przodu"
        case .appOpen: return "Aplikacja otwarta"
        case .calendarText: return "Kalendarz (tekst w wydarzeniu)"
        case .fullscreen: return "Pełny ekran aktywny"
        case .screensaver: return "Wygaszacz ekranu"
        case .displayAsleep: return "Ekran uśpiony"
        case .focusActive: return "Tryb Skupienia (Focus)"
        case .meetingActive: return "Spotkanie online (video)"
        case .videoActive: return "Odtwarzanie wideo"
        case .script: return "Skrypt (AppleScript)"
        }
    }

    /// Kinds that need a text field (app name / search text / script path).
    public var needsText: Bool {
        switch self {
        case .frontmostApp, .appOpen, .calendarText, .script: return true
        default: return false
        }
    }
}

public enum BreakRuleOutcome: String, Codable, CaseIterable, Identifiable {
    case autoSkip
    case postpone
    case ignoreNaturalBreak
    case treatAsNaturalBreak
    /// Opposite of postponing: when the condition holds (a long build, an idle render…) offer a
    /// break right now instead of waiting for the timer.
    case suggestBreak

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .autoSkip: return "Automatycznie pomiń"
        case .postpone: return "Odrocz"
        case .ignoreNaturalBreak: return "Ignoruj naturalną pauzę"
        case .treatAsNaturalBreak: return "Traktuj jako naturalną pauzę"
        case .suggestBreak: return "Zaproponuj przerwę teraz"
        }
    }
}

public struct BreakRule: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var enabled: Bool = true
    public var kind: BreakRuleKind = .frontmostApp
    /// Match text: app name (partial, case-insensitive), calendar text, or script path.
    public var text: String = ""
    /// Reverse the condition ("isn't" / script "is false").
    public var inverted: Bool = false
    /// What to do when the rule matches.
    public var outcome: BreakRuleOutcome = .postpone
    /// Postpone interval in minutes (used by .postpone outcome).
    public var postponeMinutes: Int = 5
    /// `.suggestBreak`: the condition must hold this long before a break is offered.
    public var sustainSeconds: Int = 60
    /// `.suggestBreak`: minimum spacing between two offers from this rule.
    public var cooldownMinutes: Int = 30

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case id, enabled, kind, text, inverted, outcome, postponeMinutes, sustainSeconds, cooldownMinutes
    }

    /// Tolerant decoding: rules saved by older versions lack the newer keys and must keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        kind = try c.decodeIfPresent(BreakRuleKind.self, forKey: .kind) ?? .frontmostApp
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        inverted = try c.decodeIfPresent(Bool.self, forKey: .inverted) ?? false
        outcome = try c.decodeIfPresent(BreakRuleOutcome.self, forKey: .outcome) ?? .postpone
        postponeMinutes = try c.decodeIfPresent(Int.self, forKey: .postponeMinutes) ?? 5
        sustainSeconds = try c.decodeIfPresent(Int.self, forKey: .sustainSeconds) ?? 60
        cooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 30
    }

    /// Short human name for messages: the script's file name, or "<kind>: <text>".
    public var displayName: String {
        if kind == .script, !text.isEmpty {
            return URL(fileURLWithPath: text).deletingPathExtension().lastPathComponent
        }
        return text.isEmpty ? kitL(kind.label) : "\(kitL(kind.label)): \(text)"
    }
}

public final class BreakRuleStore {
    public static let storageKey = "breakRulesList"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [BreakRule] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let rules = try? JSONDecoder().decode([BreakRule].self, from: data) else { return [] }
        return rules
    }

    @discardableResult
    public func save(_ rules: [BreakRule]) -> Bool {
        guard let data = try? JSONEncoder().encode(rules) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }

    public func add(_ rule: BreakRule) {
        var rules = load()
        rules.append(rule)
        save(rules)
    }

    public func update(_ rule: BreakRule) {
        var rules = load()
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save(rules)
    }

    public func remove(id: UUID) {
        var rules = load()
        rules.removeAll { $0.id == id }
        save(rules)
    }
}
