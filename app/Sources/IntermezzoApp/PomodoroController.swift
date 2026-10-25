import AppKit
import CoreGraphics
import Foundation
import IntermezzoKit
import SwiftUI

enum PomodoroKeys {
    static let enabled = "pomodoroMode"
    static let ledger = "pomodoroLedger"
    static let activeTask = "pomodoroActiveTask"
    static let dailyGoal = "pomodoroDailyGoal"
    static let rhythmExperiment = "rhythmExperiment"
    static let rhythmExperimentBackup = RhythmSettingsBackup.backupKey
    static let cycleMinutes = RhythmSettingsBackup.cycleMinutesKey
    static let shortBreakSeconds = RhythmSettingsBackup.shortBreakSecondsKey
}



/// Owns the Pomodoro plan/history (`PomodoroLedger`) and keeps it in step with
/// the break engine: a pomodoro is the work period before a break. It is
/// completed when the break starts and voided when the cycle is reset.
@MainActor
final class PomodoroController: ObservableObject {
    static let shared = PomodoroController()

    @Published private(set) var ledger: PomodoroLedger
    @Published private(set) var activeTaskID: UUID?
    @Published private(set) var rhythm: RhythmExperiment?

    // Rhythm experiment bookkeeping (memory only): the day whose arm was applied,
    // the arm applied, and whether the user took over that day.
    private var rhythmAppliedDay: Date?
    private var rhythmAppliedArm: RhythmArm?

    private let defaults: UserDefaults
    private let calendar = Calendar.current

