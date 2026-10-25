import Foundation

/// What a stretch of the day was spent on.
public enum RibbonKind: String, Sendable {
    case focus, breakTaken, breakSkipped, meeting
}

/// One non-overlapping stretch of the day ribbon. `label` is the project for `focus`; empty otherwise
/// (meeting titles never reach reports).
public struct RibbonSegment: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var kind: RibbonKind
    public var label: String

    public init(start: Date, end: Date, kind: RibbonKind, label: String) {
        self.start = start
        self.end = end
        self.kind = kind
        self.label = label
    }
}

/// A break (taken or skipped) as fed to the ribbon.
public struct RibbonBreak: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var skipped: Bool

    public init(start: Date, end: Date, skipped: Bool) {
        self.start = start
        self.end = end
        self.skipped = skipped
    }
}

/// Builds the day ribbon: focus, breaks and meetings clipped to one calendar day.
/// Priority on overlap: meeting > break > focus; the lower one is trimmed or split around the higher one.
/// Overlaps within the same priority are resolved deterministically: earlier start (then earlier end) wins.
public enum DayRibbon {
    /// Segments shorter than this are dropped.
    static let minimumDuration: TimeInterval = 1

    public static func build(day: Date, calendar: Calendar, pomodoros: [PomodoroRecord],
                             breaks: [RibbonBreak], meetings: [DateInterval]) -> [RibbonSegment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart), dayEnd > dayStart else { return [] }

        let meetingSegs = meetings.map {
            RibbonSegment(start: $0.start, end: $0.end, kind: .meeting, label: "")
        }
        let breakSegs = breaks.map {
            RibbonSegment(start: $0.start, end: $0.end, kind: $0.skipped ? .breakSkipped : .breakTaken, label: "")
        }
        let focusSegs = pomodoros.map {
            RibbonSegment(start: $0.startedAt, end: $0.date, kind: .focus, label: $0.project)
        }

        var occupied: [(Date, Date)] = []
        var result: [RibbonSegment] = []
        for group in [meetingSegs, breakSegs, focusSegs] {
            let ordered = group.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            for seg in ordered {
                let lo = max(seg.start, dayStart), hi = min(seg.end, dayEnd)
                for piece in subtract(occupied, from: (lo, hi)) {
                    result.append(RibbonSegment(start: piece.0, end: piece.1, kind: seg.kind, label: seg.label))
                    occupied.append(piece)
                }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Joins segments of the same kind and label that touch (gap <= 1 s) or overlap, so a meeting is one block.
    /// Input order by start is kept; the input need not be sorted.
    public static func merged(_ segments: [RibbonSegment]) -> [RibbonSegment] {
        var out: [RibbonSegment] = []
        for seg in segments.sorted(by: { $0.start < $1.start }) {
            if var last = out.last, last.kind == seg.kind, last.label == seg.label,
               seg.start.timeIntervalSince(last.end) <= 1 {
                last.end = max(last.end, seg.end)
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    /// `range` minus every interval in `taken`, keeping only pieces of at least `minimumDuration`.
    private static func subtract(_ taken: [(Date, Date)], from range: (Date, Date)) -> [(Date, Date)] {
        var pieces = [range]
        for t in taken {
            pieces = pieces.flatMap { p -> [(Date, Date)] in
                guard t.0 < p.1, t.1 > p.0 else { return [p] }
                var out: [(Date, Date)] = []
                if t.0 > p.0 { out.append((p.0, t.0)) }
                if t.1 < p.1 { out.append((t.1, p.1)) }
                return out
            }
        }
        return pieces.filter { $0.1.timeIntervalSince($0.0) >= minimumDuration }
    }
}
