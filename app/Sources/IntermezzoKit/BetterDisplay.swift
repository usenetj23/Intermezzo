import Foundation

// BetterDisplay (a third-party display manager) can be asked, through distributed notifications, to
// read and change a display's brightness and to switch True Tone. This file holds the pure parts:
// the message format and the decisions about evening dimming.

public struct BetterDisplayResponse: Equatable, Sendable {
    public let uuid: String?
    public let result: Bool
    public let payload: String?
}

public struct BetterDisplayDevice: Equatable, Sendable {
    /// Equals the CoreGraphics display id.
    public let displayID: Int
    public let name: String
}

public enum BetterDisplayProtocol {
    public static let requestName = "pro.betterdisplay.BetterDisplay.request"
    public static let responseName = "pro.betterdisplay.BetterDisplay.response"
    public static let bundleIdentifier = "pro.betterdisplay.BetterDisplay"

    /// `parameters` with a nil value are sent as valueless parameters (a query).
    public static func requestJSON(uuid: String, command: String, parameters: [(String, String?)]) -> String {
        var params: [String: Any] = [:]
        for (key, value) in parameters { params[key] = value ?? NSNull() }
        let object: [String: Any] = ["uuid": uuid, "commands": [command], "parameters": params]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decodeResponse(_ json: String) -> BetterDisplayResponse? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return nil }
        return BetterDisplayResponse(uuid: object["uuid"] as? String, result: object["result"] as? Bool ?? false,
                                     payload: object["payload"] as? String)
    }

    /// The answer to `get identifiers` is a run of JSON objects separated by commas, not an array.
    /// Names of the display groups in an `identifiers` answer for `type=displayGroup`.
    public static func parseGroupNames(payload: String) -> [String] {
        guard let list = (try? JSONSerialization.jsonObject(with: Data("[\(payload)]".utf8))) as? [[String: Any]] else { return [] }
        return list.compactMap { ($0["deviceType"] as? String) == "DisplayGroup" ? $0["name"] as? String : nil }
    }

    public static func parseDevices(payload: String) -> [BetterDisplayDevice] {
        guard let list = (try? JSONSerialization.jsonObject(with: Data("[\(payload)]".utf8))) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard (item["deviceType"] as? String) == "Display", let id = Int(item["displayID"] as? String ?? "") else { return nil }
            return BetterDisplayDevice(displayID: id, name: item["name"] as? String ?? "#\(id)")
        }
    }

    public static func number(_ payload: String?) -> Double? {
        payload.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

public enum EveningDimming {
    /// The most the user may ask for, and the floor below which a display is never driven.
    public static let maxDimPercent = 50
    static let floorFactor = 0.5

    /// 1 in the daytime, down to `1 - maxDimPercent/100` when the screen is at its warmest.
    public static func factor(kelvin: Double, settings: LightSettings, maxDimPercent: Int) -> Double {
        let s = settings.sanitized
        let span = s.dayK - s.bedtimeK
        guard span > 1 else { return 1 }
        let warmth = min(max((s.dayK - kelvin) / span, 0), 1)
        let dim = Double(min(max(maxDimPercent, 0), Self.maxDimPercent)) / 100
        return max(Self.floorFactor, 1 - warmth * dim)
    }

    /// The brightness was changed by someone else since we set it.
    public static func userChanged(current: Double, lastSet: Double, tolerance: Double = 0.04) -> Bool {
        abs(current - lastSet) > tolerance
    }

    /// Only a change of at least this much is sent: DDC writes are slow.
    public static func needsUpdate(target: Double, lastSet: Double?, step: Double = 0.02) -> Bool {
        guard let lastSet else { return true }
        return abs(target - lastSet) >= step
    }
}

/// Displays that BetterDisplay keeps in step (a group, or two identical monitors): setting one moves the others.
public enum BetterDisplayLinks {
    /// Displays other than `leader` whose brightness followed the value just set on it.
    public static func followers(leader: Int, wanted: Double, before: [Int: Double], after: [Int: Double],
                                 tolerance: Double = 0.03) -> Set<Int> {
        var result = Set<Int>()
        for (id, now) in after where id != leader {
            guard let was = before[id] else { continue }
            if abs(now - was) > tolerance && abs(now - wanted) <= tolerance { result.insert(id) }
        }
        return result
    }
}

/// What the integration changed, kept on disk so that the originals can be put back after a crash.
public struct BetterDisplayState: Codable, Equatable, Sendable {
    public var originalBrightness: [String: Double] = [:]
    public var lastSetBrightness: [String: Double] = [:]
    public var trueToneWasOn = false
    /// Displays that follow another one (follower id -> leader id); never touched on their own.
    public var followerOf: [String: String] = [:]
    /// A BetterDisplay group switched off for a while (see `BetterDisplayGroups`), to be switched on again.
    public var disabledGroups: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case originalBrightness, lastSetBrightness, trueToneWasOn, followerOf, disabledGroups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalBrightness = try c.decodeIfPresent([String: Double].self, forKey: .originalBrightness) ?? [:]
        lastSetBrightness = try c.decodeIfPresent([String: Double].self, forKey: .lastSetBrightness) ?? [:]
        trueToneWasOn = try c.decodeIfPresent(Bool.self, forKey: .trueToneWasOn) ?? false
        followerOf = try c.decodeIfPresent([String: String].self, forKey: .followerOf) ?? [:]
        disabledGroups = try c.decodeIfPresent([String].self, forKey: .disabledGroups) ?? []
    }

    public var isEmpty: Bool { originalBrightness.isEmpty && !trueToneWasOn && disabledGroups.isEmpty }

    /// The user (or the evening ending) unlinked the displays: each follower now has its leader's values.
    public mutating func unlinkFollowers() {
        for (follower, leader) in followerOf {
            if let original = originalBrightness[leader] { originalBrightness[follower] = original }
            if let last = lastSetBrightness[leader] { lastSetBrightness[follower] = last }
        }
        followerOf = [:]
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> BetterDisplayState {
        data.flatMap { try? JSONDecoder().decode(BetterDisplayState.self, from: $0) } ?? BetterDisplayState()
    }
}
