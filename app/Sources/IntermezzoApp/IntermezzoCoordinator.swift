import Foundation
import SwiftData
import Combine
import AppKit
import ServiceManagement
import os
import UserNotifications
import IOKit
import CoreLocation
import IntermezzoKit

private let log = Logger(subsystem: "com.automit.Intermezzo", category: "coordinator")

// MARK: - Persistence model

@Model
final class BreakRecord {
    var kindRaw: String
    var startedAt: Date
    var endedAt: Date?
    var wasSkipped: Bool
    /// `BreakOutcome.rawValue`; nil on records written before outcomes were stored.
    var outcomeRaw: String? = nil
    /// Minutes of a +1 / +5 postpone (0 otherwise).
    var postponeMinutes: Int = 0
    /// Started by the user (panel, hotkey, reminder card…) rather than by the timer.
    var startedManually: Bool = false
    /// Stable id across Macs (filled on the first sync).
    var syncID: String = ""
    /// Sync device id of the Mac that took the break; only it changes the record.
    var origin: String = ""

    init(kind: BreakKind, startedAt: Date) {
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.endedAt = nil
        self.wasSkipped = false
        self.syncID = UUID().uuidString
        self.origin = SyncIdentity.deviceID
    }

    var kind: BreakKind { BreakKind(rawValue: kindRaw) ?? .short }

    var outcome: BreakOutcome { BreakOutcome(raw: outcomeRaw, wasSkipped: wasSkipped) }

    /// Time away from the computer logged as a break of its own kind (see `NaturalBreak`).
    var isNatural: Bool { kindRaw == NaturalBreak.rawKind }

    static func natural(from start: Date, to end: Date) -> BreakRecord {
        let record = BreakRecord(kind: .short, startedAt: start)
        record.kindRaw = NaturalBreak.rawKind
        record.endedAt = end
        return record
    }
}

// MARK: - Settings (UserDefaults-backed)

enum Keys {
    static let cycleMinutes = "cycleMinutes"
    static let shortBreakSeconds = "shortBreakSeconds"
    static let longBreakSeconds = "longBreakSeconds"
    static let longBreakEvery = "longBreakEvery"
    static let playSound = "playSound"
    static let idleDetection = "idleDetection"
    static let idleThresholdSeconds = "idleThresholdSeconds"
    static let idleResetAfterMinutes = "idleResetAfterMinutes"
    static let enforceWorkingHours = "enforceWorkingHours"
    static let workStartHour = "workStartHour"
    static let workEndHour = "workEndHour"
    static let workStartMinutes = "workStartMinutes"
    static let workEndMinutes = "workEndMinutes"
    static let workDaysMask = "workDaysMask"
    static let autostart = "autostart"
    static let autoStartTimer = "autoStartTimer"
    static let cursorCountdown = "cursorCountdown"
    static let breakLeadPopup = "breakLeadPopup"
    static let flashEnabled = "flashEnabled"
    static let flashIntervalMinutes = "flashIntervalMinutes"
    static let flashDurationMs = "flashDurationMs"
    static let meetingDetection = "meetingDetection"
    static let videoDetection = "videoDetection"
    static let calendarWorkDetection = "calendarWorkDetection"
    static let calendarWorkKeywords = "calendarWorkKeywords"
    /// JSON [CalendarRule]: which calendars, titles and kinds of event count as work.
    static let calendarRules = "calendarRules"
    /// Holiday guard + vacation override (no breaks on urlop / N-day switch).
    static let holidayGuard = "holidayGuard"
    static let holidayKeywords = "holidayKeywords"
    static let vacationMode = "vacationMode"
    static let vacationDays = "vacationDays"
    static let vacationUntil = "vacationUntil"
    static let vpnDetection = "vpnDetection"
    static let vpnNames = "vpnNames"
    static let wifiDetection = "wifiDetection"
    static let wifiNames = "wifiNames"
    static let geoDetection = "geoDetection"
    static let geoLat = "geoLat"
    static let geoLon = "geoLon"
    static let geoRadiusM = "geoRadiusM"
    static let focusDetection = "focusDetection"
    /// A Focus mode marked "work" counts as a work-zone match.
    static let focusWorkZone = "focusWorkZone"
    /// JSON [mode id: FocusRole].
    static let focusRoles = "focusRoles"
    /// Show the countdown beside the icon on notched screens too.
    static let menuBarCountdownNotch = "menuBarCountdownNotch"
    /// Tint the menu-bar icon by the timer state.
    static let menuBarColoredIcon = "menuBarColoredIcon"
    static let hotkeyShort = "hotkeyShort"
    static let hotkeyLong = "hotkeyLong"
    static let hotkeySkip = "hotkeySkip"
    static let hotkeyPause = "hotkeyPause"
    static let hotkeyPostpone = "hotkeyPostpone"
    static let hotkeyPauseAll = "hotkeyPauseAll"
    static let hotkeyResumeAll = "hotkeyResumeAll"
    static let hotkeyReset = "hotkeyReset"
    static let hotkeyStopSound = "hotkeyStopSound"
    static let pomodoroMode = "pomodoroMode"
    static let strictMode = "strictMode"
    static let menuBarCountdown = "menuBarCountdown"
    static let clockOutEnabled = "clockOutEnabled"
    static let clockOutStartHour = "clockOutStartHour"
    static let clockOutEndHour = "clockOutEndHour"
    static let clockOutTitle = "clockOutTitle"
    static let clockOutMessage = "clockOutMessage"
    static let breakBackgroundPath = "breakBackgroundPath"
    static let messagesDuringBreak = "messagesDuringBreak"
    static let idleDetectionMethod = "idleDetectionMethod"
    static let hidePause = "hidePause"
    static let hideMakeDue = "hideMakeDue"
    static let hideReset = "hideReset"
    static let hideQuit = "hideQuit"
    static let preventSleepDuringBreak = "preventSleepDuringBreak"
    static let alertDuplicates = "alertDuplicates"
}

/// Logging of long absences as natural breaks. Off by default.
enum NaturalBreakKeys {
    static let enabled = "naturalBreakLog"
    static let minMinutes = "naturalBreakMinMinutes"
    static let defaultMinutes = 10
}

private func bind(_ d: UserDefaults, _ key: String, _ fallback: Int) {
    if d.object(forKey: key) == nil { d.set(fallback, forKey: key) }
}

private func bind(_ d: UserDefaults, _ key: String, _ fallback: Double) {
    if d.object(forKey: key) == nil { d.set(fallback, forKey: key) }
}

func registerDefaults() {
    SurfaceTheme.migrateStoredTheme()
    let d = UserDefaults.standard
    bind(d, Keys.cycleMinutes, 45)
    bind(d, Keys.shortBreakSeconds, 300)
    bind(d, Keys.longBreakSeconds, 900)
    bind(d, Keys.longBreakEvery, 4)
    let lengths = BreakLengthLimits.reconciled(short: d.integer(forKey: Keys.shortBreakSeconds),
                                                long: d.integer(forKey: Keys.longBreakSeconds))
    d.set(lengths.short, forKey: Keys.shortBreakSeconds)
    d.set(lengths.long, forKey: Keys.longBreakSeconds)
    bind(d, Keys.playSound, 1)
    bind(d, Keys.idleDetection, 1)
    bind(d, Keys.idleThresholdSeconds, 60)
    bind(d, Keys.idleResetAfterMinutes, 5)
    bind(d, Keys.enforceWorkingHours, 0)
    bind(d, Keys.workStartHour, 8)
    bind(d, Keys.workEndHour, 18)
    bind(d, Keys.workStartMinutes, 8 * 60)
    bind(d, Keys.workEndMinutes, 18 * 60)
    bind(d, Keys.workDaysMask, 0b001_1111)   // Mon–Fri
    bind(d, Keys.autostart, 1)
    bind(d, Keys.autoStartTimer, 1)
    bind(d, Keys.cursorCountdown, 1)
    bind(d, Keys.breakLeadPopup, 30)
    bind(d, ReminderKeys.hideSkip, 0)
    bind(d, ReminderKeys.hideDelay, 0)
    bind(d, RelaxationAudioKeys.enabled, 0)
    bind(d, RelaxationAudioKeys.volume, 0.25)
    bind(d, Keys.flashEnabled, 0)
    bind(d, Keys.flashIntervalMinutes, 10)
    bind(d, Keys.flashDurationMs, 900)
    bind(d, Keys.meetingDetection, 1)
    bind(d, Keys.videoDetection, 1)
    bind(d, Keys.calendarWorkDetection, 0)
    bind(d, Keys.vpnDetection, 0)
    bind(d, Keys.focusDetection, 0)
    if d.string(forKey: Keys.calendarWorkKeywords) == nil {
        d.set("work, praca, meeting, spotkanie", forKey: Keys.calendarWorkKeywords)
    }
    if d.string(forKey: Keys.holidayKeywords) == nil {
        d.set("urlop, święto, swieto, wakacje, vacation, holiday, chorobowe, l4",
              forKey: Keys.holidayKeywords)
    }
    bind(d, Keys.holidayGuard, 0)
    bind(d, Keys.vacationMode, 0)
    bind(d, Keys.vacationDays, 7)
    bind(d, Keys.pomodoroMode, 0)
    bind(d, Keys.strictMode, 0)
    bind(d, SeamKeys.enabled, 0)
    bind(d, SessionAwareKeys.enabled, 0)
    bind(d, SeamKeys.maxDelaySeconds, SeamKeys.defaultMaxDelay)
    bind(d, Keys.menuBarCountdown, 1)
    bind(d, Keys.menuBarCountdownNotch, 0)
    bind(d, Keys.menuBarColoredIcon, 0)
    bind(d, Keys.focusWorkZone, 0)
    bind(d, Keys.messagesDuringBreak, 1)
    bind(d, MessagesStore.breakEveryKey, 3)
    if d.string(forKey: Keys.idleDetectionMethod) == nil {
        d.set("monitor", forKey: Keys.idleDetectionMethod)
    }
    bind(d, Keys.preventSleepDuringBreak, 0)
    bind(d, Keys.alertDuplicates, 1)
    bind(d, Keys.clockOutEnabled, 0)
    bind(d, Keys.clockOutStartHour, 21)
    bind(d, Keys.clockOutEndHour, 6)
    if d.string(forKey: Keys.clockOutTitle) == nil {
        d.set("Time to Switch Off", forKey: Keys.clockOutTitle)
        d.set("Zakończ pracę, zamknij laptopa. Jutro też jest dzień.",
              forKey: Keys.clockOutMessage)
    }
}

