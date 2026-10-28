import SwiftUI
import IntermezzoKit

/// Focus ▸ "Rhythm experiment": alternate two work/break rhythms in blocks of days
/// and show the user's own numbers. Never a verdict.
struct RhythmExperimentSection: View {
    @ObservedObject private var controller = PomodoroController.shared
    @State private var armA = RhythmArm.defaultA
    @State private var armB = RhythmArm.defaultB
    @State private var daysPerBlock = 3
    @State private var confirmStop = false
    /// Setup needs Pomodoro mode; a running experiment stays visible (and stoppable) without it.
    let pomodoroOn: Bool

    var body: some View {
        if pomodoroOn || controller.rhythm != nil { section }
    }

    private var section: some View {
        Section("Rhythm experiment") {
            if let exp = controller.rhythm {
                running(exp)
                if !pomodoroOn {
                    Text("Pomodoro mode is off, so the experiment is paused. Your settings stay at the last rhythm until you stop it.")
                        .settingsNote().settingsAnchor("focus-pomodoro-mode-is-off-so-the-experime")
                }
            } else {
                setup
            }
            Text("These are your own numbers, not a verdict. Fewer disruptions can come from the rhythm, the week or the task.")
                .settingsNote().settingsAnchor("focus-these-are-your-own-numbers-not-a-ver")
        }
    }

    // MARK: Setup

    private var setup: some View {
        Group {
            armEditor("A", $armA)
            armEditor("B", $armB)
            Stepper("Block length: \(daysPerBlock) days", value: $daysPerBlock, in: 2...5)
            Button("Start experiment") {
                controller.startRhythmExperiment(arms: [armA, armB], daysPerBlock: daysPerBlock)
            }.settingsAnchor("focus-start-experiment")
            .disabled(!RhythmExperiment.canStart(arms: [armA, armB]))
            if !RhythmExperiment.canStart(arms: [armA, armB]) {
                Text("Rhythms A and B are the same. Change the work or break minutes of one of them.")
                    .settingsNote().settingsAnchor("focus-rhythms-a-and-b-are-the-same-change")
            }
            Text("Alternates the two rhythms in blocks of days. Your current settings are saved and restored when you stop.")
                .settingsNote().settingsAnchor("focus-alternates-the-two-rhythms-in-blocks")
        }
    }

    private func armEditor(_ title: String, _ arm: Binding<RhythmArm>) -> some View {
        HStack {
            Text("Rhythm \(title)")
            Spacer()
            Stepper("Work \(arm.wrappedValue.workMinutes) min", value: arm.workMinutes, in: 5...120, step: 5)
            Stepper("Break \(arm.wrappedValue.shortBreakMinutes) min", value: arm.shortBreakMinutes, in: 1...30)
        }
    }

    // MARK: Running

    private func running(_ exp: RhythmExperiment) -> some View {
        let cal = Calendar.current
        let today = exp.arm(for: Date(), calendar: cal)
        let results = controller.rhythmResults()
        return Group {
            Text("Today: \(today.label) (block \(exp.blockNumber(for: Date(), calendar: cal)), \(exp.daysPerBlock) days per block)")
                .font(.headline)
            if exp.isContaminated(Date(), calendar: cal) {
                Text("You changed the settings today, so today is left out of the numbers.")
                    .settingsNote().settingsAnchor("focus-you-changed-the-settings-today-so-to")
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Rhythm").bold(); Text("Days").bold(); Text("Pomodoros").bold()
                    Text("Mean disruptions").bold(); Text("Voided").bold()
                }
                ForEach(results, id: \.arm.id) { r in
                    GridRow {
                        Text("\(r.arm.id) \(r.arm.label)")
                        Text("\(r.days)")
                        Text("\(r.pomodoros)")
                        Text(r.pomodoros == 0 ? "–" : String(format: "%.1f", r.meanDisruptions))
                        Text("\(r.voided)")
                    }
                }
            }
            .monospacedDigit()
            ForEach(results.filter { !$0.isEnough }, id: \.arm.id) { r in
                Text("Rhythm \(r.arm.id): not enough days with data yet (\(r.days) of \(RhythmExperiment.minDaysPerArm))")
                    .settingsNote()
            }
            if results.count == 2, results.allSatisfy({ $0.pomodoros > 0 }) {
                Text(difference(results[0], results[1]))
                    .font(.callout)
                    .monospacedDigit()
            }
            Button("Stop and restore my settings", role: .destructive) { confirmStop = true }
                .confirmationDialog("Stop the experiment and restore your previous settings?", isPresented: $confirmStop) {
                    Button("Stop and restore", role: .destructive) { controller.stopRhythmExperiment() }
                }
        }
    }

    /// Plain numbers only: B minus A.
    private func difference(_ a: RhythmArmResult, _ b: RhythmArmResult) -> String {
        let d = b.meanDisruptions - a.meanDisruptions
        let meanA = String(format: "%.1f", a.meanDisruptions)
        let meanB = String(format: "%.1f", b.meanDisruptions)
        let diff = String(format: "%+.1f", d)
        return String(localized: "Mean disruptions per pomodoro: \(a.arm.id) \(meanA), \(b.arm.id) \(meanB) (difference \(diff))")
    }
}
