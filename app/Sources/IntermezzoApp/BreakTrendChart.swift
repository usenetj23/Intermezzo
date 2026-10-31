import SwiftUI
import IntermezzoKit

// Recent break momentum: the line climbs after a finished break and drops after
// a skipped one, coloured green (high) through amber to red (low). Points sit at
// their real time (long gaps such as a night are collapsed, see TrendTimeline) and
// carry an icon telling how each break ended.
// Shape/Path, NOT Canvas — Canvas + RenderBox triggers a Metal (RPS) telemetry
// crash on macOS 27 beta (rb_commit -> NSCFNumber length).
struct BreakTrendChart: View {
    let markers: [BreakMarker]

    private static let sidePad: CGFloat = 22
    /// Room above the highest point for its icon.
    private static let topPad: CGFloat = 30
    private static let bottomPad: CGFloat = 16
    private static let minSpacing: CGFloat = 28

    private var levels: [Double] {
        BreakMomentum.levels(markers.map {
            .init(skipped: $0.wasSkipped, weight: $0.weight,
                  lossShare: $0.outcome == .postponed ? BreakMomentum.postponeShare(minutes: $0.postponeMinutes) : 1)
        })
    }

    private func layout(in size: CGSize) -> (points: [CGPoint], gaps: [TrendTimeline.CollapsedGap]) {
        let l = levels
        guard l.count >= 2, l.count == markers.count else { return ([], []) }
        let usableW = Double(max(1, size.width - Self.sidePad * 2))
        let timeline = TrendTimeline.layout(times: markers.map(\.startedAt), width: usableW,
                                            minSpacing: Double(Self.minSpacing))
        let usableH = size.height - Self.topPad - Self.bottomPad
        let points = l.enumerated().map { i, v in
            CGPoint(x: Self.sidePad + CGFloat(timeline.x[i]),
                    y: Self.topPad + usableH * (1 - CGFloat(v)))
        }
        return (points, timeline.collapsedGaps)
    }

    /// Red at 0, amber in the middle, green at 1.
    private func color(_ level: Double) -> Color {
        Color(hue: 0.02 + 0.33 * level, saturation: 0.85, brightness: 0.95)
    }

    var body: some View {
        GeometryReader { geo in
            let (pts, gaps) = layout(in: geo.size)
            let collapsed = Set(gaps.map(\.afterIndex))
            let l = levels
            ZStack(alignment: .topLeading) {
                if pts.count >= 2 {
                    ForEach(0..<(pts.count - 1), id: \.self) { i in
                        TrendSegment(points: pts, index: i)
                            .stroke(LinearGradient(colors: [color(l[i]), color(l[i + 1])],
                                                   startPoint: .leading, endPoint: .trailing),
                                    style: collapsed.contains(i)
                                        ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5])
                                        : StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .opacity(collapsed.contains(i) ? 0.55 : 1)
                    }
                    ForEach(gaps, id: \.afterIndex) { gap in
                        let a = pts[gap.afterIndex], b = pts[gap.afterIndex + 1]
                        Text(TrendTimeline.gapLabel(seconds: gap.seconds))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .position(x: (a.x + b.x) / 2, y: max(a.y, b.y) + 12)
                    }
                    ForEach(0..<(pts.count - 1), id: \.self) { i in
                        Circle()
                            .fill(.white)
                            .frame(width: 7, height: 7)
                            .position(pts[i])
                    }
                    ForEach(markers.indices, id: \.self) { i in
                        if !markers[i].isRunning {
                            OutcomeIcon(marker: markers[i])
                                .position(x: pts[i].x, y: pts[i].y - (i == pts.count - 1 ? 24 : 15))
                        }
                    }
                    badge(wasSkipped: markers.last?.wasSkipped ?? false, level: l[l.count - 1])
                        .position(pts[pts.count - 1])
                }
            }
        }
    }

    private func badge(wasSkipped: Bool, level: Double) -> some View {
        ZStack {
            Circle().fill(color(level))
            Image(systemName: wasSkipped ? "exclamationmark" : "flame.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }
}

/// Small glyph above a point: how the break ended, with a hand when the user started it.
private struct OutcomeIcon: View {
    let marker: BreakMarker

    var body: some View {
        HStack(spacing: 1) {
            if marker.startedManually {
                Image(systemName: "hand.point.up.left.fill")
            }
            if marker.outcome == .postponed, marker.postponeMinutes > 0 {
                Text(verbatim: "+\(marker.postponeMinutes)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            } else {
                Image(systemName: Self.symbol(marker.outcome))
            }
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(marker.outcome.lowersMomentum ? Color(red: 1, green: 0.62, blue: 0.55) : .white.opacity(0.85))
    }

    static func symbol(_ outcome: BreakOutcome) -> String {
        switch outcome {
        case .completed: "checkmark"
        case .skipped: "forward.fill"
        case .postponed: "clock.arrow.circlepath"
        case .ruleSkipped: "gearshape.fill"
        case .skippedAhead: "forward.end.fill"
        }
    }

    static func title(_ outcome: BreakOutcome) -> String {
        switch outcome {
        case .completed: "wykonana"
        case .skipped: "pominięta"
        case .postponed: "odłożona"
        case .ruleSkipped: "pominięta przez regułę"
        case .skippedAhead: "pominięta przed startem"
        }
    }
}

/// Key for the icons that actually appear on the chart.
struct BreakTrendLegend: View {
    let markers: [BreakMarker]

    var body: some View {
        let shown = markers.filter { !$0.isRunning }
        let outcomes = BreakOutcome.allCases.filter { o in shown.contains { $0.outcome == o } }
        HStack(spacing: 14) {
            ForEach(outcomes, id: \.self) { o in
                Label {
                    Text(LocalizedStringKey(OutcomeIcon.title(o)))
                } icon: {
                    if o == .postponed { Text(verbatim: "+5").font(.system(size: 10, weight: .bold, design: .rounded)) }
                    else { Image(systemName: OutcomeIcon.symbol(o)) }
                }
            }
            if shown.contains(where: \.startedManually) {
                Label("start ręczny", systemImage: "hand.point.up.left.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
    }
}

/// One monotone cubic piece of the curve (see TrendCurve), between points[index] and points[index + 1].
private struct TrendSegment: Shape {
    let points: [CGPoint]
    let index: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = TrendCurve.controls(xs: points.map { Double($0.x) }, ys: points.map { Double($0.y) })[index]
        path.move(to: points[index])
        path.addCurve(to: points[index + 1],
                      control1: CGPoint(x: c.c1x, y: c.c1y),
                      control2: CGPoint(x: c.c2x, y: c.c2y))
        return path
    }
}