func currentConfig() -> BreakConfig {
    let d = UserDefaults.standard
    var c = BreakConfig()
    c.cycleMinutes = max(1, d.integer(forKey: Keys.cycleMinutes))
    c.shortBreakSeconds = max(10, d.integer(forKey: Keys.shortBreakSeconds))
    c.longBreakSeconds = max(60, d.integer(forKey: Keys.longBreakSeconds))
    c.longBreakEvery = max(2, d.integer(forKey: Keys.longBreakEvery))
    c.enforceWorkingHours = d.integer(forKey: Keys.enforceWorkingHours) != 0
    // One-time migration from legacy hour keys → minute-accurate keys.
    if d.object(forKey: Keys.workStartMinutes) == nil, d.object(forKey: Keys.workStartHour) != nil {
        let h = d.integer(forKey: Keys.workStartHour)
        if h > 0 { d.set(h * 60, forKey: Keys.workStartMinutes) }
    }
    if d.object(forKey: Keys.workEndMinutes) == nil, d.object(forKey: Keys.workEndHour) != nil {
        let h = d.integer(forKey: Keys.workEndHour)
        if h > 0 { d.set(h * 60, forKey: Keys.workEndMinutes) }
    }
    c.workingHoursStart = d.integer(forKey: Keys.workStartMinutes)
    c.workingHoursEnd = d.integer(forKey: Keys.workEndMinutes)
    // A meal or other fixed-length break replaces the length of whichever kind is next: the cycle may be
    // on a long break, and then only overriding the short one would leave the regular length.
    if let custom = CustomBreak.active {
        c.shortBreakSeconds = custom.seconds
        c.longBreakSeconds = custom.seconds
    }
    return c
}


/// Owns the engine, the 1-second heartbeat, idle detection, overlay windows
/// and history recording. Lives as an ObservableObject for SwiftUI.
@MainActor
final class BreakCoordinator: ObservableObject {
    @Published private(set) var statusText: String = String(localized: "Paused")
    /// Collected during a tick and published at its end for the Diagnostics pane.
    private var gateFactors: [GateFactor] = []
    /// Where each factor is set, so a card in Diagnostics can open the right pane.
    private static let gateLinks: [String: String] = [
        "vacation": "General#vacation", "holiday": "General#holiday", "hours": "General#hours",
        "zone": "General#zone-calendar", "zone-calendar": "General#zone-calendar", "zone-vpn": "General#zone-vpn",
        "zone-wifi": "General#zone-wifi", "zone-geo": "General#zone-geo", "zone-lan": "Work log#lan",
        "meeting": "General#meeting", "video": "General#video", "focus": "General#focus",
        "rules": "Rules", "manual": "Status#pause", "idle": "Advanced#idle",
        "zone-focus": "General#focus",
    ]
    private func gate(_ id: String, _ group: GateGroup, _ title: String, _ verdict: GateVerdict,
                      _ detail: String, info: Bool = false) {
        // Plain texts are looked up here; texts with values arrive already built by L("… %@", value).
        gateFactors.append(GateFactor(id: id, group: group, title: L(title), verdict: verdict,
                                      detail: L(detail), informational: info, link: Self.gateLinks[id]))
    }
    private static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    @Published private(set) var statusSymbol: String = "timer"
    @Published private(set) var headlineText: String = String(localized: "Breaks paused")
    @Published private(set) var countdownText: String = "—:—"
    @Published private(set) var completedTodayDisplay: String = ""
    @Published private(set) var isOnBreak = false
    /// 0…1 — progress of the work cycle (or of the live break) for the panel ring.
    @Published private(set) var ringProgress: Double = 0
    /// Human-readable reason the timer is paused ("" when running).
    @Published private(set) var pauseReasonText: String = ""

    /// Pause reasons owned by automatic policies — synced every tick.
    /// (.manual / .userAway are driven by user actions and idle detection.)
    private static let policyReasons: Set<PauseReason> = [
        .vacation, .holiday, .outsideWorkingHours, .inMeeting, .watchingVideo,
        .ruleMatch, .outsideWorkZone, .inFocusMode,
    ]

    private var completedTodayCount: Int = 0
    private var lastStatsRefresh = Date.distantPast
    var engine = BreakEngine()
    /// "Natural seam" gate state (see Coordinator/SeamBreaks.swift).
    var seamGate = SeamGate()
    var reminderEscalation = ReminderEscalation()
    /// Edge-glow strength while a reminder-only break is being ignored (overrides the pre-break glow).
    var overdueGlow: Double?
    let context: ModelContext
    private var openRecord: BreakRecord?
    private var heartbeat: Timer?
    private var overlay: BreakOverlayController?

    /// Closes break windows that outlived their break (called by the app's watchdog).
    func sweepOverlayStrays() { overlay?.sweepStrays() }
    private var cursorCountdown: CursorCountdownController?
    private let edgeGlow = EdgeGlowController()
    let flash = FlashReminderController()
    private let reminders = ReminderController()
    let intelligence = IntelligenceController()
    let workDetector = WorkDetector.shared
    let relaxation = RelaxationAudioController()
    let scripts = ScriptActionController()
    let messages = MessagesStore()
    let eventMonitor = IdleEventMonitor()
    let sleepGuard = SleepGuard()
    /// Message currently offered as a hint on the break screen, and the
    /// article the user tapped (opened in Settings once the break is over).
    private var currentBreakMessage: BreakMessage?
    private var pendingMessageID: String?
    /// Generic Break Actions (notification / sound / flash /
    /// speech / volume / music / script at Before Due, After Start,
    /// After Any End — lazily built so `flash`/`notify` are available).
    private lazy var breakActions: BreakActionController = BreakActionController(
        notify: { [weak self] title, body in self?.notify(title: title, body: body) },
        flashPulse: { [weak self] hex in self?.flash.pulse(colorHex: hex) })
    private var awaySince: Date?
    private var clockOutOverlay: ClockOutController?
    private var clockOutAcknowledgedAt: Date?
    private var tickCount: Int = 0
    let screenTime = ScreenTimeStore()
    private var pendingScreenSeconds = 0
    private var lastBlinkNudge = Date()
    @Published private(set) var screenTimeToday: String = ""
    /// Fade-out muzyki na 5 s przed końcem przerwy — odpalamy raz na przerwę.
    private var musicFadeStarted = false
    // Break Rules: live list refreshed whenever the
    // stored JSON changes, plus a per-rule result cache (5 s) so conditions
    // like EventKit fetches or osascript don't run on every heartbeat.
    private var rulesSignature: Data?
    private var liveRules: [BreakRule] = []
    private var ruleEvalCache: [UUID: (at: Date, hit: Bool)] = [:]
    /// Total non-skipped breaks ever completed — drives content rotation
    /// and the Pomodoro session counter.
    private(set) var totalCompletedBreaks: Int = 0

    init(modelContainer: ModelContainer) {
        self.context = ModelContext(modelContainer)
        registerDefaults()
        ExerciseSeed.syncLibrary(context)
        cursorCountdown = CursorCountdownController(
            onStart: { [weak self] in self?.takeShortNow(source: "reminder-card") },
            onSnooze1: { [weak self] in self?.snooze(minutes: 1) },
            onSnooze5: { [weak self] in self?.snooze(minutes: 5) },
            onSkip: { [weak self] in self?.handleSkip(source: "reminder-card") })
        overlay = BreakOverlayController(
            onSkip: { [weak self] in self?.handleSkip(source: "break-overlay") },
            onExtend: { [weak self] minutes in self?.snooze(minutes: minutes) })
        overlay?.onButtonClick = { [weak self] title in
            self?.breakActions.fireButtonAction(title: title)
        }
        clockOutOverlay = ClockOutController { [weak self] in
            self?.clockOutAcknowledgedAt = Date()
        }
    }

    /// Exercises assigned to this break kind (library rows and the user's own).
    private func assignedExercises(for kind: BreakKind) -> [Exercise] {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return all.filter { kind == .long ? $0.assignToLong : $0.assignToShort }
    }

    // MARK: Engine driving

