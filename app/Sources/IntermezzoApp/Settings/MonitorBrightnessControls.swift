import SwiftUI
import IntermezzoKit

/// One display's own brightness settings while the brightness equaliser is on: where its brightness comes
/// from, its own multiplier and limits, and its brightest white in nits. The built-in screen gets the same
/// settings as every monitor (it is a peer, not an exception).
struct MonitorBrightnessControls: View {
    let group: MonitorGroup
    let profile: MonitorProfile
    @ObservedObject private var registry = MonitorRegistry.shared
    @ObservedObject private var brightness = ScreenBrightnessController.shared
    @ObservedObject private var edid = DisplayEDID.shared
    @AppStorage(BrightnessKeys.automatic) private var automatic = false

    var body: some View {
        Picker("Jasność", selection: Binding(
            get: { profile.brightnessSource ?? .automatic },
            set: { value in registry.update(group.key) { $0.brightnessSource = value == .automatic ? nil : value } })) {
            if group.isBuiltIn {
                Text("Automatycznie (korektor albo macOS w automacie)").tag(BrightnessSource.automatic)
            } else {
                Text("Automatycznie (korektor albo nity w automacie)").tag(BrightnessSource.automatic)
            }
            Text("Korektor (wykresy godzin i pokoju)").tag(BrightnessSource.equalizer)
            Text("Nie zmieniaj jasności").tag(BrightnessSource.off)
        }.settingsAnchor("light-jasnosc")
        if profile.brightnessSource != .off {
            Stepper("Własny mnożnik: \(profile.brightnessScale ?? 100)%", value: Binding(
                get: { profile.brightnessScale ?? 100 },
                set: { value in registry.update(group.key) { $0.brightnessScale = value == 100 ? nil : value } }),
                    in: PeerBrightness.scaleRange, step: 5)
            Stepper("Najciemniej: \(profile.brightnessMinPercent ?? PeerBrightness.percentRange.lowerBound)%", value: Binding(
                get: { profile.brightnessMinPercent ?? PeerBrightness.percentRange.lowerBound },
                set: { value in registry.update(group.key) { $0.brightnessMinPercent = value } }),
                    in: PeerBrightness.percentRange, step: 5)
            Stepper("Najjaśniej: \(profile.brightnessMaxPercent ?? PeerBrightness.percentRange.upperBound)%", value: Binding(
                get: { profile.brightnessMaxPercent ?? PeerBrightness.percentRange.upperBound },
                set: { value in registry.update(group.key) { $0.brightnessMaxPercent = value } }),
                    in: PeerBrightness.percentRange, step: 5)
            nitsControls
        }
        if group.isBuiltIn, automatic {
            Text("W automacie jasność tego ekranu ustawia macOS; mnożnik i limity działają, gdy automat jest wyłączony.")
                .settingsNote().settingsAnchor("light-w-automacie-jasnosc-tego-ekranu-ust")
        } else if !group.isBuiltIn, !BetterDisplayLight.isInstalled {
            Text("Jasność monitora zmieniam przez BetterDisplay, którego tu nie ma: te ustawienia na razie nic nie zmieniają.")
                .settingsNote().settingsAnchor("light-jasnosc-monitora-zmieniam-przez-bet")
        }
    }

    @ViewBuilder private var nitsControls: some View {
        Toggle("Własna maksymalna jasność (nity)", isOn: Binding(
            get: { profile.maxNits != nil },
            set: { on in registry.update(group.key) { $0.maxNits = on ? Int(detectedNits.rounded()) : nil } })).settingsAnchor("light-wlasna-maksymalna-jasnosc-nity")
        if let nits = profile.maxNits {
            Stepper("Maksymalnie \(nits) nit", value: Binding(
                get: { nits },
                set: { value in registry.update(group.key) { $0.maxNits = value } }),
                    in: PeerBrightness.nitsRange, step: 25)
        }
        Text(detectedNote).settingsNote()
    }

    /// What the app would use without a typed value.
    private var detectedNits: Double {
        if group.isBuiltIn { return BuiltInDisplay.shared.sdrLimits()?.nominal ?? BuiltInDisplay.fallbackMaxNits }
        return edid.maxNits(for: group.key) ?? PeerBrightness.defaultExternalMaxNits
    }

    private var detectedNote: String {
        if group.isBuiltIn {
            guard let limits = BuiltInDisplay.shared.sdrLimits() else {
                return String(localized: "Brak odczytu z macOS: przyjmuję \(Int(BuiltInDisplay.fallbackMaxNits)) nit.")
            }
            if limits.ceiling > limits.nominal {
                return String(localized: "Odczyt z macOS: \(Int(limits.nominal.rounded())) nit (maks. SDR; do \(Int(limits.ceiling.rounded())) przy mocnym świetle).")
            }
            return String(localized: "Odczyt z macOS: \(Int(limits.nominal.rounded())) nit (maks. SDR).")
        }
        if let edid = edid.maxNits(for: group.key) {
            return String(localized: "Monitor podaje w EDID: \(Int(edid.rounded())) nit.")
        }
        return String(localized: "Monitor nie podaje maksymalnej jasności: przyjmuję \(Int(PeerBrightness.defaultExternalMaxNits)) nit. Wpisz wartość z jego specyfikacji, żeby automat był dokładniejszy.")
    }
}

/// The short state of a display's brightness for the monitor rows ("brightness 62% · equaliser").
enum MonitorBrightnessSummary {
    static func text(_ status: ScreenBrightnessController.DisplayStatus?) -> String? {
        guard let status else { return nil }
        if status.heldByException { return String(localized: "jasność bez zmian (wyjątek)") }
        let percent = status.level.map { Int(($0 * 100).rounded()) } ?? 0
        switch status.kind {
        case .equalizer: return String(localized: "jasność \(percent)% · korektor")
        case .followsBuiltIn(let nits): return String(localized: "jasność \(percent)% · za wbudowanym, \(Int(nits.rounded())) nit")
        case .apple: return String(localized: "jasność: macOS (automat)")
        case .off: return String(localized: "jasność bez zmian")
        case .untouched: return nil
        }
    }
}
