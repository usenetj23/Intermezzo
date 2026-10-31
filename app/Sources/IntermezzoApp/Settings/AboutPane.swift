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
    @ObservedObject private var updates = UpdateChecker.shared
    @AppStorage(UpdateKeys.enabled) private var checkUpdates = false

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
            Divider().frame(width: 260).padding(.top, 8)
            Text("Aktualizacje").font(.headline)
            Toggle("Sprawdzaj raz na dobę, czy jest nowa wersja", isOn: $checkUpdates).settingsAnchor("about-sprawdzaj-raz-na-dobe-czy-jest-nowa")
                .toggleStyle(.switch)
                .fixedSize()
            HStack(spacing: 10) {
                Button("Sprawdź teraz") { Task { await updates.check(manual: true) } }.settingsAnchor("about-sprawdz-teraz")
                    .disabled(updates.state == .checking)
                updateStatus
            }
            .controlSize(.small)
            Text("Aplikacja pyta GitHub o najnowsze wydanie zwykłym zapytaniem HTTPS, bez identyfikatora i bez danych o Twoim Macu (GitHub widzi Twój adres IP). Niczego nie pobiera ani nie instaluje: nową wersję pobierasz sam ze strony wydań.")
                .settingsNote().settingsAnchor("about-aplikacja-pyta-github-o-najnowsze-wy")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                DiagnosticsCollector.copyToPasteboard {
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { copied = false }
                }
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

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.state {
        case .idle:
            EmptyView()
        case .checking:
            Text("Sprawdzam…").foregroundStyle(.secondary)
        case .upToDate(let version):
            Label("Masz najnowszą wersję (\(version))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let release):
            HStack(spacing: 8) {
                Label("Dostępna wersja \(release.version.description)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.orange)
                Button("Otwórz stronę wydania") { updates.open(release) }.settingsAnchor("about-otworz-strone-wydania")
                Button("Pomiń tę wersję") { updates.skip(release) }.settingsAnchor("about-pomin-te-wersje")
            }
        case .failed(let reason):
            Label("Nie udało się sprawdzić: \(reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }
}

// MARK: - Exercises (edit + assignment)
