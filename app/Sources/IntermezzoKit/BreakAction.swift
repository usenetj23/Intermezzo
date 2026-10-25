import Foundation

// MARK: - Break Actions data model ("do things around a break").
//
// A list of actions, each with a kind and a timing point (before due /
// after start / after any end) plus an offset. JSON persistence is provided
// here (pure); reading/writing UserDefaults and executing live in the app.

public enum BreakActionKind: String, Codable, CaseIterable, Sendable {
    case notification
    case playSound
    case fadeoutSound
    case flashScreen
    case speakText
    case soundVolume
    case musicPause
    case musicPlay
    /// Hydration registry: record "N ml of <drink>" (optionally pushed to
    /// Apple Health). Typical setup: when=buttonClicked, title="Water".
    case logDrink
    case script
}

public enum BreakActionWhen: String, Codable, CaseIterable, Sendable {
    case beforeDue
    case afterStart
    /// Break has fully faded in.
    case afterFadeIn
    /// Break starts to fade out on completion or skip.
    case beforeFadeOut
    /// Break has fully faded out (completion).
    case beforeFinish
    /// Same as beforeFinish but can be offset after completion.
    case afterFinish
    /// Break was postponed/skipped instead of completed.
    case afterPostpone
    /// Any end: completion OR postpone/skip.
    case afterAnyEnd
    /// Run only when the user clicks the named button in the control panel.
    case buttonClicked
}

/// How long the overlay takes to fade in or out; both the UI and the
/// action scheduler must agree on this value.
public let breakFadeDuration: TimeInterval = 0.5

public struct BreakActionItem: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var kind: BreakActionKind = .notification
    public var when: BreakActionWhen = .afterStart
    /// Offset from the timing point, seconds. For `.beforeDue` the action
    /// fires `offset` seconds BEFORE the break starts; for the other points
    /// `offset` seconds AFTER it.
    public var offsetSeconds: Int = 0
    public var title: String = kitL("Przerwa")
    public var message: String = kitL("Zrób przerwę.")
    public var soundName: String = "Glass"      // NSSound name or file path
    public var fadeSeconds: Int = 3             // fadeoutSound duration
    public var colorHex: String = "FFFFFF"      // flashScreen color
    public var speakText: String = kitL("Czas na przerwę")
    /// soundVolume mode: mute | restore | set | increase | decrease
    public var volumeMode: String = "mute"
    public var volumePercent: Int = 50
    public var scriptPath: String = ""
    /// logDrink: what was drunk — one of HydrationStore.drinkKinds.
    public var drinkKind: String = "woda"
    /// logDrink: how much, millilitres.
    public var amountMl: Int = 250
    public var enabled: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case id, kind, when, offsetSeconds, title, message, soundName,
             fadeSeconds, colorHex, speakText, volumeMode, volumePercent,
             scriptPath, drinkKind, amountMl, enabled
    }

    /// Tolerant decoding: fields added in later versions may be missing
    /// from stored JSON written by older builds — fall back to the default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func or<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        id = or(.id, UUID())
        kind = or(.kind, .notification)
        when = or(.when, .afterStart)
        offsetSeconds = or(.offsetSeconds, 0)
        title = or(.title, kitL("Przerwa"))
        message = or(.message, kitL("Zrób przerwę."))
        soundName = or(.soundName, "Glass")
        fadeSeconds = or(.fadeSeconds, 3)
        colorHex = or(.colorHex, "FFFFFF")
        speakText = or(.speakText, kitL("Czas na przerwę"))
        volumeMode = or(.volumeMode, "mute")
        volumePercent = or(.volumePercent, 50)
        scriptPath = or(.scriptPath, "")
        drinkKind = or(.drinkKind, "woda")
        amountMl = or(.amountMl, 250)
        enabled = or(.enabled, true)
    }
}

public enum BreakActionStore {
    public static let storageKey = "breakActionsList"

    /// Decode from JSON Data (nil on garbage; empty array is valid).
    public static func decode(_ data: Data?) -> [BreakActionItem]? {
        guard let data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode([BreakActionItem].self, from: data)
    }

    public static func encode(_ items: [BreakActionItem]) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(items)
    }
}
