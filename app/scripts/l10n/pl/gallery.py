# Script gallery, break presets, rule labels, weather tips. Polish.
# Key = the literal in the Swift source; every key here must also be in ../en/gallery.py.
STRINGS = {
    "Wykrywa, gdy aktywnie prowadzisz lub odbierasz rozmowę FaceTime. Przerwa zostanie odroczona do końca spotkania.":
        "Wykrywa, gdy aktywnie prowadzisz lub odbierasz rozmowę FaceTime. Przerwa zostanie odroczona do końca spotkania.",
    "Zalecane: odroczony lub pomijany automatycznie.": "Zalecane: odroczenie lub automatyczne pominięcie.",
    "Sprawdza, czy któryś klient wideokonferencji ma otwarte aktywne okno. Nie pomija przerw tylko dlatego, że aplikacja działa w tle.":
        "Sprawdza, czy któryś klient wideokonferencji ma otwarte aktywne okno. Nie pomija przerw tylko dlatego, że aplikacja działa w tle.",
    "Zalecane: odroczenie przerwy.": "Zalecane: odroczenie przerwy.",
    "Gry Steam nie zawsze są wykrywalne jak zwykłe aplikacje. Ten skrypt sprawdza proces gry lub Big Picture. Przerwa w środku rajdu? Nigdy.":
        "Gry Steam nie zawsze są wykrywalne jak zwykłe aplikacje. Ten skrypt sprawdza proces gry lub Big Picture. Przerwa w środku rajdu? Nigdy.",
    "Zalecane: pomijaj automatycznie podczas grania.": "Zalecane: pomijaj automatycznie podczas grania.",
    "Podgląd/Skim/App Books na pierwszym planie: wpatrujesz się w ekran, ale nie ruszasz myszką — Intermezzo nie powinien traktować tego jako naturalnej przerwy, a przerwy oddelegować na po przeczytaniu rozdziału.":
        "Podgląd/Skim/Książki na pierwszym planie: wpatrujesz się w ekran, ale nie ruszasz myszką — Intermezzo nie powinno traktować tego jako naturalnej przerwy, a przerwy powinno odroczyć do końca rozdziału.",
    "Wykrywa tryb slajdów Keynote lub PowerPointa — publiczność patrzy na Ciebie, nie na Twój nadgarstek. Przerwa poczeka do końca prezentacji.":
        "Wykrywa tryb slajdów Keynote lub PowerPointa — publiczność patrzy na Ciebie, nie na Twój nadgarstek. Przerwa poczeka do końca prezentacji.",
    "Zalecane: pomijaj automatycznie.": "Zalecane: pomijaj automatycznie.",
    "TeamViewer, AnyDesk, Parsec, Jump Desktop, Windows App lub udostępnianie ekranu macOS na pierwszym planie. Przerwa nie wskoczy w środek sesji u klienta ani cudzej pomocy.":
        "TeamViewer, AnyDesk, Parsec, Jump Desktop, Windows App lub udostępnianie ekranu macOS na pierwszym planie. Przerwa nie wskoczy w środek sesji u klienta ani cudzej pomocy.",
    "OBS, ScreenFlow, Loom, Screen Studio, CleanShot lub nagranie ekranu w QuickTime ma otwarte okno. Wykrywa narzędzie, nie sam fakt nagrywania, więc przy otwartym OBS bez nagrywania też zadziała.":
        "OBS, ScreenFlow, Loom, Screen Studio, CleanShot lub nagranie ekranu w QuickTime ma otwarte okno. Wykrywa narzędzie, nie sam fakt nagrywania, więc przy otwartym OBS bez nagrywania też zadziała.",
    "Okno przeglądarki z tytułem spotkania: Google Meet, Microsoft Teams, Whereby, Jitsi, Webex lub Zoom w przeglądarce. Wideo w kartach nie jest wykrywane przez aplikacje desktopowe, dlatego osobna reguła. Wymaga uprawnienia Ułatwień dostępu.":
        "Okno przeglądarki z tytułem spotkania: Google Meet, Microsoft Teams, Whereby, Jitsi, Webex lub Zoom w przeglądarce. Wideo w kartach nie jest wykrywane przez reguły dla aplikacji desktopowych, dlatego osobna reguła. Wymaga uprawnienia „Dostępność”.",
    "Okno huddle Slacka albo połączenie głosowe na Discordzie. Rozmowa jest wtedy ważniejsza niż przypomnienie o przerwie. Wymaga uprawnienia Ułatwień dostępu.":
        "Okno huddle Slacka albo połączenie głosowe na Discordzie. Rozmowa jest wtedy ważniejsza niż przypomnienie o przerwie. Wymaga uprawnienia „Dostępność”.",
    "Terminal na pierwszym planie, a w systemie działa żywy ssh, mosh, vim, nvim lub htop. Chroni długie sesje zdalne i edycję, której nie chcesz przerywać w pół zdania.":
        "Terminal na pierwszym planie, a w systemie działa aktywna sesja ssh lub mosh albo vim, nvim lub htop. Chroni długie sesje zdalne i edycję, której nie chcesz przerywać w pół zdania.",
    "Logic, GarageBand, Ableton, Pro Tools, Cubase, Reaper, Final Cut, Premiere, DaVinci Resolve lub Blender na pierwszym planie. Wejście w stan flow trudno odbudować po przerwie w środku nagrania lub renderu.":
        "Logic, GarageBand, Ableton, Pro Tools, Cubase, Reaper, Final Cut, Premiere, DaVinci Resolve lub Blender na pierwszym planie. Stan flow trudno odbudować po przerwie w środku nagrania lub renderu.",
    "Launchery i gry, które nie są Steamem: Epic, Battle.net, GOG Galaxy, Heroic, CrossOver, Whisky, RetroArch, Minecraft. Uzupełnia regułę „Gra Valve / Steam”.":
        "Launchery i gry, które nie są Steamem: Epic, Battle.net, GOG Galaxy, Heroic, CrossOver, Whisky, RetroArch, Minecraft. Uzupełnia regułę „Gra Valve / Steam”.",
    "Gdy ekran jest powielony na projektorze lub telewizorze (Mirror: On), to prawie na pewno ktoś na niego patrzy. Przerwa na cały ekran na czyjejś prezentacji byłaby niezręczna.":
        "Gdy ekran jest powielony na projektorze lub telewizorze (Mirror: On), to prawie na pewno ktoś na niego patrzy. Przerwa na cały ekran na czyjejś prezentacji byłaby niezręczna.",
    "Działa xcodebuild, swift-build, cargo, gradle, mvn, ninja, ffmpeg lub HandBrake. Podczas czekania i tak nie masz nic do roboty, więc Intermezzo zaproponuje przerwę — dopiero gdy zadanie trwa dłużej niż ustawiony czas (domyślnie 2 min), a od ostatniej przerwy minęło co najmniej 10 minut pracy.":
        "Działa xcodebuild, swift-build, cargo, gradle, mvn, ninja, ffmpeg lub HandBrake. Podczas czekania i tak nie masz nic do roboty, więc Intermezzo zaproponuje przerwę — dopiero gdy zadanie trwa dłużej niż ustawiony czas (domyślnie 2 min), a od ostatniej przerwy minęło co najmniej 10 minut pracy.",
    "Wynik: zaproponuj przerwę teraz (nie odkłada, tylko podpowiada).":
        "Wynik: zaproponuj przerwę teraz (nie odracza, tylko podpowiada).",
    "W godzinach obiadu przerwy nie są potrzebne: i tak odchodzisz od komputera. Traktuje tę godzinę jak naturalną przerwę. Godziny zmienisz w edytorze skryptu.":
        "W godzinach obiadu przerwy nie są potrzebne: i tak odchodzisz od komputera. Traktuje tę godzinę jak naturalną przerwę. Godziny zmienisz w edytorze skryptu.",
    "Zalecane: traktuj jako naturalną przerwę.": "Zalecane: traktuj jako naturalną przerwę.",
    "20-20-20": "20-20-20",
    "Co 20 min: 20 s patrzenia w dal. Co trzecia przerwa (≈ 1 h) to 5 minut ruchu.":
        "Co 20 min: 20 s patrzenia w dal. Co trzecia przerwa (≈ 1 h) to 5 minut ruchu.",
    "AOA / Harvard Health / Kaur 2022 (konsensus; pojedyncze 20 s bywa niewystarczające)":
        "AOA / Harvard Health / Kaur 2022 (konsensus; pojedyncze 20 s bywa niewystarczające)",
    "Częste mikroprzerwy": "Częste mikroprzerwy",
    "Co 10 min: 30 s od ekranu. Dla intensywnej pracy wzrokowej; co trzecia przerwa dłuższa.":
        "Co 10 min: 30 s od ekranu. Dla intensywnej pracy wzrokowej; co trzecia przerwa dłuższa.",
    "Redondo i in. 2025 (24 osoby, 40 min czytania: przerwy co 10 min zmniejszały podrażnienie oczu)":
        "Redondo i in. 2025 (24 osoby, 40 min czytania: przerwy co 10 min zmniejszały podrażnienie oczu)",
    "5 min po 30 min": "5 min po 30 min",
    "Co 30 min: 5 minut przerwy; co czwarta to 15 minut.":
        "Co 30 min: 5 minut przerwy; co czwarta to 15 minut.",
    "Dyrek i in. 2024, przegląd (Eur. J. Clin. Exp. Med.)":
        "Dyrek i in. 2024, przegląd (Eur. J. Clin. Exp. Med.)",
    "Przepisy BHP: 5 min po godzinie": "Przepisy BHP: 5 min po godzinie",
    "Po godzinie nieprzerwanej pracy przy monitorze minimum 5 minut przerwy.":
        "Po godzinie nieprzerwanej pracy przy monitorze minimum 5 minut przerwy.",
    "Polskie przepisy o stanowiskach z monitorami (za CIOP-PIB, Kamińska 2016)":
        "Polskie przepisy o stanowiskach z monitorami (za CIOP-PIB, Kamińska 2016)",
    "Zrównoważony (domyślny)": "Zrównoważony (domyślny)",
    "45 min pracy, 5 min przerwy, co czwarta 15 min.": "45 min pracy, 5 min przerwy, co czwarta 15 min.",
    "Ustawienia domyślne Intermezzo": "Ustawienia domyślne Intermezzo",
    "Aplikacja z przodu": "Aplikacja z przodu",
    "Aplikacja otwarta": "Aplikacja otwarta",
    "Kalendarz (tekst w wydarzeniu)": "Kalendarz (tekst w wydarzeniu)",
    "Pełny ekran aktywny": "Pełny ekran aktywny",
    "Wygaszacz ekranu": "Wygaszacz ekranu",
    "Ekran uśpiony": "Ekran uśpiony",
    "Tryb Skupienia (Focus)": "Tryb Skupienia",
    "Spotkanie online (video)": "Spotkanie online (wideo)",
    "Odtwarzanie wideo": "Odtwarzanie wideo",
    "Skrypt (AppleScript)": "Skrypt (AppleScript)",
    "Automatycznie pomiń": "Automatycznie pomiń",
    "Odrocz": "Odrocz",
    "Ignoruj naturalną pauzę": "Ignoruj naturalną przerwę",
    "Traktuj jako naturalną pauzę": "Traktuj jako naturalną przerwę",
    "Zaproponuj przerwę teraz": "Zaproponuj przerwę teraz",
    "Słonecznie, ale mroźno — postój chwilę przy oknie i popatrz w dal.":
        "Słonecznie, ale mroźno — postój chwilę przy oknie i popatrz w dal.",
    "Słonecznie (UV %lld) — wyjdź na 5 minut na zewnątrz i popatrz w dal.":
        "Słonecznie (UV %lld) — wyjdź na 5 minut na zewnątrz i popatrz w dal.",
    "Ładna pogoda — podejdź do okna i popatrz na horyzont przez 20 sekund.":
        "Ładna pogoda — podejdź do okna i popatrz na horyzont przez 20 sekund.",
    "Za oknem deszcz — rozciągnij kark i ramiona w pomieszczeniu.":
        "Za oknem deszcz — rozciągnij kark i ramiona w pomieszczeniu.",
    "Pada śnieg — wstań i weź kilka głębokich oddechów przy oknie.":
        "Pada śnieg — wstań i weź kilka głębokich oddechów przy oknie.",
    "Mgła za oknem — daj oczom odpocząć, zamknij je na 20 sekund.":
        "Mgła za oknem — daj oczom odpocząć, zamknij je na 20 sekund.",
}
