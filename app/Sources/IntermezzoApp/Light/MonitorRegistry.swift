import AppKit
import IntermezzoKit

enum MonitorKeys {
    /// This Mac only (the "lightMonitors" prefix is local in SyncPolicy): the displays belong to the machine.
    static let profiles = "lightMonitors"
}

/// The connected monitors of one kind (identical models are one group).
struct MonitorGroup: Identifiable, Equatable {
    let key: MonitorKey
    let name: String
    let displayIDs: [CGDirectDisplayID]
    var id: String { key.id }
    var count: Int { displayIDs.count }
}

/// Which monitors are connected and what the user set for each kind of monitor. The settings are kept
/// per model, so they come back by themselves when the same monitors are plugged in again.
@MainActor
final class MonitorRegistry: ObservableObject {
    static let shared = MonitorRegistry()

    @Published private(set) var groups: [MonitorGroup] = []
    @Published private(set) var profiles: MonitorProfiles

    private let defaults = UserDefaults.standard
    /// `lastSeen` is refreshed at most this often: every write wakes all UserDefaults observers.
    private static let seenRefresh: TimeInterval = 24 * 3600

    private init() {
        profiles = MonitorProfiles.decode(UserDefaults.standard.data(forKey: MonitorKeys.profiles))
    }

    // MARK: Reading the displays

    private func activeDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName ?? "#\(id)"
    }

    /// Looks at the connected displays: virtual ones (no real model) and mirrors get no row and keep the
    /// general curve. A monitor met for the first time starts with no settings of its own.
    func refresh() {
        var order: [MonitorKey] = []
        var byKey: [MonitorKey: (name: String, ids: [CGDirectDisplayID])] = [:]
        for id in activeDisplays() where CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay {
            let key = MonitorKey(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id))
            guard key.isIdentifiable else { continue }
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = (name(of: id), [id])
            } else {
                byKey[key]?.ids.append(id)
            }
        }
        let next = order.compactMap { key in byKey[key].map { MonitorGroup(key: key, name: $0.name, displayIDs: $0.ids) } }
        if next != groups { groups = next }
        remember(next)
    }

    /// Writes only when something is new or stale.
    private func remember(_ connected: [MonitorGroup]) {
        let now = Date()
        var updated = profiles
        for group in connected {
            if var profile = updated.profile(for: group.key) {
                guard profile.name != group.name || now.timeIntervalSince(profile.lastSeen) > Self.seenRefresh else { continue }
                profile.name = group.name
                profile.lastSeen = now
                updated = updated.setting(profile, for: group.key)
            } else {
                updated = updated.setting(MonitorProfile(name: group.name, lastSeen: now), for: group.key)
            }
        }
        save(updated)
    }

    private func save(_ next: MonitorProfiles) {
        guard next != profiles else { return }
        profiles = next
        defaults.set(next.encoded(), forKey: MonitorKeys.profiles)
    }

    // MARK: Lookup

    private func key(ofDisplay id: CGDirectDisplayID) -> MonitorKey? {
        groups.first { $0.displayIDs.contains(id) }?.key
    }

    func profile(forDisplay id: CGDirectDisplayID) -> MonitorProfile? {
        key(ofDisplay: id).flatMap { profiles.profile(for: $0) }
    }

    /// Displays that are left alone (no colour change, no dimming).
    var untouchedDisplays: Set<UInt32> {
        Set(groups.filter { profiles.profile(for: $0.key)?.untouched == true }.flatMap { $0.displayIDs })
    }

    /// Remembered monitors that are not connected now, the most recently seen first.
    var rememberedOffline: [(key: MonitorKey, profile: MonitorProfile)] {
        let connected = Set(groups.map(\.key))
        return profiles.items
            .compactMap { id, profile in MonitorKey(id: id).map { (key: $0, profile: profile) } }
            .filter { !connected.contains($0.key) }
            .sorted { $0.profile.lastSeen > $1.profile.lastSeen }
    }

    // MARK: Changes

    /// Applies `change` to the monitor's profile, keeps its values in range and lets the light follow at once.
    func update(_ key: MonitorKey, _ change: (inout MonitorProfile) -> Void) {
        var profile = profiles.profile(for: key) ?? MonitorProfile(name: groups.first { $0.key == key }?.name ?? "", lastSeen: Date())
        change(&profile)
        profile.warmestK = profile.warmestK.map(MonitorLight.clampedWarmest)
        profile.dimPercent = profile.dimPercent.map(MonitorLight.clampedDimPercent)
        save(profiles.setting(profile, for: key))
        LightController.shared.monitorSettingsChanged()
    }

    /// Back to the general curve; "leave alone" is a separate choice and stays.
    func resetOverrides(_ key: MonitorKey) {
        update(key) {
            $0.warmestK = nil
            $0.dimPercent = nil
        }
    }

    func forget(_ key: MonitorKey) {
        save(profiles.removing(key))
    }
}
