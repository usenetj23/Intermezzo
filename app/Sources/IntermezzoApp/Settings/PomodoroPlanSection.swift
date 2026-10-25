import SwiftUI
import AppKit
import UniformTypeIdentifiers
import IntermezzoKit

/// Today's plan: tasks with an estimate in pomodoros, the task the next
/// pomodoro is for, and a daily goal.
struct PomodoroPlanSection: View {
    @ObservedObject private var pomodoro = PomodoroController.shared
    @AppStorage(PomodoroKeys.dailyGoal) private var dailyGoal = 8
    @State private var newTitle = ""
    @State private var newProject = ""
    @State private var newEstimate = 2
    @State private var askingNewProject = false
    @State private var newProjectName = ""

    private static let newProjectTag = "\u{0}new"

    var body: some View {
        Section("Plan") {
            Stepper("Daily goal: \(dailyGoal) pomodoros", value: $dailyGoal, in: 1...30)
            ForEach(pomodoro.ledger.tasks) { task in
                taskRow(task)
            }
            VStack(alignment: .leading, spacing: 8) {
                TextField("What will you work on?", text: $newTitle)
                    .textFieldStyle(.editable)
                    .frame(maxWidth: .infinity)
                    .onSubmit(add)
                HStack {
                    projectPicker
                    Stepper("\(newEstimate) 🍅", value: $newEstimate, in: 1...12)
                        .fixedSize()
                    Spacer()
                    Button("Add", action: add)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            forecastLine
            Text("Estimate how many pomodoros a task needs, then compare with the real count: the statistics show how your estimates hold up.")
                .settingsNote()
        }
        .onChange(of: pomodoro.ledger.projects) { _, _ in validateSelection() }
        .alert("New project", isPresented: $askingNewProject) {
            TextField("Name", text: $newProjectName)
            Button("Create") { createProject() }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var projectPicker: some View {
        Picker("Project", selection: Binding(
            get: { newProject },
            set: { choice in
                if choice == Self.newProjectTag {
                    newProjectName = ""
                    askingNewProject = true
                } else {
                    newProject = choice
                }
            })) {
            Text("No project").tag("")
            ForEach(pomodoro.projects) { p in
                Label(p.name, systemImage: "circle.fill")
                    .tint(pomodoro.color(forProject: p.name))
                    .tag(p.name)
            }
            Divider()
            Text("New project…").tag(Self.newProjectTag)
        }
        .labelsHidden()
        .frame(width: 140)
    }

    private func createProject() {
        newProject = pomodoro.createOrRestoreProject(named: newProjectName) ?? newProject
    }

    /// A remembered selection that was renamed or archived elsewhere falls back to "No project".
    private func validateSelection() {
        newProject = pomodoro.ledger.activeProjectName(newProject) ?? ""
    }

    private func add() {
        validateSelection()
        pomodoro.addTask(title: newTitle, estimate: newEstimate, project: newProject)
        newTitle = ""
    }

    /// The plan laid onto today's meetings and the end of working hours.
    @ViewBuilder
    private var forecastLine: some View {
        if let f = pomodoro.forecast() {
            if let finish = f.finishAt {
                Label("The plan fits today: done around \(finish.formatted(date: .omitted, time: .shortened))",
                      systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(.green).font(.caption)
            } else {
                Label("\(f.fitting) of \(f.fitting + f.spill) pomodoros fit before the end of working hours (meetings and breaks included); \(f.spill) move to another day",
                      systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: PomodoroTask) -> some View {
        let isCurrent = pomodoro.currentTask?.id == task.id
        HStack(spacing: 8) {
            Button {
                pomodoro.select(task.id)
            } label: {
                Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
            }
            .buttonStyle(.plain)
            .disabled(task.isFinished)
            .help("Use for the next pomodoro")
            Text(task.title)
                .strikethrough(task.isFinished)
                .foregroundStyle(task.isFinished ? .secondary : .primary)
                .lineLimit(1)
            if !task.project.isEmpty {
                Text(task.project)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(pomodoro.color(forProject: task.project).opacity(0.22)))
            }
            Spacer()
            Text("\(task.done) / \(task.estimate) 🍅")
                .font(.callout.monospacedDigit())
                .foregroundStyle(task.done > task.estimate ? .orange : .secondary)
            if !task.isFinished {
                Button("Done") { pomodoro.finishTask(task.id) }.controlSize(.small)
            }
            Button(role: .destructive) { pomodoro.removeTask(task.id) } label: { Image(systemName: "trash") }
                .controlSize(.small)
        }
    }
}

/// Today, the last 7 days, streak, interruptions and estimate accuracy.
struct PomodoroStatsSection: View {
    @ObservedObject private var pomodoro = PomodoroController.shared
    @State private var reportPeriod = ReportPeriod.week
    @State private var reportError: String?

    var body: some View {
        let today = pomodoro.completedToday()
        let week = pomodoro.week()
        let interrupts = pomodoro.interruptionsToday()
        Section("Pomodoro statistics") {
            HStack(spacing: 24) {
                stat("\(today) / \(pomodoro.dailyGoal)", "today")
                if BreakStyleSettings.motivation.showsStreakCounters {
                    stat("\(pomodoro.streak())", "day streak")
                }
                stat("\(pomodoro.voidedToday())", "voided today")
                stat("\(interrupts.internal) / \(interrupts.external)", "self / other")
            }
            HStack(alignment: .bottom, spacing: 6) {
                let top = max(week.max() ?? 1, 1)
                ForEach(Array(week.enumerated()), id: \.offset) { index, count in
                    VStack(spacing: 3) {
                        Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == week.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.45))
                            .frame(width: 22, height: max(3, CGFloat(count) / CGFloat(top) * 46))
                    }
                }
                Spacer()
            }
            .frame(height: 70, alignment: .bottom)
            if let ratio = pomodoro.ledger.estimateRatio() {
                Text(ratioText(ratio)).settingsNote()
            }
            projectTotals
            goldenHours
            reportControls
            Text("A pomodoro counts only when you finish it. Resetting the timer or leaving for a long time voids it.")
                .settingsNote()
        }
    }

    private var reportControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Report")
                Spacer()
                Picker("Report", selection: $reportPeriod) {
                    ForEach(ReportPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Export report…", action: exportReport)
            }
            if let reportError { Text(reportError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf, .commaSeparatedText]
        panel.nameFieldStringValue = String(localized: "Intermezzo report.pdf")
        panel.message = String(localized: "Choose PDF (summary and a day ribbon per day) or CSV (one line per pomodoro).")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let range = reportPeriod.range()
        let data = ReportData.load(range: range)
        do {
            if url.pathExtension.lowercased() == "csv" {
                try ReportExporter.exportCSV(data: data, range: range, to: url)
            } else {
                try ReportExporter.exportPDF(data: data, range: range, to: url)
            }
            reportError = nil
        } catch {
            reportError = error.localizedDescription
        }
    }

    /// Time per project over the last 7 days.
    @ViewBuilder
    private var projectTotals: some View {
        let totals = pomodoro.projectTotalsThisWeek()
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Last 7 days by project").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(totals, id: \.project) { t in
                    HStack {
                        Text(t.project.isEmpty ? String(localized: "No project") : t.project)
                        Spacer()
                        Text("\(t.count) 🍅 · \(AudioFit.clock(TimeInterval(t.seconds)))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    /// Hours in which your pomodoros had the fewest interruptions and app switches.
    @ViewBuilder
    private var goldenHours: some View {
        let hours = pomodoro.goldenHours()
        if hours.count >= 2, let best = hours.first, let worst = hours.last {
            VStack(alignment: .leading, spacing: 2) {
                Label("Your calmest hour: \(hourText(best.hour))", systemImage: "sun.max")
                    .font(.callout)
                let bestScore = String(format: "%.1f", best.disruptions)
                let worstScore = String(format: "%.1f", worst.disruptions)
                let worstHour = hourText(worst.hour)
                let weight = Int(PomodoroRecord.interruptionWeight)
                Text("Averages \(bestScore) disruption points per pomodoro against \(worstScore) at \(worstHour) (an interruption counts \(weight), an app switch 1). Put demanding tasks there.")
                    .settingsNote()
            }
        } else {
            Text("Your calmest hour appears after about three pomodoros in at least two different hours of the day.")
                .settingsNote()
        }
    }

    private func hourText(_ hour: Int) -> String { String(format: "%d:00", hour) }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(label).settingsNote()
        }
    }

    private func ratioText(_ ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        if percent > 110 { return String(localized: "Finished tasks took \(percent)% of the estimate: plan more pomodoros per task.") }
        if percent < 90 { return String(localized: "Finished tasks took \(percent)% of the estimate: you can plan tighter.") }
        return String(localized: "Finished tasks took \(percent)% of the estimate: your estimates hold up.")
    }
}


/// Range choices of the report picker.
enum ReportPeriod: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        }
    }

    func range(now: Date = Date()) -> ReportRange {
        switch self {
        case .today: return .day(now)
        case .week: return .week(endingOn: now)
        case .month: return .month(containing: now)
        }
    }
}
