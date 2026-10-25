import Foundation

// MARK: - Messages
//
// A curated, offline library of short articles: tips about eyes / body /
// focus, feature explanations, welcome text. Nothing leaves the machine —
// there is no vendor feed, only our own catalog. The Settings page lists
// them with unread markers and search; during a break an unread hint may
// appear on the break screen (it never changes the break itself).

public struct BreakMessage: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var body: String
    /// Settings pane key for the "Show Me" button (nil = nothing to open).
    public var pane: String?
    /// One-line teaser shown on the break screen.
    public var breakHint: String

    public init(id: String, title: String, subtitle: String, body: String,
                pane: String?, breakHint: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.pane = pane
        self.breakHint = breakHint
    }
}

public enum MessagesCatalog {
    /// The offline catalog, oldest advice first. Polish source text, localized at construction.
    /// Welcome first, then the evidence-based health articles, then feature explainers.
    public static let all: [BreakMessage] = [core[0]] + HealthMessages.all + Array(core.dropFirst())

    private static let core: [BreakMessage] = [
        BreakMessage(
            id: "welcome",
            title: String(localized: "Witaj w Intermezzo"),
            subtitle: String(localized: "Pauzy, które naprawdę działają"),
            body: String(localized: """
            Intermezzo przypomina Ci o przerwach, ale nie walczy z Tobą.

            • Mikropauzy co kilkanaście minut — oczy, kark, nadgarstki.
            • Długie przerwy co 45 minut — wstań, przejdź się, napij wody.
            • Reguły — pauza nie wyskoczy w środku spotkania, prezentacji czy filmu.
            • Skróty i adresy intermezzo:// — steruj pauzami z dowolnej aplikacji i automatyzacji.

            Najważniejsza zasada: pauza ma być odpoczynkiem od EKRANU, nie zmianą ekranu.
            """),
            pane: nil,
            breakHint: String(localized: "Wstań, patrz w dal przez 20 sekund. To cała filozofia.")),
        BreakMessage(
            id: "eyes-20-20-20",
            title: String(localized: "Wzrok: zasada 20-20-20"),
            subtitle: String(localized: "Najważniejszy nawyk przy monitorze"),
            body: String(localized: """
            Co 20 minut patrz przez 20 sekund na obiekt oddalony o 20 stóp (ok. 6 metrów).

            Dlaczego to działa: mięsień rzęskowy rozluźnia się dopiero, gdy patrzysz
            w dal. Ciągłe skupianie wzroku na monitorze to najczęstsza przyczyna pieczenia oczu
            i bólów głowy u osób pracujących przy komputerze.

            Jak to robić dobrze:
            1. Podczas micro-pauzy oderwij wzrok od monitora — najlepiej przez okno.
            2. Zamrugaj świadomie kilkanaście razy.
            3. Obniż jasność monitora wieczorem, włącz tryb nocny.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Patrz 20 sekund w dal. Zamrugaj. Wróć do pracy.")),
        BreakMessage(
            id: "neck-shoulders",
            title: String(localized: "Kark i ramiona"),
            subtitle: String(localized: "Miejsce, gdzie zbiera się cały stres"),
            body: String(localized: """
            Przy monitorze ramiona niech opadną, a nie unoszą do uszu.

            Ćwiczenia na przerwie (30 sekund):
            • Powolne skręty głowy — ucho do ramienia, bez szarpnięć, 5 s na stronę.
            • Krążenia ramion do tyłu — 10 powtórzeń, wydech w dół.
            • Splecione dłonie za plecami, klatka do przodu — otwarcie na 15 s.

            Jeśli czujesz punkt bólu między łopatkami — to znak, że siedzisz za długo
            w jednej pozycji, a nie że potrzebujesz mocniejszego krzesła.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Krążenia ramion do tyłu x10. Skłon głowy na każdą stronę 5 s.")),
        BreakMessage(
            id: "wrists-hands",
            title: String(localized: "Nadgarstki i dłonie"),
            subtitle: String(localized: "Przeciążenie boli dopiero po latach"),
            body: String(localized: """
            Nadgarstki podczas pisania powinny być w jednej linii z przedramieniem —
            klawiatura niżej, nie na krawędzi biurka.

            Na przerwie:
            • Wyprostuj rękę, drugą dłonią delikatnie odegnij palce w dół — 15 s.
            • „Modlitwa”: złóż dłonie jak do modlitwy i opuszczaj je, aż poczujesz rozciąganie.
            • Rozcieraj dłonie o siebie przez 10 sekund — to przywraca czucie.

            Mrowienie palców to sygnał ostrzegawczy. Nie ignoruj go.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Wyprostuj rękę, odgnij palce drugą — 15 sekund. Powtórz.")),
        BreakMessage(
            id: "back-pelvis",
            title: String(localized: "Kręgosłup i odcinek lędźwiowy"),
            subtitle: String(localized: "Najgorsza pozycja to kolejna"),
            body: String(localized: """
            Nie ma jednej „zdrowej” pozycji siedzącej — zdrowa to NASTĘPNA.

            Wyprost w staniu: ręce na biodra, delikatne odchylenie do tyłu, 10 s.
            Na siedząco: kolano do klatki, 20 s na stronę (rozciąganie gruszkowatego).

            Ustaw monitor na wysokość oczu. Jeśli patrzysz w dół — szyja płaci rachunek.
            """),
            pane: nil,
            breakHint: String(localized: "Odchylenie do tyłu z rękami na biodrach. 10 sekund. Drugie ćwiczenie: kolano do klatki.")),
        BreakMessage(
            id: "breathing-4444",
            title: String(localized: "Oddychanie pudełkowe 4-4-4-4"),
            subtitle: String(localized: "Reset układu nerwowego w 2 minuty"),
            body: String(localized: """
            Wdech 4 s — zatrzymanie 4 s — wydech 4 s — zatrzymanie 4 s. Pięć rund.

            To technika z treningu pilotów i sportowców: obniża tętno i wycisza
            tryb „walcz albo uciekaj”, w który wpadasz przy deadline'ach.

            Najlepiej robić to na długiej przerwie, zanim znowu usiądziesz do pracy.
            """),
            pane: nil,
            breakHint: String(localized: "Wdech 4 s, zatrzymanie 4, wydech 4, zatrzymanie 4. Pięć rund.")),
        BreakMessage(
            id: "water-caffeine",
            title: String(localized: "Woda i kofeina"),
            subtitle: String(localized: "Paliwo, o którym zapominasz"),
            body: String(localized: """
            Szklanka wody przy każdej długiej przerwie — odwodnienie objawia się
            spadkiem koncentracji i „głodem” na słodycze.

            Kofeina: ostatnia kawa najpóźniej 8 godzin przed snem.
            Kawa o 16:00 nadal krąży o północy. Alternatywa na poobiedni zjazd:
            10 minut ruchu na świeżym powietrzu działa lepiej niż drugie espresso.
            """),
            pane: nil,
            breakHint: String(localized: "Szklanka wody teraz. Serio. Teraz.")),
        BreakMessage(
            id: "real-lunch",
            title: String(localized: "Prawdziwa przerwa obiadowa"),
            subtitle: String(localized: "Z dala od biurka"),
            body: String(localized: """
            Lunch zjedzony przy monitorze to nie przerwa — to druga zmiana.

            Zasady:
            • Min. 20 minut, najlepiej 30, bez ekranu.
            • Wyjdź na zewnątrz, jeśli możesz — naturalne światło reguluje rytm dobowy.
            • Dodaj w Przerwach stałą przerwę na swoją porę obiadu — Intermezzo przypilnuje.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Odejdź od biurka. Zjedz obiad bez scrollowania.")),
        BreakMessage(
            id: "rules-explained",
            title: String(localized: "Reguły: pauza nie przeszkadza w pracy"),
            subtitle: String(localized: "Spotkanie, film, prezentacja?"),
            body: String(localized: """
            W zakładce Reguły dodajesz reguły typu: „jeśli Zoom jest na pierwszym planie —
            odrocz pauzę o 5 minut”. Intermezzo sprawdza reguły tuż przed nadejściem przerwy.

            Dostępne warunki: aplikacja z przodu / otwarta (z zaprzeczeniem),
            kalendarz (szukany tekst), pełny ekran, wygaszacz, ekran uśpiony,
            Focus, spotkanie online, odtwarzanie wideo, własny AppleScript.

            Wynik: automatyczne pominięcie, odroczenie o N minut,
            „traktuj jako naturalną pauzę” albo „ignoruj naturalną pauzę”.
            """),
            pane: "Rules",
            breakHint: String(localized: "Ciekawe: w Regułach możesz powiedzieć pauzie, by nie wchodziła w spotkania.")),
        BreakMessage(
            id: "shortcuts-explained",
            title: String(localized: "Skróty i adresy intermezzo://"),
            subtitle: String(localized: "Automatyzacja dla leniwych (czyli mądrych)"),
            body: AutomationCatalog.explanation(),
            pane: "General",
            breakHint: String(localized: "Skrót + oddech = zrobiona pauza. Sprawdź skróty w Ustawieniach → Ogólne.")),
        BreakMessage(
            id: "scripts-explained",
            title: String(localized: "Akcje i skrypty na przerwach"),
            subtitle: String(localized: "Wycisz dźwięk, odpal skrypt, pokaż tekst"),
            body: String(localized: """
            Akcje przerw: na każdym etapie przerwy (przed, po, przy kliknięciu przycisku)
            możesz: pokazać powiadomienie, zagrać lub wygasić dźwięk, rozjaśnić ekran,
            wyciszyć system (z zapamiętaniem stanu), pauzować muzykę, uruchomić AppleScript.

            Do tego własne teksty na przerwie, slajdy zdjęć i filmy z YouTube
            jako tapeta przerwy. Wszystko offline, wszystko Twoje.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Wiesz, że możesz kazać Intermezzo wyciszyć system na czas przerwy?")),
        BreakMessage(
            id: "pomodoro",
            title: String(localized: "Technika Pomodoro"),
            subtitle: String(localized: "25 minut pracy, 5 przerwy"),
            body: String(localized: """
            Jeśli łatwo się rozpraszasz: włącz Pomodoro — krótsze cykle (25 minut),
            długa pauza (15–20 minut) co cztery pomidorki.

            Zasada: w trakcie pomodoro nie zmieniasz zadania. Pauza jest nagrodą
            za zamknięty cykl, nie wymówką.
            """),
            pane: "Breaks",
            breakHint: String(localized: "25 minut pracy to ile? Tyle, ile wynosi Twój cykl.")),
        BreakMessage(
            id: "sleep-hygiene",
            title: String(localized: "Niebieskie światło i koniec dnia"),
            subtitle: String(localized: "Wieczór to nie przedłużenie dnia"),
            body: String(localized: """
            Godzinę przed snem: tryb nocny na maksa, żadnej pracy na ekranie.

            Koniec dnia w Intermezzo przypomni Ci o „wyjściu z pracy” o wybranej godzinie.
            Praca bez granic czasowych to najcichsza droga do wypalenia.
            """),
            pane: "Clock Out",
            breakHint: String(localized: "Wieczorem: odłóż. Jutro projekt nadal będzie czekał.")),
        BreakMessage(
            id: "desk-work-rhythm",
            title: String(localized: "Rytm pracy przy komputerze"),
            subtitle: String(localized: "Jak nie wypalić się do zera"),
            body: String(localized: """
            1. Praca blokami 45–90 minut, nie maratonem 6-godzinnym.
            2. Pauza = ruch + dal + oddech. Scrollowanie telefonu to NIE pauza.
            3. Trudne zadania rano, po przerwie — uwaga wraca na szczyt.
            4. Jedno zamknięte okno > dziesięć otwartych. Powiadomienia na Focus.
            5. Jeśli nie możesz zrobić przerwy — coś w planowaniu jest nie tak,
               nie w ciele. Napraw harmonogram, nie tabelki z rozciąganiem.
            """),
            pane: nil,
            breakHint: String(localized: "Pauza to ruch + dal + oddech. Telefon to nie odpoczynek.")),
    ]
}

public final class MessagesStore {
    public static let readKey = "messagesReadIDs"
    public static let breakEveryKey = "messagesBreakEvery"
    public static let pendingKey = "messagesPendingOpen"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func readIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.readKey) ?? [])
    }

    public func isUnread(_ message: BreakMessage) -> Bool {
        !readIDs().contains(message.id)
    }

    public func markRead(id: String) {
        var ids = readIDs()
        ids.insert(id)
        defaults.set(Array(ids), forKey: Self.readKey)
    }

    public func markAllRead() {
        defaults.set(MessagesCatalog.all.map { $0.id }, forKey: Self.readKey)
    }

    /// Pick the next unread hint for the break screen. `every` = cadence
    /// (defaults to 3 breaks); returns nil when disabled or all read.
    public func messageForBreak(breakIndex: Int, enabled: Bool) -> BreakMessage? {
        guard enabled else { return nil }
        let every = max(1, defaults.integer(forKey: Self.breakEveryKey))
        guard (breakIndex + 1) % every == 0 else { return nil }
        let read = readIDs()
        return MessagesCatalog.all.first { !read.contains($0.id) }
    }
}
