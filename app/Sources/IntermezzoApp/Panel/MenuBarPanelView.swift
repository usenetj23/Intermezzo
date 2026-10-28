import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct MenuBarPanelView: View {
    @ObservedObject var coordinator: BreakCoordinator
    @AppStorage(Keys.strictMode) private var strictMode = false
    // Temptation blockers (Advanced pane).
    @AppStorage(Keys.hidePause) private var hidePause = false
    @AppStorage(Keys.hideMakeDue) private var hideMakeDue = false
    @AppStorage(Keys.hideReset) private var hideReset = false
    @AppStorage(Keys.hideQuit) private var hideQuit = false
    @AppStorage(PomodoroKeys.enabled) private var pomodoroMode = false
    @AppStorage(LightKeys.enabled) private var lightEnabled = false
    @ObservedObject private var light = LightController.shared
    @ObservedObject private var awake = KeepAwakeController.shared

    @Environment(\.surfaceTheme) private var theme

    var strictBreakEnabled: Bool { strictMode && coordinator.isOnBreak }

    private var accent: Color {
        if coordinator.isOnBreak { return Color(red: 1.0, green: 0.66, blue: 0.30) }
        if coordinator.engineIsPaused { return Color.gray }
        return theme.accent
    }

    private var caption: String {
        if coordinator.isOnBreak { return String(localized: "do końca przerwy") }
        if coordinator.engineIsPaused { return coordinator.pauseReasonText }
        return String(localized: "do następnej przerwy")
    }

    var body: some View {
        VStack(spacing: 16) {
            // Pierścień: postęp cyklu pracy (lub bieżącej przerwy). Statyczny —
            // zmienia się raz na sekundę, bez animacji ani cieni.
            ZStack {
                Circle().stroke(Color.white.opacity(0.20), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: coordinator.ringProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 3) {
                    Text(coordinator.countdownText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 18)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, 2)

            Text(coordinator.completedTodayDisplay)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if pomodoroMode && !coordinator.isOnBreak {
                PomodoroPanelBlock()
            }

            if coordinator.isOnBreak {
                HStack(spacing: 8) {
                    PanelButton(title: "+1 min", symbol: "plus.circle", kind: .tile) {
                        coordinator.snooze(minutes: 1)
                    }
                    PanelButton(title: "+5 min", symbol: "plus.circle.fill", kind: .tile) {
                        coordinator.snooze(minutes: 5)
                    }
                }
                if strictBreakEnabled {
                    TwoStepSkipButton { coordinator.handleSkip() }
                } else {
                    PanelButton(title: String(localized: "Pomiń przerwę"), symbol: "forward.end.fill", kind: .primary,
                                tint: accent) { coordinator.handleSkip() }
                }
            } else {
                if !hideMakeDue {
                    PanelButton(title: String(localized: "Przerwa teraz"), symbol: "cup.and.saucer.fill", kind: .primary) {
                        coordinator.takeShortNow()
                        AppDelegate.shared?.dismissPanel()
                    }
                    PanelButton(title: String(localized: "Długa przerwa"), symbol: "figure.walk", kind: .secondary) {
                        coordinator.takeLongNow()
                        AppDelegate.shared?.dismissPanel()
                    }
                }
                HStack(spacing: 8) {
                    PanelButton(title: "+1 min", symbol: "plus", kind: .tile,
                                isEnabled: coordinator.canSnoozeNow) {
                        coordinator.snooze(minutes: 1)
                    }
                    PanelButton(title: "+5 min", symbol: "plus.square", kind: .tile,
                                isEnabled: coordinator.canSnoozeNow) {
                        coordinator.snooze(minutes: 5)
                    }
                    if !hideReset {
                        PanelButton(title: String(localized: "Reset"), symbol: "arrow.counterclockwise", kind: .tile) {
                            coordinator.resetAll()
                            AppDelegate.shared?.dismissPanel()
                        }
                    }
                }
            }

            PanelButton(title: awake.manualLevel == nil ? String(localized: "Czuwanie: włącz na godzinę")
                                                        : String(localized: "Czuwanie: wyłącz"),
                        symbol: "cup.and.saucer", kind: .ghost) {
                awake.manualLevel == nil ? awake.turnOn(duration: .minutes(60)) : awake.turnOff()
            }
            if lightEnabled {
                PanelButton(title: light.pausedUntil == nil ? String(localized: "Światło: wyłącz na godzinę")
                                                            : String(localized: "Światło: wznów"),
                            symbol: light.pausedUntil == nil ? "sun.max" : "moon.stars", kind: .ghost) {
                    light.pausedUntil == nil ? light.disable(forMinutes: 60) : light.resumeNow()
                }
            }

            HStack(spacing: 8) {
                if !hidePause {
                    PanelButton(title: coordinator.engineIsPaused ? String(localized: "Wznów") : String(localized: "Wstrzymaj"),
                                symbol: coordinator.engineIsPaused ? "play.fill" : "pause.fill",
                                kind: .ghost) { coordinator.togglePause() }
                }
                PanelButton(title: String(localized: "Ustawienia"), symbol: "gearshape", kind: .ghost, iconOnly: true) {
                    AppDelegate.shared?.openSettingsWindow()
                }
                if !hideQuit {
                    PanelButton(title: String(localized: "Zakończ"), symbol: "power", kind: .ghost, iconOnly: true) {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

// MARK: - Strict-mode skip (confirm within 2 s, else reset)

struct TwoStepSkipButton: View {
    let onSkip: () -> Void
    @State private var armed = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            if armed {
                resetTask?.cancel()
                armed = false
                onSkip()
            } else {
                armed = true
                resetTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { armed = false }
                }
            }
        } label: {
            Text(armed ? "Na pewno? Kliknij ponownie" : "Skip break")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(armed ? .red : .orange)
    }
}

// MARK: - Settings window (sidebar)
