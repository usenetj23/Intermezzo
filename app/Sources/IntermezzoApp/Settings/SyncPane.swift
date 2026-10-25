import AppKit
import SwiftUI
import IntermezzoKit

/// Sync between the user's Macs, and a backup, through one or more cloud folders.
struct SyncPane: View {
    @AppStorage(SyncKeys.enabled) private var enabled = 0
    @AppStorage(SyncKeys.deviceName) private var deviceName = ""
    @AppStorage(SyncKeys.scopeWork) private var scopeWork = 1
    @AppStorage(SyncKeys.scopeBreaks) private var scopeBreaks = 1
    @AppStorage(SyncKeys.scopeSettings) private var scopeSettings = 1
    @AppStorage(SyncKeys.scopePomodoro) private var scopePomodoro = 1
    @ObservedObject private var sync = SyncController.shared
    @State private var paths: [String] = []

    var body: some View {
        Form {
            Section {
                Toggle("Synchronizuj i trzymaj kopię w chmurze", isOn: flag($enabled))
                    .onChange(of: enabled) { _, on in if on != 0 { sync.syncNow() } }
                Text("Ustawienia, rejestr pracy, historia przerw i Pomodoro trafiają do wybranych folderów w chmurze. Inne Twoje Maki czytają je stamtąd, a nowy lub przeinstalowany Mac po włączeniu tej opcji z tym samym folderem odzyska wszystko sam. Każdy Mac zapisuje tylko własny plik, więc chmura nigdy nie scala jednej bazy z dwóch miejsc.")
                    .settingsNote()
            }
            if enabled != 0 {
                foldersSection
                scopeSection
                statusSection
            }
        }
        .formStyle(.grouped)
        .onAppear { paths = Self.loadPaths() }
    }

    private var foldersSection: some View {
        let clouds = Self.clouds()
        let others = paths.filter { p in !clouds.contains { $0.path.path == p } }
        return Section("Gdzie") {
            if clouds.isEmpty {
                Text("Na tym Macu nie ma iCloud Drive ani folderu OneDrive, Dropbox czy Google Drive. Wybierz folder ręcznie, np. udział sieciowy.")
                    .settingsNote()
            }
            ForEach(clouds, id: \.path) { cloud in
                Toggle(isOn: Binding(get: { paths.contains(cloud.path.path) },
                                     set: { setFolder(cloud.path.path, on: $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloud.title)
                        Text(Self.display(cloud.path)).settingsNote()
                    }
                }
            }
            ForEach(others, id: \.self) { path in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((path as NSString).lastPathComponent)
                        Text(Self.display(URL(fileURLWithPath: path))).settingsNote()
                    }
                    Spacer()
                    Button("Usuń") { setFolder(path, on: false) }
                }
            }
            HStack {
                Spacer()
                Button("Dodaj inny folder…", action: pickFolder)
            }
            if paths.count > 1 {
                Text("Kopia trafia do każdego zaznaczonego folderu; przy odczycie liczy się najnowszy plik każdego Maca.")
                    .settingsNote()
            }
            TextField("Nazwa tego Maca", text: $deviceName, prompt: Text(Host.current().localizedName ?? "Mac"))
        }
    }

    private var scopeSection: some View {
            Section("Co synchronizować") {
                Toggle("Rejestr pracy (odcinki, korekty, notatki)", isOn: flag($scopeWork))
                Toggle("Historia przerw", isOn: flag($scopeBreaks))
                Toggle("Ustawienia", isOn: flag($scopeSettings))
                Toggle("Pomodoro i projekty", isOn: flag($scopePomodoro))
                Text("Lokalne zostają: uprawnienia, pozycje okien, ścieżki do plików (muzyka, skrypty, obrazy), dzisiejsze liczniki. Przy konflikcie ustawień wygrywa nowsza zmiana. Mac dołączający do folderu z danymi innego Maca najpierw przejmuje jego ustawienia.")
                    .settingsNote()
            }
    }

    private var statusSection: some View {
            Section("Stan") {
                LabeledContent("Ostatnia synchronizacja") {
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                    else if let last = sync.lastSync { Text(last, format: .relative(presentation: .named)) }
                    else { Text("jeszcze nie").foregroundStyle(.secondary) }
                }
                if let error = sync.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                }
                if sync.peers.isEmpty {
                    Text("Nie widać jeszcze innych Maców w tym folderze.").foregroundStyle(.secondary)
                } else {
                    ForEach(sync.peers) { peer in
                        LabeledContent {
                            Text(peer.writtenAt, format: .relative(presentation: .named))
                        } label: {
                            Label(peer.name, systemImage: "laptopcomputer")
                        }
                    }
                }
                Button("Synchronizuj teraz") { sync.syncNow() }
                    .disabled(paths.isEmpty || sync.isSyncing)
            }
    }

    // MARK: Helpers

    private func flag(_ value: Binding<Int>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != 0 }, set: { value.wrappedValue = $0 ? 1 : 0 })
    }

    private func setFolder(_ path: String, on: Bool) {
        var next = paths.filter { $0 != path }
        if on { next.append(path) }
        paths = next
        UserDefaults.standard.set(next, forKey: SyncKeys.folderPaths)
        if on { sync.syncNow() }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Wybierz")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url.path, on: true)
    }

    private static func loadPaths() -> [String] {
        let d = UserDefaults.standard
        return SyncFolders.paths(list: d.stringArray(forKey: SyncKeys.folderPaths),
                                 legacy: d.string(forKey: SyncKeys.folderPath))
    }

    /// Where the files really go: the chosen folder plus the app's subfolder.
    private static func display(_ folder: URL) -> String {
        (SyncController.syncDir(in: folder).path as NSString).abbreviatingWithTildeInPath
    }

    /// Cloud folders that exist on this Mac, found at run time (nothing is assumed installed):
    /// iCloud Drive and every account folder macOS keeps in ~/Library/CloudStorage.
    private static func clouds() -> [(title: String, path: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var out: [(String, URL)] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud.path) { out.append(("iCloud Drive", icloud)) }
        let storage = home.appendingPathComponent("Library/CloudStorage")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: storage.path)) ?? []
        for name in names.sorted() {
            if let title = SyncFolders.cloudTitle(forStorageFolder: name) {
                out.append((title, storage.appendingPathComponent(name)))
            }
        }
        return out
    }
}
