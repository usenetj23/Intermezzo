import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct BreaksPane: View {
    @AppStorage(Keys.cycleMinutes) private var cycleMinutes = 45
    @AppStorage(Keys.shortBreakSeconds) private var shortBreakSeconds = 300
    @AppStorage(Keys.longBreakSeconds) private var longBreakSeconds = 900
    @AppStorage(Keys.longBreakEvery) private var longBreakEvery = 4
    @AppStorage(Keys.playSound) private var playSound = true
    @AppStorage(MediaPauseKeys.enabled) private var pauseMedia = true
    @AppStorage(MediaPauseKeys.resume) private var resumeMedia = true
    @AppStorage(Keys.cursorCountdown) private var cursorCountdown = true
    @AppStorage(Keys.breakLeadPopup) private var breakLeadPopup = 30
    @AppStorage(ReminderKeys.hideSkip) private var reminderHideSkip = false
    @AppStorage(ReminderKeys.hideDelay) private var reminderHideDelay = false
    @AppStorage(Keys.strictMode) private var strictMode = false
    @State private var actionItems: [BreakActionItem] = []
    @AppStorage(ScriptActionKeys.enabled) private var scriptsEnabled = false
    @State private var scriptPaths: [String: String] = [
        ScriptActionKeys.startPath: UserDefaults.standard.string(forKey: ScriptActionKeys.startPath) ?? "",
        ScriptActionKeys.endPath: UserDefaults.standard.string(forKey: ScriptActionKeys.endPath) ?? "",
    ]

    /// "Dziś: 750 ml (woda 500, kawa 250)" — live hydration balance shown
    /// next to the drink-editor row (recomputed whenever the pane redraws).
    private var hydrationTodayText: String {
        let s = HydrationStore.todaySummary()
        guard s.totalMl > 0 else { return String(localized: "Dziś: jeszcze nic zapisane") }
        let parts = s.byKind.map { "\(L($0.0)) \($0.1) ml" }.joined(separator: ", ")
        return String(localized: "Dziś: \(s.totalMl) ml (\(parts))")
    }

    private func durationText(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s"
    }

    var body: some View {
        Form {
            BreakPresetSection()
            BreakStyleSection()
            RemindersSection().expertOnly()
            Section("Focus Duration") {
                Slider(value: Binding(get: { Double(cycleMinutes) },
                                      set: { cycleMinutes = Int($0) }),
                       in: 10...90, step: 5)
                Text("Break reminder every \(cycleMinutes) min")
                    .foregroundStyle(.secondary)
            }
            Section("Short Break") {
                let shortRange = BreakLengthLimits.shortRange(longSeconds: longBreakSeconds)
                Slider(value: Binding(get: { Double(shortBreakSeconds) },
                                      set: { shortBreakSeconds = Int($0) }),
                       in: Double(shortRange.lowerBound)...Double(shortRange.upperBound), step: 10)
                Text("Duration: \(durationText(shortBreakSeconds))")
                    .foregroundStyle(.secondary)
                Text("Nie może być dłuższa niż długa przerwa (\(durationText(longBreakSeconds))).")
                    .settingsNote()
            }
            Section("Long Break") {
                let longRange = BreakLengthLimits.longRange(shortSeconds: shortBreakSeconds)
                Slider(value: Binding(get: { Double(longBreakSeconds) },
                                      set: { longBreakSeconds = Int($0) }),
                       in: Double(longRange.lowerBound)...Double(longRange.upperBound), step: 30)
                Text("Duration: \(durationText(longBreakSeconds))")
                    .foregroundStyle(.secondary)
                Text("Nie może być krótsza niż krótka przerwa (\(durationText(shortBreakSeconds))).")
                    .settingsNote()
                Stepper("Long break after \(longBreakEvery) short breaks",
                      value: $longBreakEvery, in: 2...12)
            }
            Section {
                Toggle("Play sound at break start", isOn: $playSound)
                Toggle("Wstrzymuj wideo i muzykę na czas przerwy", isOn: $pauseMedia)
                if pauseMedia {
                    Toggle("Wznawiaj odtwarzanie po przerwie", isOn: $resumeMedia)
                }
                Toggle("Countdown popup next to cursor", isOn: $cursorCountdown)
                if cursorCountdown {
                    Group {
                        Stepper("Show interactive popup in last \(breakLeadPopup) s",
                              value: $breakLeadPopup, in: 10...300, step: 5)
                        Toggle("Hide Skip button in reminder (strict)",
                              isOn: $reminderHideSkip)
                        Toggle("Hide Delay (+1/+5) buttons in reminder (strict)",
                              isOn: $reminderHideDelay)
                    }
                    .expertOnly()
                }
                Toggle("Strict mode (skip needs confirmation)", isOn: $strictMode)
                    .expertOnly()
            }

            RelaxationAudioSection()

            Section("Break Actions") {
                ForEach(actionItems.indices, id: \.self) { i in
                    actionEditor(i)
                }
                Button("＋ Add Action") {
                    actionItems.append(BreakActionItem())
                    persistActions()
                }
                Text("Actions run at three points: Before Due (offset seconds before the break), After Start, and After Any End — completed, postponed or skipped.")
                    .settingsNote()
            }
            .expertOnly()

            Section("Break Scripts") {
                Toggle("Run scripts when breaks start and end", isOn: $scriptsEnabled)
                if scriptsEnabled {
                    scriptPathRow(title: "When break starts:", key: ScriptActionKeys.startPath)
                    scriptPathRow(title: "When break ends:", key: ScriptActionKeys.endPath)
                    Text("AppleScript (.applescript/.scpt) or shell scripts run at break start and after any end — e.g. mute audio on start, restore on end.")
                        .settingsNote()
                }
            }
            .expertOnly()

        }
        .formStyle(.grouped)
        .onAppear {
            let fixed = BreakLengthLimits.reconciled(short: shortBreakSeconds, long: longBreakSeconds)
            if fixed.short != shortBreakSeconds { shortBreakSeconds = fixed.short }
            if fixed.long != longBreakSeconds { longBreakSeconds = fixed.long }
        }
        .onAppear {
            actionItems = BreakActionStore.decode(UserDefaults.standard.data(forKey: BreakActionStore.storageKey)) ?? []
        }
    }







    // MARK: Break Actions editor

    private func itemBinding<T>(_ i: Int, _ keyPath: WritableKeyPath<BreakActionItem, T>) -> Binding<T> {
        Binding(
            get: { actionItems[i][keyPath: keyPath] },
            set: { actionItems[i][keyPath: keyPath] = $0; persistActions() })
    }

    private func persistActions() {
        if let data = BreakActionStore.encode(actionItems) {
            UserDefaults.standard.set(data, forKey: BreakActionStore.storageKey)
        }
    }

    private static let actionKindNames: [BreakActionKind: String] = [
        .notification: String(localized: "Display Notification"),
        .playSound: String(localized: "Play Sound"),
        .fadeoutSound: String(localized: "Fadeout Sound"),
        .flashScreen: String(localized: "Flash Screen"),
        .speakText: String(localized: "Speak Text"),
        .soundVolume: String(localized: "Sound Volume"),
        .musicPause: String(localized: "Music Pause"),
        .musicPlay: String(localized: "Music Play"),
        .logDrink: String(localized: "Zapisz napój (Nawodnienie)"),
        .script: String(localized: "Run Script"),
    ]

    private static let systemSounds = ["Glass", "Funk", "Bell", "Ping", "Tink",
                                       "Submarine", "Sosumi", "Hero", "Purr"]

    @ViewBuilder
    private func actionEditor(_ i: Int) -> some View {
        let kind = actionItems[i].kind
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker("", selection: itemBinding(i, \.kind)) {
                    ForEach(BreakActionKind.allCases, id: \.self) { k in
                        Text(Self.actionKindNames[k] ?? k.rawValue).tag(k)
                    }
                }
                .frame(width: 168)
                Picker("", selection: itemBinding(i, \.when)) {
                    Text("Before Due").tag(BreakActionWhen.beforeDue)
                    Text("After Start").tag(BreakActionWhen.afterStart)
                    Text("After Fade In").tag(BreakActionWhen.afterFadeIn)
                    Text("Before Fade Out").tag(BreakActionWhen.beforeFadeOut)
                    Text("Before Finish").tag(BreakActionWhen.beforeFinish)
                    Text("After Finish").tag(BreakActionWhen.afterFinish)
                    Text("After Postpone/Skip").tag(BreakActionWhen.afterPostpone)
                    Text("After Any End").tag(BreakActionWhen.afterAnyEnd)
                    Text("When Button Clicked").tag(BreakActionWhen.buttonClicked)
                }
                .frame(width: 190)
                if actionItems[i].when != .buttonClicked {
                    // Editable seconds field — the stepper was too slow for
                    // e.g. "fire 180 s before due" and clipped the row.
                    HStack(spacing: 4) {
                        TextField("0", value: itemBinding(i, \.offsetSeconds),
                                format: .number)
                            .textFieldStyle(.editable).labelsHidden()
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                        Text(actionItems[i].when == .beforeDue
                             ? "s przed" : "s po")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Toggle("On", isOn: itemBinding(i, \.enabled))
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button { moveActionItem(i, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                Button { moveActionItem(i, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == actionItems.count - 1)
                Button { removeActionItem(i) } label: { Image(systemName: "trash") }
            }

            switch kind {
            case .logDrink:
                HStack(spacing: 8) {
                    Picker("", selection: itemBinding(i, \.drinkKind)) {
                        ForEach(HydrationStore.drinkKinds, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    TextField("ml", value: itemBinding(i, \.amountMl), format: .number)
                        .textFieldStyle(.editable).labelsHidden()
                        .frame(width: 60)
                    Text("ml")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(hydrationTodayText)
                        .settingsNote()
                }
            case .notification:
                HStack {
                    TextField("Title", text: itemBinding(i, \.title))
                        .textFieldStyle(.editable).labelsHidden().frame(maxWidth: 180)
                    TextField("Message", text: itemBinding(i, \.message))
                        .textFieldStyle(.editable).labelsHidden().frame(maxWidth: 340)
                }
            case .playSound:
                HStack(spacing: 12) {
                    Picker("Sound:", selection: itemBinding(i, \.soundName)) {
                        ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
                        Text("Custom file…").tag("")
                    }
                    .frame(width: 180)
                    if actionItems[i].soundName.isEmpty {
                        TextField("/path/to/sound.mp3", text: itemBinding(i, \.soundName))
                            .textFieldStyle(.editable).labelsHidden().frame(maxWidth: 300)
                    }
                    Slider(value: Binding(get: { Double(actionItems[i].volumePercent) },
                                         set: { actionItems[i].volumePercent = Int($0); persistActions() }),
                           in: 0...100)
                        .frame(width: 160)
                    Text("\(actionItems[i].volumePercent)%").font(.caption)
                }
            case .fadeoutSound:
                Stepper("Fade over \(actionItems[i].fadeSeconds)s",
                      value: itemBinding(i, \.fadeSeconds), in: 1...30)
            case .flashScreen:
                HStack {
                    ColorPicker("Flash color:", selection: Binding(
                        get: { colorFromHex(actionItems[i].colorHex) },
                        set: { c in
                            let ns = NSColor(c).usingColorSpace(.deviceRGB)
                            let v = Int((ns?.redComponent ?? 1) * 255) * 65536
                                + Int((ns?.greenComponent ?? 1) * 255) * 256
                                + Int((ns?.blueComponent ?? 1) * 255)
                            actionItems[i].colorHex = String(format: "%06X", v)
                            persistActions()
                        }))
                }
            case .speakText:
                TextField("Text to speak (voice follows the text language):", text: itemBinding(i, \.speakText))
                    .textFieldStyle(.editable).frame(maxWidth: 420)
            case .soundVolume:
                HStack(spacing: 12) {
                    Picker("Mode:", selection: itemBinding(i, \.volumeMode)) {
                        Text("Mute").tag("mute")
                        Text("Restore remembered").tag("restore")
                        Text("Set to %").tag("set")
                        Text("Increase by %").tag("increase")
                        Text("Decrease by %").tag("decrease")
                    }
                    .frame(width: 220)
                    if actionItems[i].volumeMode == "set"
                        || actionItems[i].volumeMode == "increase"
                        || actionItems[i].volumeMode == "decrease" {
                        Slider(value: Binding(get: { Double(actionItems[i].volumePercent) },
                                             set: { actionItems[i].volumePercent = Int($0); persistActions() }),
                               in: 0...100)
                            .frame(width: 160)
                        Text("\(actionItems[i].volumePercent)%").font(.caption)
                    }
                }
            case .musicPause, .musicPlay:
                Text("Music resumes only if it was playing when paused; nothing launches if Music quit.")
                    .settingsNote()
            case .script:
                scriptPathRowForItem(i)
            }
            if actionItems[i].when == .buttonClicked {
                HStack {
                    Text("Button title:")
                    TextField("e.g. Water", text: itemBinding(i, \.title))
                        .textFieldStyle(.editable).labelsHidden().frame(maxWidth: 240)
                    Text("Shown as a button on the break screen.")
                        .settingsNote()
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func scriptPathRowForItem(_ i: Int) -> some View {
        HStack {
            Text("Script:")
            Text(actionItems[i].scriptPath)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Browse…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    actionItems[i].scriptPath = url.path
                    persistActions()
                }
            }
            .controlSize(.small)
            if !actionItems[i].scriptPath.isEmpty {
                Button("Clear") {
                    actionItems[i].scriptPath = ""
                    persistActions()
                }
                .controlSize(.small)
            }
        }
    }

    private func moveActionItem(_ i: Int, by delta: Int) {
        let j = i + delta
        guard actionItems.indices.contains(i), actionItems.indices.contains(j) else { return }
        actionItems.swapAt(i, j)
        persistActions()
    }

    private func removeActionItem(_ i: Int) {
        guard actionItems.indices.contains(i) else { return }
        actionItems.remove(at: i)
        persistActions()
    }

    @ViewBuilder
    private func scriptPathRow(title: LocalizedStringKey, key: String) -> some View {
        HStack {
            Text(title)
            Text(scriptPaths[key] ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Browse…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    scriptPaths[key] = url.path
                    UserDefaults.standard.set(url.path, forKey: key)
                }
            }
            .controlSize(.small)
            if !(scriptPaths[key] ?? "").isEmpty {
                Button("Clear") {
                    scriptPaths[key] = ""
                    UserDefaults.standard.removeObject(forKey: key)
                }
                .controlSize(.small)
            }
        }
    }
}