    // Focus signals gathered between ledger writes.
    private var pendingSwitches = 0
    private var pendingActive = 0
    private var lastSample: Date?
    private var lastFlush = Date()
    private var activationObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = PomodoroLedger.load(defaults.data(forKey: PomodoroKeys.ledger), parkingCorruptIn: defaults)
        ledger = loaded.ledger
        switch loaded.outcome {
        case .parkedCorrupt:
            Trace.log("pomodoro: stored ledger undecodable, raw bytes kept under \(PomodoroLedger.corruptKey)")
        case .corruptSlotTaken:
            Trace.log("pomodoro: stored ledger undecodable, \(PomodoroLedger.corruptKey) already holds an earlier copy (kept)")
        case .loaded, .empty:
            break
        }
        activeTaskID = defaults.string(forKey: PomodoroKeys.activeTask).flatMap(UUID.init(uuidString:))
        rhythm = defaults.data(forKey: PomodoroKeys.rhythmExperiment)
            .flatMap { try? JSONDecoder().decode(RhythmExperiment.self, from: $0) }
        // Counting frontmost-app changes needs no permission (names are never stored).
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { if self?.ledger.current != nil { self?.pendingSwitches += 1 } }
        }
    }

    var isEnabled: Bool { defaults.integer(forKey: PomodoroKeys.enabled) != 0 }

    var dailyGoal: Int {
        let stored = defaults.integer(forKey: PomodoroKeys.dailyGoal)
        return stored > 0 ? stored : 8
    }

    /// Task the next pomodoro is for: the chosen one while it is still open,
    /// otherwise the first open task of the plan.
    var currentTask: PomodoroTask? {
        if let id = activeTaskID, let t = ledger.tasks.first(where: { $0.id == id && !$0.isFinished }) { return t }
        return ledger.tasks.first { !$0.isFinished }
    }

    // MARK: - Plan

    func addTask(title: String, estimate: Int, project: String = "") {
        apply(ledger.addingTask(title: title, estimate: estimate, project: project))
    }

    func removeTask(_ id: UUID) {
        apply(ledger.removingTask(id))
        if activeTaskID == id { select(nil) }
    }

    func finishTask(_ id: UUID) { apply(ledger.finishingTask(id)) }

    /// Gives a project-less task an active project (sensor suggestion accepted).
    func assignProject(_ name: String, toTask id: UUID) { apply(ledger.assigningProject(name, toTask: id)) }

    func select(_ id: UUID?) {
        activeTaskID = id
        defaults.set(id?.uuidString, forKey: PomodoroKeys.activeTask)
    }

    // MARK: - Projects

    /// Active (not archived) projects, sorted by name.
    var projects: [PomodoroProject] { ledger.activeProjects }

    func upsertProject(_ project: PomodoroProject) { apply(ledger.upsertingProject(project)) }

    /// Creates the project or restores an archived one; returns the name to select (nil for blank).
    func createOrRestoreProject(named name: String) -> String? {
        guard let r = ledger.creatingOrRestoringProject(named: name) else { return nil }
        apply(r.ledger)
        return r.name
    }

    /// `false` when the name is blank or already used by another project.
    @discardableResult
    func renameProject(id: UUID, to name: String) -> Bool {
        guard let renamed = ledger.renamingProject(id: id, to: name) else { return false }
        apply(renamed)
        return true
    }

    /// The project's own colour; the accent colour for no/unknown project.
    func color(forProject name: String) -> Color {
        guard let p = ledger.project(named: name), let c = ColorHex.components(p.colorHex) else { return .accentColor }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b)
    }

    // MARK: - Engine sync

    func recordInterruption(_ kind: PomodoroInterruption) { apply(ledger.recordingInterruption(kind)) }

    func complete(at date: Date) {
        guard isEnabled else { return }
        flushSignals()
        apply(ledger.completing(at: date))
    }

    func abandon(at date: Date) {
        pendingSwitches = 0
        pendingActive = 0
        apply(ledger.voiding(at: date))
    }

    /// Called every UI tick: starts a pomodoro when work begins, drops a
    /// running one when the mode is switched off.
    func reconcile(isWorking: Bool, minutes: Int, now: Date) {
        if rhythm != nil { tickRhythm(isWorking: isWorking, now: now) }
        if !isEnabled {
            if ledger.current != nil { apply(ledger.voiding(at: now)) }
            return
        }
        if isWorking && ledger.current == nil {
            apply(ledger.starting(taskID: currentTask?.id, minutes: minutes, at: now))
            FocusShortcuts.fire(.sessionStart)
            if ProjectSensors.isEnabled { ProjectSensors.suggestForSessionStart(controller: self) }
        }
        sampleActivity(isWorking: isWorking, now: now)
    }

    /// Counts the seconds the user was actually at the keyboard/mouse while a
    /// pomodoro runs; written to the ledger every 15 s.
    private func sampleActivity(isWorking: Bool, now: Date) {
        defer { lastSample = now }
        guard isWorking, ledger.current != nil, let last = lastSample else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
        if idle < 5 { pendingActive += Int(min(2, max(0, now.timeIntervalSince(last))).rounded()) }
        if now.timeIntervalSince(lastFlush) >= 15 { flushSignals(now: now) }
    }

    private func flushSignals(now: Date = Date()) {
        lastFlush = now
        guard pendingSwitches > 0 || pendingActive > 0 else { return }
        apply(ledger.recordingActivity(appSwitches: pendingSwitches, activeSeconds: pendingActive))
        pendingSwitches = 0
        pendingActive = 0
    }

    // MARK: - Statistics for the UI

    func completedToday(now: Date = Date()) -> Int { ledger.completedCount(on: now, calendar: calendar) }
    func voidedToday(now: Date = Date()) -> Int { ledger.voidedCount(on: now, calendar: calendar) }
    func interruptionsToday(now: Date = Date()) -> (internal: Int, external: Int) {
        ledger.interruptions(on: now, calendar: calendar)
    }
    func streak(now: Date = Date()) -> Int { ledger.streakDays(endingOn: now, calendar: calendar) }
    func week(now: Date = Date()) -> [Int] { ledger.weekCounts(endingOn: now, calendar: calendar) }

    // MARK: - Day forecast

    /// Pomodoros still planned: estimate minus done over open tasks.
    var remainingPomodoros: Int {
        ledger.tasks.filter { !$0.isFinished }.reduce(0) { $0 + max(0, $1.estimate - $1.done) }
    }

    /// Where the remaining plan lands between today's meetings and the end of working hours.
    func forecast(now: Date = Date()) -> PomodoroForecast.Result? {
        let remaining = remainingPomodoros
        guard remaining > 0 else { return nil }
        let d = defaults
        let endMinutes = d.object(forKey: "workEndMinutes") == nil ? 18 * 60 : d.integer(forKey: "workEndMinutes")
        let dayStart = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .minute, value: endMinutes, to: dayStart) else { return nil }
        let cycle = PomodoroForecast.Cycle(
            workMinutes: max(1, d.integer(forKey: PomodoroKeys.cycleMinutes)),
            shortBreakMinutes: max(1, d.integer(forKey: PomodoroKeys.shortBreakSeconds) / 60),
            longBreakMinutes: max(1, d.integer(forKey: "longBreakSeconds") / 60),
            longEvery: max(1, d.integer(forKey: "longBreakEvery")))
        let busy = WorkDetector.shared.busyIntervals(from: now, to: end)
        return PomodoroForecast.plan(pomodoros: remaining, from: now, until: end, busy: busy,
                                     cycle: cycle, startingAtIndex: completedToday(now: now))
    }

    func projectTotalsThisWeek(now: Date = Date()) -> [PomodoroProjectTotal] {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return ledger.projectTotals(from: start, to: end)
    }

    func goldenHours() -> [PomodoroHourStat] { ledger.goldenHours(calendar: calendar) }

    // MARK: - Rhythm experiment

    /// Saves the user's settings, then lets the next working tick apply today's arm.
    func startRhythmExperiment(arms: [RhythmArm], daysPerBlock: Int, now: Date = Date()) {
        guard rhythm == nil, RhythmExperiment.canStart(arms: arms) else { return }
        switch RhythmSettingsBackup.begin(in: defaults) {
        case .fresh: break
        case .restoredLeftover: Trace.log("rhythm experiment: restored a leftover settings backup before starting")
        case .parkedCorrupt: Trace.log("rhythm experiment: leftover backup undecodable, kept under \(RhythmSettingsBackup.corruptKey)")
        }
        rhythmAppliedDay = nil
        rhythmAppliedArm = nil
        saveRhythm(RhythmExperiment(arms: arms, startedOn: now, daysPerBlock: daysPerBlock))
    }

    /// Ends the experiment and puts the saved settings back exactly as they were.
    func stopRhythmExperiment() {
        if RhythmSettingsBackup.end(in: defaults) == .undecodableKept {
            Trace.log("rhythm experiment: settings backup undecodable, left in place (settings not restored)")
        }
        defaults.removeObject(forKey: PomodoroKeys.rhythmExperiment)
        rhythmAppliedDay = nil
        rhythmAppliedArm = nil
        rhythm = nil
    }

    func rhythmResults(now: Date = Date()) -> [RhythmArmResult] {
        rhythm?.results(records: ledger.records, voided: ledger.voided, calendar: calendar) ?? []
    }

    /// Per-tick check, cheap and timer-free. Only the stored settings change (the
    /// engine reads them on the next cycle/break), only while WORKING and only
    /// while Pomodoro mode is on (off = nothing is applied or rewritten), so a
    /// break on screen or a paused engine is never touched.
    private func tickRhythm(isWorking: Bool, now: Date) {
        guard let exp = rhythm, isWorking, isEnabled else { return }
        let today = calendar.startOfDay(for: now)
        if rhythmAppliedDay != today {
            rhythmAppliedDay = today
            // A day the user already took over stays theirs (also after a restart).
            guard !exp.isContaminated(today, calendar: calendar) else { rhythmAppliedArm = nil; return }
            let arm = exp.arm(for: today, calendar: calendar)
            rhythmAppliedArm = arm
            defaults.set(arm.workMinutes, forKey: PomodoroKeys.cycleMinutes)
            defaults.set(arm.shortBreakMinutes * 60, forKey: PomodoroKeys.shortBreakSeconds)
            Trace.log("rhythm experiment: applied arm \(arm.id) \(arm.label)")
        } else if let arm = rhythmAppliedArm,
                  defaults.integer(forKey: PomodoroKeys.cycleMinutes) != arm.workMinutes
                    || defaults.integer(forKey: PomodoroKeys.shortBreakSeconds) != arm.shortBreakMinutes * 60 {
            // Manual change: this day no longer counts, and we stop applying anything today.
            rhythmAppliedArm = nil
            saveRhythm(exp.markingContaminated(today, calendar: calendar))
            Trace.log("rhythm experiment: settings changed by user, day excluded")
        }
    }

    private func saveRhythm(_ new: RhythmExperiment) {
        rhythm = new
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: PomodoroKeys.rhythmExperiment) }
    }

    // MARK: - Persistence

    /// A ledger merged with the other Macs' (the running pomodoro is already kept by the merge).
    func adoptSynced(_ ledger: PomodoroLedger) { apply(ledger) }

    private func apply(_ new: PomodoroLedger) {
        guard new != ledger else { return }
        ledger = new
        if let data = PomodoroLedger.encode(new) { defaults.set(data, forKey: PomodoroKeys.ledger) }
    }
}
