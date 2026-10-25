import XCTest
@testable import IntermezzoKit

/// Fake process: never touches the system. Exits when told, or on terminate /
/// kill depending on how it is configured.
private final class FakeProcess: ShortcutProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var output: ShortcutProcessOutput?
    private var waiters: [CheckedContinuation<ShortcutProcessOutput, Never>] = []
    private let honoursTerminate: Bool
    private(set) var terminateCalls = 0
    private(set) var killCalls = 0

    init(exitImmediately status: Int32? = nil, stdout: String = "", honoursTerminate: Bool = true) {
        self.honoursTerminate = honoursTerminate
        if let status { exit(status, stdout: stdout) }
    }

    func exit(_ status: Int32, stdout: String = "") {
        lock.lock()
        guard output == nil else { lock.unlock(); return }
        let out = ShortcutProcessOutput(status: status, stdout: Data(stdout.utf8), stderr: Data())
        output = out
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume(returning: out) }
    }

    func waitForExit() async -> ShortcutProcessOutput {
        await withCheckedContinuation { c in
            lock.lock()
            if let output { lock.unlock(); c.resume(returning: output); return }
            waiters.append(c)
            lock.unlock()
        }
    }

    func terminate() {
        lock.lock(); terminateCalls += 1; lock.unlock()
        if honoursTerminate { exit(15) }
    }

    func kill() {
        lock.lock(); killCalls += 1; lock.unlock()
        exit(9)
    }
}

private final class LaunchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func record(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
    var launched: [String] { lock.lock(); defer { lock.unlock() }; return names }
}

private struct LaunchFailed: Error {}

private extension Result where Success == Void, Failure == FocusShortcutError {
    var failure: FocusShortcutError? {
        if case .failure(let error) = self { return error }
        return nil
    }
    var succeeded: Bool { failure == nil }
}

final class ShortcutPlanTests: XCTestCase {

    // MARK: - ShortcutPlan.shortcut(for:settings:)

    func testEmptyNameGivesNil() {
        XCTAssertNil(ShortcutPlan.shortcut(for: .breakStart, settings: [.breakStart: ""]))
    }

    func testWhitespaceNameGivesNil() {
        XCTAssertNil(ShortcutPlan.shortcut(for: .breakStart, settings: [.breakStart: "  \t\n "]))
    }

    func testConfiguredNameReturned() {
        let settings: [FocusEvent: String] = [.sessionStart: "Deep Work", .breakEnd: "Work Focus"]
        XCTAssertEqual(ShortcutPlan.shortcut(for: .sessionStart, settings: settings), "Deep Work")
        XCTAssertEqual(ShortcutPlan.shortcut(for: .breakEnd, settings: settings), "Work Focus")
        XCTAssertNil(ShortcutPlan.shortcut(for: .breakStart, settings: settings))
    }

    func testDefaultsKeysMatchContract() {
        XCTAssertEqual(FocusEvent.sessionStart.defaultsKey, "focusShortcut.sessionStart")
        XCTAssertEqual(FocusEvent.breakStart.defaultsKey, "focusShortcut.breakStart")
        XCTAssertEqual(FocusEvent.breakEnd.defaultsKey, "focusShortcut.breakEnd")
        XCTAssertEqual(ShortcutPlan.enabledKey, "focusShortcutsEnabled")
    }

    // MARK: - ShortcutPlan.run(_:lister:launcher:)

    func testMissingShortcutIsReportedNotThrown() async {
        let log = LaunchLog()
        let result = await ShortcutPlan.run("Gone", lister: { ["Other"] }, launcher: { name in
            log.record(name)
            return FakeProcess(exitImmediately: 0)
        })
        XCTAssertEqual(result.failure, .notFound("Gone"))
        XCTAssertTrue(log.launched.isEmpty, "a missing shortcut must never be launched")
    }

    func testNameMatchIsExact() async {
        let log = LaunchLog()
        let result = await ShortcutPlan.run("deep work", lister: { ["Deep Work", "deep work "] },
                                            launcher: { name in
            log.record(name)
            return FakeProcess(exitImmediately: 0)
        })
        XCTAssertEqual(result.failure, .notFound("deep work"))
        XCTAssertTrue(log.launched.isEmpty)
    }

    func testBlankNameIsNotFoundWithoutListing() async {
        let result = await ShortcutPlan.run("   ", lister: { XCTFail("must not list"); return ["   "] },
                                            launcher: { _ in XCTFail("must not launch"); return FakeProcess(exitImmediately: 0) })
        XCTAssertEqual(result.failure, .notFound("   "))
    }

    func testOptionLikeNameIsRefused() async {
        let log = LaunchLog()
        let result = await ShortcutPlan.run("--help", lister: { ["--help"] }, launcher: { name in
            log.record(name)
            return FakeProcess(exitImmediately: 0)
        })
        XCTAssertEqual(result.failure, .notFound("--help"))
        XCTAssertTrue(log.launched.isEmpty)
    }

