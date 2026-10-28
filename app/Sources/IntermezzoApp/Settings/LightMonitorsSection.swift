import SwiftUI
import IntermezzoKit

/// Colour and dimming per kind of monitor: every connected monitor is a row that opens to its own settings.
/// Identical monitors share one row. What was set is remembered, so it applies again when the monitors return.
struct LightMonitorsSection: View {
    @ObservedObject private var registry = MonitorRegistry.shared

    var body: some View {
        Section("Monitory") {
            ForEach(registry.groups) { group in
                MonitorRow(group: group)
            }
            let offline = registry.rememberedOffline
            if !offline.isEmpty {
                DisclosureGroup("Zapamiętane, niepodłączone") {
                    ForEach(offline, id: \.key) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.profile.name)
                                Text(MonitorRow.summary(of: entry.profile)).settingsNote()
                            }
                            Spacer()
                            Button("Usuń") { registry.forget(entry.key) }.controlSize(.small)
                        }
                    }
                }
            }
            Text("Nowy monitor od razu dostaje ogólną krzywą. Takie same monitory mają wspólne ustawienia. Ustawienia są pamiętane tylko na tym Macu i wracają, gdy monitor zostanie podłączony ponownie.")
                .settingsNote().settingsAnchor("light-nowy-monitor-od-razu-dostaje-ogolna")
        }
    }
}

private struct MonitorRow: View {
    let group: MonitorGroup
    @ObservedObject private var registry = MonitorRegistry.shared
    @ObservedObject private var light = LightController.shared
    @AppStorage(BetterDisplayKeys.dim) private var bdDim = false
    /// The slider's value while it is dragged; the setting is saved when it is let go.
    @State private var draftK: Double?

    private var profile: MonitorProfile {
        registry.profiles.profile(for: group.key) ?? MonitorProfile(name: group.name, lastSeen: Date())
    }

    static func summary(of profile: MonitorProfile) -> String {
        if profile.untouched { return String(localized: "bez zarządzania") }
        var parts: [String] = []
        if let k = profile.warmestK { parts.append(String(localized: "kolor do \(Int(k)) K")) }
        if let p = profile.dimPercent { parts.append(String(localized: "przyciemnienie \(p)%")) }
        return parts.isEmpty ? String(localized: "ogólna krzywa") : parts.joined(separator: " · ")
    }

    var body: some View {
        DisclosureGroup {
            Toggle("Nie zarządzaj tym monitorem (np. telewizorem)", isOn: Binding(
                get: { profile.untouched },
                set: { value in registry.update(group.key) { $0.untouched = value } })).settingsAnchor("light-nie-zarzadzaj-tym-monitorem-np-telew")
            if !profile.untouched {
                colourControls
                if BetterDisplayLight.isInstalled { dimControls }
                HStack {
                    Button("Podgląd wieczoru") {
                        if let id = group.displayIDs.first { light.previewMonitor(displayID: id) }
                    }.settingsAnchor("light-podglad-wieczoru")
                    .disabled(light.previewingDisplay != nil)
                    Button("Przywróć ogólne") { registry.resetOverrides(group.key) }.settingsAnchor("light-przywroc-ogolne")
                        .disabled(!profile.hasOverrides)
                }
                .controlSize(.small)
            }
        } label: {
            HStack {
                Text(group.name)
                if group.count > 1 { Text(verbatim: "× \(group.count)").foregroundStyle(.secondary) }
                Spacer()
                Text(Self.summary(of: profile)).settingsNote()
            }
        }
    }

    private var colourControls: some View {
        Group {
            Toggle("Własny limit koloru", isOn: Binding(
                get: { profile.warmestK != nil },
                set: { on in registry.update(group.key) { $0.warmestK = on ? light.settings.bedtimeK : nil } })).settingsAnchor("light-wlasny-limit-koloru")
            if let saved = profile.warmestK {
                let shown = draftK ?? saved
                Slider(value: Binding(get: { shown }, set: { draftK = $0 }),
                       in: LightSettings.minKelvin...LightSettings.maxKelvin, step: 100) { editing in
                    guard !editing, let value = draftK else { return }
                    registry.update(group.key) { $0.warmestK = value }
                    draftK = nil
                } label: {
                    Text("Najcieplejszy kolor: \(Int(shown)) K")
                }
            }
        }
    }

    private var dimControls: some View {
        Group {
            Toggle("Własne przyciemnienie", isOn: Binding(
                get: { profile.dimPercent != nil },
                set: { on in registry.update(group.key) { $0.dimPercent = on ? BetterDisplayLight.shared.globalDimPercent : nil } })).settingsAnchor("light-wlasne-przyciemnienie")
            if let percent = profile.dimPercent {
                Stepper("Przyciemnij maksymalnie o \(percent)%", value: Binding(
                    get: { percent },
                    set: { value in registry.update(group.key) { $0.dimPercent = value } }),
                        in: 0...EveningDimming.maxDimPercent, step: 5)
                if !bdDim {
                    Text("Przyciemnianie sprzętowe jest wyłączone (sekcja BetterDisplay), więc ten wybór na razie nic nie zmienia.")
                        .settingsNote().settingsAnchor("light-przyciemnianie-sprzetowe-jest-wylacz")
                }
            }
        }
    }
}
