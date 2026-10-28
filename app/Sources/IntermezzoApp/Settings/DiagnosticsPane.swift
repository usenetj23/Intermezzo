import SwiftUI
import IntermezzoKit

/// Latest result of the gate checks, redrawn only when something in it changes (not every tick).
@MainActor
final class GateDiagnostics: ObservableObject {
    static let shared = GateDiagnostics()
    @Published private(set) var report = GateReport()

    func update(_ new: GateReport) {
        if new != report { report = new }
    }
}

/// Why the timer runs or stands: the chain of gates from the clock to the timer, and a board of
/// every factor sorted into "blocks", "lets through" and "no effect right now".
struct DiagnosticsPane: View {
    @ObservedObject private var diag = GateDiagnostics.shared

    private static let red = Color(red: 0.95, green: 0.38, blue: 0.38)
    private static let green = Color(red: 0.35, green: 0.85, blue: 0.55)

    private func color(_ verdict: GateVerdict) -> Color {
        switch verdict {
        case .blocking: return Self.red
        case .passing: return Self.green
        case .inactive: return .secondary
        }
    }

    private func symbol(_ verdict: GateVerdict) -> String {
        switch verdict {
        case .blocking: return "xmark.octagon.fill"
        case .passing: return "checkmark.circle.fill"
        case .inactive: return "minus.circle"
        }
    }

    var body: some View {
        let report = diag.report
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                chain(report)
                board(report)
                Text("Timer rusza, gdy nic go nie blokuje. W strefie pracy wystarczy jedno dopasowanie z włączonych źródeł (kalendarz, VPN, Wi-Fi, miejsce). Karty z przerywaną ramką tylko informują i nie zmieniają timera.")
                    .settingsNote()
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    // MARK: Chain

    private func chain(_ report: GateReport) -> some View {
        HStack(spacing: 6) {
            ForEach(GateGroup.allCases, id: \.self) { group in
                groupNode(group, report: report)
                arrow
            }
            timerNode(report)
        }
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
    }

    private func groupNode(_ group: GateGroup, report: GateReport) -> some View {
        let verdict = report.verdict(of: group)
        let blocking = report.factors.filter { $0.group == group && $0.verdict == .blocking && !$0.informational }.count
        return VStack(spacing: 4) {
            Image(systemName: symbol(verdict))
                .font(.title2)
                .foregroundStyle(color(verdict))
            Text(group.title)
                .font(.caption.weight(.semibold))
            Text(blocking > 0 ? "blokuje: \(blocking)" : (verdict == .passing ? "przepuszcza" : "bez wpływu"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color(verdict).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color(verdict).opacity(0.5)))
    }

    private func timerNode(_ report: GateReport) -> some View {
        let tint: Color = report.onBreak ? .blue : (report.running ? Self.green : .orange)
        let icon = report.onBreak ? "figure.walk.circle.fill" : (report.running ? "play.circle.fill" : "pause.circle.fill")
        return VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(tint)
            Text(report.headline)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1.5))
    }

    // MARK: Board

    private func board(_ report: GateReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            column("Blokuje", .blocking, report)
            column("Przepuszcza", .passing, report)
            column("Bez wpływu teraz", .inactive, report)
        }
    }

    private func column(_ title: String, _ verdict: GateVerdict, _ report: GateReport) -> some View {
        let items = report.items(verdict)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color(verdict)).frame(width: 8, height: 8)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("—").foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(items) { card($0, verdict) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func card(_ factor: GateFactor, _ verdict: GateVerdict) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(factor.title).font(.caption.weight(.semibold))
            Text(factor.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                tag(factor.group.title)
                if factor.informational { tag("tylko informacja") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color(verdict).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color(verdict).opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: factor.informational ? [4, 3] : []))
        )
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
