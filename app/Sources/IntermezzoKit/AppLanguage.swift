import Foundation

/// Interface language: follow the system, or force English or Polish.
/// The choice is applied through the `AppleLanguages` override and takes effect after a restart.
public enum AppLanguage: String, CaseIterable, Equatable {
    case system, english = "en", polish = "pl"

    public init(stored: String?) {
        self = stored.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Value for the `AppleLanguages` default; nil removes the override.
    public var appleLanguages: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .polish: return ["pl"]
        }
    }

    /// The choice that matches an existing `AppleLanguages` override.
    public static func current(appleLanguages: [String]?) -> AppLanguage {
        guard let first = appleLanguages?.first else { return .system }
        if first.hasPrefix("pl") { return .polish }
        if first.hasPrefix("en") { return .english }
        return .system
    }
}
