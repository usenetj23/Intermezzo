import Foundation
import IntermezzoKit
import SwiftData

/// One stored presence interval (see `WorkInterval`).
@Model
final class WorkSessionRecord {
    var start: Date
    var end: Date
    var activeSeconds: Double
    /// `WorkPlace.rawValue`.
    var placeRaw: String = WorkPlace.office.rawValue
    /// Added by hand, or a recorded interval edited by hand.
    var isCorrection: Bool = false
    var note: String = ""
    /// Stable id across Macs (filled on the first sync).
    var syncID: String = ""
    /// Last change anywhere, so the newest edit wins when Macs sync.
    var modifiedAt: Date = Date.distantPast

    init(start: Date, end: Date, activeSeconds: Double, place: WorkPlace = .office) {
        self.start = start
        self.end = end
        self.activeSeconds = activeSeconds
        self.placeRaw = place.rawValue
        self.syncID = UUID().uuidString
        self.modifiedAt = Date()
    }

    var place: WorkPlace {
        get { WorkPlace(rawValue: placeRaw) ?? .office }
        set { placeRaw = newValue.rawValue }
    }

    var interval: WorkInterval {
        WorkInterval(start: start, end: end, activeSeconds: activeSeconds, place: place,
                     isCorrection: isCorrection, note: note)
    }
}

/// Work-time register: turns heartbeat activity in the work zone into stored intervals and
/// day summaries with overtime against the working hours from General.
@MainActor
final class WorkLogController: ObservableObject {
    static let shared = WorkLogController()

    @Published private(set) var zone = WorkZoneProbe.Reading()
    /// Bumped when stored intervals change, so the pane re-reads them.
    @Published private(set) var revision = 0

    private let probe = WorkZoneProbe()
    private let context = ModelContext(Store.container)
    private var tracker = WorkSessionTracker()
    private var openRecord: WorkSessionRecord?
    private var lastObserved = Date.distantPast
    private var lastSaved = Date.distantPast
    private var resumed = false

    private static let observeInterval: TimeInterval = 15
    private static let saveInterval: TimeInterval = 60

    var isEnabled: Bool { UserDefaults.standard.integer(forKey: WorkLogKeys.enabled) != 0 }

    /// Called every heartbeat; does real work every 15 s only.
    func tick(now: Date, secondsSinceInput: TimeInterval) {
        guard isEnabled else {
            if tracker.current != nil { finish() }
            return
        }
        guard now.timeIntervalSince(lastObserved) >= Self.observeInterval else { return }
        lastObserved = now
        if !resumed { resume(now: now) }
        probe.poll(now: now)
        if probe.reading != zone { zone = probe.reading }

        let closed = tracker.observe(now: now, lastInputAt: now.addingTimeInterval(-secondsSinceInput),
                                     place: zone.place ?? WorkDetector.shared.presencePlace)
        if let closed {
            write(closed, into: openRecord)
            openRecord = nil
            save(now: now)
        }
        if let current = tracker.current {
            if openRecord == nil {
                let record = WorkSessionRecord(start: current.start, end: current.end,
                                               activeSeconds: current.activeSeconds, place: current.place)
                context.insert(record)
                openRecord = record
                UserDefaults.standard.set(record.syncID, forKey: Self.ownOpenKey)
                Trace.log("work log: interval started at \(current.start)")
                save(now: now)
            } else if now.timeIntervalSince(lastSaved) >= Self.saveInterval {
                write(current, into: openRecord)
                save(now: now)
            }
        }
    }

    /// Quit or register switched off: store the open interval as it stands.
    func finish() {
        if let current = tracker.close() { write(current, into: openRecord) }
        openRecord = nil
        save(now: Date())
    }

    func settingsChanged() {
        probe.invalidate()
        lastObserved = .distantPast
    }

    // MARK: Reading

