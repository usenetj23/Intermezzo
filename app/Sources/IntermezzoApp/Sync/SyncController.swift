import Foundation
import IntermezzoKit
import SwiftData

/// Local-only sync keys (the `sync` prefix keeps them out of the shared settings).
enum SyncKeys {
    static let enabled = "syncEnabled"
    /// The single folder of earlier versions; read once into `folderPaths`.
    static let folderPath = "syncFolderPath"
    /// All sync folders ([String]); every one gets this Mac's file.
    static let folderPaths = "syncFolderPaths"
    static let deviceID = "syncDeviceID"
    static let deviceName = "syncDeviceName"
    static let scopeWork = "syncScopeWork"
    static let scopeBreaks = "syncScopeBreaks"
    static let scopeSettings = "syncScopeSettings"
    static let scopePomodoro = "syncScopePomodoro"
    /// JSON [key: Date] — when each tracked setting last changed on this Mac (or was taken from another).
    static let stamps = "syncStamps"
    /// Binary plist [key: Data] — values as last seen, to notice changes.
    static let baseline = "syncBaseline"
    static let tombstones = "syncWorkTombstones"
}

enum SyncIdentity {
    /// Random per Mac, made once.
    static var deviceID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: SyncKeys.deviceID), !id.isEmpty { return id }
        let id = UUID().uuidString
        d.set(id, forKey: SyncKeys.deviceID)
        return id
    }

    static var deviceName: String {
        let custom = UserDefaults.standard.string(forKey: SyncKeys.deviceName) ?? ""
        return custom.isEmpty ? (Host.current().localizedName ?? "Mac") : custom
    }
}

/// Deleted work-log intervals, so a deletion travels to the other Macs instead of being re-added.
enum SyncTombstones {
    private static let keep: TimeInterval = 180 * 86400

    static func all() -> [String: Date] {
        let d = UserDefaults.standard.data(forKey: SyncKeys.tombstones)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return d.flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
    }

    static func add(_ id: String, at date: Date = Date()) {
        guard !id.isEmpty else { return }
        var list = all().filter { Date().timeIntervalSince($0.value) < keep }
        list[id] = max(list[id] ?? .distantPast, date)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        UserDefaults.standard.set(try? encoder.encode(list), forKey: SyncKeys.tombstones)
    }
}

/// Keeps this Mac in step with the others through a shared folder (see IntermezzoKit/Sync.swift).
@MainActor
final class SyncController: ObservableObject {
    static let shared = SyncController()

    struct Peer: Identifiable, Equatable {
        let id: String
        let name: String
        let writtenAt: Date
    }

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private let defaults = UserDefaults.standard
    private let context = ModelContext(Store.container)
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var observer: NSObjectProtocol?
    /// Last content written, per sync folder (a newly added folder gets written even if nothing changed).
    private var lastWritten: [String: Data] = [:]

    private static let period: TimeInterval = 5 * 60
    private static let afterChange: TimeInterval = 20
    /// Change-driven rounds are at least this far apart (a burst of edits makes one upload).
    private static let minChangeGap: TimeInterval = 60
    private var lastChangeSync = Date.distantPast

    var isEnabled: Bool { defaults.integer(forKey: SyncKeys.enabled) != 0 && !folders.isEmpty }

