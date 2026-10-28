import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct AboutPane: View {
    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        VStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 48))
            Text("Intermezzo").font(.title).bold()
            Text("Version \(version) — break reminder for macOS")
                .foregroundStyle(.secondary)
            Text(L(BreakContent.trivia.randomElement() ?? ""))
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
                .font(.callout)
            Divider().frame(width: 260).padding(.top, 12)
            Text("Diagnostyka").font(.headline)
            HStack(spacing: 10) {
                Button("Otwórz logi…") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: Trace.logPath))
                }.settingsAnchor("about-otworz-logi")
                Button("Ustawienia systemowe…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }.settingsAnchor("about-ustawienia-systemowe")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Exercises (edit + assignment)
