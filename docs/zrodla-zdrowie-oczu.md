# Źródła treści zdrowotnych Intermezzo

Treści w `HealthMessages.swift`, `ExerciseLibrary.swift` i profilach przerw (`BreakPreset.swift`) opierają się na poniższych pracach. To **nie jest porada medyczna**. Znaczna część zaleceń to konsensus ekspertów, a badania mają małe próby.

## Przeczytane w całości (tekst pobrany)
| Źródło | Co z niego wzięto |
|---|---|
| Kaur i in. 2022, *Digital Eye Strain – A Comprehensive Review*, Ophthalmol. Ther. 11(5):1655–1680 (PMC9434525) | trzy grupy objawów; ≈15–20 → 4–6 mrugnięć/min; próg ok. 4 h/dzień; ekran ok. 50 cm, 15–20° poniżej poziomu; <1000 lx; kontrast 60–70%, czcionka ≥12; niespójne dowody dla filtrów niebieskiego światła; krótkowzroczność u dzieci |
| Lapa i in. 2023, *Real-Time Blink Detection as an Indicator of CVS*, IJERPH 20(5):4569 (PMC10001854) | częstość mrugania (22 → 10 → 7/min w cytowanym badaniu), korelacja z nasileniem objawów (r = −0,78, **11 osób, eksploracyjne**) |
| Moreira i in. 2022, *Occupational Health: Physical Activity, Musculoskeletal Symptoms and QoL in Computer Workers*, Healthcare 10(12):2457 (PMC9778108) | zalecenia WHO 150–300 min/tydz.; kark, bark, lędźwie; ćwiczenia ochronne; zmienność ruchu |
| Medical News Today, *Computer eye strain* | 20-20-20, ósemka, przełączanie ostrości, odległość 89–102 cm, góra ekranu 13–15 cm poniżej oczu |
| Harvard Health, *Effective tips for reducing eye strain* (za AAO) | 50–66 cm, środek ekranu poniżej oczu, odblaski, nawilżanie, brak dowodów dla okularów z filtrem |
| Towson Univ. EHS, *Ergonomics Guidelines for Laboratories* (2024) | statyczna postawa, rotacja zadań, blat tuż poniżej łokci, kolana ok. 90°, mikroprzerwy |

## Znane tylko ze streszczeń (abstrakt / wyszukiwarka)
| Źródło | Co z niego wzięto | Uwaga |
|---|---|---|
| Redondo, Jiménez, Vera, Rosenfield 2025, *The impact of break schedules on digital eye strain symptoms and ocular accommodation during prolonged near work*, Exp. Eye Res. 258:110463 | 24 osoby, 40 min czytania: przerwy co 10 min i we własnym tempie zmniejszały podrażnienie; więcej przejściowej krótkowzroczności bez przerw | zidentyfikowane po tytule; PII S0014483525002349 zgodne według wyszukiwarki |
| Dyrek i in. 2024, *Prolonged screen-time as the cause of ocular disorders…*, Eur. J. Clin. Exp. Med. 22(1):222–231 | 5 min po 30 min, 20-20-20, odległość, światło, powłoka antyodblaskowa | abstrakt |
| Kamińska 2016, *Bezpieczeństwo Pracy* 9:24–27 (CIOP-PIB) | polski wymóg: ≥5 min po godzinie pracy z monitorem, wliczane do czasu pracy | za streszczeniem wyszukiwarki; PDF nie otworzył się |
| Blasioli i Baleiron (2025, przegląd); Mierczak i Garus-Pakowska 2025, Front. Public Health | niepewna rola niebieskiego światła; niska świadomość profilaktyki (ok. 32% zadowalająca) | streszczenia |
| Shin, Lee, Choi, Saakes 2018, *Actuating a Monitor for Posture Changes*, CHI EA; kontynuacja KAIST (12 osób, 4 h) | powolne przesuwanie monitora zwiększa korekty pozycji | abstrakty |
| Camboim i in. 2023, *Posture monitoring in healthcare: a systematic mapping study*, Med. Biol. Eng. Comput. 61(8):1887–1899 | monitorowanie postawy czujnikami (IoT/IMU) | abstrakt; Intermezzo nie używa kamery ani czujników |
| *Digital Journal of Ophthalmology*, *Effects of digital screen property modification…* | zmniejszenie jasności obniżyło zmęczenie (−0,82), program zmieniający barwę nie | fragment z wyszukiwarki |
| Univ. Bologna, wytyczne VDT | 15 min na każde 120 min | wytyczne instytucjonalne |

## Nie udało się otworzyć (blokada serwera, HTTP 403 / błąd TLS)
- ResearchGate: *Visual health and prolonged use of screens in working-age adults*; *Modern workplace visual ergonomics…*; *Working with display screen equipment: health problems and preventive measures*; polska praca CIOP o obciążeniu narządu wzroku (nr 308316313).
- ScienceDirect: `S2405844023064630` (Heliyon 2023).
- MDPI: `2227-9032/10/12/2457` (rozpoznane przez Europe PMC jako Moreira 2022 — patrz wyżej), `2673-7078/1/2/18`, `2313-576X/11/4/122`.
- `h-ph.pl` (Hygeia 2015): błędny certyfikat TLS serwera — weryfikacji nie omijano.

Treści z tych prac **nie** zostały użyte. Jeśli chcesz je uwzględnić, wklej tekst lub PDF.

## Co z tego wdrożono
- 5 profili przerw (20-20-20, częste mikroprzerwy, 5 min/30 min, BHP 5 min/60 min, zrównoważony) z podanym źródłem.
- Biblioteka 26 ćwiczeń (oczy, kark/barki, nadgarstki, plecy, nogi, stanowisko), krótkie dla krótkich przerw, dłuższe dla długich.
- 14 wiadomości z linią „Źródła:” i oceną siły dowodów.
- Przypomnienie o mruganiu (opcja) i dzienny licznik aktywnego czasu przy ekranie z jednorazowym alertem po 4 h.
- Świadomie nie wdrożono: detekcji mrugania kamerą (prywatność, mała próba w badaniu), czujników postawy, ruchomego monitora.
