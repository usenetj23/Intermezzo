import Foundation

public enum ExerciseCategory: String, CaseIterable {
    case eyes, upperBody, handsWrists, backCore, legs, workstation, breathing

    public var title: String {
        switch self {
        case .eyes: return "Oczy"
        case .upperBody: return "Kark i barki"
        case .handsWrists: return "Dłonie i nadgarstki"
        case .backCore: return "Plecy i tułów"
        case .legs: return "Nogi i krążenie"
        case .workstation: return "Stanowisko pracy"
        case .breathing: return "Oddech"
        }
    }
}

public struct LibraryExercise: Identifiable, Equatable {
    public let id: String
    public let category: ExerciseCategory
    public let title: String
    public let detail: String
    public let short: Bool
    public let long: Bool

    /// Display name in the Exercises pane; also the de-dup key when syncing.
    public var name: String { "\(category.title) · \(title)" }
}

/// Curated exercise set for the break overlay. Short-break entries are
/// doable in ~60 s; long-break entries may take a few minutes. Eye drills
/// follow the AOA / Medical News Today / Harvard Health guidance (distance
/// gaze, near-far focus, figure eight, complete blinks); body drills target the
/// neck/shoulder/back/wrist regions most often affected in computer workers
/// (Moreira 2022).
public enum ExerciseLibrary {
    private static func ex(_ id: String, _ c: ExerciseCategory, _ title: String, _ detail: String,
                           short: Bool, long: Bool) -> LibraryExercise {
        LibraryExercise(id: id, category: c, title: title, detail: detail, short: short, long: long)
    }

