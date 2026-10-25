import XCTest
@testable import IntermezzoKit

/// Runner whose every call blocks until the test releases it.
private final class ControlledRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var startedEvents: [FocusEvent] = []
    private var gates: [CheckedContinuation<Void, Never>] = []

    var started: [FocusEvent] { lock.lock(); defer { lock.unlock() }; return startedEvents }
    var waiting: Int { lock.lock(); defer { lock.unlock() }; return gates.count }

    func run(_ job: FocusShortcutJob) async -> Result<Void, FocusShortcutError> {
        lock.lock(); startedEvents.append(job.event); lock.unlock()
        await withCheckedContinuation { c in
            lock.lock(); gates.append(c); lock.unlock()
        }
        return .success(())
    }

    func release() {
        lock.lock()
        let gate = gates.isEmpty ? nil : gates.removeFirst()
        lock.unlock()
        gate?.resume()
    }
}

private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<2000 {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("condition not met in time", file: file, line: line)
}

final class FocusShortcutQueueTests: XCTestCase {

    private let settings: [FocusEvent: String] = [
        .sessionStart: "Work", .breakStart: "Rest", .breakEnd: "Back",
    ]

    private func submit(_ queue: FocusShortcutQueue, _ event: FocusEvent) async {
        let accepted = await queue.submit(event, enabled: true, settings: settings)
        XCTAssertTrue(accepted)
    }

