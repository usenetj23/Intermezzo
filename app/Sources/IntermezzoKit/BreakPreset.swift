import Foundation

/// Ready-made break rhythms taken from published recommendations. Each one
/// states where it comes from, so the user can judge the evidence.
public struct BreakPreset: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let summary: String
    public let source: String
    public let cycleMinutes: Int
    public let shortBreakSeconds: Int
    public let longBreakSeconds: Int
    public let longBreakEvery: Int

    public static let all: [BreakPreset] = [
        BreakPreset(
            id: "20-20-20", title: "20-20-20",
            summary: "Co 20 min: 20 s patrzenia w dal. Co trzecia przerwa (≈ 1 h) to 5 minut ruchu.",
            source: "AOA / Harvard Health / Kaur 2022 (konsensus; pojedyncze 20 s bywa niewystarczające)",
            cycleMinutes: 20, shortBreakSeconds: 20, longBreakSeconds: 300, longBreakEvery: 3),
        BreakPreset(
            id: "frequent-10", title: "Częste mikroprzerwy",
            summary: "Co 10 min: 30 s od ekranu. Dla intensywnej pracy wzrokowej; co trzecia przerwa dłuższa.",
            source: "Redondo i in. 2025 (24 osoby, 40 min czytania: przerwy co 10 min zmniejszały podrażnienie oczu)",
            cycleMinutes: 10, shortBreakSeconds: 30, longBreakSeconds: 300, longBreakEvery: 3),
        BreakPreset(
            id: "dyrek-5-30", title: "5 min po 30 min",
            summary: "Co 30 min: 5 minut przerwy; co czwarta to 15 minut.",
            source: "Dyrek i in. 2024, przegląd (Eur. J. Clin. Exp. Med.)",
            cycleMinutes: 30, shortBreakSeconds: 300, longBreakSeconds: 900, longBreakEvery: 4),
        BreakPreset(
            id: "bhp-5-60", title: "Przepisy BHP: 5 min po godzinie",
            summary: "Po godzinie nieprzerwanej pracy przy monitorze minimum 5 minut przerwy.",
            source: "Polskie przepisy o stanowiskach z monitorami (za CIOP-PIB, Kamińska 2016)",
            cycleMinutes: 60, shortBreakSeconds: 300, longBreakSeconds: 900, longBreakEvery: 2),
        BreakPreset(
            id: "balanced", title: "Zrównoważony (domyślny)",
            summary: "45 min pracy, 5 min przerwy, co czwarta 15 min.",
            source: "Ustawienia domyślne Intermezzo",
            cycleMinutes: 45, shortBreakSeconds: 300, longBreakSeconds: 900, longBreakEvery: 4),
    ]

    public static func matching(cycleMinutes: Int, shortSeconds: Int,
                                longSeconds: Int, longEvery: Int) -> BreakPreset? {
        all.first {
            $0.cycleMinutes == cycleMinutes && $0.shortBreakSeconds == shortSeconds
                && $0.longBreakSeconds == longSeconds && $0.longBreakEvery == longEvery
        }
    }
}
