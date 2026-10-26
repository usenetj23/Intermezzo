import Foundation

// Sync between the user's Macs through any shared folder (OneDrive, iCloud Drive, Dropbox, SMB).
// Each Mac writes only its own file there and reads the others'; every file carries the full state
// that Mac knows, so merging all of them gives the same result on every Mac. The live SwiftData
// store is never put in the cloud folder: concurrent sync would corrupt it.

/// Which UserDefaults keys travel between Macs. Everything is shared except what only makes sense
/// on one machine: window geometry, permissions, migrations, file paths, daily counters, debug flags.
public enum SyncPolicy {
    private static let localPrefixes = ["NS", "com_apple_", "Apple", "permissionAsked", "sync", "fx",
                                        "screenTime", "last", "legacy", "betterDisplay", "lightMonitors"]
    private static let localKeys: Set<String> = [
        "pomodoroLedger",      // merged separately (see PomodoroLedger.merged)
        "autostart",           // the login item is registered per Mac
        "snoozeBudget",        // today's postpones on this Mac
        "hydrationLog", "naturalBreakLog", "tickProfile", "exerciseLibraryVersion",
        "surfaceThemeGlassRenamed", "imageThemeItems", "breakStartScriptPath", "breakEndScriptPath",
        "lightDisabledUntil",  // a pause on this Mac only
        "awakeMode", "awakeUntil",  // what keeps this Mac awake right now
        "weatherLat", "weatherLon",  // each Mac's own place
    ]

    public static func isSynced(key: String) -> Bool {
        if localKeys.contains(key) { return false }
        if localPrefixes.contains(where: key.hasPrefix) { return false }
        if key.contains("Path") { return false }            // files live at different places per Mac
        return true
    }
}

/// One setting value (any property-list type) with the time it was last changed.
public struct SyncSetting: Codable, Equatable, Sendable {
    /// Binary property list of `[value]`.
    public let data: Data
    public let changedAt: Date

    public init(value: Any, changedAt: Date) throws {
        self.data = try PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0)
        self.changedAt = changedAt
    }

    public var value: Any? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [Any])?.first
    }
}

/// A work-log interval as shared: edits anywhere win by `modifiedAt`, deletions are tombstones.
public struct SyncWork: Codable, Equatable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var active: Double
    public var place: String
    public var isCorrection: Bool
    public var note: String
    public var modifiedAt: Date
    public var deleted: Bool

    public init(id: String, start: Date, end: Date, active: Double = 0, place: String = "office",
                isCorrection: Bool = false, note: String = "", modifiedAt: Date, deleted: Bool = false) {
        self.id = id; self.start = start; self.end = end; self.active = active; self.place = place
        self.isCorrection = isCorrection; self.note = note; self.modifiedAt = modifiedAt; self.deleted = deleted
    }
}

/// A break as shared. Only the Mac that took it (`origin`) ever changes it.
public struct SyncBreak: Codable, Equatable, Sendable {
    public var id: String
    public var origin: String
    public var kind: String
    public var start: Date
    public var end: Date?
    public var wasSkipped: Bool
    public var outcome: String?
    public var postponeMinutes: Int
    public var startedManually: Bool

    public init(id: String, origin: String, kind: String, start: Date, end: Date?, wasSkipped: Bool,
                outcome: String? = nil, postponeMinutes: Int = 0, startedManually: Bool = false) {
        self.id = id; self.origin = origin; self.kind = kind; self.start = start; self.end = end
        self.wasSkipped = wasSkipped; self.outcome = outcome; self.postponeMinutes = postponeMinutes
        self.startedManually = startedManually
    }
}

public struct SyncPomodoro: Codable, Equatable, Sendable {
    public var ledger: Data
    public var changedAt: Date

    public init(ledger: Data, changedAt: Date) {
        self.ledger = ledger
        self.changedAt = changedAt
    }
}

