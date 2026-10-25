import Foundation
import IntermezzoKit

/// Result of one `shortcuts list`, so the UI can tell failure from "none".
enum ShortcutListing: Equatable {
    case unavailable
    case failed
    case loaded([String])

    var names: [String] {
        if case .loaded(let names) = self { return names }
        return []
    }
}

/// Focus through the user's own Shortcuts (there is no public Focus API).
/// Runs `/usr/bin/shortcuts` directly — argv only, never a shell — off the
/// main thread, under `ShortcutPlan.timeout`. Fire-and-forget: a failure only
/// updates `FocusShortcutsStatus.shared.lastStatus` and the Trace log; it never
/// reaches the break engine or the Pomodoro.
enum FocusShortcuts {
    static let executablePath = "/usr/bin/shortcuts"

    /// False when the `shortcuts` command line tool is missing.
    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: executablePath) }

    /// Names from `shortcuts list` (empty when unavailable, failed or timed out).
    static func list() async -> [String] { await listing().names }

    /// One `shortcuts list` child. Callers go through
    /// `FocusShortcutsStatus.shared.sharedListing()` so only one runs at a time.
    static func listing() async -> ShortcutListing {
        guard isAvailable else { return .unavailable }
        let handle: ShortcutProcess
        do {
            handle = try ShortcutProcess.launch(["list"])
        } catch {
            Trace.log("focus shortcuts: list could not start")
            return .failed
        }
        let outcome = await ShortcutPlan.supervise(handle, timeout: ShortcutPlan.timeout,
                                                   killGrace: ShortcutPlan.killGrace)
        switch outcome {
        case .exited(let output) where output.status == 0:
            if output.stdoutTruncated { Trace.log("focus shortcuts: list output truncated at cap") }
            return .loaded(ShortcutPlan.parseList(output.stdout, truncated: output.stdoutTruncated))
        case .exited(let output):
            Trace.log("focus shortcuts: list failed exit=\(output.status)")
            return .failed
        case .timedOut:
            Trace.log("focus shortcuts: list timed out")
            return .failed
        }
    }

    /// Runs `shortcuts run <name>` with the name as a single argument, only if
    /// `lister()` contains it exactly at this moment.
    static func run(_ name: String,
                    lister: @escaping () async -> [String] = FocusShortcuts.list) async
        -> Result<Void, FocusShortcutError> {
        guard isAvailable else { return .failure(.notFound(name)) }
        return await ShortcutPlan.run(name, lister: lister, launcher: { name in
            try ShortcutProcess.launch(["run", name])
        })
    }

    /// Queues the shortcut configured for `event`, if the feature is on.
    @MainActor static func fire(_ event: FocusEvent) {
        FocusShortcutsStatus.shared.fire(event)
    }

    /// One call per processed engine event (coordinator).
    @MainActor static func handle(_ engineEvent: EngineEvent) {
        FocusEvent.events(for: engineEvent).forEach(fire)
    }
}

/// Last-run status for the settings UI, the single FIFO run queue and the
/// single in-flight `shortcuts list` shared by Settings, the debug route and
/// the queue's pre-run name check.
@MainActor
final class FocusShortcutsStatus: ObservableObject {
    static let shared = FocusShortcutsStatus()

    @Published private(set) var lastStatus = ""
    @Published private(set) var running: Set<FocusEvent> = []

    private var listTask: Task<ShortcutListing, Never>?
    private var submitChain: Task<Void, Never>?
    private lazy var queue = FocusShortcutQueue(
        runner: { job in
            await FocusShortcuts.run(job.name, lister: {
                await FocusShortcutsStatus.shared.sharedListing().names
            })
        },
        observer: { job, result in
            await FocusShortcutsStatus.shared.observe(job, result: result)
        },
        isEnabled: { FocusShortcutsStatus.isEnabled })

    private init() {}

    nonisolated static var isEnabled: Bool { UserDefaults.standard.integer(forKey: ShortcutPlan.enabledKey) != 0 }

    static func configuredShortcuts(_ defaults: UserDefaults = .standard) -> [FocusEvent: String] {
        var settings: [FocusEvent: String] = [:]
        for event in FocusEvent.allCases {
            if let name = defaults.string(forKey: event.defaultsKey) { settings[event] = name }
        }
        return settings
    }

    /// Joins the `shortcuts list` already running, or starts one.
    func sharedListing() async -> ShortcutListing {
        if let listTask { return await listTask.value }
        let task = Task.detached { await FocusShortcuts.listing() }
        listTask = task
        let result = await task.value
        listTask = nil
        return result
    }

