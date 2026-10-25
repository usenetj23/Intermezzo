import Foundation

/// Moments at which the user's own Shortcut may switch Focus.
public enum FocusEvent: String, CaseIterable, Sendable {
    case sessionStart, breakStart, breakEnd

    /// UserDefaults key holding the shortcut name for this event (String).
    public var defaultsKey: String { "focusShortcut.\(rawValue)" }
}

/// Why running a Shortcut did not succeed. Reported, never thrown at the caller.
public enum FocusShortcutError: Error, Equatable, Sendable {
    /// The name is blank, not safe as an argument, or not in `shortcuts list`.
    case notFound(String)
    /// `shortcuts` exited with this non-zero status (or could not be launched).
    case failed(Int32)
    /// Still running after the timeout; it was terminated (and killed if needed).
    case timedOut
}

/// What a finished child process left behind (outputs already capped).
public struct ShortcutProcessOutput: Equatable, Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
    /// stdout hit the cap: its last line may be cut in the middle.
    public let stdoutTruncated: Bool

    public init(status: Int32, stdout: Data, stderr: Data, stdoutTruncated: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
    }
}

/// A launched child process. The app wraps `Process`; tests use a fake.
public protocol ShortcutProcessHandle: AnyObject, Sendable {
    /// Resolves once the process has exited (never throws, never blocks a thread).
    func waitForExit() async -> ShortcutProcessOutput
    /// Polite stop (SIGTERM).
    func terminate()
    /// Hard stop (SIGKILL) for a process that ignored `terminate()`.
    func kill()
}

/// Result of supervising a process under a timeout.
public enum ShortcutRunOutcome: Equatable, Sendable {
    case exited(ShortcutProcessOutput)
    case timedOut
}

/// Byte buffer that silently stops growing at `cap` — keeps a chatty child
/// from filling memory while its pipe is still drained.
public struct CappedBuffer: Equatable, Sendable {
    public let cap: Int
    public private(set) var data = Data()
    public private(set) var truncated = false

    public init(cap: Int) { self.cap = max(0, cap) }

    public mutating func append(_ chunk: Data) {
        let room = cap - data.count
        guard room > 0 else {
            if !chunk.isEmpty { truncated = true }
            return
        }
        if chunk.count > room {
            data.append(chunk.prefix(room))
            truncated = true
        } else {
            data.append(chunk)
        }
    }
}

/// Pure orchestration of "Focus through the user's Shortcuts". The process
/// itself is injected (`launcher`), so every path — not found, failed,
/// timed out, killed — is testable without running a real Shortcut.
public enum ShortcutPlan {
    /// UserDefaults Int flag, default 0 (off): with it off nothing runs.
    public static let enabledKey = "focusShortcutsEnabled"
    /// Seconds a shortcut may run before it is terminated.
    public static let timeout: TimeInterval = 10
    /// Seconds between `terminate()` and `kill()`.
    public static let killGrace: TimeInterval = 2
    /// Max bytes kept from each of stdout / stderr.
    public static let outputCap = 64 * 1024
    /// Status reported when the process could not be launched at all.
    public static let launchFailedStatus: Int32 = -1

    /// The configured shortcut for `event`, or nil when none / blank.
    /// The name is returned exactly as stored (it must match `shortcuts list`).
    public static func shortcut(for event: FocusEvent, settings: [FocusEvent: String]) -> String? {
        guard let name = settings[event], isUsable(name) else { return nil }
        return name
    }

    /// Non-blank and not option-like: a leading "-" could be read as a flag
    /// by the `shortcuts` command line, so such names are refused outright.
    public static func isUsable(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.hasPrefix("-")
            && !name.contains(where: \.isNewline)
    }

    /// Names from `shortcuts list` output: one per line, kept exact
    /// (only the line break itself is removed), blank lines dropped.
    /// When the output was `truncated` at the cap, the last line may be a cut
    /// name that could match a different shortcut, so it is dropped.
    public static func parseList(_ data: Data, truncated: Bool = false) -> [String] {
        let text = String(decoding: data, as: UTF8.self)
        var lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        if truncated, !lines.isEmpty { lines.removeLast() }
        return lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Bidi controls that can make a name look like a different one.
    private static let bidiControls: Set<UInt32> = [
        0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
    ]

    /// The name for DISPLAY only: control and bidi characters removed. The
    /// stored and launched name is never changed.
    public static func displayName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars
        where scalar.properties.generalCategory != .control && !bidiControls.contains(scalar.value) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Runs the named shortcut: refuses unusable names, checks the name is in
    /// `lister()` (exact match) right now, launches it and supervises it.
    /// - Parameters:
    ///   - lister: current shortcut names (the app passes `shortcuts list`).
    ///   - launcher: starts `shortcuts run` for the name, passed as one argument.
    public static func run(_ name: String,
                           lister: () async -> [String],
                           launcher: (String) throws -> any ShortcutProcessHandle,
                           timeout: TimeInterval = ShortcutPlan.timeout,
                           killGrace: TimeInterval = ShortcutPlan.killGrace) async
        -> Result<Void, FocusShortcutError> {
        guard isUsable(name) else { return .failure(.notFound(name)) }
        guard await lister().contains(name) else { return .failure(.notFound(name)) }
        let handle: any ShortcutProcessHandle
        do {
            handle = try launcher(name)
        } catch {
            return .failure(.failed(launchFailedStatus))
        }
        switch await supervise(handle, timeout: timeout, killGrace: killGrace) {
        case .timedOut:
            return .failure(.timedOut)
        case .exited(let output) where output.status == 0:
            return .success(())
        case .exited(let output):
            return .failure(.failed(output.status))
        }
    }

    private enum Race: Sendable {
        case exited(ShortcutProcessOutput)
        case deadline
        case graceOver
    }

    /// Waits for `handle` to exit, at most `timeout` seconds. Past that it is
    /// terminated; if it is still alive after `killGrace` it is killed.
    /// Returns only once the process has actually exited.
    public static func supervise(_ handle: any ShortcutProcessHandle,
                                 timeout: TimeInterval,
                                 killGrace: TimeInterval) async -> ShortcutRunOutcome {
        await withTaskGroup(of: Race.self) { group -> ShortcutRunOutcome in
            group.addTask { .exited(await handle.waitForExit()) }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds(timeout))
                return .deadline
            }
            let first = await group.next() ?? .deadline
            if case .exited(let output) = first {
                group.cancelAll()
                return .exited(output)
            }
            handle.terminate()
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds(killGrace))
                return .graceOver
            }
            if case .graceOver = await group.next() ?? .graceOver {
                handle.kill()
            }
            group.cancelAll()
            return .timedOut
        }
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