/// The file one Mac writes to the sync folder.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public static let schema = 1

    public var schema = SyncSnapshot.schema
    public var deviceID: String
    public var deviceName: String
    public var writtenAt: Date
    public var settings: [String: SyncSetting]
    public var work: [SyncWork]
    public var breaks: [SyncBreak]
    public var pomodoro: SyncPomodoro?

    public init(deviceID: String, deviceName: String, writtenAt: Date, settings: [String: SyncSetting] = [:],
                work: [SyncWork] = [], breaks: [SyncBreak] = [], pomodoro: SyncPomodoro? = nil) {
        self.deviceID = deviceID; self.deviceName = deviceName; self.writtenAt = writtenAt
        self.settings = settings; self.work = work; self.breaks = breaks; self.pomodoro = pomodoro
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> SyncSnapshot {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try d.decode(SyncSnapshot.self, from: data)
    }
}

public enum SyncMerge {
    /// Newest change per key; equal times settle on the value bytes, so every Mac picks the same.
    public static func settings(_ sources: [[String: SyncSetting]]) -> [String: SyncSetting] {
        var out: [String: SyncSetting] = [:]
        for source in sources {
            for (key, s) in source {
                guard let have = out[key] else { out[key] = s; continue }
                if s.changedAt > have.changedAt
                    || (s.changedAt == have.changedAt && s.data.lexicographicallyPrecedes(have.data)) {
                    out[key] = s
                }
            }
        }
        return out
    }

    /// Newest edit per interval (a deletion is an edit); ties go to the deletion.
    public static func work(_ sources: [[SyncWork]]) -> [SyncWork] {
        var out: [String: SyncWork] = [:]
        for item in sources.joined() {
            guard let have = out[item.id] else { out[item.id] = item; continue }
            if item.modifiedAt > have.modifiedAt || (item.modifiedAt == have.modifiedAt && item.deleted && !have.deleted) {
                out[item.id] = item
            }
        }
        return out.values.sorted { $0.start < $1.start }
    }

    /// One copy per break: the author's own, else a finished one, else any.
    public static func breaks(_ sources: [(deviceID: String, items: [SyncBreak])]) -> [SyncBreak] {
        var out: [String: (SyncBreak, fromAuthor: Bool)] = [:]
        for source in sources {
            for item in source.items {
                let fromAuthor = item.origin == source.deviceID
                guard let have = out[item.id] else { out[item.id] = (item, fromAuthor); continue }
                if (fromAuthor && !have.fromAuthor) || (!have.fromAuthor && have.0.end == nil && item.end != nil) {
                    out[item.id] = (item, fromAuthor)
                }
            }
        }
        return out.values.map(\.0).sorted { $0.start < $1.start }
    }
}

/// Several sync folders at once (e.g. iCloud Drive and OneDrive): every Mac writes its file to
/// each of them, and the newest file of each other Mac wins whichever folder it came from.
public enum SyncFolders {
    /// A readable name for a folder in ~/Library/CloudStorage, or nil when it is not a known cloud.
    public static func cloudTitle(forStorageFolder name: String) -> String? {
        let providers = [("OneDrive", "OneDrive"), ("Dropbox", "Dropbox"), ("GoogleDrive", "Google Drive"), ("Box", "Box")]
        for (prefix, title) in providers {
            guard name == prefix || name.hasPrefix(prefix + "-") else { continue }
            let account = name.dropFirst(prefix.count).drop { $0 == "-" }
            return account.isEmpty || account == prefix ? title : "\(title) (\(account))"
        }
        return nil
    }

    /// The folder list, migrated from the single folder of earlier versions; no empties, no repeats.
    public static func paths(list: [String]?, legacy: String?) -> [String] {
        var seen = Set<String>()
        return (list ?? [legacy ?? ""]).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func newestPerDevice(_ snapshots: [SyncSnapshot]) -> [SyncSnapshot] {
        var best: [String: SyncSnapshot] = [:]
        for s in snapshots where (best[s.deviceID]?.writtenAt ?? .distantPast) < s.writtenAt || best[s.deviceID] == nil {
            best[s.deviceID] = s
        }
        return Array(best.values)
    }
}
