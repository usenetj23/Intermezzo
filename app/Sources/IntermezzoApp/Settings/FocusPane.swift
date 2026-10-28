import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct FocusPane: View {
    @AppStorage(Keys.pomodoroMode) private var pomodoroMode = false
    @AppStorage(Keys.cycleMinutes) private var cycleMinutes = 45
    @AppStorage(Keys.shortBreakSeconds) private var shortBreakSeconds = 300
    @AppStorage(Keys.longBreakSeconds) private var longBreakSeconds = 900
    @AppStorage(Keys.longBreakEvery) private var longBreakEvery = 4

    private func applyClassicPomodoro() {
        cycleMinutes = 25; shortBreakSeconds = 300
        longBreakSeconds = 900; longBreakEvery = 4
    }
    private func applyLongFocus() {
        cycleMinutes = 50; shortBreakSeconds = 600
        longBreakSeconds = 900; longBreakEvery = 3
    }

    var body: some View {
        Form {
            Section("Pomodoro Technique") {
                Toggle("Enable Pomodoro mode", isOn: $pomodoroMode).settingsAnchor("focus-enable-pomodoro-mode")
                if pomodoroMode {
                    Button("Classic 25/5 (4 → 15 min)") { applyClassicPomodoro() }.settingsAnchor("focus-classic-25-5-4-15-min")
                    Button("Deep focus 50/10") { applyLongFocus() }.settingsAnchor("focus-deep-focus-50-10")
                    Text("Work one pomodoro, then take the suggested break fully. Pick a task and log interruptions from the menu-bar panel.")
                        .settingsNote().settingsAnchor("focus-work-one-pomodoro-then-take-the-sugg")
                } else {
                    Text("Pomodoro structures work into focused sprints with a real break after each. Turn it on to pick a preset.")
                        .settingsNote().settingsAnchor("focus-pomodoro-structures-work-into-focuse")
                }
            }
            SeamBreaksSection().expertOnly()
            RhythmExperimentSection(pomodoroOn: pomodoroMode).expertOnly()
            SessionAwareSection().expertOnly()
            FocusShortcutsSection().expertOnly()
            if pomodoroMode {
                PomodoroPlanSection()
                PomodoroProjectsSection().expertOnly()
                ProjectSensorsSection().expertOnly()
                PomodoroStatsSection()
            }
        }
        .formStyle(.grouped)
    }
}