    func startIfNeeded() {
        guard engine.isPaused else { return }
        engine.start(now: Date(), config: currentConfig())
        // "Start timer automatically" off → begin in a manual pause; the user
        // resumes from the panel / hotkey.
        if UserDefaults.standard.integer(forKey: Keys.autoStartTimer) == 0 {
            engine.pause(reason: .manual, now: Date())
        }
        // Schedule the heartbeat directly on the main run loop (no Task hop).
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.profiledTick() }
        }
        t.tolerance = 0.3          // lets the system coalesce this wake-up with others
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
        NSLog("Intermezzo: heartbeat scheduled, state=\(String(describing: engine.state))")
        tick()
    }

    private var tickCostTotal: UInt64 = 0
    private var tickCostMax: UInt64 = 0
    private var tickCostCount = 0

    /// Heartbeat with optional cost accounting: `defaults write com.automit.Intermezzo tickProfile 1`
    /// logs the average and worst tick time (CPU time of this thread) once a minute.
    private func profiledTick() {
        guard UserDefaults.standard.integer(forKey: "tickProfile") != 0 else { tick(); return }
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        tick()
        let cost = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
        tickCostTotal += cost
        tickCostMax = max(tickCostMax, cost)
        tickCostCount += 1
        if tickCostCount >= 60 {
            Trace.log("tick cost: avg \(tickCostTotal / UInt64(tickCostCount) / 1000) µs, max \(tickCostMax / 1000) µs over \(tickCostCount) ticks")
            tickCostTotal = 0; tickCostMax = 0; tickCostCount = 0
        }
    }

    private func tick() {
        let now = Date()
        var config = currentConfig()
        let d = UserDefaults.standard
        gateFactors.removeAll(keepingCapacity: true)

        // Working-hours gating (weekday mask + minute-accurate range, e.g. 6:30–14:30).
        // Priority: Vacation override > Holiday guard > fixed working hours.
        // A calendar event that matches the rules counts as work next to the hours
        // (see atWorkNow), so it extends them and never replaces them.
        var onVacation = false
        if d.integer(forKey: Keys.vacationMode) != 0 {
            let until = Date(timeIntervalSince1970: d.double(forKey: Keys.vacationUntil))
            if now < until {
                onVacation = true
            } else {
                d.set(0, forKey: Keys.vacationMode)      // expired — auto-off
            }
        }
        let onHoliday = d.integer(forKey: Keys.holidayGuard) != 0
            && workDetector.holidayToday
        // Every policy below only declares what it WANTS; one syncReasons()
        // call per tick (further down) pauses/resumes accordingly, so no
        // policy can ever leave a stale pause behind.
        var desired = Set<PauseReason>()
        var outsideHours = false
        // For Diagnostics: 0 off, 2 shadowed by vacation/holiday, 3 evaluated.
        var hoursMode = 0
        var hoursDetail = ""
        if onVacation {
            desired.insert(.vacation)
            hoursMode = 2
        } else if onHoliday {
            desired.insert(.holiday)
            hoursMode = 2
        } else if config.enforceWorkingHours {
            let comp = Calendar.current.dateComponents([.hour, .minute, .weekday], from: now)
            let minuteOfDay = (comp.hour ?? 0) * 60 + (comp.minute ?? 0)
            // weekday: 1 = Sunday … 7 = Saturday → shift so bit0 = Monday
            let weekdayIndex = ((comp.weekday ?? 2) + 5) % 7
            let mask = d.integer(forKey: Keys.workDaysMask)
            let dayOK = (mask & (1 << weekdayIndex)) != 0
            let general = WeekHours.Window(start: config.workingHoursStart, end: config.workingHoursEnd)
            let today = d.integer(forKey: "perDayHours") != 0
                ? WeekHours.decode(d.data(forKey: "weekHours")).window(forDay: weekdayIndex, default: general)
                : general
            let timeOK = today.contains(minute: minuteOfDay)
            outsideHours = !(dayOK && timeOK)
            hoursMode = 3
            hoursDetail = dayOK
                ? L("teraz %@ · dziś %@", Self.clock(minuteOfDay), "\(Self.clock(today.start))–\(Self.clock(today.end))")
                : L("teraz %@ · dziś dzień wolny", Self.clock(minuteOfDay))
        }
        let vacationUntil = Date(timeIntervalSince1970: d.double(forKey: Keys.vacationUntil))
        gate("vacation", .schedule, "Tryb urlopu", onVacation ? .blocking : .inactive,
             onVacation ? L("do %@", vacationUntil.formatted(date: .abbreviated, time: .omitted)) : "wyłączony")
        let holidayOn = d.integer(forKey: Keys.holidayGuard) != 0
        gate("holiday", .schedule, "Ochrona świąt i urlopów", onHoliday ? .blocking : (holidayOn ? .passing : .inactive),
             onHoliday ? "dziś w kalendarzu jest wydarzenie urlop/święto"
                       : (holidayOn ? "dziś bez wydarzenia urlop/święto" : "wyłączona"))

        // Intelligence — pause while in a meeting / watching video.
        // (IntelligenceController caches its probes for 4 s.)
        tickCount += 1
        let meetingOn = d.integer(forKey: Keys.meetingDetection) != 0
        let inMeeting = meetingOn && intelligence.meetingInProgress()
        if inMeeting { desired.insert(.inMeeting) }
        gate("meeting", .detection, "Spotkanie (Zoom, Teams, Webex)", inMeeting ? .blocking : (meetingOn ? .passing : .inactive),
             inMeeting ? intelligence.meetingReason : (meetingOn ? "brak spotkania" : "wykrywanie wyłączone"))
        let videoOn = d.integer(forKey: Keys.videoDetection) != 0
        let watchingVideo = videoOn && intelligence.videoInProgress()
        if watchingVideo { desired.insert(.watchingVideo) }
        gate("video", .detection, "Wideo", watchingVideo ? .blocking : (videoOn ? .passing : .inactive),
             watchingVideo ? "oglądasz wideo" : (videoOn ? "brak wideo" : "wykrywanie wyłączone"))

        // ── Break Rules ────────────────────────
        // Pick up live edits from the Settings pane.
        let rulesData = d.data(forKey: BreakRuleStore.storageKey)
        if rulesData != rulesSignature {
            rulesSignature = rulesData
            liveRules = (try? JSONDecoder().decode([BreakRule].self,
                                                   from: rulesData ?? Data())) ?? []
            Trace.log("rules reloaded: \(liveRules.count) rule(s)")
            let live = Set(liveRules.map(\.id))
            suggestGates = suggestGates.filter { live.contains($0.key) }
        }
        let enabledRules = liveRules.filter { $0.enabled }
        // A Focus rule needs the Focus probe even when the standalone
        // Focus-detection toggle is off.
        // (Focus probe handled by focusNow() below; no extra opt-in needed.)
        // Natural-break outcomes: "treat as natural" holds breaks while the
        // condition matches; "ignore natural break" suppresses the idle
        // auto-pause below so breaks keep coming anyway.
        var ignoreNaturalBreak = false
        var holdRules = 0
        var holdingRules: [String] = []
        for rule in enabledRules {
            switch rule.outcome {
            case .treatAsNaturalBreak:
                holdRules += 1
                if ruleConditionMatches(rule, now: now) {
                    desired.insert(.ruleMatch)
                    holdingRules.append("\(rule.kind.rawValue): \(rule.text)")
                }
            case .ignoreNaturalBreak:
                if ruleConditionMatches(rule, now: now) { ignoreNaturalBreak = true }
            case .suggestBreak:
                evaluateSuggestion(rule, now: now, config: config)
            default:
                break
            }
        }

        gate("rules", .detection, "Reguły wstrzymujące", holdingRules.isEmpty ? (holdRules > 0 ? .passing : .inactive) : .blocking,
             holdingRules.isEmpty ? (holdRules > 0 ? "żadna reguła nie wstrzymuje" : "brak reguł tego typu")
                                  : holdingRules.joined(separator: "; "))

        // Work zone: Calendar / VPN-by-name / Wi-Fi-by-
        // SSID / GPS-location are ACTIVATORS. When any of them is enabled,
        // breaks only run while at least one matches (an event titled
        // "praca", VPN "work" connected, office SSID, inside saved place).
        // All off = breaks always run. Focus keeps its own PAUSE meaning.
        let calOn = d.integer(forKey: Keys.calendarWorkDetection) != 0
        let vpnOn = d.integer(forKey: Keys.vpnDetection) != 0
        let wifiOn = d.integer(forKey: Keys.wifiDetection) != 0
        let geoOn = d.integer(forKey: Keys.geoDetection) != 0
        workDetector.calendarEnabled = calOn
        workDetector.vpnEnabled = vpnOn
        workDetector.wifiEnabled = wifiOn
        workDetector.geoEnabled = geoOn
        // Until the user opens the rules, the old keyword list works as one rule over every calendar.
        workDetector.calendarRules = d.object(forKey: Keys.calendarRules) == nil
            ? [CalendarRules.legacy(keywords: d.string(forKey: Keys.calendarWorkKeywords) ?? "")]
            : CalendarRules.decode(d.data(forKey: Keys.calendarRules))
        workDetector.holidayEnabled = d.integer(forKey: Keys.holidayGuard) != 0
        workDetector.holidayKeywords = csvList(d.string(forKey: Keys.holidayKeywords))
        workDetector.vpnNames = csvList(d.string(forKey: Keys.vpnNames))
        workDetector.wifiNames = csvList(d.string(forKey: Keys.wifiNames))
        let gLat = d.double(forKey: Keys.geoLat)
        let gLon = d.double(forKey: Keys.geoLon)
        workDetector.geoCenter = (calOn || geoOn) && !(gLat == 0 && gLon == 0)
            ? CLLocationCoordinate2D(latitude: gLat, longitude: gLon) : nil
        if geoOn {
            let rad = d.double(forKey: Keys.geoRadiusM)
            workDetector.geoRadiusMeters = rad > 0 ? rad : 300
        }
        workDetector.poll(now: now)
        gate("zone-calendar", .zone, "Kalendarz", calOn && workDetector.calendarMatch ? .passing : .inactive,
             !calOn ? "wyłączone"
                    : (workDetector.calendarMatch ? L("trwa: %@", workDetector.calendarMatchSummary) : "brak pasującego wydarzenia"))
        let vpnNames = workDetector.vpnConnectedNames.joined(separator: ", ")
        gate("zone-vpn", .zone, "VPN", vpnOn && workDetector.vpnMatch ? .passing : .inactive,
             !vpnOn ? "wyłączone"
                    : (workDetector.vpnMatch ? L("połączono: %@", vpnNames)
                       : (vpnNames.isEmpty ? "brak połączenia VPN" : L("połączono (%@), ale nie z listy", vpnNames))))
        gate("zone-wifi", .zone, "Wi-Fi", wifiOn && workDetector.wifiMatch ? .passing : .inactive,
             !wifiOn ? "wyłączone"
                     : (workDetector.wifiMatch ? L("sieć: %@", workDetector.currentSSID)
                        : (workDetector.currentSSID.isEmpty ? "brak Wi-Fi albo brak zgody na Lokalizację"
                           : L("sieć %@ nie jest z listy", workDetector.currentSSID))))
        gate("zone-geo", .zone, "Zapisane miejsce", geoOn && workDetector.geoMatch ? .passing : .inactive,
             !geoOn ? "wyłączone"
                    : (workDetector.geoMatch ? "w promieniu miejsca"
                       : (workDetector.geoDistanceM >= 0 ? L("%lld m od miejsca", Int(workDetector.geoDistanceM)) : "położenie nieznane")))
        let workLog = WorkLogController.shared
        // Focus: which modes are on and what each is for (work, hold breaks, ignore).
        let focusOn = d.integer(forKey: Keys.focusDetection) != 0
        let focusWorkOn = d.integer(forKey: Keys.focusWorkZone) != 0
        let focusRoles = (try? JSONDecoder().decode([String: FocusRole].self,
                                                    from: d.data(forKey: Keys.focusRoles) ?? Data())) ?? [:]
        let focusSnap = (focusOn || focusWorkOn) ? focusSnapshot(now) : nil
        let activeFocus = focusSnap?.active ?? []
        let focusAtWork = focusWorkOn && activeFocus.contains { FocusModes.role(for: $0.id, stored: focusRoles) == .work }
        workDetector.focusAtWork = focusAtWork   // also reaches the work log and the lamps through presencePlace
        let activeFocusNames = activeFocus.map(\.name).joined(separator: ", ")
        var focusZoneDetail = "wyłączone"
        if focusWorkOn {
            if focusSnap == nil {
                focusZoneDetail = "brak dostępu do danych Focus (Pełny dostęp do dysku)"
            } else if activeFocus.isEmpty {
                focusZoneDetail = "żaden Focus nie jest włączony"
            } else {
                focusZoneDetail = focusAtWork ? L("włączony: %@ (praca)", activeFocusNames)
                                              : L("włączony: %@ (nie jako praca)", activeFocusNames)
            }
        }
        gate("zone-focus", .zone, "Focus oznaczony jako praca", focusAtWork ? .passing : .inactive, focusZoneDetail)
        // The LAN, dock adapter or work Wi-Fi marked in the work log counts as a match here too, so one
        // place of work is set up once. It never switches the work zone on by itself (that stays with the four sources).
        let lanMatch = workLog.isEnabled && workLog.zone.inZone
        // At work in any sense: one match from any source is enough, whatever the clock says.
        let atWorkNow = (calOn && workDetector.calendarMatch)
            || (vpnOn && workDetector.vpnMatch)
            || (wifiOn && workDetector.wifiMatch)
            || (geoOn && workDetector.geoMatch)
            || lanMatch
            || focusAtWork
        // Working hours and the work zone are alternatives, not both required: the timer runs inside the
        // hours OR while the Mac is at work (overtime, an outage, a day off), and holds only when neither holds.
        let inHoursNow = hoursMode == 3 && !outsideHours
        gate("zone-lan", .zone, "LAN i karta z Rejestru pracy", lanMatch ? .passing : .inactive,
             !workLog.isEnabled ? "rejestr pracy wyłączony"
                                : (lanMatch ? L("%@: liczy się do strefy przerw", workLog.zone.reason)
                                            : "rejestr pracy też nie widzi strefy pracy"))
        if workDetector.hasActivators {
            let zoneBlock = !atWorkNow && !inHoursNow
            if zoneBlock { desired.insert(.outsideWorkZone) }
            gate("zone", .zone, "Strefa pracy", zoneBlock ? .blocking : .passing,
                 atWorkNow ? "co najmniej jedno źródło pasuje"
                           : (inHoursNow ? "żadne źródło nie pasuje, ale trwają godziny pracy"
                                         : "żadne źródło nie pasuje i są poza godzinami pracy"))
            if atWorkNow != lastZoneState {
                lastZoneState = atWorkNow
                Trace.log("work-zone: \(atWorkNow ? "IN — breaks active" : "OUT — breaks held")")
            }
        }
        let hoursBlock = outsideHours && !atWorkNow
        if hoursBlock { desired.insert(.outsideWorkingHours) }
        if !workDetector.hasActivators {
            gate("zone", .zone, "Strefa pracy", .inactive, "wszystkie źródła wyłączone: przerwy działają wszędzie")
        }
        switch hoursMode {
        case 2: gate("hours", .schedule, "Godziny pracy", .inactive, "pominięte: urlop lub święto ma pierwszeństwo")
        case 3:
            gate("hours", .schedule, "Godziny pracy", hoursBlock ? .blocking : .passing,
                 hoursBlock ? L("%@ · poza godzinami i poza strefą pracy", hoursDetail)
                            : (outsideHours ? L("%@ · poza godzinami, ale jesteś w strefie pracy", hoursDetail)
                                            : L("%@ · w godzinach pracy", hoursDetail)))
        default: gate("hours", .schedule, "Godziny pracy", .inactive, "wyłączone: przerwy działają całą dobę")
        }
        // Focus / Do-Not-Disturb: pause while on (separate from the zone).
        // Modes whose role is "hold breaks" pause the timer; without access to the Focus files only the
        // coarse on/off probe is left.
        let pausingFocus = activeFocus.filter { FocusModes.role(for: $0.id, stored: focusRoles) == .pause }
        let inFocus = focusOn && (focusSnap != nil ? !pausingFocus.isEmpty : focusNow(now))
        if inFocus { desired.insert(.inFocusMode) }
        var focusDetail = "wykrywanie wyłączone"
        if focusOn {
            if inFocus {
                focusDetail = pausingFocus.isEmpty
                    ? "Focus jest włączony"
                    : L("wstrzymuje: %@", pausingFocus.map(\.name).joined(separator: ", "))
            } else if activeFocus.isEmpty {
                focusDetail = "żaden Focus nie jest włączony"
            } else {
                focusDetail = L("włączony: %@ (nie wstrzymuje)", activeFocusNames)
            }
        }
        gate("focus", .detection, "Focus / Nie przeszkadzać", inFocus ? .blocking : (focusOn ? .passing : .inactive), focusDetail)
        engine.syncReasons(desired, managed: BreakCoordinator.policyReasons, now: now)

    // Idle detection → auto-pause; long absence → Timer Reset Logic.
    // "Ignore natural break" rules matching now keep the countdown running
    // (and lift a pause we previously took for an away period).
    let idleDetection = d.integer(forKey: Keys.idleDetection) != 0
    // Advanced: choose the idle detection mechanism. The event
    // tap (Event Monitor) is more reliable but needs Accessibility; if the
    // tap cannot be created we transparently stay on Event Source polling.
    let idleMethod = d.string(forKey: Keys.idleDetectionMethod) ?? "source"
    if idleDetection && idleMethod == "monitor" {
        if !eventMonitor.isRunning { eventMonitor.start() }
        else if tickCount % 30 == 0 { eventMonitor.reenableIfNeeded() }
    }
    if idleDetection {
        var idle = secondsSinceLastUserInput()
        if idleMethod == "monitor", eventMonitor.isRunning {
            // Be conservative: only treat the user as idle when BOTH the
            // event tap and HID source polling agree. An unauthorized tap
            // sees no events; polling then keeps us from false away-time.
            idle = min(idle, eventMonitor.idleSeconds())
        }
        let threshold = TimeInterval(max(10, d.integer(forKey: Keys.idleThresholdSeconds)))
            if idle > threshold && !ignoreNaturalBreak {
                if awaySince == nil {
                    awaySince = now
                    engine.pause(reason: .userAway, now: now)
                }
            } else if awaySince != nil {
                let awayFor = now.timeIntervalSince(awaySince!)
                awaySince = nil
                let resetAfter = TimeInterval(max(1, d.integer(forKey: Keys.idleResetAfterMinutes)) * 60)
                logNaturalBreak(away: awayFor, now: now)
                // The time without input also includes the idle threshold that had to pass before "away" began.
                let withoutInput = awayFor + threshold
                let creditEnabled = d.object(forKey: "awayCreditsBreak") as? Bool ?? true
                let credit = creditEnabled
                    ? AwayCredit.kind(awaySeconds: withoutInput, nextKind: engine.previewNextKind(config: config), config: config)
                    : nil
                if let credit {
                    engine.creditAway(kind: credit, now: now, config: config)
                    if awayFor > resetAfter { PomodoroController.shared.abandon(at: now) }
                    Trace.log("away \(Int(withoutInput)) s counted as a \(credit) break")
                    post(title: "Witaj z powrotem",
                         body: credit == .long
                            ? L("Byłeś nieobecny %lld min: zaliczone jako długa przerwa, timer zaczyna od nowa.", Int(withoutInput / 60))
                            : L("Byłeś nieobecny %lld min: zaliczone jako krótka przerwa, timer zaczyna od nowa.", Int(withoutInput / 60)),
                         symbol: "hand.wave.fill")
                } else if awayFor > resetAfter {
                    // "Timer Reset Logic": restart the work cycle at
                    // FULL length — returning never triggers an instant break.
                    engine.resetCycle(now: now, config: config)
                    PomodoroController.shared.abandon(at: now)
                } else if awayFor > config.breakDuration(for: .short) + 30 {
                    post(title: "Witaj z powrotem",
                         body: L("Byłeś nieobecny %lld min — zaliczyć to jako przerwę?", Int(awayFor / 60)),
                         symbol: "hand.wave.fill",
                         actions: [ToastAction(title: "Zalicz przerwę") { [weak self] in
                             self?.creditBreak(away: awayFor)
                         }])
                }
                engine.resume(reason: .userAway, now: now)
            }
        } else if awaySince != nil {
            awaySince = nil
            engine.resume(reason: .userAway, now: now)
        }

        // Clock Out — evening boundary reminder ("Time to Switch Off").
        if d.integer(forKey: Keys.clockOutEnabled) != 0, !isOnBreak {
            let hour = Calendar.current.component(.hour, from: now)
            let start = d.integer(forKey: Keys.clockOutStartHour)
            let end = d.integer(forKey: Keys.clockOutEndHour)
            // Window wraps midnight: inside = hour >= start || hour < end.
            let inside: Bool = start <= end ? (hour >= start && hour < end)
                                            : (hour >= start || hour < end)
            if inside {
                if clockOutAcknowledgedAt == nil ||
                    now.timeIntervalSince(clockOutAcknowledgedAt!) > 15 * 60 {
                    showClockOutOverlay()
                }
            } else {
                clockOutOverlay?.dismiss()
                clockOutAcknowledgedAt = nil
            }
        } else {
            clockOutOverlay?.dismiss()
        }

        // Rules with skip/postpone outcomes are evaluated right before the
        // break becomes due: a postponing rule repeats
        // until its condition clears; a skipping rule closes a skipped record
        // and restarts the full cycle without showing the overlay.
        if !isOnBreak, !engine.isPaused, enabledRules.contains(where: {
            $0.outcome == .postpone || $0.outcome == .autoSkip
        }), let left = engine.timeUntilBreak(now: now), left <= 1.5 {
            Trace.log("due-window: left=\(String(format: "%.1f", left)) rules=\(enabledRules.count)")
            ruleDueCheck(now: now, config: config, rules: enabledRules)
        }

        // Calendar-aware breaks: never pop up into a meeting — hold the break
        // back in 3-minute steps while an event is running / about to start.
        if d.integer(forKey: "calendarAwareBreaks") != 0, !isOnBreak, !engine.isPaused,
           let left = engine.timeUntilBreak(now: now), left <= 1.5,
           workDetector.calendarBusy(within: 5, now: now) {
            engine.snooze(minutes: 3, now: now)
            Trace.log("calendar-aware: meeting running/starting — break held back 3 min")
        }

        applySeamGate(now: now)
        applyReminderOnly(now: now)
        // Meal break window open and the regular timer runs out now: this break becomes the meal.
        var mealStarting: ScheduledBreak?
        var mealKind: BreakKind = .short
        if !isOnBreak, !engine.isPaused, CustomBreak.active == nil,
           let left = engine.timeUntilBreak(now: now), left <= 0,
           let meal = reminders.mealInWindow(now: now), let minutes = meal.customMinutes {
            // How the meal counts in the cycle depends on the regular lengths, so read them before the override.
            mealKind = currentConfig().kindForCustomLength(seconds: max(1, minutes) * 60)
            CustomBreak.active = (meal.label, max(1, minutes) * 60)
            config = currentConfig()
            mealStarting = meal
        }
        let events = engine.tick(now: now, config: config, startKind: mealStarting == nil ? nil : mealKind)
        if let meal = mealStarting {
            if events.contains(where: { if case .breakStarted = $0 { return true } else { return false } }) {
                reminders.markFired(meal, now: now)
                Trace.log("scheduled break: \(meal.label) (regular timer ran out in its window)")
            } else {
                CustomBreak.active = nil
            }
        }
        process(events: events, now: now, config: config)

        // Muzyka: fade-out zaczyna się 5 s PRZED końcem przerwy, tak aby
        // dźwięk milkł dokładnie w momencie jej zakończenia (nie po).
        if isOnBreak {
            let left = engine.remainingBreakTime(now: now)
            if left <= 5.2 {
                if !musicFadeStarted {
                    musicFadeStarted = true
                    relaxation.stop(fadeSeconds: min(5.0, max(0.4, left)))
                    Trace.log("relaxation: pre-end fade \(String(format: "%.1f", left))s")
                }
            } else {
                musicFadeStarted = false
            }
        } else {
            musicFadeStarted = false
        }

        publishGateReport(now: now)
        // Fetch the weather before the break so its effect is there from the first second.
        if !isOnBreak, let untilBreak = engine.timeUntilBreak(now: now), untilBreak <= 90 {
            WeatherController.shared.refreshIfNeeded()
        }
        refreshUI(now: now, config: config)

        // Break Actions — Before Due point (fires once per approaching break).
        breakActions.tick(now: now,
                         timeUntilBreak: engine.timeUntilBreak(now: now),
                         onBreak: isOnBreak,
                         paused: engine.isPaused)

        trackScreenTime(now: now)
        WorkLogController.shared.tick(now: now, secondsSinceInput: secondsSinceLastUserInput())
        nudgeBlinkIfDue(now: now)

        // Posture flash — only while genuinely working (not on break, not paused).
        flash.tick(now: now, canFlash: !isOnBreak && !engine.isPaused)
        reminders.tick(now: now, canRemind: !isOnBreak && !engine.isPaused) { [weak self] scheduled in
            self?.offerOrStart(scheduled)
        }
    }

    /// Adds the factors that live in the engine state, then hands the whole report to the Diagnostics pane.
    private func publishGateReport(now: Date) {
        let d = UserDefaults.standard
        var reasons: Set<PauseReason> = []
        var running = false
        switch engine.state {
        case .paused(let r): reasons = r
        case .working: running = true
        case .onBreak: break
        }
        gate("manual", .user, "Wstrzymanie ręczne", reasons.contains(.manual) ? .blocking : .inactive,
             reasons.contains(.manual) ? "timer wstrzymany przyciskiem lub skrótem" : "nie wstrzymano")
        if d.integer(forKey: Keys.idleDetection) == 0 {
            gate("idle", .user, "Brak aktywności", .inactive, "wykrywanie wyłączone")
        } else if reasons.contains(.userAway) {
            let minutes = awaySince.map { Int(now.timeIntervalSince($0) / 60) } ?? 0
            gate("idle", .user, "Brak aktywności", .blocking, L("brak ruchu myszy i klawiatury od %lld min", minutes))
        } else {
            gate("idle", .user, "Brak aktywności", .passing, "pracujesz przy komputerze")
        }
        GateDiagnostics.shared.update(GateReport(factors: gateFactors, running: running,
                                                 onBreak: engine.activeBreakKind != nil))
    }

    // MARK: - Break Rules

    /// Evaluate skip/postpone rules right before a break is due.
    /// First matching rule wins: postpone pushes the break back (re-checked
    /// every cycle until the condition clears), auto-skip records a skipped
    /// break and restarts the full cycle without showing the overlay.
    private func ruleDueCheck(now: Date, config: BreakConfig, rules: [BreakRule]) {
        for rule in rules {
            guard rule.outcome == .postpone || rule.outcome == .autoSkip else { continue }
            guard ruleConditionMatches(rule, now: now) else { continue }
            switch rule.outcome {
            case .postpone:
                let minutes = min(120, max(1, rule.postponeMinutes))
                engine.snooze(minutes: minutes, now: now)
                Trace.log("rule '\(rule.kind.rawValue)/\(rule.text)' matched -> postpone \(minutes) min")
            case .autoSkip:
                let kind = engine.previewNextKind(config: config)
                let rec = BreakRecord(kind: kind, startedAt: now)
                rec.endedAt = now
                rec.wasSkipped = true
                rec.outcomeRaw = BreakOutcome.ruleSkipped.rawValue
                context.insert(rec)
                _ = engine.skipUpcoming(now: now, config: config)
                PomodoroController.shared.complete(at: now)
                breakActions.fireNow(when: .afterPostpone)
                Trace.log("rule '\(rule.kind.rawValue)/\(rule.text)' matched -> auto skip")
            default:
                break
            }
            return
        }
    }

    // MARK: "Suggest a break now" rules

    private var suggestGates: [UUID: SuggestBreakGate] = [:]

    /// A `.suggestBreak` rule speaks up when its condition has held long enough (a build that is
    /// really long, a render that is really running), enough work has passed since the last break,
    /// and the cooldown allows it. It only offers — the user decides.
    private func evaluateSuggestion(_ rule: BreakRule, now: Date, config: BreakConfig) {
        let sustain = TimeInterval(max(5, rule.sustainSeconds))
        let cooldown = TimeInterval(max(1, rule.cooldownMinutes) * 60)
        var gate = suggestGates[rule.id] ?? SuggestBreakGate(sustainSeconds: sustain, cooldownSeconds: cooldown)
        if gate.sustainSeconds != sustain || gate.cooldownSeconds != cooldown {
            gate = SuggestBreakGate(sustainSeconds: sustain, cooldownSeconds: cooldown)
        }
        let canSpeak = !isOnBreak && !engine.isPaused
        let cycle = TimeInterval(config.cycleMinutes * 60)
        let worked = cycle - (engine.timeUntilBreak(now: now) ?? cycle)
        let met = canSpeak && ruleConditionMatches(rule, now: now)
        if gate.shouldOffer(conditionMet: met, workedSeconds: worked, now: now) {
            Trace.log("suggest-break: '\(rule.displayName)' held \(Int(sustain)) s — offering a break")
            post(title: "Dobra pora na przerwę",
                 body: L("%@: w tej chwili i tak nie musisz patrzeć na ekran. Zrobić krótką przerwę teraz?", rule.displayName),
                 symbol: "figure.cooldown",
                 actions: [ToastAction(title: "Zacznij przerwę") { [weak self] in
                               self?.takeShortNow(source: "rule-suggest")
                           },
                           ToastAction(title: "Nie teraz") {}])
        }
        suggestGates[rule.id] = gate
    }

    /// Condition check with a 5-second per-rule cache so expensive probes
    /// (EventKit, osascript) don't run on every heartbeat.
    private func ruleConditionMatches(_ rule: BreakRule, now: Date) -> Bool {
        if let hit = ruleEvalCache[rule.id], now.timeIntervalSince(hit.at) < 5 {
            return hit.hit
        }
        let hit = evaluateRuleCondition(rule)
        ruleEvalCache[rule.id] = (now, hit)
        return hit
    }

    private func evaluateRuleCondition(_ rule: BreakRule) -> Bool {
        let needle = rule.text.lowercased().trimmingCharacters(in: .whitespaces)
        let raw: Bool
        switch rule.kind {
        case .frontmostApp:
            if !needle.isEmpty, let front = NSWorkspace.shared.frontmostApplication {
                raw = nameMatch(needle, front.localizedName) || nameMatch(needle, front.bundleIdentifier)
            } else {
                raw = false
            }
        case .appOpen:
            if needle.isEmpty {
                raw = false
            } else {
                raw = NSWorkspace.shared.runningApplications.contains {
                    $0.activationPolicy == .regular &&
                    (nameMatch(needle, $0.localizedName) || nameMatch(needle, $0.bundleIdentifier))
                }
            }
        case .calendarText:
            raw = workDetector.calendarEventMatches(rule.text, now: Date())
        case .fullscreen:
            raw = frontmostWindowCoversScreen()
        case .screensaver:
            raw = screensaverActive()
        case .displayAsleep:
            raw = displayAsleep()
        case .focusActive:
            raw = focusNow(Date())
        case .meetingActive:
            raw = intelligence.meetingInProgress()
        case .videoActive:
            raw = intelligence.videoInProgress()
        case .script:
            raw = scriptRuleMatch(rule.text)
        }
        return rule.inverted ? !raw : raw
    }

    private func nameMatch(_ needle: String, _ hay: String?) -> Bool {
        guard let hay, !needle.isEmpty else { return false }
        return hay.lowercased().contains(needle)
    }

    /// Screensaver process running (legacyScreenSaver / ScreenSaverEngine).
    private func screensaverActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            guard let name = $0.localizedName?.lowercased() else { return false }
            return name == "screensaver" || name == "legacyscreensaver"
                || name == "screensaverengine"
        }
    }

    /// Any attached display currently powered off. CGDisplayIsAsleep was
    /// removed from public headers, so resolve the (still-present) symbol
    /// at runtime; degrade to "awake" when unavailable.
    private func displayAsleep() -> Bool {
        typealias AsleepFn = @convention(c) (UInt32) -> Bool
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGDisplayIsAsleep") else { return false }
        let fn = unsafeBitCast(sym, to: AsleepFn.self)
        var ids = [UInt32](repeating: 0, count: 4)
        var count: UInt32 = 4
        guard CGGetActiveDisplayList(4, &ids, &count) == .success, count > 0 else { return false }
        for i in 0..<Int(count) where !fn(ids[i]) { return false }
        return true
    }

    /// Frontmost app owns a window covering (nearly) a whole display —
    /// native fullscreen or a maximized video window.
    private func frontmostWindowCoversScreen() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == front.processIdentifier else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer >= 0 else { continue }
            guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let w = b["Width"] ?? 0, h = b["Height"] ?? 0
            for s in NSScreen.screens where w >= s.frame.width * 0.95 && h >= s.frame.height * 0.95 {
                return true
            }
        }
        return false
    }

    /// AppleScript rule: exit code 0 = condition true. Run asynchronously;
    /// the previous cached answer is used while the script executes (15 s TTL).
    private var scriptRuleCache: [String: (at: Date, hit: Bool)] = [:]
    private var scriptRuleRunning = false
    private func scriptRuleMatch(_ path: String) -> Bool {
        let p = path.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, FileManager.default.fileExists(atPath: p) else { return false }
        let now = Date()
        if let c = scriptRuleCache[p], now.timeIntervalSince(c.at) < 15 { return c.hit }
        guard !scriptRuleRunning else { return scriptRuleCache[p]?.hit ?? false }
        scriptRuleRunning = true
        // AppleScript rules now run under a 30 s supervised timeout (previously
        // unbounded); a rule script running longer is killed and counts as not matched.
        Task { [weak self] in
            let result = await ScriptRunner.run(path: p, timeout: ScriptRunner.ruleTimeout)
            // `return false` also exits 0 — the printed value decides (see ScriptRuleResult).
            let hit = ScriptRuleResult.isHit(exitStatus: result.status, output: result.stdout)
            self?.scriptRuleCache[p] = (Date(), hit)
            self?.scriptRuleRunning = false
        }
        return scriptRuleCache[p]?.hit ?? false
    }

    /// After the break: if the user tapped the tip banner on the break
    /// screen, open Settings with the full article (the
    /// article is read AFTER the break, never during it).
    private func openPendingMessageIfNeeded() {
        guard let id = pendingMessageID else { return }
        pendingMessageID = nil
        UserDefaults.standard.set(id, forKey: MessagesStore.pendingKey)
        AppDelegate.shared?.openSettingsWindow()
        NotificationCenter.default.post(name: .openMessage, object: id)
    }

    /// Shared handler for every event source (heartbeat or a panel button).
    private func process(events: [EngineEvent], now: Date, config: BreakConfig) {
        for event in events {
            log.info("event: \(String(describing: event), privacy: .public)")
            FocusShortcuts.handle(event)
            switch event {
            case .breakStarted(let kind):
                seamGate.reset()
                PomodoroController.shared.complete(at: now)
                let record = BreakRecord(kind: kind, startedAt: now)
                record.startedManually = manualStartPending
                manualStartPending = false
                context.insert(record)
                openRecord = record
                isOnBreak = true
                let done = fetchCompletedToday(now: now)
                // Assigned exercise, else the built-in tip rotation. With "Match the
                // break to the session" on, only the user's OWN assigned exercises
                // win over the advice (library rows are seeded as assigned).
                let assigned = assignedExercises(for: kind)
                let asContent: (Exercise) -> BreakContent = { BreakContent(headline: $0.title, detail: $0.detail) }
                let choice = BreakContentChoice.choose(
                    sessionAwareEnabled: UserDefaults.standard.integer(forKey: SessionAwareKeys.enabled) != 0,
                    customAssigned: {
                        assigned.filter { !ExerciseLibrary.isLibraryName($0.name) }.randomElement().map(asContent)
                    },
                    anyAssigned: { assigned.randomElement().map(asContent) },
                    advice: { sessionAdvice(kind: kind, now: now) },
                    resolve: { sessionAwareContent(for: $0, kind: kind) },
                    rotation: { BreakContent.content(kind: kind.rawValue, index: totalCompletedBreaks) })
                // Every third break: a weather-aware suggestion instead of the stock tip
                // (never over session-aware instructions, see applyingWeatherTip).
                var weatherTip: String?
                if UserDefaults.standard.object(forKey: "weatherTips") as? Bool ?? true,
                   totalCompletedBreaks % 3 == 2,
                   let wx = WeatherController.shared.snapshot, wx.isFresh {
                    weatherTip = WeatherAdvice.tip(effect: wx.effect, uvIndex: wx.uvIndex,
                                                   temperatureC: wx.temperatureC)
                }
                let content = CustomBreak.active.map {
                    BreakContent(headline: $0.label, detail: L("Przerwa %lld min", $0.seconds / 60))
                } ?? choice.applyingWeatherTip(weatherTip)
                // Text Theme takes over the content stage when on.
                let textTheme = TextThemeSnapshot.fromDefaults(seed: totalCompletedBreaks)
                // Image Theme (photos) may coexist — it renders behind the text.
                let imageTheme = ImageThemeSnapshot.fromDefaults(seed: totalCompletedBreaks)
                // "When Button Clicked" actions appear as buttons in the panel,
                // de-duplicated by title but keeping the configured order.
                var seenTitles = Set<String>()
                let buttonTitles: [String] = (BreakActionStore.decode(
                    UserDefaults.standard.data(forKey: BreakActionStore.storageKey)) ?? [])
                    .filter { $0.enabled && $0.when == .buttonClicked }
                    .map { $0.title }
                    .filter { seenTitles.insert($0).inserted }
                // Occasional tip banner on the break screen: it never pauses, extends or skips the break itself).
                let tipMessage = messages.messageForBreak(
                    breakIndex: totalCompletedBreaks,
                    enabled: UserDefaults.standard.integer(forKey: Keys.messagesDuringBreak) != 0)
                currentBreakMessage = tipMessage
                pendingMessageID = nil
                if let tipMessage {
                    Trace.log("message banner shown: \(tipMessage.id)")
                }
                // Before our own sound starts: only other apps' media is paused.
                MediaPauser.shared.breakWillStart()
                overlay?.show(kind: kind,
                             duration: engine.activeBreakTotal > 0 ? engine.activeBreakTotal : config.breakDuration(for: kind),
                             progressText: BreakStyleSettings.motivation.progressText(breakNumber: max(1, done)),
                             headline: L(content.headline),
                             detail: L(content.detail),
                             trend: BreakStyleSettings.motivation.showsTrendChart ? buildTrend(now: now) : [],
                             textTheme: textTheme,
                             imageTheme: imageTheme,
                             buttonTitles: buttonTitles,
                             messageHint: tipMessage?.breakHint,
                             onMessageOpen: { [weak self] in
                                 guard let id = self?.currentBreakMessage?.id else { return }
                                 self?.messages.markRead(id: id)
                                 self?.pendingMessageID = id
                             })
                if UserDefaults.standard.integer(forKey: Keys.playSound) != 0 {
                    NSSound(named: NSSound.Name(kind == .long ? "Funk" : "Glass"))?.play()
                }
                relaxation.startDuringBreak(kind: kind)
                if UserDefaults.standard.integer(forKey: Keys.preventSleepDuringBreak) != 0 {
                    sleepGuard.begin(reason: "Intermezzo break in progress")
                }
                scripts.breakDidStart()
                breakActions.breakDidStart()
            case .breakCompleted:
                openRecord?.endedAt = now
                openRecord?.outcomeRaw = BreakOutcome.completed.rawValue
                openRecord = nil
                isOnBreak = false
                totalCompletedBreaks += 1
                CustomBreak.active = nil
                relaxation.stop(fadeSeconds: 0.5)  // safety — fade ruszył 5 s wcześniej
                sleepGuard.end()
                scripts.breakDidEnd()
                breakActions.breakDidEnd(completed: true)
                MediaPauser.shared.breakDidEnd()
                openPendingMessageIfNeeded()
                overlay?.dismiss()
            case .breakSkipped(let kind):
                openRecord?.endedAt = now
                openRecord?.wasSkipped = true
                openRecord?.outcomeRaw = BreakOutcome.skipped.rawValue
                openRecord = nil
                isOnBreak = false
                _ = kind
                CustomBreak.active = nil
                relaxation.stop(fadeSeconds: 1.5)  // skip: szybkie wyciszenie
                sleepGuard.end()
                scripts.breakDidEnd()
                breakActions.breakDidEnd(completed: false)
                MediaPauser.shared.breakDidEnd()
                openPendingMessageIfNeeded()
                overlay?.dismiss()
            case .breakPostponed(let kind):
                openRecord?.endedAt = now
                openRecord?.wasSkipped = true
                openRecord?.outcomeRaw = BreakOutcome.postponed.rawValue
                openRecord?.postponeMinutes = pendingPostponeMinutes
                pendingPostponeMinutes = 0
                openRecord = nil
                isOnBreak = false
                _ = kind
                CustomBreak.active = nil
                relaxation.stop(fadeSeconds: 0.2)
                sleepGuard.end()
                scripts.breakDidEnd()
                breakActions.fireNow(when: .afterPostpone)
                MediaPauser.shared.breakDidEnd()
                overlay?.dismiss(animated: false)
            case .resumed:
                break
            }
        }
    }

    func refreshUI(now: Date, config: BreakConfig) {
        var isWorking = false
        if case .working = engine.state { isWorking = true }
        PomodoroController.shared.reconcile(isWorking: isWorking, minutes: config.cycleMinutes, now: now)
        // SwiftData query at most every 10 s — the number only moves when a
        // break actually completes; per-tick queries were pure CPU noise.
        if now.timeIntervalSince(lastStatsRefresh) >= 10 {
            lastStatsRefresh = now
            completedTodayCount = fetchCompletedToday(now: now)
        }
        if let kind = engine.activeBreakKind {
            let leftStr = TimeFormat.short(engine.remainingBreakTime(now: now))
            statusText = kind == .long ? String(localized: "Long break \(leftStr)") : String(localized: "Break \(leftStr)")
            statusSymbol = "cup.and.saucer.fill"
            headlineText = kind == .long ? String(localized: "Long break ends in") : String(localized: "Break ends in")
            countdownText = leftStr
            let total = engine.activeBreakTotal > 0 ? engine.activeBreakTotal : config.breakDuration(for: kind)
            setRing(1 - engine.remainingBreakTime(now: now) / max(total, 1))
            setPauseReason("")
            // The fullscreen overlay owns the screen during a break —
            // the cursor popup must disappear with it.
            cursorCountdown?.update(text: nil)
            edgeGlow.hide()
        } else if engine.isPaused {
            statusText = String(localized: "Paused")
            statusSymbol = "pause.circle"
            headlineText = String(localized: "Breaks paused")
            countdownText = "—:—"
            setRing(0)
            setPauseReason(describePause())
            cursorCountdown?.update(text: nil)
            edgeGlow.hide()
        } else if let left = engine.timeUntilBreak(now: now) {
            if left < 180 { WeatherController.shared.refreshIfNeeded() }   // scene ready before the break
            // Compact so the item never gets hidden by menu-bar overflow/notch:
            // the button shows a state icon (timer/cup/pause) + MM:SS countdown.
            statusText = TimeFormat.short(left)
            statusSymbol = "timer"
            headlineText = String(localized: "Next break in")
            countdownText = TimeFormat.short(left)
            setRing(1 - left / max(TimeInterval(config.cycleMinutes * 60), 1))
            setPauseReason("")
            let glowLead = TimeInterval(max(10, UserDefaults.standard.integer(forKey: Keys.breakLeadPopup)))
            edgeGlow.update(progress: overdueGlow ?? (BreakStyleSettings.edgeGlow && left <= glowLead ? 1 - left / glowLead : nil))
            // Cursor reminder: chip while there is time,
            // interactive "start soon" popup inside the configured lead window.
            if UserDefaults.standard.integer(forKey: Keys.cursorCountdown) != 0 {
                let lead = TimeInterval(max(10, UserDefaults.standard.integer(forKey: Keys.breakLeadPopup)))
                if left <= lead {
                    let kindWord = L(engine.previewNextKind(config: config) == .long ? "długa" : "krótka")
                    cursorCountdown?.update(text: TimeFormat.short(left),
                                           headline: String(localized: "Za chwilę \(kindWord) przerwa"),
                                           urgent: true,
                                           progress: 1.0 - (left / lead))
                } else {
                    // Outside the lead window: nothing at the cursor — the ring
                    // + card appear only in the last `lead` seconds.
                    cursorCountdown?.update(text: nil)
                }
            } else {
                cursorCountdown?.update(text: nil)
            }
        }
        let nextKind = engine.previewNextKind(config: config)
        let nextName = nextKind == .long ? String(localized: "DŁUGA") : String(localized: "krótka")
        completedTodayDisplay = String(localized: "Dziś wykonane: \(completedTodayCount) · następna: \(nextName)")
        do {
            if context.hasChanges { try context.save() }
        } catch {
            log.error("context.save failed: \(error, privacy: .public)")
        }
    }

    private func setRing(_ value: Double) {
        let v = min(1, max(0, value))
        if abs(v - ringProgress) > 0.001 { ringProgress = v }
    }

    private func setPauseReason(_ text: String) {
        if text != pauseReasonText { pauseReasonText = text }
    }

    /// Most relevant active pause reason, localized, for the panel/status.
    private func describePause() -> String {
        guard case .paused(let reasons) = engine.state else { return "" }
        let order: [(PauseReason, String)] = [
            (.manual, String(localized: "Wstrzymane ręcznie")), (.vacation, String(localized: "Urlop")),
            (.holiday, String(localized: "Święto")),
            (.outsideWorkingHours, String(localized: "Poza godzinami pracy")),
            (.outsideWorkZone, String(localized: "Poza strefą pracy")),
            (.inMeeting, String(localized: "Spotkanie")), (.watchingVideo, String(localized: "Wideo")),
            (.inFocusMode, String(localized: "Tryb Skupienia")),
            (.ruleMatch, String(localized: "Reguła wstrzymuje")), (.userAway, String(localized: "Brak aktywności")),
        ]
        return order.first { reasons.contains($0.0) }?.1 ?? String(localized: "Wstrzymane")
    }

    // MARK: User actions

    /// Settings > Appearance weather previews: a few seconds of the scene on screen with the
    /// configured themes, chime and relaxation audio. Click-through and invisible to the
    /// engine (no record, actions, scripts or Focus).
    func previewWeatherScene() {
        guard !isOnBreak, overlay?.isPresenting != true else { return }
        Trace.log("weather scene preview")
        let seed = totalCompletedBreaks
        overlay?.show(kind: .short, duration: Self.previewSeconds,
                      headline: L("Podgląd sceny"),
                      detail: L("Przezroczysty dla myszy, zniknie sam."),
                      trend: buildTrend(now: Date()),
                      textTheme: TextThemeSnapshot.fromDefaults(seed: seed),
                      imageTheme: ImageThemeSnapshot.fromDefaults(seed: seed),
                      preview: true)
        if UserDefaults.standard.integer(forKey: Keys.playSound) != 0 {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        relaxation.startDuringBreak(kind: .short)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewSeconds) { [weak self] in
            guard let self, !self.isOnBreak else { return }
            self.relaxation.stop(fadeSeconds: 1.0)
        }
    }
    private static let previewSeconds: TimeInterval = 8

    /// A fixed-time break is due: start it, or (when asked to) offer it in a notification first.
    private func offerOrStart(_ scheduled: ScheduledBreak) {
        guard scheduled.askFirst else { startScheduled(scheduled); return }
        ToastCenter.shared.show(
            title: scheduled.label,
            body: scheduled.customMinutes.map { L("Przerwa %lld min", $0) } ?? L(scheduled.isLong ? "Długa przerwa" : "Krótka przerwa"),
            symbol: "fork.knife",
            actions: [ToastAction(title: "Zacznij") { [weak self] in self?.startScheduled(scheduled) },
                      ToastAction(title: "Nie teraz") {}])
    }

    private func startScheduled(_ scheduled: ScheduledBreak) {
        guard !isOnBreak else { return }
        if let minutes = scheduled.customMinutes {
            CustomBreak.active = (scheduled.label, max(1, minutes) * 60)
            takeShortNow(source: "scheduled: \(scheduled.label)")
        } else if scheduled.isLong {
            takeLongNow(source: "scheduled: \(scheduled.label)")
        } else {
            takeShortNow(source: "scheduled: \(scheduled.label)")
        }
    }

    func takeShortNow(source: String = "ui") {
        Trace.log("break NOW requested (short) via \(source)")
        takeNow(.short, source: source)
    }
    func takeLongNow(source: String = "ui") {
        Trace.log("break NOW requested (long) via \(source)")
        takeNow(.long, source: source)
    }

    /// Set around a user-requested start so `.breakStarted` can mark the record (hand icon on the trend).
    private var manualStartPending = false
    /// Minutes of the +1 / +5 that is closing the live break, for `.breakPostponed`.
    private var pendingPostponeMinutes = 0

    private func takeNow(_ kind: BreakKind, source: String) {
        manualStartPending = !source.hasPrefix("scheduled")
        act { engine.takeBreakNow(kind: kind, now: Date(), config: currentConfig()) }
        manualStartPending = false
    }

    /// +1 / +5 postpone a break that is on screen or about to be: during the break, or inside the lead window
    /// of the "break soon" card. Far from a break they would only push the timer by hours.
    var canSnoozeNow: Bool {
        if engine.activeBreakKind != nil { return true }
        guard let left = engine.timeUntilBreak(now: Date()) else { return false }
        return left <= TimeInterval(max(10, UserDefaults.standard.integer(forKey: Keys.breakLeadPopup)))
    }

    /// +1 / +5: while working = postpone the break (snooze); while on a live
    /// break = CLOSE the popup instantly and show the next one in N minutes
    /// ("skip this one, ask me again later" — user-requested semantics).
    func snooze(minutes: Int) {
        guard canSnoozeNow else {
            Trace.log("snooze refused: no break on screen or about to start")
            ToastCenter.shared.show(title: "Odroczenie działa tuż przed przerwą",
                                    body: "Można odłożyć przerwę, która trwa albo zaraz się zacznie.",
                                    symbol: "hourglass")
            return
        }
        if BreakStyleSettings.snoozesLeft() == 0 {
            Trace.log("snooze refused: daily limit used up")
            ToastCenter.shared.show(title: "Limit odroczeń na dziś wykorzystany",
                                    body: "Poziom surowości możesz zmienić w Przerwy › Podejście do przerw.",
                                    symbol: "hourglass.bottomhalf.filled")
            return
        }
        BreakStyleSettings.consumeSnooze()
        if engine.activeBreakKind != nil {
            Trace.log("postpone: closing live break, next popup in \(minutes) min")
            pendingPostponeMinutes = minutes
            act { engine.postponeBreak(minutes: minutes, now: Date()) }
            pendingPostponeMinutes = 0
        } else {
            Trace.log("snooze +\(minutes) min (break was due sooner)")
            engine.snooze(minutes: minutes, now: Date())
            refreshUI(now: Date(), config: currentConfig())
        }
    }

    /// "a, b ,c" -> ["a","b","c"] lowercased, trimmed, empty dropped.
    private func csvList(_ raw: String?) -> [String] {
        (raw ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var lastZoneState = true

    /// Focus/DND probe, 20 s throttled (plain JSON file read).
    private var focusState = false
    private var lastFocusProbe = Date.distantPast
    private var focusSnapshotCache: (at: Date, value: WorkDetector.FocusSnapshot?)?
    private func focusSnapshot(_ now: Date) -> WorkDetector.FocusSnapshot? {
        if let cache = focusSnapshotCache, now.timeIntervalSince(cache.at) < 20 { return cache.value }
        let value = WorkDetector.focusSnapshot()
        focusSnapshotCache = (now, value)
        return value
    }

    private func focusNow(_ now: Date) -> Bool {
        if now.timeIntervalSince(lastFocusProbe) > 20 {
            lastFocusProbe = now
            focusState = WorkDetector.detectFocus()
        }
        return focusState
    }

    func handleSkip(source: String = "ui") {
        if engine.activeBreakKind != nil {
            Trace.log("skip live break via \(source) — next reminder in \(currentConfig().cycleMinutes) min")
            act { engine.skipBreak(now: Date(), config: currentConfig()) }
        } else if !engine.isPaused, engine.timeUntilBreak(now: Date()) != nil {
            // Skip z karty przed pauzą ("przełóż"): przerwa jeszcze
            // nie wystartowała — kasujemy nadchodzącą i resetujemy cykl.
            let now = Date()
            let config = currentConfig()
            let kind = engine.previewNextKind(config: config)
            let rec = BreakRecord(kind: kind, startedAt: now)
            rec.endedAt = now
            rec.wasSkipped = true
            rec.outcomeRaw = BreakOutcome.skippedAhead.rawValue
            context.insert(rec)
            _ = engine.skipUpcoming(now: now, config: config)
            PomodoroController.shared.complete(at: now)
            breakActions.fireNow(when: .afterPostpone)
            Trace.log("skip upcoming break from reminder card (kind=\(kind == .long ? "long" : "short")) via \(source) — next reminder in \(config.cycleMinutes) min")
            refreshUI(now: now, config: config)
        }
    }

    /// Fire Break Actions of kind buttonClicked whose title matches (used by
    /// the overlay Water button and by intermezzo://button/<title> automation).
    func fireButtonTitle(_ title: String) {
        breakActions.fireButtonAction(title: title)
    }

    /// "Pause All Indefinitely": freeze the timer until the
    /// user explicitly resumes.
    func pauseAll() {
        Trace.log("pauseAll (next break was in \(Int(engine.timeUntilBreak(now: Date()) ?? -1))s)")
        engine.pause(reason: .manual)
        seamGate.reset()
        refreshUI(now: Date(), config: currentConfig())
    }

    /// "Resume All Breaks": drop the manual pause and continue the countdown.
    func resumeAll() {
        Trace.log("resumeAll")
        act { engine.resume(reason: .manual) }
        Trace.log("resumed; engine.isPaused=\(engine.isPaused)")
    }

    /// "Reset All Breaks": restart the countdown at full cycle length.
    func resetAll() {
        let before = engine.timeUntilBreak(now: Date()) ?? -1
        engine.resetCycle(now: Date(), config: currentConfig())
        seamGate.reset()
        PomodoroController.shared.abandon(at: Date())
        Trace.log("resetAll: \(Int(before))s -> \(Int(engine.timeUntilBreak(now: Date()) ?? -1))s")
        refreshUI(now: Date(), config: currentConfig())
    }

    /// "Stop Sound": silence anything this app is currently playing.
    func stopSounds() {
        Trace.log("stopSounds")
        breakActions.stopAllSounds()
        relaxation.stop()
    }

    /// Show the evening Clock-Out panel with the user's custom texts.
    private func showClockOutOverlay() {
        let d = UserDefaults.standard
        // Untouched defaults are keys, so they follow the app language; custom texts pass through.
        let title = L(d.string(forKey: Keys.clockOutTitle) ?? "Time to Switch Off")
        let msg = L(d.string(forKey: Keys.clockOutMessage) ?? "Zakończ pracę.")
        clockOutOverlay?.show(title: title, message: msg)
    }

    /// Run an engine action and feed any resulting events to the shared
    /// handler (same path the heartbeat uses), then refresh the UI.
    private func act(_ action: () -> EngineEvent?) {
        let now = Date()
        let config = currentConfig()
        if let event = action() {
            process(events: [event], now: now, config: config)
        }
        refreshUI(now: now, config: config)
    }

    func togglePause() {
        if engine.activeBreakKind != nil {
            // Live break: toggle the pause that will apply when it ends.
            if engine.isPausePending(.manual) { engine.resume(reason: .manual) }
            else { engine.pause(reason: .manual) }
        } else if engine.isPaused {
            act { engine.resume(reason: .manual) }
        } else {
            engine.pause(reason: .manual)
            refreshUI(now: Date(), config: currentConfig())
        }
    }

    var engineIsPaused: Bool { engine.isPaused }

    // MARK: Helpers

    private func fetchCompletedToday(now: Date) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        // fetchCount may ignore unsaved inserts (the break that just started).
        if context.hasChanges { try? context.save() }
        let descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { !$0.wasSkipped && $0.startedAt >= start && $0.kindRaw != "natural" })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Recent break activity (last 10 records, oldest first) for the
    /// trend chart drawn on the break overlay and in Settings › Status.
    func buildTrend(now: Date) -> [BreakMarker] {
        var descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { $0.kindRaw != "natural" },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 10
        // A break still running on another Mac (synced) is not this overlay's business.
        let me = SyncIdentity.deviceID
        let recent = ((try? context.fetch(descriptor)) ?? []).filter { $0.endedAt != nil || $0.origin == me }.reversed()
        let config = currentConfig()
        let short = config.shortBreakSeconds
        return recent.map { r in
            let planned = r.kind == .long ? config.longBreakSeconds : short
            // The break that is running right now has no outcome yet: show it as under way (completed).
            let outcome: BreakOutcome = r.endedAt == nil ? .completed : r.outcome
            return BreakMarker(minutesAgo: now.timeIntervalSince(r.startedAt) / 60.0,
                               wasSkipped: outcome.lowersMomentum,
                               durationSeconds: r.endedAt.map { Int($0.timeIntervalSince(r.startedAt)) } ?? 0,
                               weight: BreakMomentum.weight(seconds: planned, shortSeconds: short),
                               startedAt: r.startedAt,
                               outcome: outcome,
                               isRunning: r.endedAt == nil,
                               postponeMinutes: r.postponeMinutes,
                               startedManually: r.startedManually)
        }
    }

    func secondsSinceLastUserInput() -> TimeInterval {
        let anyEvent = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    }

    // MARK: Eye-health helpers

    /// Active = the user touched the Mac within the last 2 minutes and is not on a break.
    private var userIsActive: Bool { !isOnBreak && secondsSinceLastUserInput() < 120 }

    /// Counts active screen time, flushed every 15 s; one toast per day past 4 h.
    private func trackScreenTime(now: Date) {
        if userIsActive { pendingScreenSeconds += 1 }
        guard pendingScreenSeconds >= 15 else { return }
        let crossed = screenTime.add(seconds: pendingScreenSeconds, now: now)
        pendingScreenSeconds = 0
        screenTimeToday = ScreenTimeStore.format(seconds: screenTime.seconds(now: now))
        if crossed {
            post(title: "4 godziny przy ekranie",
                 body: "Dziś to już ok. 4 h aktywnej pracy przy Macu — zrób dłuższą przerwę bez ekranu: ruch, światło dzienne, dal.",
                 symbol: "display")
        }
    }

    private func nudgeBlinkIfDue(now: Date) {
        let d = UserDefaults.standard
        guard d.integer(forKey: "blinkNudge") != 0, !engine.isPaused, userIsActive else { return }
        let minutes = max(1, d.integer(forKey: "blinkNudgeMinutes"))
        guard now.timeIntervalSince(lastBlinkNudge) >= TimeInterval(minutes * 60) else { return }
        lastBlinkNudge = now
        sendBlinkNudge()
    }

    func sendBlinkNudge() {
        post(title: "Zamrugaj", body: "10 pełnych, wolnych mrugnięć — powieka do powieki.", symbol: "eye")
    }

    /// Self-test for the notification pipeline (intermezzo://notify, Status pane).
    func sendTestNotification() {
        post(title: "Intermezzo", body: L("Powiadomienia działają. Następna przerwa za %@.", countdownText),
             symbol: "checkmark.seal.fill")
    }

    /// Central notification entry point. `notifyStyle`: "toast" (default, themed
    /// in-app popup), "system" (Notification Center) or "both".
    func post(title: String, body: String, symbol: String = "bell.fill",
              actions: [ToastAction] = []) {
        let style = UserDefaults.standard.string(forKey: "notifyStyle") ?? "toast"
        if style != "system" {
            ToastCenter.shared.show(title: title, body: body, symbol: symbol, actions: actions)
        }
        if style != "toast" {
            SystemNotificationActions.shared.send(title: L(title), body: L(body), actions: actions.map { ToastAction(title: L($0.title), handler: $0.handler) })
        }
    }

    private func notify(title: String, body: String) {
        post(title: title, body: body)
    }

    /// Adds a completed break to the history and restarts the work cycle
    /// ("Zalicz przerwę" after a long absence).
    /// A long absence (lunch, a walk) is kept as a break of its own kind, outside the regular break statistics.
    private func logNaturalBreak(away: TimeInterval, now: Date) {
        let d = UserDefaults.standard
        guard d.integer(forKey: NaturalBreakKeys.enabled) != 0,
              NaturalBreak.shouldLog(awaySeconds: away, minMinutes: d.integer(forKey: NaturalBreakKeys.minMinutes)) else { return }
        context.insert(BreakRecord.natural(from: now.addingTimeInterval(-away), to: now))
        Trace.log("natural break logged: \(Int(away / 60)) min away")
    }

    func creditBreak(away: TimeInterval) {
        let now = Date()
        let rec = BreakRecord(kind: .short, startedAt: now.addingTimeInterval(-away))
        rec.endedAt = now
        context.insert(rec)
        totalCompletedBreaks += 1
        engine.resetCycle(now: now, config: currentConfig())
        refreshUI(now: now, config: currentConfig())
        Trace.log("credited away time as a break (\(Int(away)) s)")
    }
}

enum TimeFormat {
    static func short(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

extension BreakEngine {
    /// Remaining time of an active break (Kit-side convenience for UI).
    func remainingBreakTime(now: Date) -> TimeInterval {
        switch self.stateSnapshot {
        case .onBreak(_, let until): return max(0, until.timeIntervalSince(now))
        default: return 0
        }
    }

    private var stateSnapshot: EngineState { state }
}
