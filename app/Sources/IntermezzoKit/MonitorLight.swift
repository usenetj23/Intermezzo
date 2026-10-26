import Foundation

// Light settings that belong to one kind of monitor: a limit for how warm its colour may get, its own
// evening dimming and a switch that leaves it alone (a TV). Monitors are told apart by the model in
// their EDID, so two identical monitors share one profile. Pure logic only; the app reads the displays.

/// A kind of monitor: the EDID's vendor and product numbers.
public struct MonitorKey: Hashable, Codable, Sendable {
    public let vendor: UInt32
    public let model: UInt32

    public init(vendor: UInt32, model: UInt32) {
        self.vendor = vendor
        self.model = model
    }

    /// The key behind an `id` string; nil when the text is not one.
    public init?(id: String) {
        let parts = id.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let vendor = UInt32(parts[0], radix: 16), let model = UInt32(parts[1], radix: 16) else { return nil }
        self.init(vendor: vendor, model: model)
    }

    public var id: String { String(format: "%08x-%08x", vendor, model) }

    /// Virtual displays, adapters and some projectors report 0 or all ones instead of a real model.
    public var isIdentifiable: Bool {
        ![0, 0xFFFF_FFFF].contains(vendor) && ![0, 0xFFFF_FFFF].contains(model)
    }
}

public struct MonitorProfile: Codable, Equatable, Sendable {
    public var name: String
    /// The warmest colour this monitor may show (kelvin); nil follows the general curve.
    public var warmestK: Double?
    /// This monitor's own evening dimming (percent); nil uses the general one.
    public var dimPercent: Int?
    /// Leave this monitor alone: no colour change and no dimming.
    public var untouched: Bool
    public var lastSeen: Date

    public init(name: String, warmestK: Double? = nil, dimPercent: Int? = nil, untouched: Bool = false, lastSeen: Date) {
        self.name = name
        self.warmestK = warmestK
        self.dimPercent = dimPercent
        self.untouched = untouched
        self.lastSeen = lastSeen
    }

    public var hasOverrides: Bool { warmestK != nil || dimPercent != nil }
}

/// Every monitor the app has seen, keyed by `MonitorKey.id`. Changes return a new value.
public struct MonitorProfiles: Equatable, Sendable {
    public let items: [String: MonitorProfile]

    public init(items: [String: MonitorProfile] = [:]) {
        self.items = items
    }

    public func profile(for key: MonitorKey) -> MonitorProfile? { items[key.id] }

    public func setting(_ profile: MonitorProfile, for key: MonitorKey) -> MonitorProfiles {
        MonitorProfiles(items: items.merging([key.id: profile]) { _, new in new })
    }

    public func removing(_ key: MonitorKey) -> MonitorProfiles {
        MonitorProfiles(items: items.filter { $0.key != key.id })
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(items)) ?? Data()
    }

    /// Empty for missing or unreadable data: the app then behaves as if no monitor had settings.
    public static func decode(_ data: Data?) -> MonitorProfiles {
        guard let data else { return MonitorProfiles() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // One unreadable entry must not take the others with it: the next save would erase them all.
        guard let entries = try? decoder.decode([String: Lossy].self, from: data) else { return MonitorProfiles() }
        return MonitorProfiles(items: entries.compactMapValues(\.profile))
    }

    private struct Lossy: Decodable {
        let profile: MonitorProfile?
        init(from decoder: Decoder) throws { profile = try? MonitorProfile(from: decoder) }
    }
}

public enum MonitorLight {
    public static func clampedWarmest(_ kelvin: Double) -> Double {
        min(max(kelvin, LightSettings.minKelvin), LightSettings.maxKelvin)
    }

    public static func clampedDimPercent(_ percent: Int) -> Int {
        min(max(percent, 0), EveningDimming.maxDimPercent)
    }

    /// What this monitor shows when the general curve asks for `global`: never warmer than its limit,
    /// neutral when it is left alone.
    public static func kelvin(global: Double, profile: MonitorProfile?) -> Double {
        guard let profile else { return global }
        if profile.untouched { return LightSettings.maxKelvin }
        guard let warmest = profile.warmestK else { return global }
        return max(global, clampedWarmest(warmest))
    }

    /// Brightness factor (1 = no dimming) for this monitor. `kelvin` is the general curve's value, so the
    /// colour limit does not change how much the monitor is dimmed.
    public static func dimFactor(kelvin: Double, settings: LightSettings, globalPercent: Int,
                                 profile: MonitorProfile?) -> Double {
        if profile?.untouched == true { return 1 }
        let percent = clampedDimPercent(profile?.dimPercent ?? globalPercent)
        return EveningDimming.factor(kelvin: kelvin, settings: settings, maxDimPercent: percent)
    }
}
