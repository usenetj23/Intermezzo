import Foundation

extension FocusEvent {
    /// Starts may be superseded by a later end; an end is never dropped.
    public var isStart: Bool { self != .breakEnd }

    /// Focus events caused by one engine event. Every way a live break ends
    /// (completed, skipped, postponed) maps to `.breakEnd`.
    public static func events(for engineEvent: EngineEvent) -> [FocusEvent] {
        switch engineEvent {
        case .breakStarted: return [.breakStart]
        case .breakCompleted, .breakSkipped, .breakPostponed: return [.breakEnd]
        case .resumed: return []
        }
    }
}

/// One queued run: the event and the shortcut name captured when it fired.
public struct FocusShortcutJob: Equatable, Sendable {
    public let event: FocusEvent
    public let name: String

    public init(event: FocusEvent, name: String) {
        self.event = event
        self.name = name
    }
}

/// Serialises every Focus shortcut run through ONE FIFO queue, so a break-end
/// shortcut can never finish before the break-start one it follows.
///
/// - One slot at a time; the runner does both the `shortcuts list` check and
///   the `shortcuts run` inside the slot. Worst case per slot: list ≤ 10 s
///   (+ 2 s kill grace) + run ≤ 10 s (+ 2 s) ≈ 24 s, so a queued event can wait
///   about that long per job ahead of it (at most 2 ahead after pruning).
/// - A newly queued END removes the START jobs still pending before it (Focus
///   would be switched on only to be switched off again). A START already
///   running is not interrupted; the END runs after it.
/// - Queuing the same event as the pending tail coalesces into one job (the
///   newer name wins). An event is never dropped just because the same event
///   is running — it is queued behind it.
/// - Owed END: once a break-START shortcut has begun running, exactly one END
///   is owed. It goes through even when the user turns the feature off in the
///   meantime (otherwise Focus would stay in its break state). `isEnabled` is
///   re-checked before every job: with the feature off, every job except that
///   owed END is dropped. The debt lives in memory only — quitting the app
///   during a break cannot send the END.
public actor FocusShortcutQueue {
    public typealias Runner = @Sendable (FocusShortcutJob) async -> Result<Void, FocusShortcutError>
    /// Called with `nil` when a job starts and with its result when it ends.
    public typealias Observer = @Sendable (FocusShortcutJob, Result<Void, FocusShortcutError>?) async -> Void

    private let runner: Runner
    private let observer: Observer
    private let isEnabled: @Sendable () -> Bool
    /// A break START began running and its END has not run yet.
    public private(set) var endOwed = false
    public private(set) var pending: [FocusShortcutJob] = []
    public private(set) var current: FocusShortcutJob?
    private var draining = false

    public init(runner: @escaping Runner, observer: @escaping Observer = { _, _ in },
                isEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.runner = runner
        self.observer = observer
        self.isEnabled = isEnabled
    }

    public var isIdle: Bool { !draining && pending.isEmpty && current == nil }

    /// Queues `event` if a usable shortcut is configured and either the feature
    /// is on or this is the END owed to a START that ran. Returns false (and
    /// queues nothing) otherwise.
    @discardableResult
    public func submit(_ event: FocusEvent, enabled: Bool, settings: [FocusEvent: String]) -> Bool {
        guard enabled || (event == .breakEnd && endOwed),
              let name = ShortcutPlan.shortcut(for: event, settings: settings) else { return false }
        enqueue(FocusShortcutJob(event: event, name: name))
        return true
    }

    public func enqueue(_ job: FocusShortcutJob) {
        var next = pending
        if !job.event.isStart { next.removeAll { $0.event.isStart } }
        if let tail = next.last, tail.event == job.event {
            next[next.count - 1] = job
        } else {
            next.append(job)
        }
        pending = next
        guard !draining else { return }
        draining = true
        Task { await self.drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            if !isEnabled() && !(job.event == .breakEnd && endOwed) { continue }
            if job.event == .breakStart { endOwed = true }
            if job.event == .breakEnd { endOwed = false }
            current = job
            await observer(job, nil)
            let result = await runner(job)
            current = nil
            await observer(job, result)
        }
        draining = false
    }
}
