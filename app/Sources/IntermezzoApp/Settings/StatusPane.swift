import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct StatusPane: View {
    /// Not observed here: the countdown changes every second, and observing it would redraw the whole form
    /// (trend chart included) every second. The live rows below observe it themselves.
    private let coordinator: BreakCoordinator
    @ObservedObject private var health = MenuBarHealth.shared
    @State private var trend: [BreakMarker] = []
    private let trendRefresh = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        self.coordinator = AppDelegate.shared.coordinator
    }

    var body: some View {
        Form {
            if health.parked {
                Section {
                    Label {
                        Text("macOS schował ikonę Intermezzo, bo pasek menu jest pełny (notch). Odliczanie widać w pływającej pastylce — przeciągnij ją, gdzie chcesz. Aby odzyskać ikonę, wyłącz lub przesuń inne elementy paska (System → Pasek menu).")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Section("Teraz") {
                StatusNowRow(coordinator: coordinator, onBreaksChanged: refreshTrend)
            }
            if trend.count >= 2 {
                Section("Trend przerw") {
                    VStack(spacing: 6) {
                        BreakTrendChart(markers: trend)
                            .frame(height: 116)
                        BreakTrendLegend(markers: trend)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("Zdrowie oczu") {
                StatusScreenTimeRow(coordinator: coordinator)
                Text("Orientacyjny próg ryzyka: ok. 4 h dziennie (Kaur i in. 2022).")
                    .settingsNote()
            }
            Section("Akcje") {
                HStack(spacing: 10) {
                    Button("Pauza teraz") { coordinator.takeShortNow(source: "status-pane") }
                    Button("Długa pauza") { coordinator.takeLongNow(source: "status-pane") }
                    StatusSnoozeButtons(coordinator: coordinator)
                    Button("Pomiń najbliższą") { coordinator.handleSkip(source: "status-pane") }
                }
                HStack(spacing: 10) {
                    Button("Wstrzymaj timer") { coordinator.pauseAll() }
                        .settingsAnchor("pause")
                    Button("Wznów timer") { coordinator.resumeAll() }
                    Button("Zresetuj cykl") { coordinator.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollsToSettingsAnchor()
        .frame(minWidth: 520, minHeight: 420)
        // The chart changes only when a break starts, ends or is skipped; no need to refetch every tick.
        .onAppear(perform: refreshTrend)
        .onReceive(trendRefresh) { _ in refreshTrend() }
    }

    private func refreshTrend() {
        trend = coordinator.buildTrend(now: Date())
    }
}

/// +1 / +5, enabled only while a break is on screen or about to start (redrawn with the countdown).
private struct StatusSnoozeButtons: View {
    @ObservedObject var coordinator: BreakCoordinator

    var body: some View {
        Group {
            Button("+1 min") { coordinator.snooze(minutes: 1) }
            Button("+5 min") { coordinator.snooze(minutes: 5) }
        }
        .disabled(!coordinator.canSnoozeNow)
        .help("Odroczenie działa podczas przerwy i tuż przed nią.")
    }
}

/// The live part of the Status pane: redrawn every second on its own.
private struct StatusNowRow: View {
    @ObservedObject var coordinator: BreakCoordinator
    let onBreaksChanged: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: coordinator.statusSymbol)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.engineIsPaused && !coordinator.isOnBreak
                     ? coordinator.pauseReasonText : coordinator.headlineText)
                    .font(.headline)
                Text(coordinator.countdownText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(coordinator.completedTodayDisplay)
                    .settingsNote()
            }
        }
        // The chart changes only when a break starts, ends or is skipped.
        .onChange(of: coordinator.isOnBreak) { _, _ in onBreaksChanged() }
        .onChange(of: coordinator.completedTodayDisplay) { _, _ in onBreaksChanged() }
    }
}

private struct StatusScreenTimeRow: View {
    @ObservedObject var coordinator: BreakCoordinator

    var body: some View {
        LabeledContent("Aktywny czas przy ekranie dziś",
                       value: coordinator.screenTimeToday.isEmpty ? "—" : coordinator.screenTimeToday)
    }
}
