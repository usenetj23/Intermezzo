import SwiftUI
import IntermezzoKit

/// "Gotowe profile przerw": one-tap rhythms from published recommendations,
/// each with its source and the profile currently in use highlighted.
struct BreakPresetSection: View {
    @AppStorage(Keys.cycleMinutes) private var cycleMinutes = 45
    @AppStorage(Keys.shortBreakSeconds) private var shortBreakSeconds = 300
    @AppStorage(Keys.longBreakSeconds) private var longBreakSeconds = 900
    @AppStorage(Keys.longBreakEvery) private var longBreakEvery = 4
    @Environment(\.surfaceTheme) private var theme

    private var activeID: String? {
        BreakPreset.matching(cycleMinutes: cycleMinutes, shortSeconds: shortBreakSeconds,
                             longSeconds: longBreakSeconds, longEvery: longBreakEvery)?.id
    }

    var body: some View {
        Section {
            ForEach(BreakPreset.all) { preset in
                let active = preset.id == activeID
                Button { apply(preset) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: active ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(active ? theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized: preset.title).font(.system(size: 13, weight: .semibold))
                            Text(localized: preset.summary).settingsNote()
                            Text(localized: preset.source).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Profil ustawia rytm pracy i długość przerw. Dowody są ograniczone (małe próby, konsensus) — dobierz to, co pasuje do Twojej pracy; suwaki poniżej nadal działają.")
                .settingsNote().settingsAnchor("breaks-profil-ustawia-rytm-pracy-i-dlugosc")
        } header: {
            Text("Gotowe profile przerw")
        }
    }

    private func apply(_ p: BreakPreset) {
        cycleMinutes = p.cycleMinutes
        shortBreakSeconds = p.shortBreakSeconds
        longBreakSeconds = p.longBreakSeconds
        longBreakEvery = p.longBreakEvery
        Trace.log("break preset applied: \(p.id)")
    }
}