    var folders: [URL] {
        SyncFolders.paths(list: defaults.stringArray(forKey: SyncKeys.folderPaths),
                          legacy: defaults.string(forKey: SyncKeys.folderPath))
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// The subfolder the app writes into inside a chosen cloud folder.
    static let subfolder = "Intermezzo Sync"

    static func syncDir(in folder: URL) -> URL {
        folder.appendingPathComponent(subfolder, isDirectory: true)
    }

    private func scope(_ key: String) -> Bool { defaults.object(forKey: key) == nil || defaults.integer(forKey: key) != 0 }

    /// Called once at launch.
    func start() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localChange() }
        }
        let t = Timer(timeInterval: Self.period, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        timer = t
        schedule(after: 10)
    }

    func syncNow() {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        let me = SyncIdentity.deviceID
        let dirs = folders.map(Self.syncDir(in:))
        Task.detached(priority: .utility) {
            let reads = dirs.map { (dir: $0, result: Self.readPeers(in: $0, excluding: me)) }
            await MainActor.run { self.finish(reads) }
        }
    }

    // MARK: Merge

    private func finish(_ reads: [(dir: URL, result: Result<[SyncSnapshot], Error>)]) {
        defer { isSyncing = false }
        var remotes: [SyncSnapshot] = []
        var readable: [URL] = []
        var errors: [String] = []
        for read in reads {
            switch read.result {
            case .success(let snaps):
                remotes += snaps
                readable.append(read.dir)
            case .failure(let error):
                errors.append("\(read.dir.deletingLastPathComponent().lastPathComponent): \(error.localizedDescription)")
                Trace.log("sync: cannot read \(read.dir.path): \(error.localizedDescription)")
            }
        }
        guard !readable.isEmpty else {
            lastError = errors.joined(separator: "\n")
            return
        }
        let newest = SyncFolders.newestPerDevice(remotes)
        peers = newest.map { Peer(id: $0.deviceID, name: $0.deviceName, writtenAt: $0.writtenAt) }
            .sorted { $0.name < $1.name }
        merge(newest)
        for dir in readable { write(to: dir) }
        if !errors.isEmpty { lastError = errors.joined(separator: "\n") }
    }

    private func merge(_ remotes: [SyncSnapshot]) {
        refreshStamps(firstRunAdopts: !remotes.isEmpty)
        if scope(SyncKeys.scopeSettings) { applySettings(SyncMerge.settings(remotes.map(\.settings))) }
        if scope(SyncKeys.scopeWork) {
            let merged = SyncMerge.work([WorkLogController.shared.syncItems()] + remotes.map(\.work))
            if WorkLogController.shared.applySynced(merged) { Trace.log("sync: work log updated") }
        }
        if scope(SyncKeys.scopeBreaks) {
            let me = SyncIdentity.deviceID
            let merged = SyncMerge.breaks([(me, localBreaks())] + remotes.map { ($0.deviceID, $0.breaks) })
            applyBreaks(merged)
        }
        if scope(SyncKeys.scopePomodoro) { applyPomodoro(remotes.compactMap(\.pomodoro)) }
    }

    // MARK: Settings

    /// UserDefaults changes all the time (screen-time counter, our own stamps), so one check is
    /// scheduled at most every 20 s, and it syncs only when a tracked setting really changed.
    /// Nothing is stamped before the first sync: a Mac joining a folder must adopt, not override.
    private func localChange() {
        guard isEnabled, pending == nil, defaults.data(forKey: SyncKeys.baseline) != nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = nil
                let changed = self.refreshStamps(firstRunAdopts: false)
                // A running pomodoro rewrites its activity every 15 s; that alone waits for the regular
                // round instead of uploading a file to every cloud folder every 20 s.
                guard !changed.isEmpty, changed != [PomodoroKeys.ledger] else { return }
                if Date().timeIntervalSince(self.lastChangeSync) < Self.minChangeGap {
                    self.schedule(after: Self.minChangeGap)
                    return
                }
                self.lastChangeSync = Date()
                self.syncNow()
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterChange, execute: item)
    }

    private func schedule(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { self?.syncNow() }
        }
    }

    private var trackedValues: [String: Any] {
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.automit.Intermezzo") ?? [:]
        return domain.filter { SyncPolicy.isSynced(key: $0.key) || $0.key == PomodoroKeys.ledger }
    }

    /// Stamps every tracked setting whose value changed since last seen. The very first time a Mac
    /// joins a folder that already holds other Macs, its values are stamped as old, so it adopts theirs.
    /// Returns the tracked settings that changed.
    @discardableResult
    private func refreshStamps(firstRunAdopts: Bool) -> Set<String> {
        let firstRun = defaults.data(forKey: SyncKeys.baseline) == nil
        var baseline = loadBaseline()
        var stamps = loadStamps()
        let now = Date()
        var changed = Set<String>()
        for (key, value) in trackedValues {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0),
                  baseline[key] != data else { continue }
            baseline[key] = data
            stamps[key] = firstRun && firstRunAdopts ? .distantPast : now
            changed.insert(key)
        }
        guard !changed.isEmpty || firstRun else { return [] }
        saveBaseline(baseline)
        saveStamps(stamps)
        return changed
    }

    private func localSettings() -> [String: SyncSetting] {
        let stamps = loadStamps()
        var out: [String: SyncSetting] = [:]
        for (key, value) in trackedValues where key != PomodoroKeys.ledger {
            out[key] = try? SyncSetting(value: value, changedAt: stamps[key] ?? .distantPast)
        }
        return out
    }

    private func applySettings(_ remote: [String: SyncSetting]) {
        var stamps = loadStamps()
        var baseline = loadBaseline()
        var applied: [String] = []
        for (key, setting) in remote where SyncPolicy.isSynced(key: key) {
            guard setting.changedAt > (stamps[key] ?? .distantPast), let value = setting.value else { continue }
            // Baseline first: the didChange notification must not stamp this as a local edit.
            baseline[key] = setting.data
            stamps[key] = setting.changedAt
            defaults.set(value, forKey: key)
            applied.append(key)
        }
        saveBaseline(baseline)
        saveStamps(stamps)
        if !applied.isEmpty { Trace.log("sync: \(applied.count) setting(s) taken from another Mac: \(applied.sorted().joined(separator: ", "))") }
    }

    // MARK: Breaks

    private func localBreaks() -> [SyncBreak] {
        let all = (try? context.fetch(FetchDescriptor<BreakRecord>())) ?? []
        let me = SyncIdentity.deviceID
        for r in all where r.syncID.isEmpty { r.syncID = UUID().uuidString }
        for r in all where r.origin.isEmpty { r.origin = me }
        if context.hasChanges { try? context.save() }
        return all.map {
            SyncBreak(id: $0.syncID, origin: $0.origin, kind: $0.kindRaw, start: $0.startedAt, end: $0.endedAt,
                      wasSkipped: $0.wasSkipped, outcome: $0.outcomeRaw, postponeMinutes: $0.postponeMinutes,
                      startedManually: $0.startedManually)
        }
    }

    /// Other Macs' breaks in, updated from their author; this Mac's own records are never touched.
    private func applyBreaks(_ merged: [SyncBreak]) {
        let me = SyncIdentity.deviceID
        let all = (try? context.fetch(FetchDescriptor<BreakRecord>())) ?? []
        let byID = Dictionary(all.map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })
        var added = 0
        for item in merged where item.origin != me {
            let r: BreakRecord
            if let existing = byID[item.id] { r = existing } else {
                r = BreakRecord(kind: BreakKind(rawValue: item.kind) ?? .short, startedAt: item.start)
                r.syncID = item.id
                context.insert(r)
                added += 1
            }
            r.kindRaw = item.kind; r.startedAt = item.start; r.endedAt = item.end; r.wasSkipped = item.wasSkipped
            r.outcomeRaw = item.outcome; r.postponeMinutes = item.postponeMinutes
            r.startedManually = item.startedManually; r.origin = item.origin
        }
        if context.hasChanges { try? context.save() }
        if added > 0 { Trace.log("sync: \(added) break(s) from other Macs") }
    }

    // MARK: Pomodoro

    private func applyPomodoro(_ remotes: [SyncPomodoro]) {
        let controller = PomodoroController.shared
        var planStamp = loadStamps()[PomodoroKeys.ledger] ?? .distantPast
        var ledger = controller.ledger
        for remote in remotes {
            guard let other = try? JSONDecoder().decode(PomodoroLedger.self, from: remote.ledger) else { continue }
            let newer = remote.changedAt > planStamp
            ledger = ledger.merged(with: other, otherIsNewer: newer)
            if newer { planStamp = remote.changedAt }
        }
        guard ledger != controller.ledger else { return }
        controller.adoptSynced(ledger)
        // Record the adopted plan under the time it was made, not now, so Macs do not ping-pong.
        var stamps = loadStamps(); stamps[PomodoroKeys.ledger] = planStamp; saveStamps(stamps)
        var baseline = loadBaseline()
        if let value = defaults.object(forKey: PomodoroKeys.ledger),
           let data = try? PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0) {
            baseline[PomodoroKeys.ledger] = data
        }
        saveBaseline(baseline)
        Trace.log("sync: pomodoro ledger merged")
    }

    // MARK: Files

    private func write(to dir: URL) {
        let me = SyncIdentity.deviceID
        var snapshot = SyncSnapshot(deviceID: me, deviceName: SyncIdentity.deviceName, writtenAt: .distantPast)
        if scope(SyncKeys.scopeSettings) { snapshot.settings = localSettings() }
        if scope(SyncKeys.scopeWork) { snapshot.work = WorkLogController.shared.syncItems() }
        if scope(SyncKeys.scopeBreaks) { snapshot.breaks = localBreaks() }
        if scope(SyncKeys.scopePomodoro), let data = defaults.data(forKey: PomodoroKeys.ledger) {
            snapshot.pomodoro = SyncPomodoro(ledger: data, changedAt: loadStamps()[PomodoroKeys.ledger] ?? .distantPast)
        }
        // Skip the write (and the cloud upload) when nothing but the clock would change.
        guard let content = try? snapshot.encoded(), content != lastWritten[dir.path] else {
            lastSync = Date(); lastError = nil
            return
        }
        snapshot.writtenAt = Date()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try snapshot.encoded().write(to: dir.appendingPathComponent("\(me).json"), options: .atomic)
            lastWritten[dir.path] = content
            lastSync = Date(); lastError = nil
            Trace.log("sync: wrote \(snapshot.work.count) work, \(snapshot.breaks.count) breaks, \(snapshot.settings.count) settings")
        } catch {
            lastError = error.localizedDescription
            Trace.log("sync: write failed: \(error.localizedDescription)")
        }
    }

    /// Other Macs' files. iCloud Drive may hold only a placeholder (".name.json.icloud"): ask for the
    /// download and pick the file up at the next round.
    nonisolated private static func readPeers(in dir: URL, excluding me: String) -> Result<[SyncSnapshot], Error> {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let names = try fm.contentsOfDirectory(atPath: dir.path)
            var out: [SyncSnapshot] = []
            for name in names {
                if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                    let real = String(name.dropFirst().dropLast(".icloud".count))
                    try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(real))
                    continue
                }
                guard name.hasSuffix(".json"), name != "\(me).json",
                      let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                      let snap = try? SyncSnapshot.decode(data), snap.schema <= SyncSnapshot.schema else { continue }
                out.append(snap)
            }
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    // MARK: Storage helpers

    private func loadStamps() -> [String: Date] {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return defaults.data(forKey: SyncKeys.stamps).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
    }

    private func saveStamps(_ stamps: [String: Date]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        defaults.set(try? encoder.encode(stamps), forKey: SyncKeys.stamps)
    }

    private func loadBaseline() -> [String: Data] {
        guard let data = defaults.data(forKey: SyncKeys.baseline),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Data] else { return [:] }
        return dict
    }

    private func saveBaseline(_ baseline: [String: Data]) {
        defaults.set(try? PropertyListSerialization.data(fromPropertyList: baseline, format: .binary, options: 0),
                     forKey: SyncKeys.baseline)
    }
}
