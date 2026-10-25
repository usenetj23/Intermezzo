import SwiftUI
import IntermezzoKit

/// Menu-bar panel block shown while Pomodoro mode is on: what this pomodoro
/// is for, today's count against the goal, and one-tap interruption logging.
struct PomodoroPanelBlock: View {
    @ObservedObject private var pomodoro = PomodoroController.shared
    @Environment(\.surfaceTheme) private var theme

    private var run: PomodoroRun? { pomodoro.ledger.current }
    private var taskTitle: String {
        let title = run?.taskTitle ?? pomodoro.currentTask?.title ?? ""
        return title.isEmpty ? String(localized: "No task selected") : title
    }

    private var projectName: String { run?.project ?? pomodoro.currentTask?.project ?? "" }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: "🍅")
                if !projectName.isEmpty {
                    Circle().fill(pomodoro.color(forProject: projectName)).frame(width: 8, height: 8)
                        .help(projectName)
                }
                Text(taskTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(run?.taskTitle.isEmpty == false || pomodoro.currentTask != nil
                                     ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                Text(verbatim: "\(pomodoro.completedToday()) / \(pomodoro.dailyGoal)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.accent)
            }
            HStack(spacing: 8) {
                interruptionButton(.internal, title: "Self", symbol: "brain.head.profile",
                                   count: run?.internalInterruptions ?? 0)
                interruptionButton(.external, title: "Other", symbol: "person.wave.2",
                                   count: run?.externalInterruptions ?? 0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    private func interruptionButton(_ kind: PomodoroInterruption, title: LocalizedStringKey,
                                    symbol: String, count: Int) -> some View {
        Button {
            pomodoro.recordInterruption(kind)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(title)
                if count > 0 { Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(.secondary) }
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(run == nil)
        .help(kind == .internal ? "I interrupted myself (mail, a quick look)" : "Someone or something interrupted me")
    }
}
