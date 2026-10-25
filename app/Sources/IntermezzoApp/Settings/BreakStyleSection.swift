import SwiftUI
import IntermezzoKit

/// How firm breaks are, what tone the break screen has, and whether it may block the mouse.
struct BreakStyleSection: View {
    @AppStorage(BreakStyleSettings.strictnessKey) private var strictness = Strictness.classic.rawValue
    @AppStorage(BreakStyleSettings.motivationKey) private var motivation = MotivationStyle.streak.rawValue
    @AppStorage(BreakStyleSettings.softBreakKey) private var softBreak = 0
    @AppStorage(BreakStyleSettings.edgeGlowKey) private var edgeGlow = 0
    @AppStorage(ReminderOnlyKeys.enabled) private var remindOnly = 0
    @AppStorage(ReminderOnlyKeys.repeatMinutes) private var repeatMinutes = 0

    var body: some View {
        Section("Podejście do przerw") {
            Picker("Surowość", selection: $strictness) {
                Text("Klasyczna").tag(Strictness.classic.rawValue)
                Text("Luźna").tag(Strictness.casual.rawValue)
                Text("Zrównoważona").tag(Strictness.balanced.rawValue)
                Text("Twarda").tag(Strictness.hardcore.rawValue)
            }
            note(strictnessNote)
            Group {
                Picker("Styl motywacji", selection: $motivation) {
                    Text("Passa").tag(MotivationStyle.streak.rawValue)
                    Text("Spokojny").tag(MotivationStyle.calm.rawValue)
                }
                note(motivationNote)
                Toggle("Miękka przerwa: przyciemnienie przepuszcza kliknięcia", isOn: Binding(
                    get: { softBreak != 0 }, set: { softBreak = $0 ? 1 : 0 }))
                Toggle("Poświata krawędzi ekranu przed przerwą (bursztyn → czerwień)", isOn: Binding(
                    get: { edgeGlow != 0 }, set: { edgeGlow = $0 ? 1 : 0 }))
            }
            .expertOnly()
            Toggle("Tylko przypominaj, bez przerwy na ekranie", isOn: Binding(
                get: { remindOnly != 0 }, set: { remindOnly = $0 ? 1 : 0 }))
            if remindOnly != 0 {
                Stepper("Silniejsze przypomnienie co \(repeatMinutes == 0 ? ReminderOnlyKeys.defaultRepeat : repeatMinutes) min",
                        value: Binding(get: { repeatMinutes == 0 ? ReminderOnlyKeys.defaultRepeat : repeatMinutes },
                                       set: { repeatMinutes = $0 }),
                        in: ReminderOnlyKeys.repeatRange)
                note("Gdy przerwa jest należna, nic nie zasłania ekranu. Dostajesz łagodne powiadomienie i dźwięk; jeśli je zignorujesz, co kilka minut pojawia się mocniejsze, a krawędzie ekranu zaczynają świecić na czerwono. Kończysz je przyciskiem Zacznij przerwę, Zrobiłem przerwę, odroczeniem albo odejściem od komputera. Ten tryb ma pierwszeństwo przed surowością i miękką przerwą.")
            }
            if softBreak != 0 {
                Text("Przerwa nie przejmuje myszki ani Docka, więc nie ma na niej przycisków. Zakończysz ją z paska menu albo skrótem.")
                    .settingsNote()
                    .expertOnly()
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(LocalizedStringKey(text)).settingsNote()
    }

    private var strictnessNote: String {
        switch Strictness(stored: strictness) {
        case .classic:
            return "Tak działa aplikacja od początku: odroczenia +1 i +5 min bez limitu, Skip wymaga przytrzymania, Esc kończy przerwę."
        case .casual:
            return "Do 6 odroczeń (+1 i +5 min) na dobę. Skip i Esc działają jak w klasycznej. Po wyczerpaniu limitu przyciski odroczenia znikają."
        case .balanced:
            return "Do 3 odroczeń (+1 i +5 min) na dobę. Skip i Esc działają jak w klasycznej. Po wyczerpaniu limitu przyciski odroczenia znikają."
        case .hardcore:
            return "Bez odroczeń, bez przycisku Skip i bez Esc na ekranie przerwy. Awaryjnie przerwę kończysz z paska menu."
        }
    }

    private var motivationNote: String {
        switch MotivationStyle(stored: motivation) {
        case .streak:
            return "Na ekranie przerwy wykres Twoich ostatnich przerw (rośnie po ukończonej, spada po pominiętej), hasła o passie oraz licznik dni z rzędu w Pomodoro i statystykach."
        case .calm:
            return "Bez wykresu, haseł o passie i liczników dni z rzędu. Zostaje sam numer przerwy dziś. Statystyki i mapa regularności nadal są dostępne, bez oceniania."
        }
    }
}
