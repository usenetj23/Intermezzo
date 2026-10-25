import AppKit
import IntermezzoKit

/// UserDefaults keys of reminder-only mode.
enum ReminderOnlyKeys {
    /// Int flag, default 0 (off): a due break is announced, never forced on the screen.
    static let enabled = "reminderOnlyMode"
    /// Int minutes between stronger nudges while the reminder is ignored.
    static let repeatMinutes = "reminderRepeatMinutes"
    static let defaultRepeat = 10
    static let repeatRange = 3...30
}

/// Reminder-only mode (RestStop style): when a break is due, nothing covers the screen.
/// A gentle toast and chime come first; while ignored, stronger nudges and a red edge glow follow
/// until the user starts a break, says they had one, or steps away long enough to reset the cycle.
extension BreakCoordinator {
    private var reminderOnlyEnabled: Bool {
        UserDefaults.standard.integer(forKey: ReminderOnlyKeys.enabled) != 0
    }

    private var repeatInterval: TimeInterval {
        let range = ReminderOnlyKeys.repeatRange
        let stored = UserDefaults.standard.integer(forKey: ReminderOnlyKeys.repeatMinutes)
        let minutes = stored == 0 ? ReminderOnlyKeys.defaultRepeat : min(range.upperBound, max(range.lowerBound, stored))
        return TimeInterval(minutes * 60)
    }

    /// Called once per heartbeat right before `engine.tick`. Keeps the break "not started" while it is due.
    func applyReminderOnly(now: Date) {
        guard reminderOnlyEnabled, !isOnBreak, !engine.isPaused,
              let left = engine.timeUntilBreak(now: now) else {
            clearReminderOnly()
            return
        }
        if left > Self.seamRearmWindow {
            clearReminderOnly()
            return
        }
        guard left <= Self.seamDueWindow else { return }

        engine.holdBreak(seconds: Self.seamHoldSeconds, now: now)
        guard let step = reminderEscalation.advance(now: now, repeatEvery: repeatInterval) else { return }
        let kindWord = L(engine.previewNextKind(config: currentConfig()) == .long ? "długa" : "krótka")
        switch step {
        case .gentle:
            Trace.log("reminder-only: gentle reminder")
            nudge(title: "Czas na przerwę", body: L("Za chwilę %@ przerwa. Nic Cię nie blokuje.", kindWord), sound: "Glass")
        case .stronger(let level):
            Trace.log("reminder-only: ignored, nudge level \(level)")
            nudge(title: "Przerwa wciąż czeka", body: L("Minęło już trochę czasu. Zrób %@ przerwę albo ją odłóż.", kindWord), sound: "Sosumi")
        }
        overdueGlow = reminderEscalation.glowProgress
    }

    private func clearReminderOnly() {
        guard reminderEscalation != ReminderEscalation() || overdueGlow != nil else { return }
        reminderEscalation.reset()
        overdueGlow = nil
    }

    private func nudge(title: String, body: String, sound: String) {
        ToastCenter.shared.show(
            title: title, body: body, symbol: "bell.badge.fill",
            actions: [ToastAction(title: "Zacznij przerwę") { [weak self] in self?.takeShortNow(source: "reminder-only") },
                      ToastAction(title: "Zrobiłem przerwę") { [weak self] in self?.acknowledgeBreakTaken() },
                      ToastAction(title: "+5 min") { [weak self] in self?.snooze(minutes: 5) }])
        if UserDefaults.standard.integer(forKey: Keys.playSound) != 0 {
            NSSound(named: NSSound.Name(sound))?.play()
        }
    }

    /// "I already took one": counts as a completed break and restarts the work cycle.
    func acknowledgeBreakTaken() {
        let now = Date()
        let config = currentConfig()
        let record = BreakRecord(kind: engine.previewNextKind(config: config), startedAt: now)
        record.endedAt = now
        record.outcomeRaw = BreakOutcome.completed.rawValue
        record.startedManually = true
        context.insert(record)
        engine.resetCycle(now: now, config: config)
        clearReminderOnly()
        Trace.log("reminder-only: user says a break was taken")
        refreshUI(now: now, config: config)
    }
}
