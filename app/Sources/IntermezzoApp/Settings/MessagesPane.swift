import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct MessagesPane: View {
    @Binding var openMessageID: String?
    @Binding var selection: SettingsPane?
    @State private var readIDs: Set<String> = []
    @State private var searchText = ""
    @AppStorage(Keys.messagesDuringBreak) private var duringBreak = true
    @AppStorage(MessagesStore.breakEveryKey) private var breakEvery = 3
    private let store = MessagesStore()

    private var filtered: [BreakMessage] {
        guard !searchText.isEmpty else { return MessagesCatalog.all }
        let needle = searchText.lowercased()
        return MessagesCatalog.all.filter {
            $0.title.lowercased().contains(needle)
                || $0.subtitle.lowercased().contains(needle)
                || $0.body.lowercased().contains(needle)
        }
    }

    private var opened: BreakMessage? {
        guard let id = openMessageID else { return nil }
        return MessagesCatalog.all.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Szukaj wiadomości…", text: $searchText)
                    .textFieldStyle(.editable)
                    .frame(maxWidth: 220)
                Spacer()
                Button("Oznacz wszystkie jako przeczytane") {
                    store.markAllRead()
                    readIDs = store.readIDs()
                }.settingsAnchor("messages-oznacz-wszystkie-jako-przeczytane")
                .controlSize(.small)
            }
            .padding([.horizontal, .top], 12)

            List {
                Section {
                    Toggle("Pokazuj skrócone porady na ekranie przerwy", isOn: $duringBreak).settingsAnchor("messages-pokazuj-skrocone-porady-na-ekranie-p")
                    if duringBreak {
                        Stepper("Co \(breakEvery) przerwy", value: $breakEvery, in: 1...10)
                    }
                }
                Section("Wiadomości") {
                    ForEach(filtered) { message in
                        Button {
                            openMessageID = message.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: readIDs.contains(message.id)
                                      ? "envelope" : "envelope.fill")
                                    .foregroundStyle(readIDs.contains(message.id)
                                                   ? AnyShapeStyle(.secondary)
                                                   : AnyShapeStyle(Color.accentColor))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(message.title)
                                        .fontWeight(readIDs.contains(message.id) ? .regular : .semibold)
                                    Text(message.subtitle)
                                        .settingsNote()
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { readIDs = store.readIDs() }
        .onChange(of: openMessageID) { _, new in
            if let id = new {
                store.markRead(id: id)
                readIDs = store.readIDs()
            }
        }
        .sheet(isPresented: Binding(
            get: { opened != nil },
            set: { if !$0 { openMessageID = nil } })) {
            if let message = opened {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.title).font(.title2.bold())
                            Text(message.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            openMessageID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                    ScrollView {
                        Text(message.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let pane = message.pane, let target = SettingsPane(rawValue: pane) {
                        Button("Pokaż ustawienia") {
                            openMessageID = nil
                            selection = target
                        }.settingsAnchor("messages-pokaz-ustawienia")
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
                .frame(width: 520, height: 420)
                .themedSheet()
            }
        }
    }
}

// MARK: - Rules