    func intervals(from start: Date, to end: Date) -> [WorkInterval] {
        let descriptor = FetchDescriptor<WorkSessionRecord>(
            predicate: #Predicate { $0.end > start && $0.start < end },
            sortBy: [SortDescriptor(\.start)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.interval)
    }

    // MARK: Corrections

    /// Stored intervals touching `day`, oldest first (for the day editor).
    func records(on day: Date, calendar: Calendar = .current) -> [WorkSessionRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<WorkSessionRecord>(
            predicate: #Predicate { $0.end > start && $0.start < end },
            sortBy: [SortDescriptor(\.start)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The interval being recorded right now cannot be edited: the tracker would overwrite it.
    func isLive(_ record: WorkSessionRecord) -> Bool { record === openRecord }

    func addCorrection(start: Date, end: Date, place: WorkPlace, note: String) {
        guard end > start else { return }
        let record = WorkSessionRecord(start: start, end: end, activeSeconds: 0, place: place)
        record.isCorrection = true
        record.note = note
        context.insert(record)
        Trace.log("work log: manual interval added \(start) – \(end) (\(place.rawValue))")
        save(now: Date())
    }

    func update(_ record: WorkSessionRecord, start: Date, end: Date, place: WorkPlace, note: String) {
        guard !isLive(record), end > start else { return }
        let changedTime = record.start != start || record.end != end || record.place != place
        record.start = start
        record.end = end
        record.place = place
        record.note = note
        record.modifiedAt = Date()
        if changedTime { record.isCorrection = true }
        Trace.log("work log: interval edited to \(start) – \(end) (\(place.rawValue))")
        save(now: Date())
    }

    func delete(_ record: WorkSessionRecord) {
        guard !isLive(record) else { return }
        Trace.log("work log: interval deleted \(record.start) – \(record.end)")
        SyncTombstones.add(record.syncID)
        context.delete(record)
        save(now: Date())
    }

    func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [WorkDaySummary] {
        WorkLog.summarize(intervals(from: start, to: end), schedule: Self.schedule(), calendar: calendar)
            .filter { $0.day >= calendar.startOfDay(for: start) && $0.day < end }
    }

    /// Working hours and days as set in General (per-day hours included).
    static func schedule() -> WorkSchedule {
        let d = UserDefaults.standard
        let general = WeekHours.Window(start: d.integer(forKey: Keys.workStartMinutes),
                                       end: d.integer(forKey: Keys.workEndMinutes))
        return WorkSchedule(daysMask: d.integer(forKey: Keys.workDaysMask), hours: general,
                            perDay: d.integer(forKey: "perDayHours") != 0 ? WeekHours.decode(d.data(forKey: "weekHours")) : nil)
    }

    // MARK: Private

    /// The interval this Mac was recording, so a relaunch resumes it and never one synced from another Mac.
    private static let ownOpenKey = "syncOwnOpenWork"

    /// After a relaunch, keep extending this Mac's last interval if it ended within the bridge.
    private func resume(now: Date) {
        resumed = true
        guard let id = UserDefaults.standard.string(forKey: Self.ownOpenKey) else { return }
        var descriptor = FetchDescriptor<WorkSessionRecord>(predicate: #Predicate { $0.syncID == id })
        descriptor.fetchLimit = 1
        // A hand-made entry is never extended by the tracker.
        guard let last = try? context.fetch(descriptor).first, !last.isCorrection,
              now.timeIntervalSince(last.end) <= tracker.bridge else { return }
        tracker = WorkSessionTracker(resuming: last.interval)
        openRecord = last
        Trace.log("work log: resumed interval from \(last.start)")
    }

    private func write(_ interval: WorkInterval, into record: WorkSessionRecord?) {
        guard let record else {
            context.insert(WorkSessionRecord(start: interval.start, end: interval.end,
                                             activeSeconds: interval.activeSeconds, place: interval.place))
            return
        }
        record.end = interval.end
        record.activeSeconds = interval.activeSeconds
        record.modifiedAt = Date()
    }

    // MARK: Sync

    /// Every stored interval plus deletions, for this Mac's sync file.
    func syncItems() -> [SyncWork] {
        let all = (try? context.fetch(FetchDescriptor<WorkSessionRecord>())) ?? []
        for r in all where r.syncID.isEmpty { r.syncID = UUID().uuidString }
        for r in all where r.modifiedAt == .distantPast { r.modifiedAt = r.end }
        if context.hasChanges { try? context.save() }
        let alive = all.map {
            SyncWork(id: $0.syncID, start: $0.start, end: $0.end, active: $0.activeSeconds, place: $0.placeRaw,
                     isCorrection: $0.isCorrection, note: $0.note, modifiedAt: $0.modifiedAt)
        }
        let gone = SyncTombstones.all().map {
            SyncWork(id: $0.key, start: $0.value, end: $0.value, modifiedAt: $0.value, deleted: true)
        }
        return alive + gone
    }

    /// Takes in the merged intervals; the one being recorded here is left alone. Returns whether anything changed.
    @discardableResult
    func applySynced(_ items: [SyncWork]) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<WorkSessionRecord>())) ?? []
        var byID = Dictionary(all.map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })
        let tombstones = SyncTombstones.all()
        var changed = false
        for item in items {
            if let local = byID[item.id] {
                guard !isLive(local), item.modifiedAt > local.modifiedAt else { continue }
                if item.deleted {
                    context.delete(local)
                    byID[item.id] = nil
                    SyncTombstones.add(item.id, at: item.modifiedAt)
                } else {
                    local.start = item.start; local.end = item.end; local.activeSeconds = item.active
                    local.placeRaw = item.place; local.isCorrection = item.isCorrection; local.note = item.note
                    local.modifiedAt = item.modifiedAt
                }
                changed = true
            } else if !item.deleted, (tombstones[item.id] ?? .distantPast) < item.modifiedAt {
                let r = WorkSessionRecord(start: item.start, end: item.end, activeSeconds: item.active)
                r.syncID = item.id; r.placeRaw = item.place; r.isCorrection = item.isCorrection
                r.note = item.note; r.modifiedAt = item.modifiedAt
                context.insert(r)
                byID[item.id] = r
                changed = true
            } else if item.deleted, tombstones[item.id] == nil {
                SyncTombstones.add(item.id, at: item.modifiedAt)
            }
        }
        if changed { save(now: Date()) }
        return changed
    }

    private func save(now: Date) {
        lastSaved = now
        do {
            try context.save()
            revision += 1
        } catch {
            Trace.log("work log: save failed: \(error)")
        }
    }
}
