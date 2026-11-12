# Light pane (screen colour by the time of day). English.
# Key = the literal in the Swift source; every key here must also be in ../pl/light.py.
STRINGS = {
    "Dostosowuj barwę ekranu do pory dnia":
        "Adjust the screen colour to the time of day",
    "Wieczorem ciepła barwa zmniejsza ilość światła krótkofalowego (ok. 460–480 nm), które najsilniej hamuje melatoninę i przesuwa zegar dobowy. Badania wskazują ten kierunek, ale nie podają jednej „właściwej” temperatury, a równie ważna jest jasność ekranu i pokoju. Profile poniżej to rozsądne kompromisy, nie zalecenie lekarskie.":
        "In the evening a warm colour reduces the short-wavelength light (about 460–480 nm) that suppresses melatonin the most and shifts the body clock. Research points in this direction but does not give one “right” temperature, and the brightness of the screen and the room matters just as much. The profiles below are reasonable compromises, not medical advice.",
    "Wyłącz Night Shift i True Tone w Ustawieniach systemowych → Ekrany, bo nakładają się na tę funkcję. Ekrany przez DisplayLink, AirPlay i część Sidecar nie obsługują zmiany barwy, a treści HDR mogą ją częściowo omijać. Po zamknięciu aplikacji kolory wracają same; awaryjnie: Intermezzo --reset-light albo adres intermezzo://light/off.":
        "Turn off Night Shift and True Tone in System Settings → Displays, because they stack on top of this feature. Screens connected through DisplayLink, AirPlay and some Sidecar setups do not support colour changes, and HDR content may partly bypass them. The colours return by themselves when the app quits; in an emergency use Intermezzo --reset-light or the address intermezzo://light/off.",
    "Bez zmiany barwy: %@":
        "No colour change: %@",
    "Barwa":
        "Colour",
    "Pora":
        "Time of day",
    "Wieczór po zachodzie":
        "Evening after sunset",
    "Pora snu":
        "Bedtime",
    "Zachód słońca":
        "Sunset",
    "Wschód słońca":
        "Sunrise",
    "Wstrzymane do %@":
        "Paused until %@",
    "Podgląd doby (12 s)":
        "Preview the day (12 s)",
    "Zatrzymaj podgląd":
        "Stop the preview",
    "Harmonogram":
        "Schedule",
    "Profil":
        "Profile",
    "Zalecane":
        "Recommended",
    "Klasyczne":
        "Classic",
    "Daleko od równika":
        "Far from the equator",
    "Praca do późna":
        "Working late",
    "Wstaję o":
        "I wake up at",
    "Dzień 6500 K, po zachodzie 3400 K, przed snem do 1900 K. Ocieplanie zaczyna się 2 godziny przed porą snu.":
        "Day 6500 K, after sunset 3400 K, before bed down to 1900 K. Warming up starts 2 hours before bedtime.",
    "Dzień 6500 K i 3400 K wieczorem, bez dalszego ocieplania przed snem.":
        "Day 6500 K and 3400 K in the evening, with no further warming before bed.",
    "Dla wysokich szerokości geograficznych: długi zmierzch, łagodniejsze i dłuższe przejście, 2300 K przed snem.":
        "For high latitudes: a long twilight, a gentler and longer transition, 2300 K before bed.",
    "Pora snu przesunięta o 2,5 godziny: dłuższy wieczór, 2300 K przed snem.":
        "Bedtime moved by 2.5 hours: a longer evening, 2300 K before bed.",
    "Lokalizacja":
        "Location",
    "Źródło":
        "Source",
    "Współrzędne":
        "Coordinates",
    "Wpisz szerokość i długość oddzielone przecinkiem, np. 52.4, 22":
        "Enter the latitude and longitude separated by a comma, e.g. 52.4, 22",
    "To jedna pozycja dla Światła (wschód i zachód słońca), pogody na ekranie przerwy i słońca na jego obrazie. Najpierw liczą się wpisane współrzędne, potem lokalizacja Maca, na końcu przybliżone miejsce ze strefy czasowej. Wschód i zachód liczy lokalnie, bez internetu. Miejsce pracy dla strefy pracy ustawiasz osobno w Ogólne.":
        "This is the one position for Light (sunrise and sunset), the weather on the break screen and the sun in its picture. The place you type in comes first, then the Mac's own position, then the city of the time zone. Sunrise and sunset are computed locally, without the internet. The work place of the work zone is set separately in General.",
    "Uwzględniaj zachmurzenie":
        "Take cloud cover into account",
    "Pochmurne popołudnie ściemnia się wcześniej. Korzysta z tej samej anonimowej pogody co ekran przerwy (Open-Meteo), bez dodatkowych danych.":
        "A cloudy afternoon gets dark earlier. It uses the same anonymous weather as the break screen (Open-Meteo), with no extra data.",
    "Przełączenie (włączenie Światła, pełny ekran): %lld s":
        "Switch (Light turning on, full screen): %lld s",
    "Wykres barwy ekranu w ciągu doby":
        "Chart of the screen colour over the day",
    "wpisana ręcznie":
        "typed in",
    "z lokalizacji Maca":
        "from the Mac's location",
    "przybliżona, ze strefy czasowej %@":
        "approximate, from the time zone %@",
    "nieznana (wpisz współrzędne)":
        "unknown (enter coordinates)",
    "Światło":
        "Light",
    "Barwa ekranu według pory dnia i godziny snu":
        "Screen colour by the time of day and bedtime",
    "Włącza dopasowanie barwy ekranu do pory dnia":
        "Turns on adjusting the screen colour to the time of day",
    "Wyłącza dopasowanie barwy i przywraca kolory systemu (awaryjne wyłączenie)":
        "Turns the colour adjustment off and restores the system colours (the emergency switch)",
    "Wstrzymuje zmianę barwy na podany czas; bez czasu na godzinę":
        "Pauses the colour change for the given time; without a time, for an hour",
    "Światło: wyłącz na godzinę":
        "Light: turn off for an hour",
    "Światło: wznów":
        "Light: resume",
    "Wyjątki":
        "Exceptions",
    "Nie zmieniaj barw w aplikacjach pełnoekranowych":
        "Don't change colours in full-screen apps",
    "Dotyczy tylko tego monitora, na którym okno zajmuje cały ekran (film, gra, prezentacja). Pozostałe monitory zostają ocieplone.":
        "This applies only to the monitor on which the window fills the whole screen (a film, a game, a presentation). The other monitors stay warmed.",
    "Aplikacje bez zmiany barw":
        "Apps without colour change",
    "Gdy aplikacja z listy jest aktywnym oknem, jej monitor pokazuje normalne kolory, np. przy obróbce zdjęć i wideo. Nazwy oddzielaj przecinkami.":
        "While an app from the list is the active window, its monitor shows normal colours, e.g. when editing photos and video. Separate the names with commas.",
    "na godzinę":
        "for an hour",
    "do wschodu słońca":
        "until sunrise",
    "Połączenie":
        "Connection",
    "Przyciemniaj monitory wieczorem (sprzętowo)":
        "Dim the monitors in the evening (hardware)",
    "Przyciemnij maksymalnie o %lld%%":
        "Dim by at most %lld%%",
    "Wyłącz True Tone na czas działania Światła":
        "Turn True Tone off while Light is running",
    "Wymaga włączonego w BetterDisplay dostępu przez CLI i powiadomienia (Ustawienia → Aplikacja → Integracja). Jasność zmienia się sprzętowo (DDC), razem z ocieplaniem, a po wyłączeniu Światła wraca do pierwotnej. Gdy sam zmienisz jasność, aplikacja przestaje jej ruszać do końca wieczoru. Wyłączanie True Tone wymaga BetterDisplay Pro.":
        "Requires CLI and notification access to be enabled in BetterDisplay (Settings → Application → Integration). The brightness changes in hardware (DDC) along with the warming and returns to the original when Light is turned off. When you change the brightness yourself, the app stops touching it until the end of the evening. Turning True Tone off requires BetterDisplay Pro.",
    "działa, ekranów: %lld":
        "working, displays: %lld",
    "BetterDisplay nie jest uruchomiony":
        "BetterDisplay is not running",
    "brak odpowiedzi (włącz integrację w BetterDisplay)":
        "no answer (turn the integration on in BetterDisplay)",
    "nie zainstalowany":
        "not installed",
    "BetterDisplay nie wyłączył True Tone (ta funkcja wymaga wersji Pro).":
        "BetterDisplay did not turn True Tone off (this feature needs the Pro version).",
    "BetterDisplay":
        "BetterDisplay",
    "Światło w pokoju":
        "Light in the room",
    "Uwzględniaj jasność pokoju z czujnika w Macu":
        "Use the room's brightness from the Mac's sensor",
    "%lld lx":
        "%lld lx",
    "brak odczytu":
        "no reading",
    "Klapa zamknięta: czujnik nie widzi pokoju, działa sam harmonogram.":
        "Lid closed: the sensor cannot see the room, the schedule alone is used.",
    "Ten Mac nie udostępnia czujnika światła: działa sam harmonogram.":
        "This Mac does not provide a light sensor: the schedule alone is used.",
    "Nie wiem":
        "I don't know",
    "Ciepłe (ok. 2700 K)":
        "Warm (about 2700 K)",
    "Neutralne (ok. 4000 K)":
        "Neutral (about 4000 K)",
    "Zimne (ok. 5500 K)":
        "Cool (about 5500 K)",
    "W jasnym pokoju ocieplanie ekranu jest słabsze, a przyciemnianie przez BetterDisplay mniejsze; w ciemnym działa w pełni. Czujnik jest tylko w MacBooku, odczyt idzie przez prywatny interfejs macOS (może przestać działać po aktualizacji) i znika przy zamkniętej klapie, wtedy działa sam harmonogram. Mac nie mierzy barwy światła, więc kolor lamp wybierasz ręcznie: wieczorem ekran nie będzie wtedy dużo zimniejszy niż lampy.":
        "In a bright room the screen warming is weaker and the BetterDisplay dimming smaller; in a dark one it works in full. The sensor exists only in a MacBook, the reading goes through a private macOS interface (it may stop working after an update) and disappears with the lid closed, when the schedule alone is used. The Mac does not measure the colour of light, so you choose the lamp colour by hand: in the evening the screen will then not be much cooler than the lamps.",
    "Dodaj gotowy zestaw…":
        "Add a ready-made set…",
    "Edytory zdjęć, wideo i grafiki":
        "Photo, video and graphics editors",
    "Odtwarzacze wideo":
        "Video players",
    "Gry i launchery":
        "Games and launchers",
    "Rozłączaj grupę ekranów na czas wyjątku":
        "Switch the display group off during an exception",
    "Grupa BetterDisplay (np. dwa takie same monitory) trzyma ich jasność razem. Gdy jeden monitor ma zostać nieprzyciemniony (pełny ekran, aplikacja z listy wyjątków), grupa jest wyłączana, a po wieczorze włączana z powrotem.":
        "A BetterDisplay group (e.g. two identical monitors) keeps their brightness together. When one monitor is to stay undimmed (a full-screen app, an app from the exceptions list), the group is switched off and switched on again after the evening.",
    "Własne (wg zegara)":
        "Custom (by the clock)",
    "Własne (wg Słońca)":
        "Custom (by the Sun)",
    "Narysowany dzień: barwa o danej godzinie jest dokładnie taka, jak na wykresie, niezależnie od Słońca.":
        "A drawn day: the colour at a given hour is exactly as on the chart, whatever the Sun does.",
    "Narysowany dzień, którego siłę kontrolują wschód i zachód słońca, zachmurzenie i światło w pokoju: w dzień ekran jest neutralny, a po zmroku płynnie przechodzi do koloru z wykresu. Wykres mówi, jak ciepło może być o danej godzinie.":
        "A drawn day whose strength is controlled by sunrise and sunset, cloud cover and the light in the room: by day the screen is neutral and after dusk it moves smoothly to the colour on the chart. The chart says how warm it may get at a given hour.",
    "Przeciągaj po wykresie jak po equalizerze: każdy słupek to jedna godzina doby, a wysokość to barwa (wyżej chłodniej, niżej cieplej). Między godzinami kolor płynnie przechodzi.":
        "Drag across the chart like on an equaliser: each bar is one hour of the day and its height is the colour (higher is cooler, lower is warmer). Between the hours the colour blends smoothly.",
    "Profil „Własne (wg zegara)” nie korzysta z czujnika: wybierz „Własne (wg Słońca)” albo gotowy profil.":
        "The “Custom (by the clock)” profile does not use the sensor: choose “Custom (by the Sun)” or a ready-made profile.",
    "Monitory":
        "Monitors",
    "Zapamiętane, niepodłączone":
        "Remembered, not connected",
    "Nowy monitor od razu dostaje ogólną krzywą. Takie same monitory mają wspólne ustawienia. Ustawienia są pamiętane tylko na tym Macu i wracają, gdy monitor zostanie podłączony ponownie.":
        "A new monitor gets the general curve straight away. Identical monitors share their settings. The settings are kept on this Mac only and come back when the monitor is connected again.",
    "bez zarządzania":
        "not managed",
    "kolor do %lld K":
        "colour down to %lld K",
    "przyciemnienie %lld%%":
        "dimming %lld%%",
    "ogólna krzywa":
        "general curve",
    "Nie zarządzaj tym monitorem (np. telewizorem)":
        "Don’t manage this monitor (e.g. a TV)",
    "Podgląd wieczoru":
        "Preview the evening",
    "Przywróć ogólne":
        "Back to general",
    "Własny limit koloru":
        "Own colour limit",
    "Najcieplejszy kolor: %lld K":
        "Warmest colour: %lld K",
    "Własne przyciemnienie":
        "Own dimming",
    "Przyciemnianie sprzętowe jest wyłączone (sekcja BetterDisplay), więc ten wybór na razie nic nie zmienia.":
        "Hardware dimming is switched off (BetterDisplay section), so this choice changes nothing for now.",
    "Wykres w sekcji „Teraz” zaczęto od profilu „%@”. Możesz go dalej poprawiać palcem po wykresie.":
        "The chart in the “Now” section was started from the “%@” profile. You can keep adjusting it by dragging across the chart.",
    "Wstrzymaj zmianę barwy…":
        "Pause the colour change…",
    "Wykres barwy: zacznij od profilu…":
        "Colour chart: start from a profile…",
    "Zastępuje wykres barwy z sekcji „Teraz” (barwa godzina po godzinie) wartościami wybranego profilu. Rzeczy, które narysowałeś na wykresie, przepadną.":
        "Replaces the colour chart in the “Now” section (the colour hour by hour) with the values of the chosen profile. Anything you drew on the chart is lost.",
    "Wybierz na mapie…":
        "Pick on the map…",
    "Wybierz miejsce na mapie":
        "Pick a place on the map",
    "Kliknij mapę, żeby postawić pinezkę, i przeciągnij ją, żeby ją przesunąć. Przeciągnięcie mapy przesuwa mapę, a kółko myszy, szczypanie i przyciski + i − ją przybliżają. Cień pokazuje, gdzie teraz jest dzień, zmierzch i noc.":
        "Click the map to drop the pin and drag the pin to move it. Dragging the map moves the map, and the mouse wheel, pinching and the + and − buttons zoom it. The shading shows where it is day, twilight and night right now.",
    "Mapa jest niedostępna, ale współrzędne możesz wpisać ręcznie.":
        "The map is unavailable, but you can type the coordinates by hand.",
    "Nie wybrano jeszcze miejsca.":
        "No place chosen yet.",
    "Skala mapy: ok. %@ km na punkt ekranu":
        "Map scale: about %@ km per screen point",
    "Brak wschodu lub zachodu Słońca w tym miejscu (dzień lub noc polarna).":
        "The Sun neither rises nor sets here (polar day or night).",
    "Wschód %@, zachód %@ (czas Maca).":
        "Sunrise %@, sunset %@ (the Mac’s time).",
    "Użyj tego miejsca":
        "Use this place",
    "Przybliż":
        "Zoom in",
    "Oddal":
        "Zoom out",
    "Dane mapy: Natural Earth (domena publiczna); nazwy miast: GeoNames, licencja CC BY 4.0.":
        "Map data: Natural Earth (public domain); city names: GeoNames, licence CC BY 4.0.",
    "Barwa podąża za porą dnia powoli, nie szybciej niż ustawione K na minutę (np. 100 K zajmie wtedy kilka minut). Włączenie Światła i okno pełnoekranowe albo aplikacja wyjątek przełączają kolor w podanym czasie, ale dopiero po kilku sekundach, żeby krótkie przełączenia nie migały.":
        "The colour changes gently: it starts slowly, speeds up and slows down, and a time shorter than 8 s is not used. A full-screen window or an excluded app takes effect only after a few seconds, so brief switches do not flash the colour.",
    "Tempo zmiany barwy: najwyżej %lld K na minutę":
        "Colour change speed: at most %lld K per minute",
    "Szczegółowy dziennik Światła (do szukania przyczyny migania)":
        "Detailed Light log (to find what makes the screen blink)",
    "Zapisuje w dzienniku każdą zmianę celu, przejście, zapis koloru na ekran i akcję BetterDisplay, z powodem i czasem co do milisekundy. Włącz, gdy ekran mignie, i wyślij fragment pliku z tą chwilą.":
        "Logs every goal change, fade, screen colour write and BetterDisplay action, with the reason and the time to the millisecond. Turn it on, and when the screen blinks send the part of the file from that moment.",
    "Pokaż plik dziennika":
        "Show the log file",
    "Jasność ekranu":
        "Screen brightness",
    "Dostosowuj jasność ekranu do pory dnia i światła w pokoju":
        "Adjust the screen brightness to the time of day and the room's light",
    "Jasność = wartość z wykresu godzin × mnożnik z wykresu światła w pokoju, nie mniej niż 5%. Bez odczytu czujnika (brak czujnika, zamknięta klapa, czujnik wyłączony) liczy się sam wykres godzin. Gdy sam zmienisz jasność, korektor odpuszcza na godzinę; po wyłączeniu, wstrzymaniu Światła albo zamknięciu aplikacji jasność wraca do pierwotnej.":
        "Brightness = the value from the hours chart × the multiplier from the room light chart, never below 5%. Without a sensor reading (no sensor, lid closed, sensor turned off) the hours chart alone counts. When you change the brightness yourself, the equaliser backs off for an hour; when it is turned off, Light is paused or the app quits, the brightness goes back to what it was.",
    "Każdy słupek to jedna godzina doby, a wysokość to jasność ekranu (100% to pełna). Przeciągaj jak po wykresie barwy powyżej.":
        "Each bar is one hour of the day and its height is the screen brightness (100% is full). Drag across it like the colour chart above.",
    "Mnożnik dla światła w pokoju: w ciemnym pokoju ekran jest ciemniejszy, w jasnym jaśniejszy (powyżej 100% podnosi przyciemnioną godzinę, ale nigdy ponad pełną jasność). Między słupkami wartość przechodzi płynnie na skali logarytmicznej, a pionowa kreska pokazuje bieżący odczyt czujnika.":
        "Multiplier for the room's light: in a dark room the screen is darker, in a bright one brighter (above 100% it lifts a dimmed hour, but never past full brightness). Between the bars the value blends smoothly on a logarithmic scale, and the vertical line shows the sensor's current reading.",
    "Wykres jasności ekranu w ciągu doby":
        "Chart of the screen brightness over the day",
    "Wykres mnożnika jasności według światła w pokoju":
        "Chart of the brightness multiplier by the room's light",
    "Włącz czujnik światła w pokoju":
        "Turn on the room light sensor",
    "Korektor jasności zastępuje teraz przyciemnianie monitorów wieczorem z sekcji BetterDisplay.":
        "The brightness equaliser now replaces the evening monitor dimming from the BetterDisplay section.",
    "Wbudowany ekran zmieniam przez prywatny interfejs macOS (może przestać działać po aktualizacji), zewnętrzne monitory przez BetterDisplay. Bez automatu wyłącz „Automatycznie dostosowuj jasność” w Ustawieniach systemowych → Ekrany, bo macOS będzie poprawiał jasność po swojemu. Każdy ekran, także wbudowany, ma własne ustawienia jasności w sekcji Monitory (źródło, mnożnik, limity, nity); monitory „bez zarządzania” i okna-wyjątki zostają przy swojej jasności. Profil „Własne (wg zegara)” nie zmienia barwy według czujnika, ale korektor jasności korzysta z niego, gdy czujnik jest włączony.":
        "The built-in screen is changed through a private macOS interface (it may stop working after an update), external monitors through BetterDisplay. Without the automatic mode, turn off “Automatically adjust brightness” in System Settings → Displays, or macOS will correct the brightness its own way. Every screen, the built-in one too, has its own brightness settings in the Monitors section (source, multiplier, limits, nits); unmanaged monitors and excluded windows keep their own brightness. The “Custom (by the clock)” profile does not change the colour by the sensor, but the brightness equaliser uses it when the sensor is on.",
    "godzina %lld%% × pokój %lld%%":
        "hour %lld%% × room %lld%%",
    "godzina %lld%%, bez czujnika":
        "hour %lld%%, no sensor",
    "nie działa (Światło wyłączone lub wstrzymane)":
        "not running (Light is off or paused)",
    "Włączony korektor jasności (sekcja „Jasność ekranu”) zastępuje to przyciemnianie: jasność monitorów ustawia wtedy korektor.":
        "The brightness equaliser (the “Screen brightness” section) is on and replaces this dimming: the equaliser sets the monitors' brightness.",
    "Jasność wbudowanego ekranu zmieniono ręcznie: wracam do korektora po godzinie.":
        "The built-in screen's brightness was changed by hand: the equaliser takes over again in an hour.",
    "Ten Mac nie pozwala zmieniać jasności wbudowanego ekranu: działa tylko na monitorach przez BetterDisplay.":
        "This Mac does not allow changing the built-in screen's brightness: it works only on monitors through BetterDisplay.",
    "Wbudowany ekran jest wyłączony (np. zamknięta klapa): jasność zmieniam tylko na monitorach przez BetterDisplay.":
        "The built-in screen is off (e.g. the lid is closed): only the monitors' brightness is changed, through BetterDisplay.",
    "Profil „Własne (wg zegara)” nie zmienia barwy według czujnika: odczyt służy tylko korektorowi jasności.":
        "The “Custom (by the clock)” profile does not change the colour by the sensor: the reading is used only by the brightness equaliser.",
    "%lld nit":
        "%lld nits",
    "%lld nit z %lld":
        "%lld nits of %lld",
    "Automat: monitory podążają za wbudowanym ekranem (nity)":
        "Automatic: monitors follow the built-in screen (nits)",
    "Automatycznie (korektor albo macOS w automacie)":
        "Automatic (equaliser, or macOS in the automatic mode)",
    "Automatycznie (korektor albo nity w automacie)":
        "Automatic (equaliser, or nits in the automatic mode)",
    "Jasność":
        "Brightness",
    "Jasność monitora zmieniam przez BetterDisplay, którego tu nie ma: te ustawienia na razie nic nie zmieniają.":
        "A monitor's brightness is changed through BetterDisplay, which is not installed here: these settings do nothing for now.",
    "Klapa zamknięta: brak odniesienia dla automatu, monitory wracają do korektora.":
        "Lid closed: the automatic mode has no reference, the monitors go back to the equaliser.",
    "Korektor (wykresy godzin i pokoju)":
        "Equaliser (hours and room charts)",
    "Maksymalnie %lld nit":
        "At most %lld nits",
    "Monitor nie podaje maksymalnej jasności: przyjmuję %lld nit. Wpisz wartość z jego specyfikacji, żeby automat był dokładniejszy.":
        "The monitor does not report its maximum brightness: %lld nits is assumed. Enter the value from its specification to make the automatic mode more accurate.",
    "Monitor podaje w EDID: %lld nit.":
        "The monitor reports in its EDID: %lld nits.",
    "Najciemniej: %lld%%":
        "Darkest: %lld%%",
    "Najjaśniej: %lld%%":
        "Brightest: %lld%%",
    "Nie mogę odczytać jasności wbudowanego ekranu: monitory używają korektora.":
        "The built-in screen's brightness cannot be read: the monitors use the equaliser.",
    "Nie zmieniaj jasności":
        "Do not change the brightness",
    "Odczyt z macOS: %lld nit (maks. SDR; do %lld przy mocnym świetle).":
        "Read from macOS: %lld nits (max SDR; up to %lld in bright light).",
    "Odczyt z macOS: %lld nit (maks. SDR).":
        "Read from macOS: %lld nits (max SDR).",
    "Brak odczytu z macOS: przyjmuję %lld nit.":
        "No reading from macOS: %lld nits is assumed.",
    "Ten Mac nie ma wbudowanego ekranu: automat (nity) jest niedostępny, monitory używają korektora.":
        "This Mac has no built-in screen: the automatic (nits) mode is not available, the monitors use the equaliser.",
    "W automacie jasność tego ekranu ustawia macOS; mnożnik i limity działają, gdy automat jest wyłączony.":
        "In the automatic mode macOS sets this screen's brightness; the multiplier and limits apply when the automatic mode is off.",
    "W automacie jasność wbudowanego ekranu ustawia macOS (włącz „Automatycznie dostosowuj jasność” w Ustawieniach systemowych → Ekrany), a aplikacja tylko ją odczytuje i przelicza na nity. Monitor dostaje jasność = nity wbudowanego ÷ maksymalne nity monitora, z jego własnym mnożnikiem i limitami (Monitory poniżej); sprawdzane co ok. 30 s. Maksimum monitora pochodzi z EDID, z wpisu ręcznego albo przyjmuję 350 nitów. Przy zamkniętej klapie albo bez odczytu monitory wracają do korektora (wykresy poniżej). Monitor z wyborem „Korektor” zostaje przy wykresach.":
        "In the automatic mode macOS sets the built-in screen's brightness (turn on “Automatically adjust brightness” in System Settings → Displays); the app only reads it and converts it to nits. A monitor gets brightness = the built-in screen's nits ÷ the monitor's maximum nits, with its own multiplier and limits (Monitors below); checked about every 30 s. The monitor's maximum comes from its EDID, from a typed value, or 350 nits is assumed. With the lid closed or without a reading the monitors go back to the equaliser (charts below). A monitor set to “Equaliser” stays with the charts.",
    "Wbudowany ekran teraz":
        "Built-in screen now",
    "Własna maksymalna jasność (nity)":
        "Own maximum brightness (nits)",
    "Własny mnożnik: %lld%%":
        "Own multiplier: %lld%%",
    "jasność %lld%% · korektor":
        "brightness %lld%% · equaliser",
    "jasność %lld%% · za wbudowanym, %lld nit":
        "brightness %lld%% · follows built-in, %lld nits",
    "jasność bez zmian":
        "brightness unchanged",
    "jasność bez zmian (wyjątek)":
        "brightness unchanged (exception)",
    "jasność: macOS (automat)":
        "brightness: macOS (automatic)",
    "własna jasność":
        "own brightness",
}
