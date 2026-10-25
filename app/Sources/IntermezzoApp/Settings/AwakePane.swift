import SwiftUI
import AppKit
import IntermezzoKit

/// Keep the Mac awake: on request, during focus sessions, while chosen apps run, with safety limits.
struct AwakePane: View {
    @AppStorage(AwakeKeys.defaultLevel) private var levelRaw = KeepAwakeLevel.system.rawValue
    @AppStorage(AwakeKeys.batteryFloor) private var batteryFloor = 20
    @AppStorage(AwakeKeys.stopOnLowPower) private var stopOnLowPower = true
    @AppStorage(AwakeKeys.stopOnThermal) private var stopOnThermal = true
    @AppStorage(AwakeKeys.withFocus) private var withFocus = false
    @AppStorage(AwakeKeys.withApps) private var withApps = false
    @AppStorage(AwakeKeys.apps) private var apps = ""
    @ObservedObject private var awake = KeepAwakeController.shared
    @State private var runningAppNames: [String] = []

    var body: some View {
        Form {
            nowSection
            automaticSection
            safetySection.expertOnly()
            othersSection.expertOnly()
        }
        .formStyle(.grouped)
        .onAppear { awake.refreshOthers() }
        .readsRunningApps(into: $runningAppNames)
    }

    // MARK: Now

    private var nowSection: some View {
        Section("Czuwanie") {
            LabeledContent("Teraz") {
                if let level = awake.holding {
                    Label(level == .system ? "Mac nie zaśnie" : "Mac i ekran nie zasną", systemImage: "cup.and.saucer.fill")
                } else {
                    Text("Wyłączone").foregroundStyle(.secondary)
                }
            }
            if !awake.activeSources.isEmpty {
                Text("Powód: \(awake.activeSources.joined(separator: ", "))").settingsNote()
            }
            if let until = awake.manualUntil {
                Text("Do \(until.formatted(date: .omitted, time: .shortened))").settingsNote()
            }
            Picker("Co ma nie spać", selection: $levelRaw) {
                Text("Tylko Mac (ekran może zgasnąć)").tag(KeepAwakeLevel.system.rawValue)
                Text("Mac i ekran").tag(KeepAwakeLevel.systemAndDisplay.rawValue)
            }
            HStack {
                if awake.manualLevel == nil {
                    Menu("Włącz na…") {
                        ForEach([15, 30, 60, 120, 240, 480], id: \.self) { minutes in
                            Button(durationTitle(minutes)) { awake.turnOn(duration: .minutes(minutes)) }
                        }
                        Divider()
                        ForEach(KeepAwakeDuration.nextWholeHours(count: 3, from: Date()), id: \.self) { hour in
                            Button("do \(hour):00") { awake.turnOn(duration: .untilHour(hour)) }
                        }
                        Divider()
                        Button("Do wyłączenia") { awake.turnOn() }
                    }
                    .fixedSize()
                } else {
                    Button("Wyłącz") { awake.turnOff() }
                }
                Spacer()
            }
            if let stop = awake.lastStop, awake.manualLevel == nil {
                Label(stopText(stop), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Działa bez uprawnień administratora. Zamknięcie klapy MacBooka i tak go uśpi: tego ta funkcja nie zmienia. Stan włączenia zostaje po ponownym uruchomieniu aplikacji.")
                .settingsNote()
        }
    }

    private func durationTitle(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h")
    }

    private func stopText(_ stop: KeepAwakeStop) -> String {
        switch stop {
        case .timerEnded: return String(localized: "Czas czuwania minął.")
        case .batteryLow: return String(localized: "Wyłączone, bo bateria spadła poniżej progu.")
        case .lowPowerMode: return String(localized: "Wyłączone, bo włączył się tryb niskiego zużycia energii.")
        case .thermal: return String(localized: "Wyłączone, bo Mac się nagrzał.")
        }
    }

    // MARK: Automatic

    private var automaticSection: some View {
        Section("Automatycznie") {
            Toggle("Trzymaj Maca podczas sesji skupienia", isOn: $withFocus)
            Text("Sesja Pomodoro nie zostanie przerwana przez uśpienie Maca. Działa tylko, gdy tryb Pomodoro jest włączony.")
                .settingsNote()
            Toggle("Trzymaj Maca, gdy działa wybrana aplikacja", isOn: $withApps)
            if withApps {
                TextField("Aplikacje", text: $apps, prompt: Text(verbatim: "OBS, Xcode, ffmpeg"))
                    .textFieldStyle(.editable)
                Menu("Dodaj uruchomioną aplikację…") {
                    ForEach(runningAppNames, id: \.self) { name in
                        Button(name) { add(name) }
                    }
                }
                .fixedSize()
                Text("Nazwy oddzielaj przecinkami. Wielkość liter i końcówka .app nie mają znaczenia; można wpisać też nazwę programu z terminala, np. ffmpeg.")
                    .settingsNote()
            }
        }
    }



    private func add(_ name: String) {
        var list = KeepAwakeApps.list(fromCommaText: apps)
        if !list.contains(where: { KeepAwakeApps.normalized($0) == KeepAwakeApps.normalized(name) }) { list.append(name) }
        apps = list.joined(separator: ", ")
    }

    // MARK: Safety and others

    private var safetySection: some View {
        Section("Zabezpieczenia") {
            Stepper(value: $batteryFloor, in: 0...50, step: 5) {
                Text(batteryFloor == 0 ? "Nie wyłączaj przy niskiej baterii" : "Wyłącz na baterii poniżej \(batteryFloor)%")
            }
            Toggle("Wyłącz w trybie niskiego zużycia energii (na baterii)", isOn: $stopOnLowPower)
            Toggle("Wyłącz, gdy Mac się mocno nagrzeje", isOn: $stopOnThermal)
            Text("Zabezpieczenia dotyczą czuwania na życzenie, podczas sesji i dla wybranych aplikacji. Przerwa trzyma Maca zawsze.")
                .settingsNote()
        }
    }

    private var othersSection: some View {
        Section("Kto jeszcze trzyma Maca") {
            if awake.others.isEmpty {
                Text("Żaden inny program nie blokuje uśpienia.").settingsNote()
            }
            ForEach(Array(awake.others.prefix(8).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.process)
                    Text(verbatim: item.reason).settingsNote()
                }
            }
            HStack {
                Spacer()
                Button("Odśwież") { awake.refreshOthers() }.controlSize(.small)
            }
        }
    }
}
