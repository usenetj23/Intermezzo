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
    @State private var copied = false

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
            Button {
                DiagnosticsCollector.copyToPasteboard()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { copied = false }
            } label: {
                Label(LocalizedStringKey(copied ? "Skopiowano do schowka" : "Kopiuj diagnostykę"),
                      systemImage: copied ? "checkmark" : "doc.on.clipboard")
            }
            .controlSize(.small)
            Text("Kopiuje do schowka wersję aplikacji i macOS, model Maca, monitory, stan uprawnień i funkcje, które się wycofały, oraz kilka linii dziennika o świetle i multimediach. Bez nazw sieci, tytułów z kalendarza, miejsc i nazwy użytkownika. Nic nie jest wysyłane: wklej to do zgłoszenia na GitHubie.")
                .settingsNote().settingsAnchor("about-kopiuje-do-schowka-wersje-aplikacji")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Exercises (edit + assignment)
