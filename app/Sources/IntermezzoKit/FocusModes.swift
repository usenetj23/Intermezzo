import Foundation

/// A Focus mode as macOS knows it.
public struct FocusMode: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the app does while a Focus mode is on.
public enum FocusRole: String, Codable, CaseIterable, Sendable {
    /// The Mac is at work: counts as a work-zone match (the iPhone switches such a Focus by place).
    case work
    /// Holds breaks, as Do Not Disturb does.
    case pause
    /// Changes nothing.
    case ignore

    public var title: String {
        switch self {
        case .work: return "Praca (strefa pracy)"
        case .pause: return "Wstrzymuje przerwy"
        case .ignore: return "Ignoruj"
        }
    }
}

/// Reads the Focus files macOS keeps under ~/Library/DoNotDisturb/DB (the caller supplies the bytes).
/// The layout is not documented, so both readers search the JSON for the keys they need instead of
/// following a fixed path.
public enum FocusModes {
    public static let workModeID = "com.apple.focus.work"

    /// Names for the modes macOS ships, used when ModeConfigurations has no entry for them.
    public static let builtInNames: [String: String] = [
        "com.apple.donotdisturb.mode.default": "Nie przeszkadzać",
        "com.apple.sleep.sleep-mode": "Sen",
        "com.apple.focus.work": "Praca",
        "com.apple.focus.personal-time": "Czas osobisty",
        "com.apple.focus.reading": "Czytanie",
        "com.apple.focus.gaming": "Gry",
        "com.apple.focus.mindfulness": "Uważność",
        "com.apple.donotdisturb.mode.driving": "Jazda",
        "com.apple.donotdisturb.mode.fitness": "Fitness",
    ]

    /// Identifiers of the modes that are on right now (the records in `storeAssertionRecords`).
    public static func activeModeIDs(assertions: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: assertions) else { return [] }
        var found: [String] = []
        collectActive(root, into: &found)
        return found
    }

    private static func collectActive(_ node: Any, into found: inout [String]) {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "storeAssertionRecords" {
                    collectModeIDs(value, into: &found)
                } else {
                    collectActive(value, into: &found)
                }
            }
        } else if let list = node as? [Any] {
            for item in list { collectActive(item, into: &found) }
        }
    }

    private static func collectModeIDs(_ node: Any, into found: inout [String]) {
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key == "assertionDetailsModeIdentifier", let id = value as? String {
                    if !found.contains(id) { found.append(id) }
                } else {
                    collectModeIDs(value, into: &found)
                }
            }
        } else if let list = node as? [Any] {
            for item in list { collectModeIDs(item, into: &found) }
        }
    }

    /// Mode identifier to display name, from every `{ modeIdentifier, name }` pair in ModeConfigurations.
    public static func names(configurations: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: configurations) else { return [:] }
        var result: [String: String] = [:]
        collectNames(root, into: &result)
        return result
    }

    private static func collectNames(_ node: Any, into result: inout [String: String]) {
        if let dict = node as? [String: Any] {
            if let id = dict["modeIdentifier"] as? String, let name = dict["name"] as? String, !name.isEmpty {
                result[id] = name
            }
            for value in dict.values { collectNames(value, into: &result) }
        } else if let list = node as? [Any] {
            for item in list { collectNames(item, into: &result) }
        }
    }

    public static func displayName(for id: String, names: [String: String]) -> String {
        names[id] ?? builtInNames[id] ?? id
    }

    /// The Work mode counts as work unless the user said otherwise; every other mode holds breaks, as before.
    public static func role(for id: String, stored: [String: FocusRole]) -> FocusRole {
        stored[id] ?? (id == workModeID ? .work : .pause)
    }
}