    func testNameIsPassedVerbatim() async {
        let tricky = "Focus; rm -rf ~ $(echo hi) \"quoted\" 'x'"
        let log = LaunchLog()
        let result = await ShortcutPlan.run(tricky, lister: { [tricky] }, launcher: { name in
            log.record(name)
            return FakeProcess(exitImmediately: 0)
        })
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(log.launched, [tricky])
    }

    func testZeroExitIsSuccess() async {
        let result = await ShortcutPlan.run("A", lister: { ["A"] },
                                            launcher: { _ in FakeProcess(exitImmediately: 0) })
        XCTAssertTrue(result.succeeded)
    }

    func testNonZeroExitIsFailed() async {
        let result = await ShortcutPlan.run("A", lister: { ["A"] },
                                            launcher: { _ in FakeProcess(exitImmediately: 1) })
        XCTAssertEqual(result.failure, .failed(1))
    }

    func testLaunchErrorIsFailed() async {
        let result = await ShortcutPlan.run("A", lister: { ["A"] }, launcher: { _ in throw LaunchFailed() })
        XCTAssertEqual(result.failure, .failed(ShortcutPlan.launchFailedStatus))
    }

    func testHangingShortcutTimesOutAndIsTerminated() async {
        let process = FakeProcess()
        let result = await ShortcutPlan.run("A", lister: { ["A"] }, launcher: { _ in process },
                                            timeout: 0.05, killGrace: 0.5)
        XCTAssertEqual(result.failure, .timedOut)
        XCTAssertEqual(process.terminateCalls, 1)
        XCTAssertEqual(process.killCalls, 0)
    }

    func testProcessIgnoringTerminateIsKilled() async {
        let process = FakeProcess(honoursTerminate: false)
        let result = await ShortcutPlan.run("A", lister: { ["A"] }, launcher: { _ in process },
                                            timeout: 0.05, killGrace: 0.05)
        XCTAssertEqual(result.failure, .timedOut)
        XCTAssertEqual(process.terminateCalls, 1)
        XCTAssertEqual(process.killCalls, 1)
    }

    func testDefaultTimeoutIsTenSeconds() {
        XCTAssertEqual(ShortcutPlan.timeout, 10)
    }

    // MARK: - supervise / parsing / capping

    func testSuperviseReturnsOutputOfFinishedProcess() async {
        let outcome = await ShortcutPlan.supervise(FakeProcess(exitImmediately: 0, stdout: "A\nB\n"),
                                                   timeout: 1, killGrace: 1)
        guard case .exited(let output) = outcome else { return XCTFail("expected exit") }
        XCTAssertEqual(ShortcutPlan.parseList(output.stdout), ["A", "B"])
    }

    func testParseListKeepsNamesExactAndDropsBlankLines() {
        let data = Data("Ustaw tryb skupienia\r\n\n  \nDeep Work \nZażółć\n".utf8)
        XCTAssertEqual(ShortcutPlan.parseList(data), ["Ustaw tryb skupienia", "Deep Work ", "Zażółć"])
    }

    func testParseListOfEmptyOutputIsEmpty() {
        XCTAssertEqual(ShortcutPlan.parseList(Data()), [])
    }

    func testCappedBufferStopsAtCap() {
        var buffer = CappedBuffer(cap: 4)
        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))
        XCTAssertEqual(buffer.data, Data("abcd".utf8))
        XCTAssertTrue(buffer.truncated)
    }

    func testDefaultOutputCapIs64KB() {
        XCTAssertEqual(ShortcutPlan.outputCap, 64 * 1024)
    }

    func testTruncatedListDropsPossiblyPartialLastLine() {
        let data = Data("Alpha\nBeta\nGam".utf8)
        XCTAssertEqual(ShortcutPlan.parseList(data, truncated: true), ["Alpha", "Beta"])
        XCTAssertEqual(ShortcutPlan.parseList(data, truncated: false), ["Alpha", "Beta", "Gam"])
    }

    func testDisplayNameStripsControlAndBidiCharacters() {
        let raw = "Fo\u{202E}cus\u{0007}\u{2066}X\u{2069}\u{200F}\tY"
        XCTAssertEqual(ShortcutPlan.displayName(raw), "FocusXY")
        XCTAssertEqual(ShortcutPlan.displayName("Ustaw tryb skupienia 🍅"), "Ustaw tryb skupienia 🍅")
    }

    func testDisplayNameDoesNotChangeTheLaunchedName() async {
        let raw = "A\u{202E}B"
        let log = LaunchLog()
        _ = ShortcutPlan.displayName(raw)
        let result = await ShortcutPlan.run(raw, lister: { [raw] }, launcher: { name in
            log.record(name)
            return FakeProcess(exitImmediately: 0)
        })
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(log.launched, [raw])
    }
}
