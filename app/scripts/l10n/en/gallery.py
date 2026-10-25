# Script gallery, break presets, rule labels, weather tips. English.
# Key = the literal in the Swift source; every key here must also be in ../pl/gallery.py.
STRINGS = {
    "Wykrywa, gdy aktywnie prowadzisz lub odbierasz rozmowę FaceTime. Przerwa zostanie odroczona do końca spotkania.":
        "Detects when you are actively in a FaceTime call. The break is postponed until the meeting ends.",
    "Zalecane: odroczony lub pomijany automatycznie.": "Recommended: postpone or skip automatically.",
    "Sprawdza, czy któryś klient wideokonferencji ma otwarte aktywne okno. Nie pomija przerw tylko dlatego, że aplikacja działa w tle.":
        "Checks whether a video-call client has an active window open. It doesn't skip breaks just because the app runs in the background.",
    "Zalecane: odroczenie przerwy.": "Recommended: postpone the break.",
    "Gry Steam nie zawsze są wykrywalne jak zwykłe aplikacje. Ten skrypt sprawdza proces gry lub Big Picture. Przerwa w środku rajdu? Nigdy.":
        "Steam games aren't always detectable like ordinary apps. This script checks for the game process or Big Picture. A break in the middle of a raid? Never.",
    "Zalecane: pomijaj automatycznie podczas grania.": "Recommended: skip automatically while gaming.",
    "Podgląd/Skim/App Books na pierwszym planie: wpatrujesz się w ekran, ale nie ruszasz myszką — Intermezzo nie powinien traktować tego jako naturalnej przerwy, a przerwy oddelegować na po przeczytaniu rozdziału.":
        "Preview/Skim/Books in front: you stare at the screen without moving the mouse — Intermezzo shouldn't treat that as a natural break, and should postpone breaks until you finish the chapter.",
    "Wykrywa tryb slajdów Keynote lub PowerPointa — publiczność patrzy na Ciebie, nie na Twój nadgarstek. Przerwa poczeka do końca prezentacji.":
        "Detects Keynote or PowerPoint slideshow mode — the audience is looking at you, not at your wrist. The break waits until the presentation ends.",
    "Zalecane: pomijaj automatycznie.": "Recommended: skip automatically.",
    "TeamViewer, AnyDesk, Parsec, Jump Desktop, Windows App lub udostępnianie ekranu macOS na pierwszym planie. Przerwa nie wskoczy w środek sesji u klienta ani cudzej pomocy.":
        "TeamViewer, AnyDesk, Parsec, Jump Desktop, Windows App or macOS screen sharing in front. A break won't jump into a client's session or someone else's remote help.",
    "OBS, ScreenFlow, Loom, Screen Studio, CleanShot lub nagranie ekranu w QuickTime ma otwarte okno. Wykrywa narzędzie, nie sam fakt nagrywania, więc przy otwartym OBS bez nagrywania też zadziała.":
        "OBS, ScreenFlow, Loom, Screen Studio, CleanShot or QuickTime screen recording has a window open. It detects the tool, not the recording itself, so it also triggers with OBS open but not recording.",
    "Okno przeglądarki z tytułem spotkania: Google Meet, Microsoft Teams, Whereby, Jitsi, Webex lub Zoom w przeglądarce. Wideo w kartach nie jest wykrywane przez aplikacje desktopowe, dlatego osobna reguła. Wymaga uprawnienia Ułatwień dostępu.":
        "A browser window with a meeting title: Google Meet, Microsoft Teams, Whereby, Jitsi, Webex or Zoom in the browser. Video in tabs isn't detected by desktop-app rules, hence a separate rule. Requires the Accessibility permission.",
    "Okno huddle Slacka albo połączenie głosowe na Discordzie. Rozmowa jest wtedy ważniejsza niż przypomnienie o przerwie. Wymaga uprawnienia Ułatwień dostępu.":
        "A Slack huddle window or a Discord voice call. The conversation matters more than a break reminder then. Requires the Accessibility permission.",
    "Terminal na pierwszym planie, a w systemie działa żywy ssh, mosh, vim, nvim lub htop. Chroni długie sesje zdalne i edycję, której nie chcesz przerywać w pół zdania.":
        "Terminal in front with a live ssh, mosh, vim, nvim or htop running. It protects long remote sessions and editing you don't want to interrupt mid-sentence.",
    "Logic, GarageBand, Ableton, Pro Tools, Cubase, Reaper, Final Cut, Premiere, DaVinci Resolve lub Blender na pierwszym planie. Wejście w stan flow trudno odbudować po przerwie w środku nagrania lub renderu.":
        "Logic, GarageBand, Ableton, Pro Tools, Cubase, Reaper, Final Cut, Premiere, DaVinci Resolve or Blender in front. Flow is hard to rebuild after a break in the middle of a recording or render.",
    "Launchery i gry, które nie są Steamem: Epic, Battle.net, GOG Galaxy, Heroic, CrossOver, Whisky, RetroArch, Minecraft. Uzupełnia regułę „Gra Valve / Steam”.":
        "Launchers and games that aren't Steam: Epic, Battle.net, GOG Galaxy, Heroic, CrossOver, Whisky, RetroArch, Minecraft. Complements the “Valve / Steam game” rule.",
    "Gdy ekran jest powielony na projektorze lub telewizorze (Mirror: On), to prawie na pewno ktoś na niego patrzy. Przerwa na cały ekran na czyjejś prezentacji byłaby niezręczna.":
        "When the screen is mirrored to a projector or TV (Mirror: On), someone is almost certainly watching it. A full-screen break over someone's presentation would be awkward.",
    "Działa xcodebuild, swift-build, cargo, gradle, mvn, ninja, ffmpeg lub HandBrake. Podczas czekania i tak nie masz nic do roboty, więc Intermezzo zaproponuje przerwę — dopiero gdy zadanie trwa dłużej niż ustawiony czas (domyślnie 2 min), a od ostatniej przerwy minęło co najmniej 10 minut pracy.":
        "xcodebuild, swift-build, cargo, gradle, mvn, ninja, ffmpeg or HandBrake is running. You have nothing to do while waiting anyway, so Intermezzo suggests a break — only once the task has run longer than the set time (2 min by default) and at least 10 minutes of work have passed since your last break.",
    "Wynik: zaproponuj przerwę teraz (nie odkłada, tylko podpowiada).":
        "Outcome: suggest a break now (it doesn't postpone, only suggests).",
    "W godzinach obiadu przerwy nie są potrzebne: i tak odchodzisz od komputera. Traktuje tę godzinę jak naturalną przerwę. Godziny zmienisz w edytorze skryptu.":
        "Breaks aren't needed at lunchtime: you walk away from the computer anyway. It treats this hour as a natural break. Change the hours in the script editor.",
    "Zalecane: traktuj jako naturalną przerwę.": "Recommended: treat as a natural break.",
    "20-20-20": "20-20-20",
    "Co 20 min: 20 s patrzenia w dal. Co trzecia przerwa (≈ 1 h) to 5 minut ruchu.":
        "Every 20 min: 20 s of looking into the distance. Every third break (≈ 1 h) is 5 minutes of movement.",
    "AOA / Harvard Health / Kaur 2022 (konsensus; pojedyncze 20 s bywa niewystarczające)":
        "AOA / Harvard Health / Kaur 2022 (consensus; a single 20 s is sometimes not enough)",
    "Częste mikroprzerwy": "Frequent micro-breaks",
    "Co 10 min: 30 s od ekranu. Dla intensywnej pracy wzrokowej; co trzecia przerwa dłuższa.":
        "Every 10 min: 30 s away from the screen. For intensive visual work; every third break is longer.",
    "Redondo i in. 2025 (24 osoby, 40 min czytania: przerwy co 10 min zmniejszały podrażnienie oczu)":
        "Redondo et al. 2025 (24 people, 40 min of reading: breaks every 10 min reduced eye irritation)",
    "5 min po 30 min": "5 min after 30 min",
    "Co 30 min: 5 minut przerwy; co czwarta to 15 minut.":
        "Every 30 min: a 5-minute break; every fourth is 15 minutes.",
    "Dyrek i in. 2024, przegląd (Eur. J. Clin. Exp. Med.)":
        "Dyrek et al. 2024, review (Eur. J. Clin. Exp. Med.)",
    "Przepisy BHP: 5 min po godzinie": "Health and safety rules: 5 min per hour",
    "Po godzinie nieprzerwanej pracy przy monitorze minimum 5 minut przerwy.":
        "After an hour of uninterrupted work at a monitor, at least 5 minutes of break.",
    "Polskie przepisy o stanowiskach z monitorami (za CIOP-PIB, Kamińska 2016)":
        "Polish regulations on workstations with monitors (after CIOP-PIB, Kamińska 2016)",
    "Zrównoważony (domyślny)": "Balanced (default)",
    "45 min pracy, 5 min przerwy, co czwarta 15 min.": "45 min of work, 5 min breaks, every fourth 15 min.",
    "Ustawienia domyślne Intermezzo": "Intermezzo defaults",
    "Aplikacja z przodu": "Frontmost app",
    "Aplikacja otwarta": "App is running",
    "Kalendarz (tekst w wydarzeniu)": "Calendar (text in an event)",
    "Pełny ekran aktywny": "Full screen active",
    "Wygaszacz ekranu": "Screensaver",
    "Ekran uśpiony": "Display asleep",
    "Tryb Skupienia (Focus)": "Focus mode",
    "Spotkanie online (video)": "Online meeting (video)",
    "Odtwarzanie wideo": "Video playback",
    "Skrypt (AppleScript)": "Script (AppleScript)",
    "Automatycznie pomiń": "Skip automatically",
    "Odrocz": "Postpone",
    "Ignoruj naturalną pauzę": "Ignore natural break",
    "Traktuj jako naturalną pauzę": "Treat as a natural break",
    "Zaproponuj przerwę teraz": "Suggest a break now",
    "Słonecznie, ale mroźno — postój chwilę przy oknie i popatrz w dal.":
        "Sunny but freezing — stand by the window for a moment and look into the distance.",
    "Słonecznie (UV %lld) — wyjdź na 5 minut na zewnątrz i popatrz w dal.":
        "Sunny (UV %lld) — step outside for 5 minutes and look into the distance.",
    "Ładna pogoda — podejdź do okna i popatrz na horyzont przez 20 sekund.":
        "Nice weather — go to the window and look at the horizon for 20 seconds.",
    "Za oknem deszcz — rozciągnij kark i ramiona w pomieszczeniu.":
        "Rain outside — stretch your neck and shoulders indoors.",
    "Pada śnieg — wstań i weź kilka głębokich oddechów przy oknie.":
        "It's snowing — stand up and take a few deep breaths by the window.",
    "Mgła za oknem — daj oczom odpocząć, zamknij je na 20 sekund.":
        "Fog outside — rest your eyes, close them for 20 seconds.",
}
