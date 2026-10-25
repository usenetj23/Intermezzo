import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

/// Built-in catalog of ready-made AppleScript rules plus the user's own scripts.
/// Install = write the script to our Application Scripts folder + add it as a rule;
/// the editor changes a script's settings or code, or creates a new one.
/// Everything local — no downloads, no vendor catalog, no network.
struct ScriptGalleryPane: View {
    /// Bumped to redraw: whether a script is installed is read from the disk when a row is drawn.
    @State private var refreshTick = 0
    @State private var custom: [CustomScript] = []
    @State private var message = ""
    @State private var editing: ScriptEditorTarget?
    @State private var deleting: CustomScript?

    var body: some View {
        List {
            Section {
                Text("Zainstaluj gotowe reguły-skrypty albo utwórz własne. Skrypty trafiają do Biblioteka → Application Scripts → com.automit.Intermezzo → Rules i zostają dodane jako reguła „Odrocz”. Wynik reguły zmienisz na stronie Reguły, a nastawy skryptu (np. listę aplikacji albo godziny) w edytorze.")
                    .settingsNote()
                HStack {
                    Spacer()
                    Button("Nowy skrypt…") { editing = .new() }
                }
            }
            if !custom.isEmpty {
                Section("Własne skrypty") {
                    ForEach(custom) { script in
                        HStack {
                            Text(script.name).font(.headline)
                            Spacer()
                            Button("Edytuj…") { editing = ScriptEditorTarget(url: script.url, gallery: nil) }
                            Button("Pokaż w Finderze") {
                                NSWorkspace.shared.activateFileViewerSelecting([script.url])
                            }
                            Button("Usuń", role: .destructive) { deleting = script }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section("Galeria") {
                ForEach(ScriptGallery.catalog) { script in
                    galleryRow(script)
                }
                .id(refreshTick)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .task { refresh() }
        // Scripts may be added or removed in Finder while the window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .frame(minWidth: 560, minHeight: 440)
        .sheet(item: $editing) { target in
            ScriptEditorSheet(target: target, onSaved: refresh)
        }
        .confirmationDialog("Usunąć skrypt?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { script in
            Button("Usuń skrypt i jego regułę", role: .destructive) {
                ScriptGallery.remove(script.url)
                refresh()
            }
            Button("Anuluj", role: .cancel) {}
        } message: { script in
            Text("„\(script.name)” zniknie z dysku razem z regułą, która go uruchamia.")
        }
    }

    private func galleryRow(_ script: GalleryScript) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(localized: script.title).font(.headline)
                Spacer()
                if ScriptGallery.isInstalled(script) {
                    Button("Edytuj…") {
                        editing = ScriptEditorTarget(url: ScriptGallery.installedPath(for: script), gallery: script)
                    }
                    Button("Pokaż w Finderze") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [ScriptGallery.installedPath(for: script)])
                    }
                    Button("Odinstaluj", role: .destructive) {
                        deleting = CustomScript(url: ScriptGallery.installedPath(for: script), name: L(script.title))
                    }
                } else {
                    Button("Zainstaluj") {
                        install(script)
                    }
                    .tint(.accentColor)
                }
            }
            Text(localized: script.summary)
                .settingsNote()
            Text(localized: script.outcomeNote)
                .settingsNote()
        }
        .padding(.vertical, 4)
    }

    private func refresh() {
        custom = ScriptGallery.customScripts()
        refreshTick += 1
        Trace.log("script gallery: \(ScriptGallery.catalog.filter { ScriptGallery.isInstalled($0) }.count) installed in \(ScriptGallery.scriptsDir.path)")
    }

    private func install(_ script: GalleryScript) {
        guard ScriptGallery.install(script) else {
            message = String(localized: "Instalacja nie powiodła się.")
            return
        }
        ScriptGallery.addRule(path: ScriptGallery.installedPath(for: script).path,
                              outcome: ScriptGallery.suggestedOutcome(for: script))
        refresh()
    }
}

// MARK: - Advanced
