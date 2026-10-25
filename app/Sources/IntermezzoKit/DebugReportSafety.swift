import Foundation

extension DebugOutputPath {
    /// Roots for `debug/report`: ONLY the per-user temp folder (mode 0700). The
    /// report holds projects, clients, rates and earnings, so it never goes to
    /// the shared, world-readable `/tmp`.
    public static func reportRoots(temporaryDirectory: String) -> [String] { [temporaryDirectory] }

    /// Roots for the PNG render routes (no private data): shared `/tmp` and the
    /// temp folder, the temp folder last so a missing `out=` lands there.
    public static func renderRoots(temporaryDirectory: String) -> [String] {
        ["/tmp", "/private/tmp", temporaryDirectory]
    }

    /// Owner read/write only (0600).
    public static func restrictToOwner(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: url.path)
    }
}

/// Bounds for numbers a debug render URL passes in, so a crafted URL cannot ask
/// for a gigantic bitmap or an endless simulation.
public enum DebugRenderLimits {
    public static let dimensionRange: ClosedRange<Double> = 64...4096
    public static let maxSeconds: Double = 600

    /// Width/height: unparsable or non-finite gives `default`, anything else is clamped.
    public static func dimension(_ raw: String?, default fallback: Double) -> Double {
        guard let value = raw.flatMap(Double.init), value.isFinite else { return fallback }
        return min(dimensionRange.upperBound, max(dimensionRange.lowerBound, value))
    }

    /// Simulated seconds: 0...`maxSeconds`.
    public static func seconds(_ raw: String?, default fallback: Double) -> Double {
        guard let value = raw.flatMap(Double.init), value.isFinite else { return fallback }
        return min(maxSeconds, max(0, value))
    }
}

/// One job at a time, plus a short cooldown after it, so a URL fired in a loop
/// cannot keep the main thread busy back to back.
public struct ExclusiveRun: Equatable {
    public let cooldown: TimeInterval
    private var running = false
    private var finishedAt: Date?

    public init(cooldown: TimeInterval) { self.cooldown = cooldown }

    /// True (and marks running) when no job runs and the cooldown has passed.
    public mutating func tryBegin(now: Date) -> Bool {
        guard !running else { return false }
        if let finishedAt, now.timeIntervalSince(finishedAt) < cooldown { return false }
        running = true
        return true
    }

    public mutating func finish(now: Date) {
        running = false
        finishedAt = now
    }
}
