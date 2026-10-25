import Foundation

/// Evidence-based articles about screen work, eyes and movement. Every body
/// ends with a "Źródła:" line and states how strong the evidence is — a lot of
/// the guidance rests on expert consensus and small studies.
public enum HealthMessages {
    public static let all: [BreakMessage] = [
        BreakMessage(
            id: "blink-rate",
            title: String(localized: "Mrugasz rzadziej, niż myślisz"),
            subtitle: String(localized: "Suche oczy zaczynają się od mrugnięć"),
            body: String(localized: """
            Normalnie mrugamy ok. 15–20 razy na minutę. Przy ekranie spada to do ok. 4–6 na minutę. \
            W jednym z cytowanych badań biurowych: 22/min w spoczynku, 10/min przy książce, 7/min przy ekranie.

            Liczy się też jakość: niepełne mrugnięcia słabiej rozprowadzają film łzowy. Częstość spada \
            jeszcze bardziej przy niskim kontraście, małej czcionce i trudnym zadaniu.

            Co robić:
            • Co jakiś czas zrób 10 pełnych, wolnych mrugnięć (powieka dotyka powieki).
            • Powiększ tekst i podnieś kontrast, gdy męczysz się przy czytaniu.
            • Włącz w Intermezzo „Przypomnienie o mruganiu” (Przypomnienie błyskiem).

            Siła dowodów: w małym badaniu eksploracyjnym (11 osób) niższa częstość mrugania silnie \
            korelowała z nasileniem objawów — to wskazówka, nie dowód.

            Źródła: Lapa i in. 2023, Int. J. Environ. Res. Public Health (PMC10001854); Kaur i in. 2022, \
            Ophthalmol. Ther. (PMC9434525).
            """),
            pane: "Flash Reminder",
            breakHint: String(localized: "Zrób 10 pełnych, wolnych mrugnięć. Przy ekranie mrugasz 3–4 razy rzadziej.")),
        BreakMessage(
            id: "break-science",
            title: String(localized: "Ile przerw i jak długich?"),
            subtitle: String(localized: "Co mówią zalecenia i badania"),
            body: String(localized: """
            Różne źródła podają różne rytmy — warto znać każdy:

            • 20-20-20: co 20 min patrz 20 s na obiekt ok. 6 m dalej (AOA, Harvard, Medical News Today).
            • 5 min po 30 min pracy (przegląd Dyrek i in. 2024).
            • Co najmniej 5 min po godzinie nieprzerwanej pracy z monitorem — wymóg polskich przepisów, \
            wliczany do czasu pracy (za CIOP-PIB).
            • Wytyczne instytucjonalne bywają łagodniejsze: np. 15 min na każde 2 godziny.

            Najświeższe badanie (Redondo i in. 2025; 24 młodych dorosłych, 40 min czytania): przerwy \
            co 10 minut i przerwy we własnym tempie zmniejszały podrażnienie oczu, a bez przerw \
            występowała większa przejściowa krótkowzroczność. Jedna przerwa w środku dawała mniej.

            Uwaga: według innego badania (relacja Review of Optometry) samo 20 sekund patrzenia w dal \
            może nie wystarczać, by wzrok w pełni „odpuścił”. Dlatego Intermezzo ma gotowe profile \
            (Przerwy → Gotowe profile) i dłuższą przerwę co kilka krótkich.

            Siła dowodów: małe próby, głównie młodzi dorośli; spójny wniosek to „częściej i krócej \
            lepiej niż rzadko”.

            Źródła: Redondo i in. 2025, Exp. Eye Res. 258:110463 (abstrakt); Dyrek i in. 2024, \
            Eur. J. Clin. Exp. Med. 22(1) (abstrakt); Kamińska 2016, Bezpieczeństwo Pracy 9 (CIOP-PIB, \
            za streszczeniem); wytyczne Univ. Bologna (VDT); Harvard Health; Medical News Today.
            """),
            pane: "Breaks",
            breakHint: String(localized: "Częściej i krócej wygrywa z rzadko i długo. Wstań, popatrz w dal.")),
        BreakMessage(
            id: "screen-setup",
            title: String(localized: "Ekran: odległość i wysokość"),
            subtitle: String(localized: "Źródła podają różne zakresy — oto wspólna część"),
            body: String(localized: """
            • Odległość: AAO (za Harvard Health) 50–66 cm; przegląd Kaur 2022 ok. 50 cm; Medical News Today \
            podaje 89–102 cm. Praktycznie: czytasz bez pochylania głowy i mrużenia oczu.
            • Wysokość: środek ekranu nieco poniżej poziomu oczu (Kaur: 15–20° poniżej poziomu); \
            Medical News Today: górna krawędź 13–15 cm poniżej oczu.
            • Ekran nie powinien odbijać okna ani lamp.
            • Materiały pomocnicze trzymaj między klawiaturą a monitorem, nie z boku.
            • Krzesło: stopy płasko, plecy podparte, ręce wsparte.

            Dla dużych i szerokich monitorów używaj górnego zakresu odległości.

            Źródła: Harvard Health (AAO); Kaur i in. 2022 (PMC9434525); Medical News Today.
            """),
            pane: nil,
            breakHint: String(localized: "Środek ekranu nieco poniżej oczu, ok. 50–65 cm od twarzy.")),
        BreakMessage(
            id: "lighting-glare",
            title: String(localized: "Światło i odblaski"),
            subtitle: String(localized: "Połowa walki o zmęczone oczy"),
            body: String(localized: """
            • Dopasuj jasność ekranu do jasności pomieszczenia — ekran jaśniejszy lub ciemniejszy od \
            otoczenia męczy.
            • Nie siedź twarzą ani plecami do okna: jedno daje oślepienie, drugie odbicie w ekranie.
            • Błyszczący ekran? Pomoże matowy filtr.
            • Przegląd Kaur 2022: wydajność spada przy oświetleniu otoczenia powyżej ok. 1000 lx; \
            Medical News Today: po 50. roku życia potrzeba mniej więcej dwa razy więcej światła niż \
            w wieku 20 lat.
            • Małe badanie randomizowane (Digital J. Ophthalmol., za streszczeniem): zmniejszenie \
            jasności ekranu obniżyło nasilenie zmęczenia oczu, a program zmieniający temperaturę barwy \
            — nie.

            Źródła: Harvard Health (AAO); Kaur i in. 2022; Medical News Today; Digital Journal of \
            Ophthalmology (streszczenie z wyszukiwarki).
            """),
            pane: nil,
            breakHint: String(localized: "Czy okno lub lampa odbija się w ekranie? Dopasuj jasność do pokoju.")),
        BreakMessage(
            id: "display-settings",
            title: String(localized: "Ustawienia ekranu"),
            subtitle: String(localized: "Kontrast i rozmiar czcionki"),
            body: String(localized: """
            • Kontrast ok. 60–70% (Kaur 2022) i wyraźna czcionka, co najmniej 12 pkt; najlepiej \
            ciemny tekst na jasnym tle.
            • Zwiększ kontrast na ekranie (AAO).
            • Powiększ tekst, jeśli mrużysz oczy — mały tekst obniża częstość mrugania.
            • Trzymaj ekran i okulary czyste.

            To zalecenia z przeglądów, oparte w dużej mierze na konsensusie ekspertów.

            Źródła: Kaur i in. 2022; Harvard Health (AAO); Lapa i in. 2023.
            """),
            pane: nil,
            breakHint: String(localized: "Mrużysz oczy? Powiększ tekst i podnieś kontrast.")),
        BreakMessage(
            id: "blue-light",
            title: String(localized: "Niebieskie światło: mit czy fakt?"),
            subtitle: String(localized: "Okulary z filtrem nie leczą zmęczenia oczu"),
            body: String(localized: """
            Amerykańska Akademia Okulistyki (AAO) nie widzi mocnych dowodów, że niebieskie światło z \
            ekranów powoduje zmęczenie oczu, i nie zaleca okularów z filtrem. Przegląd Kaur 2022: \
            wyniki badań są niespójne, a próby małe (ok. 20 osób). Systematyczny przegląd Blasioli i \
            Baleiron: rola niebieskiego światła dla przyszłego zdrowia wzroku jest niepewna.

            Co faktycznie pomaga: przerwy, mruganie, światło i ergonomia. Tryb nocny bywa wygodny \
            wieczorem, ale to nie jest leczenie zmęczenia oczu.

            Źródła: Harvard Health (AAO); Kaur i in. 2022; Blasioli i Baleiron (streszczenie).
            """),
            pane: nil,
            breakHint: String(localized: "Okulary z filtrem nie zastąpią przerwy. Patrz w dal.")),
        BreakMessage(
            id: "light-sleep",
            title: String(localized: "Światło wieczorem a sen"),
            subtitle: String(localized: "Dlaczego po zachodzie ekran powinien być cieplejszy"),
            body: String(localized: """
            Za zegar dobowy odpowiadają m.in. komórki zwojowe siatkówki z melanopsyną, najczulsze na światło niebiesko-zielone (ok. 480 nm). Wieczorne światło o dużej luminancji hamuje melatoninę i może przesunąć porę zasypiania.

            Co pokazały badania: zwykłe światło pokojowe przed snem skracało czas trwania melatoniny (Gooley i in. 2011); krótkie fale działają na zegar szczególnie silnie (Lockley i in. 2003); w badaniu laboratoryjnym wieczorny ekran LED silniej hamował melatoninę i zmniejszał senność niż starszy monitor (Cajochen i in. 2011).

            Co z tego wynika: liczy się nie tylko barwa, ale też jasność ekranu i pokoju oraz czas ekspozycji. Cieplejsza barwa i niższa jasność wieczorem to tanie, rozsądne kroki, ale żadne badanie nie wskazało jednej „właściwej” temperatury, a ocieplenie ekranu nie zastąpi ciemnej sypialni i stałej pory snu.

            W Intermezzo: panel Światło zmienia barwę ekranu zgodnie z porą dnia, wschodem i zachodem słońca oraz Twoją godziną snu.

            Siła dowodów: spójny kierunek w badaniach laboratoryjnych na małych grupach; wpływ na sen w codziennym życiu jest mniej pewny.

            Źródła: Gooley i in. 2011, J. Clin. Endocrinol. Metab. 96(3):E463; Lockley, Brainard, Czeisler 2003, J. Clin. Endocrinol. Metab. 88(9):4502; Cajochen i in. 2011, J. Appl. Physiol. 110(5):1432.
            """),
            pane: "Light",
            breakHint: String(localized: "Wieczorem ściszaj nie tylko dźwięk, ale i światło: niższa jasność, cieplejsza barwa.")),
        BreakMessage(
            id: "light-by-day",
            title: String(localized: "Barwa światła w ciągu dnia"),
            subtitle: String(localized: "Chłodniejsze w dzień, cieplejsze wieczorem"),
            body: String(localized: """
            W dzień jasne, chłodniejsze światło (o wysokiej temperaturze barwowej) sprzyja czujności, a wieczorem ciepłe światło wiąże się z łagodniejszym spadkiem aktywności organizmu. Dowody pochodzą jednak głównie z małych, krótkich badań.

            Przykłady: w badaniu biurowym Millsa i in. (2007) światło o wyższej temperaturze barwowej poprawiło samopoczucie i część wskaźników pracy; w laboratoryjnym badaniu Kozakiego i in. światło o barwie 6700 K przed snem osłabiło głęboki sen bardziej niż 3000 K (7 mężczyzn).

            Rano pomaga światło dzienne: wyjdź na zewnątrz albo usiądź przy oknie. Ekran go nie zastąpi, bo na zewnątrz jest wielokrotnie jaśniej.

            W Intermezzo: w dzień ekran zostaje neutralny (6500 K), po zachodzie ociepla się, a przed snem robi się najcieplejszy. Profil „Zalecane” to nasz kompromis oparty na tym kierunku badań, nie zalecenie lekarskie.

            Siła dowodów: małe próby i różne metody; traktuj to jako wskazówkę do własnego eksperymentu, nie receptę.

            Źródła: Mills, Tomkins, Schlangen 2007, J. Circadian Rhythms 5:2; Kozaki i in., J. Physiol. Anthropol. (wpływ temperatury barwowej na sen wolnofalowy).
            """),
            pane: "Light",
            breakHint: String(localized: "Rano wyjdź na światło dzienne: to najlepszy „ekran” dla zegara dobowego.")),
        BreakMessage(
            id: "eye-surface",
            title: String(localized: "Wilgotne oczy"),
            subtitle: String(localized: "Środowisko ma znaczenie"),
            body: String(localized: """
            • Mrugaj świadomie, zwłaszcza przy czytaniu i ekranie.
            • Zimą włącz nawilżacz powietrza; nie kieruj nawiewów (też samochodowych) w oczy.
            • Do pracy przy komputerze lepsze okulary niż soczewki kontaktowe — albo krople nawilżające.
            • Sztuczne łzy bez konserwantów mogą pomóc przy uporczywych objawach; zapytaj okulistę.

            Źródła: Harvard Health; Kaur i in. 2022.
            """),
            pane: nil,
            breakHint: String(localized: "Nawiew w twarz? Odwróć go. Zimą nawilżaj powietrze.")),
        BreakMessage(
            id: "symptoms-when",
            title: String(localized: "Objawy i kiedy do okulisty"),
            subtitle: String(localized: "Trzy grupy dolegliwości"),
            body: String(localized: """
            Cyfrowe zmęczenie oczu (DES) obejmuje trzy grupy objawów:
            • powierzchnia oka: suchość, pieczenie, łzawienie, zaczerwienienie,
            • ostrość i ogniskowanie: niewyraźne widzenie, trudność z przeostrzeniem, czasem podwójne widzenie,
            • poza okiem: bóle głowy, karku, ramion i pleców.

            Gdy objawy są uporczywe mimo przerw i poprawy stanowiska, zrób pełne badanie okulistyczne. \
            Nieskorygowana wada wzroku to jeden z głównych czynników ryzyka; okulary do pracy przy \
            komputerze projektuje się zwykle na ok. 63 cm.

            To nie porada medyczna — przy niepokojących objawach skonsultuj się z lekarzem.

            Źródła: Kaur i in. 2022 (PMC9434525); Medical News Today; Harvard Health (AAO).
            """),
            pane: nil,
            breakHint: String(localized: "Uporczywe objawy mimo przerw? Zrób badanie wzroku.")),
        BreakMessage(
            id: "screen-time-limit",
            title: String(localized: "Ile godzin przy ekranie to dużo?"),
            subtitle: String(localized: "Ok. 4 godziny dziennie jako próg ryzyka"),
            body: String(localized: """
            W przeglądzie Kaur 2022 użycie ekranu powyżej 4 godzin dziennie należy do głównych \
            czynników ryzyka cyfrowego zmęczenia oczu (obok nieskorygowanej wady wzroku i suchego oka), \
            a autorzy zalecają ograniczać średni dzienny czas ekranowy do ok. 4 godzin.

            Dla pracy biurowej to nierealne w całości — dlatego Intermezzo liczy Twój aktywny czas przy \
            Macu i raz dziennie przypomina po 4 godzinach. Wtedy: dłuższa przerwa bez ekranu, \
            spacer, wieczorem odpoczynek od telefonu.

            Dane o czasie ekranowym to w większości ankiety; traktuj 4 h jako orientację, nie granicę.

            Źródła: Kaur i in. 2022 (PMC9434525); Redondo i in. 2025.
            """),
            pane: "Status",
            breakHint: String(localized: "Spójrz na licznik czasu przy ekranie w Statusie. Dłuższa przerwa pomoże.")),
        BreakMessage(
            id: "move-more",
            title: String(localized: "Ruch: ile i jak"),
            subtitle: String(localized: "Siedzenie to osobny problem"),
            body: String(localized: """
            WHO zaleca dorosłym 150–300 minut umiarkowanej aktywności tygodniowo (lub 75–150 min \
            intensywnej). Osoby pracujące przy komputerze rzadziej spełniają te normy. Każda ilość ruchu \
            przynosi korzyść.

            Częste dolegliwości: kark, bark, odcinek lędźwiowy. Długie godziny bez przerw zwiększają \
            ryzyko, a ćwiczenia (rozciągające, wzmacniające, aerobowe) działają ochronnie. Zmienność \
            ruchu i pozycji zmniejsza obciążenie statyczne.

            Intermezzo podpowiada ćwiczenia przy każdej przerwie: oczy w krótkich, ciało w dłuższych.

            Źródła: Moreira i in. 2022, Healthcare 10(12):2457 (PMC9778108).
            """),
            pane: "Exercises",
            breakHint: String(localized: "Wstań. Każdy ruch się liczy — nawet 2 minuty.")),
        BreakMessage(
            id: "posture-variety",
            title: String(localized: "Zmieniaj pozycję, nie szukaj idealnej"),
            subtitle: String(localized: "Statyczna postawa męczy, nawet poprawna"),
            body: String(localized: """
            Wytyczne ergonomiczne (Towson EHS) i przegląd Moreira 2022 podkreślają: unikaj długiej, \
            nieruchomej pozycji, zmieniaj zadania i ruch w ciągu zmiany. Ramiona rozluźnione, łokcie \
            blisko tułowia, blat tuż poniżej łokci, kolana ok. 90°.

            W eksperymencie KAIST (CHI 2018 i kontynuacja, 12 osób, 4 godziny) powolne, niezauważalne \
            przesuwanie monitora skłaniało do częstszych korekt pozycji i skracało czas siedzenia \
            asymetrycznie, a uczestnicy odczuwali mniejsze zmęczenie. To pokazuje, że zmiana pozycji \
            sama w sobie pomaga. Znamy tylko streszczenia tych prac.

            Co robić: raz na jakiś czas zmień pozycję — wstań, przechyl oparcie, zmień wysokość blatu.

            Źródła: Towson EHS, Ergonomics Guidelines for Laboratories 2024; Moreira i in. 2022; \
            Shin i in. 2018 (KAIST, abstrakt).
            """),
            pane: nil,
            breakHint: String(localized: "Zmień pozycję. Najlepsza postawa to ta następna.")),
        BreakMessage(
            id: "workstation-checklist",
            title: String(localized: "Lista kontrolna stanowiska (30 s)"),
            subtitle: String(localized: "Przejrzyj raz w tygodniu"),
            body: String(localized: """
            ☐ Ekran: środek poniżej oczu, ok. 50–65 cm, bez odbić.
            ☐ Jasność ekranu = jasność pokoju.
            ☐ Łokcie ok. 90°, przedramiona wsparte, nadgarstki proste.
            ☐ Stopy płasko (lub na podnóżku), kolana ok. 90°.
            ☐ Plecy oparte; barki rozluźnione.
            ☐ Rzeczy często używane w zasięgu ręki, nie na wyciągniętych ramionach.
            ☐ Okno nie świeci w oczy ani w ekran.
            ☐ Woda w zasięgu ręki.

            Źródła: Harvard Health (AAO); Medical News Today; Kaur i in. 2022; Towson EHS 2024.
            """),
            pane: nil,
            breakHint: String(localized: "30 s na przegląd: ekran, łokcie, stopy, światło.")),
        BreakMessage(
            id: "outdoors-myopia",
            title: String(localized: "Dzieci, światło dzienne i krótkowzroczność"),
            subtitle: String(localized: "Dla rodziców"),
            body: String(localized: """
            Przegląd Kaur 2022 cytuje dane o przyspieszeniu krótkowzroczności u dzieci w pandemii: w \
            jednym badaniu 45,9% z 133 dzieci pogorszyło wadę o co najmniej 1 dioptrię rocznie (przed \
            pandemią 10,5%). Mniej niż godzina dziennie na słońcu wiązała się z szybszą progresją.

            Zalecenia: ogranicz czas ekranowy dzieci, dbaj o czas na dworze i regularne badania wzroku.

            Źródła: Kaur i in. 2022 (PMC9434525).
            """),
            pane: nil,
            breakHint: String(localized: "Dzieci też potrzebują dalekiego patrzenia i światła dziennego.")),
        BreakMessage(
            id: "evidence-quality",
            title: String(localized: "Skąd to wiemy — i jak pewnie"),
            subtitle: String(localized: "Uczciwie o sile dowodów"),
            body: String(localized: """
            To nie porada medyczna. Treści w Intermezzo opieramy na przeglądach i zaleceniach; część to \
            konsensus ekspertów, nie wyniki dużych prób.

            Dobrze podparte: przerwy zmniejszają objawy; ergonomia stanowiska i światło mają znaczenie; \
            ruch chroni układ mięśniowo-szkieletowy.
            Umiarkowanie: mruganie (małe badania), konkretny rytm przerw (próby po 11–24 osoby).
            Słabo / niespójnie: okulary z filtrem światła niebieskiego, programy zmieniające barwę ekranu.

            Czytaliśmy w całości: Kaur 2022 (PMC9434525), Lapa 2023 (PMC10001854), Moreira 2022 \
            (PMC9778108), Harvard Health, Medical News Today, wytyczne Towson. Tylko streszczenia: \
            Redondo 2025, Dyrek 2024, Blasioli i Baleiron, Mierczak i Garus-Pakowska 2025, Kamińska 2016, \
            Shin 2018. Nie udało się otworzyć (blokada serwera): strony ResearchGate, ScienceDirect i \
            MDPI.

            Źródła: patrz wyżej oraz plik docs/zrodla-zdrowie-oczu.md w repozytorium.
            """),
            pane: nil,
            breakHint: String(localized: "Przerwy działają. Reszta to drobne próby — traktuj jako wskazówki.")),
    ]
}
