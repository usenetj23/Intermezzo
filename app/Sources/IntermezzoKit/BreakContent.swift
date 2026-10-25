import Foundation

/// Content bank: what to actually DO during a break and how to work at a
/// screen without burning out. Polish content for Polish users.
/// Each entry is (headline, instructions).
public struct BreakContent: Equatable {
    public let headline: String
    public let detail: String

    public init(headline: String, detail: String) {
        self.headline = headline
        self.detail = detail
    }

    /// Eye-protection (20-20-20 and friends) — shown on short breaks.
    public static let eyeBank: [BreakContent] = [
        .init(headline: "Odpocznij oczu, odśwież umysł",
              detail: "Odwróć wzrok od ekranu i patrz przez 20 sekund na obiekt oddalony o min. 6 metrów. Mrugaj powoli — nawilża oczy."),
        .init(headline: "Zasada 20-20-20",
              detail: "Co 20 minut patrz 20 sekund na obiekt oddalony o 20 stóp (6 m). To najtańsza profilaktyka zmęczenia oczu."),
        .init(headline: "Szybsze mruganie",
              detail: "Przy ekranach mrugamy 3x rzadziej — oczy wysychają. Zrób 10 powolnych, pełnych mrugnięć."),
        .init(headline: "Palming — ciepło dla oczu",
              detail: "Potrzyj dłonie, zamknij oczy i przyłóż je delikatnie do powiek na 30 sekund. Ciemność + ciepło = reset wzroku."),
    ]

    /// Posture / body — shown on long breaks.
    public static let bodyBank: [BreakContent] = [
        .init(headline: "Wstań i przeciągnij się",
              detail: "Stań, splot dłonie za plecami, wypchnij klatkę do przodu, głowę lekko w górę. Utrzymaj 20 sekund. Oddychaj głęboko."),
        .init(headline: "Rozrusz kark",
              detail: "Powolne skłony głowy ucho-ramię, 10 s na stronę. Bez kręcenia głową w kółko — tylko płynne półkole."),
        .init(headline: "Kocie grzbiety",
              detail: "Podpłóń się na biurku na prostych rękach, zaokrąglij plecy w górę na wydechu, na wdechu lekko pogłęb lordozę. 5 powtórzeń."),
        .init(headline: "Rozciąganie nadgarstków",
              detail: "Prostuj palce w górę, grzbiet dłoni do siebie, przytrzymaj 15 s. Odwróć dłoń w dół — druga strona. Profilaktyka RSI."),
        .init(headline: "Ściskaj łopatki",
              detail: "Siedź prosto, ściągnij łopatki do tyłu i w dół na 10 sekund, rozluźnij. 5 powtórzeń odwraca sylwetkę 'computer neck'."),
        .init(headline: "Przysiady przy biurku",
              detail: "10 wolnych przysiadów. Krążenie wraca, mózg dostaje tlen, biodra otwierają się po siedzeniu."),
        .init(headline: "Rozluźnij szczękę",
              detail: "Odpuszczaj zaciśnięte zęby, język od podniebienia. Rozgrzyj żuchwę 10 razy. To napięcie, którego nie zauważasz."),
    ]

    /// Hydration / breathing / micro-recovery — mixed rotation.
    public static let mindBank: [BreakContent] = [
        .init(headline: "Oddech pudełkowy 4-4-4-4",
              detail: "Wdech 4 s — zatrzymanie 4 s — wydech 4 s — pauza 4 s. Cztery rundy obniżają puls i kortyzol."),
        .init(headline: "Napij się wody",
              detail: "Lekkie odwodnienie = spadek koncentracji o ~20%. Szklanka wody teraz to najtańszy nootrop."),
        .init(headline: "Popatrz przez okno",
              detail: "Widok na zieleń i dal realnie regeneruje korę wzrokową. Badania: nawet 40 sekund obniża zmęczenie uwagi."),
        .init(headline: "Zadanie: wyjdź na korytarz",
              detail: "Krótka zmiana otoczenia resetuje 'tunnel vision' od monitora. Nie zabieraj telefonu."),
        .init(headline: "Ergonomia: sprawdź fotel",
              detail: "Stopy płasko na podłodze, kolana pod kątem 90°, monitor na wysokości oczu w górnej krawędzi, oparcie pod lędźwiami."),
        .init(headline: "Rozprostuj biodra",
              detail: "Siedzenie 45 min skraca zginacze bioder. Wykrok do przodu, tylne kolano nisko, poczuj rozciąganie z przodu biodra. 20 s / noga."),
    ]

    /// Ciekawostki i porady o pracy przy ekranie (rotacja na pasku / w statystykach).
    public static let trivia: [String] = [
        "Przy monitorze mrugamy nawet 3× rzadziej niż normalnie — stąd suchość oczu.",
        "Najzdrowsza odległość od monitora: 50–70 cm, górna krawędź ekranu na wysokości oczu.",
        "Krótkie pauzy co 30–60 min zwiększają liczbę trafnych decyzji — badania NASA i University of Illinois.",
        "Zaciśnięte szczęki i uniesione ramiona to najczęstsze 'niewidoczne' napięcia pracy przy biurku.",
        "Temperatura barwowa ekranu na wieczór poniżej 3400 K poprawia zasypianie (tryb nocny istnieje nie bez powodu).",
        "Stojące biurko nie jest lepsze od siedzącego — liczy się ZMIANA pozycji co kilkanaście minut.",
        "Zasada 20-20-20 spopularyzowali optometryści: co 20 minut patrz 20 sekund na obiekt 20 stóp dalej.",
        "Napięcie karku po 8h pracy przy monitorze to efekt izometryczny — mięśnie pracują bez ruchu. Jedyna ucieczka: ruch.",
    ]

    /// Deterministic rotation: the same break number always maps to the same
    /// content, so nothing repeats until the bank cycles.
    public static func content(kind: String, index: Int) -> BreakContent {
        let bank: [BreakContent] = kind == "long" ? bodyBank : eyeBank
        if kind == "short" && index % 3 == 2 {
            return mindBank[index % mindBank.count]
        }
        return bank[index % bank.count]
    }
}

// MARK: - Rotation math (pure, testable) — used by the Text Theme overlay

/// Index of the text to display for the given rotation tick.
/// Sequential keeps counting across breaks (seed = completed-break counter);
/// random is deterministic per (seed, tick) so snapshots are stable.
public func textThemeIndex(seed: Int, tick: Int, count: Int, random: Bool) -> Int {
    guard count > 0 else { return 0 }
    guard random else { return (seed + tick) % count }
    // splitmix64-ish finalizer for stable pseudo-random selection
    var x = UInt64(bitPattern: Int64(seed &* 2654435761)) &+ UInt64(bitPattern: Int64(tick)) &* 40503
    x ^= x >> 16
    x = x &* 0x7FEB352D
    x ^= x >> 15
    return Int(x % UInt64(count))
}

