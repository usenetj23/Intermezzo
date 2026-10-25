import Foundation

/// How a break ended, for the trend chart icons. Stored as `rawValue` on the break record.
public enum BreakOutcome: String, CaseIterable, Sendable {
    case completed
    /// Skip pressed on the live break.
    case skipped
    /// +1 / +5 on the live break: the popup closes and comes back in N minutes.
    case postponed
    /// A rule skipped the break automatically.
    case ruleSkipped
    /// Skipped from the reminder card before it started.
    case skippedAhead

    /// Records written before outcomes were stored only know whether the break was skipped.
    public init(raw: String?, wasSkipped: Bool) {
        self = raw.flatMap(BreakOutcome.init(rawValue:)) ?? (wasSkipped ? .skipped : .completed)
    }

    /// Everything but a finished break drops the trend line (postponing included, by choice).
    public var lowersMomentum: Bool { self != .completed }
}

/// Horizontal placement of the trend chart points along real time.
public enum TrendTimeline {
    public struct CollapsedGap: Equatable, Sendable {
        /// The gap lies between point `afterIndex` and `afterIndex + 1`.
        public let afterIndex: Int
        public let seconds: TimeInterval
    }

    public struct Layout: Equatable, Sendable {
        /// One x per point, from 0 to `width`.
        public let x: [Double]
        public let collapsedGaps: [CollapsedGap]
    }

    /// Gaps up to `maxLinearGap` scale with time; longer ones (a night, a weekend) take a fixed
    /// `collapsedWidth` so today's breaks are not squeezed into a corner. No gap gets narrower than
    /// `minSpacing`, so the icons above the points never overlap.
    public static func layout(times: [Date], width: Double, minSpacing: Double = 24,
                              collapsedWidth: Double = 56, maxLinearGap: TimeInterval = 2 * 3600) -> Layout {
        guard times.count >= 2 else { return Layout(x: times.isEmpty ? [] : [0], collapsedGaps: []) }
        let gaps = zip(times, times.dropFirst()).map { max(0, $1.timeIntervalSince($0)) }
        let collapsed = gaps.enumerated()
            .filter { $0.element > maxLinearGap }
            .map { CollapsedGap(afterIndex: $0.offset, seconds: $0.element) }
        let isCollapsed = Set(collapsed.map(\.afterIndex))
        let fixed = min(collapsedWidth, width / Double(gaps.count))
        let linearWidth = max(0, width - fixed * Double(collapsed.count))
        let linearIdx = gaps.indices.filter { !isCollapsed.contains($0) }

        var widths = gaps.indices.map { isCollapsed.contains($0) ? fixed : 0.0 }
        let linearSeconds = linearIdx.reduce(0) { $0 + gaps[$1] }
        if linearSeconds <= 0 {
            for i in linearIdx { widths[i] = linearWidth / Double(linearIdx.count) }
        } else {
            // Lift the too-narrow gaps to the minimum, then share what is left by time.
            // Each pass can only add gaps to the pinned set, so it settles in at most n passes.
            let floor = min(minSpacing, linearWidth / Double(max(1, linearIdx.count)))
            var pinned = Set<Int>()
            for _ in 0...linearIdx.count {
                let free = linearIdx.filter { !pinned.contains($0) }
                let freeSeconds = free.reduce(0) { $0 + gaps[$1] }
                let freeWidth = linearWidth - floor * Double(pinned.count)
                let scale = freeSeconds > 0 ? freeWidth / freeSeconds : 0
                let tooNarrow = free.filter { gaps[$0] * scale < floor }
                for i in linearIdx {
                    widths[i] = pinned.contains(i) ? floor
                        : (freeSeconds > 0 ? gaps[i] * scale : freeWidth / Double(max(1, free.count)))
                }
                if tooNarrow.isEmpty { break }
                pinned.formUnion(tooNarrow)
            }
        }

        var x = [0.0]
        for w in widths { x.append(x[x.count - 1] + w) }
        x[x.count - 1] = width        // absorb rounding drift
        return Layout(x: x, collapsedGaps: collapsed)
    }

    /// Short label for a collapsed gap: hours below two days, days after that.
    public static func gapLabel(seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        return hours < 48 ? "\(hours) h" : "\(hours / 24) d"
    }
}