    func testEndEnqueuedWhileStartRunsRunsAfterIt() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        await submit(queue, .breakStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakEnd)
        XCTAssertEqual(runner.started, [.breakStart], "one run at a time")
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 2 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.breakStart, .breakEnd])
    }

    func testPendingStartIsDroppedByEnd() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        await submit(queue, .sessionStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakStart)
        await submit(queue, .breakEnd)
        let pending = await queue.pending.map(\.event)
        XCTAssertEqual(pending, [.breakEnd])
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 2 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.sessionStart, .breakEnd])
    }

    func testDuplicateEndIsCoalesced() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        await submit(queue, .sessionStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakEnd)
        await submit(queue, .breakEnd)
        let pending = await queue.pending.map(\.event)
        XCTAssertEqual(pending, [.breakEnd])
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 2 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.sessionStart, .breakEnd])
    }

    func testSameEventWhileRunningIsQueuedNotDropped() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        await submit(queue, .breakEnd)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakEnd)
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 2 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.breakEnd, .breakEnd])
    }

    func testSessionStartBreakStartBreakEndKeepOrder() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        await submit(queue, .sessionStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakStart)   // queued behind the running start
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 2 }
        await submit(queue, .breakEnd)     // breakStart already running: kept
        runner.release()
        await waitUntil { runner.waiting == 1 && runner.started.count == 3 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.sessionStart, .breakStart, .breakEnd])
    }

    func testFlagOffEnqueuesNothing() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        let accepted = await queue.submit(.breakStart, enabled: false, settings: settings)
        XCTAssertFalse(accepted)
        let idle = await queue.isIdle
        XCTAssertTrue(idle)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(runner.started, [])
    }

    func testUnconfiguredEventEnqueuesNothing() async {
        let runner = ControlledRunner()
        let queue = FocusShortcutQueue(runner: runner.run)
        let accepted = await queue.submit(.breakStart, enabled: true, settings: [.breakStart: "  "])
        XCTAssertFalse(accepted)
        let idle = await queue.isIdle
        XCTAssertTrue(idle)
    }

    func testObserverSeesStartThenResult() async {
        let log = ObserverLog()
        let queue = FocusShortcutQueue(runner: { _ in .failure(.timedOut) },
                                       observer: { job, result in log.add(job.event, result) })
        await submit(queue, .breakEnd)
        await waitUntil { await queue.isIdle && log.entries.count == 2 }
        XCTAssertEqual(log.entries.map(\.0), [.breakEnd, .breakEnd])
        XCTAssertNil(log.entries[0].1)
        XCTAssertEqual(log.entries[1].1, .timedOut)
    }

    // MARK: - Owed END after the feature is turned off

    private func flagged(_ runner: ControlledRunner, _ flag: FlagBox) -> FocusShortcutQueue {
        FocusShortcutQueue(runner: runner.run, isEnabled: { flag.value })
    }

    func testStartThenFlagOffThenEndStillRunsTheEnd() async {
        let runner = ControlledRunner()
        let flag = FlagBox(true)
        let queue = flagged(runner, flag)
        await submit(queue, .breakStart)
        await waitUntil { runner.waiting == 1 }
        runner.release()
        await waitUntil { await queue.isIdle }
        flag.value = false
        let accepted = await queue.submit(.breakEnd, enabled: false, settings: settings)
        XCTAssertTrue(accepted, "the END owed to a START that ran goes through")
        await waitUntil { runner.waiting == 1 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.breakStart, .breakEnd])
        let again = await queue.submit(.breakEnd, enabled: false, settings: settings)
        XCTAssertFalse(again, "exactly one owed END")
    }

    func testFlagOffDropsPendingStartsButOwedEndRuns() async {
        let runner = ControlledRunner()
        let flag = FlagBox(true)
        let queue = flagged(runner, flag)
        await submit(queue, .breakStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .sessionStart)            // pending behind the running START
        flag.value = false
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.breakStart], "pending START dropped once the flag is off")
        let accepted = await queue.submit(.breakEnd, enabled: false, settings: settings)
        XCTAssertTrue(accepted)
        await waitUntil { runner.waiting == 1 }
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.breakStart, .breakEnd])
    }

    func testFlagOffWithNothingOwedRunsNothing() async {
        let runner = ControlledRunner()
        let flag = FlagBox(true)
        let queue = flagged(runner, flag)
        await submit(queue, .sessionStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakStart)              // pending, never runs
        flag.value = false
        runner.release()
        await waitUntil { await queue.isIdle }
        let accepted = await queue.submit(.breakEnd, enabled: false, settings: settings)
        XCTAssertFalse(accepted, "the dropped START never ran, so no END is owed")
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(runner.started, [.sessionStart])
    }

    func testEndWithoutStartAndFlagOffRunsNothing() async {
        let runner = ControlledRunner()
        let queue = flagged(runner, FlagBox(false))
        let accepted = await queue.submit(.breakEnd, enabled: false, settings: settings)
        XCTAssertFalse(accepted)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(runner.started, [])
    }

    func testQueuedEndDroppedWhenFlagOffAndNothingOwed() async {
        let runner = ControlledRunner()
        let flag = FlagBox(true)
        let queue = flagged(runner, flag)
        await submit(queue, .sessionStart)
        await waitUntil { runner.waiting == 1 }
        await submit(queue, .breakEnd)                 // queued while on, no START ran
        flag.value = false
        runner.release()
        await waitUntil { await queue.isIdle }
        XCTAssertEqual(runner.started, [.sessionStart])
    }

    // MARK: - FocusEvent.events(for:)

    func testBreakStartedMapsToBreakStart() {
        XCTAssertEqual(FocusEvent.events(for: .breakStarted(.short)), [.breakStart])
        XCTAssertEqual(FocusEvent.events(for: .breakStarted(.long)), [.breakStart])
    }

    func testBreakCompletedMapsToBreakEnd() {
        XCTAssertEqual(FocusEvent.events(for: .breakCompleted), [.breakEnd])
    }

    func testBreakSkippedMapsToBreakEnd() {
        XCTAssertEqual(FocusEvent.events(for: .breakSkipped(.short)), [.breakEnd])
    }

    func testBreakPostponedMapsToBreakEnd() {
        XCTAssertEqual(FocusEvent.events(for: .breakPostponed(.long)), [.breakEnd])
    }

    func testResumedMapsToNothing() {
        XCTAssertEqual(FocusEvent.events(for: .resumed), [])
    }
}

/// Records observer calls; the result is reduced to its error (nil = started or OK).
private final class ObserverLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(FocusEvent, FocusShortcutError?)] = []
    private var calls = 0
    var entries: [(FocusEvent, FocusShortcutError?)] { lock.lock(); defer { lock.unlock() }; return items }

    func add(_ event: FocusEvent, _ result: Result<Void, FocusShortcutError>?) {
        lock.lock(); defer { lock.unlock() }
        switch result {
        case .none: items.append((event, nil))
        case .some(.success): items.append((event, nil))
        case .some(.failure(let error)): items.append((event, error))
        }
        calls += 1
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
