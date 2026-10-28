import SwiftUI
import IntermezzoKit

/// Focus ▸ "Focus through Shortcuts": run one of the user's own Shortcuts at
/// session start, break start and break end. Off by default; while off it does
/// not even list the user's shortcuts.
struct FocusShortcutsSection: View {
    private enum ListState: Equatable {
        case idle, loading
        case done(ShortcutListing)
    }

    @AppStorage(ShortcutPlan.enabledKey) private var enabled = false
    @ObservedObject private var status = FocusShortcutsStatus.shared
    @State private var listState: ListState = .idle

    private var names: [String] {
        if case .done(let listing) = listState { return listing.names }
        return []
    }

    var body: some View {
        Section("Focus through Shortcuts") {
            Toggle("Run my Shortcuts to change Focus", isOn: $enabled).settingsAnchor("focus-run-my-shortcuts-to-change-focus")
            if enabled {
                if let message = listMessage {
                    Text(message)
                        .settingsNote()
                }
                ForEach(FocusEvent.allCases, id: \.self) { event in
                    FocusShortcutRow(event: event, names: names,
                                     isRunning: status.running.contains(event))
                }
                HStack {
                    Button(listState == .loading ? "Refreshing…" : "Refresh list") { refresh() }
                        .disabled(listState == .loading)
                    Spacer()
                    if !status.lastStatus.isEmpty {
                        Text(status.lastStatus)
                            .settingsNote()
                            .lineLimit(2)
                    }
                }
                Text("Your Mac and iPhone share Focus only if ‘Share across devices’ is on in System Settings → Focus. Check once by hand.")
                    .settingsNote().settingsAnchor("focus-your-mac-and-iphone-share-focus-only")
            }
        }
        .onAppear { if enabled { refresh() } }
        .onChange(of: enabled) { _, isOn in if isOn { refresh() } }
    }

    private var listMessage: String? {
        switch listState {
        case .idle: return nil
        case .loading: return String(localized: "Loading your shortcuts…")
        case .done(.unavailable): return String(localized: "The Shortcuts command line tool is not available on this Mac.")
        case .done(.failed): return String(localized: "Could not read your shortcuts. Try Refresh list.")
        case .done(.loaded(let names)) where names.isEmpty:
            return String(localized: "You have no shortcuts yet. Create one in the Shortcuts app (e.g. “Set Focus”), then refresh.")
        case .done(.loaded): return nil
        }
    }

    @MainActor private func refresh() {
        guard listState != .loading else { return }
        listState = .loading
        Task {
            let listing = await FocusShortcutsStatus.shared.sharedListing()
            listState = .done(listing)
        }
    }
}

/// One event: a picker of the user's shortcuts (+ None) and a confirmed "Run now".
private struct FocusShortcutRow: View {
    let event: FocusEvent
    let names: [String]
    let isRunning: Bool
    @AppStorage private var selected: String
    @State private var confirming = false

    init(event: FocusEvent, names: [String], isRunning: Bool) {
        self.event = event
        self.names = names
        self.isRunning = isRunning
        _selected = AppStorage(wrappedValue: "", event.defaultsKey)
    }

    private var label: String { FocusShortcutsStatus.label(event) }
    private var hasSelection: Bool { ShortcutPlan.shortcut(for: event, settings: [event: selected]) != nil }
    private var shown: String { ShortcutPlan.displayName(selected) }

    var body: some View {
        HStack {
            Picker(label, selection: $selected) {
                Text("None").tag("")
                ForEach(names, id: \.self) { Text(ShortcutPlan.displayName($0)).tag($0) }
                // Keep a saved name visible even if it is gone from Shortcuts.
                if !selected.isEmpty && !names.contains(selected) {
                    Text("\(shown) (missing)").tag(selected)
                }
            }
            Button(isRunning ? "Running…" : "Run now") { confirming = true }
                .disabled(!hasSelection)
        }
        .confirmationDialog("Run “\(shown)” now?", isPresented: $confirming) {
            Button("Run Shortcut") { FocusShortcuts.fire(event) }.settingsAnchor("focus-run-shortcut")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs your shortcut and will change your Focus — on your iPhone too if Focus is shared across devices.")
        }
    }
}