    /// Always hands the event to the queue: with the feature off the queue still
    /// lets through the one END owed to a START that ran (turning the toggle off
    /// mid-break must not leave Focus in its break state). Quitting the app
    /// during a break cannot send that END.
    func fire(_ event: FocusEvent) {
        let enabled = Self.isEnabled
        let settings = Self.configuredShortcuts()
        guard ShortcutPlan.shortcut(for: event, settings: settings) != nil else { return }
        // Chain submissions so events fired in one turn reach the queue in order.
        let queue = self.queue
        let previous = submitChain
        submitChain = Task {
            await previous?.value
            await queue.submit(event, enabled: enabled, settings: settings)
        }
    }

    private func observe(_ job: FocusShortcutJob, result: Result<Void, FocusShortcutError>?) {
        guard let result else {
            running.insert(job.event)
            return
        }
        running.remove(job.event)
        let time = Date().formatted(date: .omitted, time: .shortened)
        let label = Self.label(job.event)
        let shown = ShortcutPlan.displayName(job.name)
        switch result {
        case .success:
            lastStatus = String(localized: "\(label): “\(shown)” ran at \(time)")
            Trace.log("focus shortcuts: \(job.event.rawValue) ok")
        case .failure(let error):
            lastStatus = Self.describe(error, label: label, shown: shown, time: time)
            Trace.log("focus shortcuts: \(job.event.rawValue) failed: \(Self.traceCode(error))")
        }
    }

    static func label(_ event: FocusEvent) -> String {
        switch event {
        case .sessionStart: return String(localized: "Session start")
        case .breakStart: return String(localized: "Break start")
        case .breakEnd: return String(localized: "Break end")
        }
    }

    private static func describe(_ error: FocusShortcutError, label: String, shown: String, time: String) -> String {
        switch error {
        case .notFound:
            return String(localized: "\(label): “\(shown)” was not found in Shortcuts (\(time))")
        case .failed(let status):
            return String(localized: "\(label): “\(shown)” failed (exit \(Int(status))) at \(time)")
        case .timedOut:
            let seconds = Int(ShortcutPlan.timeout)
            return String(localized: "\(label): “\(shown)” took longer than \(seconds) s and was stopped at \(time)")
        }
    }

    /// No shortcut names in the trace: only the kind of failure.
    private static func traceCode(_ error: FocusShortcutError) -> String {
        switch error {
        case .notFound: return "notFound"
        case .failed(let status): return "failed(\(status))"
        case .timedOut: return "timedOut"
        }
    }
}

/// Thin `Process` wrapper: argv only (no shell), stdin from /dev/null,
/// stdout/stderr drained continuously and capped at `ShortcutPlan.outputCap`.
final class ShortcutProcess: ShortcutProcessHandle, @unchecked Sendable {
    /// After exit, wait at most this long for the pipes to reach EOF.
    private static let drainGrace: TimeInterval = 0.5

    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock()
    private var out = CappedBuffer(cap: ShortcutPlan.outputCap)
    private var err = CappedBuffer(cap: ShortcutPlan.outputCap)
    private var outEOF = false
    private var errEOF = false
    private var status: Int32?
    private var result: ShortcutProcessOutput?
    private var waiters: [CheckedContinuation<ShortcutProcessOutput, Never>] = []

    static func launch(_ arguments: [String],
                       executable: String = FocusShortcuts.executablePath) throws -> ShortcutProcess {
        let child = ShortcutProcess(executable: executable, arguments: arguments)
        try child.start()
        return child
    }

    private init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe
    }

    private func start() throws {
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h, stdout: true) }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.read(h, stdout: false) }
        process.terminationHandler = { [weak self] p in self?.didExit(p.terminationStatus) }
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    private func read(_ handle: FileHandle, stdout: Bool) {
        let chunk = handle.availableData
        lock.lock()
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            if stdout { outEOF = true } else { errEOF = true }
        } else if stdout {
            out.append(chunk)
        } else {
            err.append(chunk)
        }
        let ready = outEOF && errEOF && status != nil
        lock.unlock()
        if ready { finish() }
    }

    private func didExit(_ code: Int32) {
        lock.lock()
        status = code
        let ready = outEOF && errEOF
        lock.unlock()
        if ready { finish(); return }
        // A grandchild holding the pipe open must not keep us waiting forever.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.drainGrace) { [self] in
            finish()
        }
    }

    private func finish() {
        lock.lock()
        guard result == nil, let code = status else { lock.unlock(); return }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        let done = ShortcutProcessOutput(status: code, stdout: out.data, stderr: err.data,
                                         stdoutTruncated: out.truncated)
        result = done
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume(returning: done) }
    }

    func waitForExit() async -> ShortcutProcessOutput {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    func kill() {
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}
