import Foundation

/// The user's own cycle settings, saved before the rhythm experiment rewrites them.
/// `nil` = the key was not set; restoring removes it again.
public struct RhythmSettingsBackup: Codable, Equatable, Sendable {
    public static let backupKey = "rhythmExperimentBackup"
    public static let cycleMinutesKey = "cycleMinutes"
    public static let shortBreakSecondsKey = "shortBreakSeconds"
    /// Where an undecodable backup is parked (never deleted) when a new start needs the slot.
    public static let corruptKey = "rhythmExperimentBackup.corrupt"

    public var cycleMinutes: Int?
    public var shortBreakSeconds: Int?

    public init(cycleMinutes: Int?, shortBreakSeconds: Int?) {
        self.cycleMinutes = cycleMinutes
        self.shortBreakSeconds = shortBreakSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cycleMinutes = try c.decodeIfPresent(Int.self, forKey: .cycleMinutes)
        shortBreakSeconds = try c.decodeIfPresent(Int.self, forKey: .shortBreakSeconds)
    }

    public static func capture(from d: UserDefaults) -> RhythmSettingsBackup {
        RhythmSettingsBackup(
            cycleMinutes: d.object(forKey: cycleMinutesKey) == nil ? nil : d.integer(forKey: cycleMinutesKey),
            shortBreakSeconds: d.object(forKey: shortBreakSecondsKey) == nil ? nil : d.integer(forKey: shortBreakSecondsKey))
    }

    public static func hasBackup(in d: UserDefaults) -> Bool { d.object(forKey: backupKey) != nil }

    /// The stored backup, or nil when absent or undecodable.
    public static func load(from d: UserDefaults) -> RhythmSettingsBackup? {
        d.data(forKey: backupKey).flatMap { try? JSONDecoder().decode(RhythmSettingsBackup.self, from: $0) }
    }

    public func save(to d: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.backupKey) }
    }

    /// Puts the values back exactly; absent ones are removed.
    public func restore(into d: UserDefaults) {
        Self.put(cycleMinutes, Self.cycleMinutesKey, d)
        Self.put(shortBreakSeconds, Self.shortBreakSecondsKey, d)
    }

    private static func put(_ v: Int?, _ key: String, _ d: UserDefaults) {
        if let v { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
    }

    public enum BeginOutcome: Equatable, Sendable {
        case fresh
        /// A leftover backup was restored first (and cleared) before the new one was taken.
        case restoredLeftover
        /// A leftover backup could not be decoded; it was parked under `corruptKey`, not deleted.
        case parkedCorrupt
    }

    /// Takes the backup for a new experiment without ever overwriting an existing one.
    @discardableResult
    public static func begin(in d: UserDefaults) -> BeginOutcome {
        var outcome = BeginOutcome.fresh
        if hasBackup(in: d) {
            if let old = load(from: d) {
                old.restore(into: d)
                outcome = .restoredLeftover
            } else {
                d.set(d.object(forKey: backupKey), forKey: corruptKey)
                outcome = .parkedCorrupt
            }
            d.removeObject(forKey: backupKey)
        }
        capture(from: d).save(to: d)
        return outcome
    }

    public enum EndOutcome: Equatable, Sendable { case restored, noBackup, undecodableKept }

    /// Restores and clears the backup; an undecodable blob is left in place.
    @discardableResult
    public static func end(in d: UserDefaults) -> EndOutcome {
        guard hasBackup(in: d) else { return .noBackup }
        guard let b = load(from: d) else { return .undecodableKept }
        b.restore(into: d)
        d.removeObject(forKey: backupKey)
        return .restored
    }
}