    public static let all: [LibraryExercise] = [
        // Oczy
        ex("eye-distance", .eyes, "Wzrok w dal",
           "Podejdź do okna i patrz na najdalszy punkt (min. 6 m) przez 20 sekund. Rozluźnij brwi i szczękę.",
           short: true, long: true),
        ex("eye-blink", .eyes, "Pełne mrugnięcia",
           "Zamknij powieki wolno, na sekundę, i otwórz. Zrób 10 takich pełnych mrugnięć. Przy ekranie mrugamy kilka razy rzadziej i często niepełnie.",
           short: true, long: true),
        ex("eye-near-far", .eyes, "Bliżej – dalej",
           "Wyciągnij kciuk na długość ręki. Patrz na niego 5 sekund, potem na odległy punkt 5 sekund. Powtórz 5 razy, płynnie.",
           short: true, long: true),
        ex("eye-eight", .eyes, "Ósemka oczami",
           "Wybierz punkt na podłodze ok. 2,5 m przed sobą. Rysuj wzrokiem leżącą ósemkę przez 30 sekund w jedną stronę i 30 w drugą.",
           short: true, long: true),
        ex("eye-three-depths", .eyes, "Trzy odległości",
           "Znajdź za oknem trzy obiekty: bliski, średni i daleki. Patrz na każdy po 7 sekund, bez mrużenia oczu.",
           short: true, long: true),
        ex("eye-palming", .eyes, "Palming",
           "Rozetrzyj dłonie, przyłóż je lekko do zamkniętych oczu (bez nacisku) i patrz w ciemność przez 30 sekund. Oddychaj wolno.",
           short: true, long: true),
        ex("eye-moisture", .eyes, "Nawilż oczy",
           "Zamrugaj 10 razy i napij się wody. Sprawdź, czy nawiew lub klimatyzacja nie dmucha prosto w twarz.",
           short: true, long: true),

        // Kark i barki
        ex("neck-tilt", .upperBody, "Ucho do ramienia",
           "Powoli pochyl głowę w bok, ucho do ramienia, 10 sekund na stronę. Drugie ramię opuść w dół. Bez szarpania.",
           short: true, long: true),
        ex("shoulder-roll", .upperBody, "Krążenia barków",
           "Zrób 10 powolnych krążeń barków do tyłu, z wydechem w dół. Barki mają opaść, nie unosić się do uszu.",
           short: true, long: true),
        ex("scapula-squeeze", .upperBody, "Ściągnij łopatki",
           "Wyprostuj się, ściągnij łopatki do tyłu i w dół na 5 sekund, rozluźnij. Powtórz 6 razy.",
           short: true, long: true),
        ex("chin-tuck", .upperBody, "Cofnij podbródek",
           "Siedząc prosto, cofnij podbródek poziomo (jak robienie „podwójnego”), przytrzymaj 5 sekund. Powtórz 8 razy. Odciąża kark.",
           short: true, long: true),
        ex("chest-opener", .upperBody, "Otwórz klatkę piersiową",
           "Złącz dłonie za plecami, wypchnij klatkę do przodu i unieś lekko brodę. Trzymaj 20 sekund, oddychaj głęboko.",
           short: true, long: true),

        // Dłonie i nadgarstki
        ex("wrist-extensor", .handsWrists, "Nadgarstek: prostowniki",
           "Wyprostuj rękę przed sobą, dłoń w górę, drugą ręką delikatnie odciągnij palce do siebie. 15 sekund, potem zmień rękę.",
           short: true, long: true),
        ex("wrist-flexor", .handsWrists, "Nadgarstek: zginacze",
           "Wyprostuj rękę, dłoń w dół, drugą ręką delikatnie dociśnij grzbiet dłoni do siebie. 15 sekund, potem zmień rękę.",
           short: true, long: true),
        ex("finger-open", .handsWrists, "Otwórz – zaciśnij",
           "Zaciśnij pięści na 3 sekundy, potem rozsuń palce szeroko na 3 sekundy. Powtórz 10 razy. Strząśnij dłonie.",
           short: true, long: true),

        // Plecy i tułów
        ex("seated-twist", .backCore, "Skręt na siedząco",
           "Usiądź prosto, dłoń na przeciwległym kolanie, skręć tułów i spójrz za siebie. 15 sekund na stronę.",
           short: true, long: true),
        ex("cat-cow", .backCore, "Kot – krowa przy biurku",
           "Oprzyj dłonie o blat, wypchnij plecy w górę na wydechu, a na wdechu lekko pogłęb odcinek lędźwiowy. 6 powtórzeń.",
           short: false, long: true),
        ex("standing-extension", .backCore, "Wyprost do tyłu",
           "Stań, dłonie na biodrach, odchyl tułów lekko do tyłu na 5 sekund. Powtórz 5 razy. Przeciwwaga dla długiego siedzenia.",
           short: false, long: true),

        // Nogi i krążenie
        ex("calf-raise", .legs, "Wspięcia na palce",
           "Stań przy biurku i wspinaj się na palce 15 razy. Pompuje krew z nóg i budzi krążenie.",
           short: true, long: true),
        ex("sit-to-stand", .legs, "Siad – wstań",
           "Usiądź i wstań z krzesła 10 razy, wolno, bez pomocy rąk.",
           short: true, long: true),
        ex("hip-flexor", .legs, "Wykrok – biodra",
           "Zrób wykrok jedną nogą do przodu, tylna noga prosta, biodra do przodu. 20 sekund na stronę. Otwiera biodra po siedzeniu.",
           short: false, long: true),
        ex("walk", .legs, "Spacer",
           "Wyjdź z pomieszczenia i przejdź się przez 2–5 minut: korytarz, schody lub podwórko. Każdy ruch się liczy.",
           short: false, long: true),

        // Stanowisko pracy
        ex("posture-reset", .workstation, "Reset postawy",
           "Stopy płasko na podłodze, kolana ok. 90°, plecy oparte, barki w dół, podbródek lekko cofnięty. Zmień pozycję ciała, nie trzymaj jednej.",
           short: true, long: true),
        ex("screen-check", .workstation, "Przegląd ekranu",
           "Odległość ok. 50–65 cm, środek ekranu nieco poniżej oczu. Czy wyprostowana głowa patrzy lekko w dół na ekran? Popraw wysokość.",
           short: true, long: true),
        ex("light-check", .workstation, "Światło i odbicia",
           "Sprawdź, czy okno lub lampa nie odbija się w ekranie. Dopasuj jasność ekranu do jasności pokoju.",
           short: true, long: true),
        ex("desk-check", .workstation, "Przegląd biurka",
           "Łokcie blisko tułowia, ok. 90°, przedramiona wsparte, nadgarstki proste. Blat tuż poniżej łokci.",
           short: false, long: true),

        // Oddech
        ex("breath-box", .breathing, "Oddech w kwadracie",
           "Wdech nosem na 4 sekundy, zatrzymaj powietrze na 4, wydech ustami na 4, pauza na 4. Powtórz 4 razy, w swoim tempie.",
           short: true, long: true),
        ex("breath-slow-exhale", .breathing, "Wolny wydech",
           "Wdech nosem na 4 sekundy, wydech przez lekko zaciśnięte usta na 6. Powtórz 6 razy i zostaw ramiona luźno.",
           short: true, long: true),
        ex("breath-shoulders-drop", .breathing, "Barki w dół",
           "Unieś barki do uszu przy wdechu, opuść je ciężko przy wydechu. Powtórz 5 razy, potem rozluźnij szczękę i dłonie.",
           short: true, long: true),
    ]
}
