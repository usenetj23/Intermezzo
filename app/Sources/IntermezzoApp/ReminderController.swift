import AppKit
import IntermezzoKit

/// Runs the user's micro-reminders and fixed-time breaks from the coordinator heartbeat.
@MainActor
final class ReminderController {
    static let microKey = "microReminders"
    static let scheduledKey = "scheduledBreaks"

    private let launchedAt = Date()
    private var lastShown: [UUID: Date] = [:]
    private var lastFired: [UUID: Date] = [:]

    /// `canRemind`: working, not on a break, not paused. `startBreak` is called for a due fixed-time break.
    func tick(now: Date, canRemind: Bool, startBreak: (ScheduledBreak) -> Void) {
        guard canRemind else { return }
        let d = UserDefaults.standard
        for r in ReminderSchedule.dueMicro(MicroReminder.decodeList(d.data(forKey: Self.microKey)),
                                           lastShown: lastShown, since: launchedAt, now: now) {
            lastShown[r.id] = now
            Trace.log("micro-reminder: \(r.title)")
            ToastCenter.shared.show(title: r.title, body: "Przypomnienie", symbol: r.symbol)
            if d.integer(forKey: Keys.playSound) != 0 { NSSound(named: NSSound.Name("Pop"))?.play() }
        }
        for b in ReminderSchedule.dueScheduled(ScheduledBreak.decodeList(d.data(forKey: Self.scheduledKey)),
                                               lastFired: lastFired, now: now, calendar: .current) {
            lastFired[b.id] = now
            Trace.log("scheduled break: \(b.label)")
            startBreak(b)
        }
    }
}
