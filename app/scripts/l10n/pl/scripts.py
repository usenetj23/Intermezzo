# Script editor and the user's own rule scripts. Polish.
STRINGS = {
    "Zainstaluj gotowe reguły-skrypty albo utwórz własne. Skrypty trafiają do Biblioteka → Application Scripts → com.automit.Intermezzo → Rules i zostają dodane jako reguła „Odrocz”. Wynik reguły zmienisz na stronie Reguły, a nastawy skryptu (np. listę aplikacji albo godziny) w edytorze.":
        "Zainstaluj gotowe reguły-skrypty albo utwórz własne. Skrypty trafiają do Biblioteka → Application Scripts → com.automit.Intermezzo → Rules i zostają dodane jako reguła „Odrocz”. Wynik reguły zmienisz na stronie Reguły, a nastawy skryptu (np. listę aplikacji albo godziny) w edytorze.",
    "Nowy skrypt…":
        "Nowy skrypt…",
    "Własne skrypty":
        "Własne skrypty",
    "Edytuj…":
        "Edytuj…",
    "Usuń":
        "Usuń",
    "Galeria":
        "Galeria",
    "Usunąć skrypt?":
        "Usunąć skrypt?",
    "Usuń skrypt i jego regułę":
        "Usuń skrypt i jego regułę",
    "„%@” zniknie z dysku razem z regułą, która go uruchamia.":
        "„%@” zniknie z dysku razem z regułą, która go uruchamia.",
    "Nazwa":
        "Nazwa",
    "Szablon":
        "Szablon",
    "Kod AppleScript":
        "Kod AppleScript",
    "Skrypt odpowiada na pytanie „czy warunek jest teraz spełniony?”: zwraca true albo false. Gdy zwróci true, reguła robi to, co ustawisz na stronie Reguły.":
        "Skrypt odpowiada na pytanie „czy warunek jest teraz spełniony?”: zwraca true albo false. Gdy zwróci true, reguła robi to, co ustawisz na stronie Reguły.",
    "Nastawy":
        "Nastawy",
    "Zainstalowana wersja jest starsza i nie ma nastaw. Kliknij „Przywróć wersję z galerii”.":
        "Zainstalowana wersja jest starsza i nie ma nastaw. Kliknij „Przywróć wersję z galerii”.",
    "Ten skrypt nie ma nastaw. Dodaj na początku kodu linię „property nazwa : wartość”, a pojawi się tutaj jako pole.":
        "Ten skrypt nie ma nastaw. Dodaj na początku kodu linię „property nazwa : wartość”, a pojawi się tutaj jako pole.",
    "Sprawdź":
        "Sprawdź",
    "Trwa test…":
        "Trwa test…",
    "Testuj teraz":
        "Testuj teraz",
    "Przywróć wersję z galerii":
        "Przywróć wersję z galerii",
    "Utwórz":
        "Utwórz",
    "Mój skrypt":
        "Mój skrypt",
    "Nie udało się odczytać skryptu.":
        "Nie udało się odczytać skryptu.",
    "Skrypt jest poprawny.":
        "Skrypt jest poprawny.",
    "Błąd w skrypcie: %@":
        "Błąd w skrypcie: %@",
    "Nie udało się zapisać pliku testowego.":
        "Nie udało się zapisać pliku testowego.",
    "Skrypt nie zadziałał (błąd uruchomienia, brak uprawnień albo przekroczony czas).":
        "Skrypt nie zadziałał (błąd uruchomienia, brak uprawnień albo przekroczony czas).",
    "Warunek jest teraz spełniony: reguła by zadziałała.":
        "Warunek jest teraz spełniony: reguła by zadziałała.",
    "Warunek nie jest teraz spełniony: reguła nic nie zrobi.":
        "Warunek nie jest teraz spełniony: reguła nic nie zrobi.",
    "Zapis nie powiódł się.":
        "Zapis nie powiódł się.",
    "Oddzielaj przecinkami.":
        "Oddzielaj przecinkami.",
    "Aplikacje":
        "Aplikacje",
    "Aplikacje do rozmów i pulpitu zdalnego":
        "Aplikacje do rozmów i pulpitu zdalnego",
    "Procesy gier":
        "Procesy gier",
    "Narzędzia":
        "Narzędzia",
    "Przeglądarki":
        "Przeglądarki",
    "Tytuł okna zawiera":
        "Tytuł okna zawiera",
    "Terminale":
        "Terminale",
    "Procesy":
        "Procesy",
    "Od godziny":
        "Od godziny",
    "Do godziny":
        "Do godziny",
    "Aplikacja na pierwszym planie":
        "Aplikacja na pierwszym planie",
    "Tytuł okna zawiera tekst":
        "Tytuł okna zawiera tekst",
    "Działa proces":
        "Działa proces",
    "Przedział godzin":
        "Przedział godzin",
    "Pusty skrypt":
        "Pusty skrypt",
    "Odinstaluj":
        "Odinstaluj",
    "FaceTime otwarty i na pierwszym planie, albo ma aktywne okno rozmowy":
        "FaceTime otwarty i na pierwszym planie, albo ma aktywne okno rozmowy",
    "Wideokonferencja":
        "Wideokonferencja",
    "Czytanie dokumentu":
        "Czytanie dokumentu",
    "Prezentacja":
        "Prezentacja",
    "Zdalna sesja":
        "Zdalna sesja",
    "ktoś ogląda Twój ekran (usługa macOS działa tylko podczas połączenia)":
        "ktoś ogląda Twój ekran (usługa macOS działa tylko podczas połączenia)",
    "Nagrywanie ekranu":
        "Nagrywanie ekranu",
    "Spotkanie w przeglądarce":
        "Spotkanie w przeglądarce",
    "Rozmowa głosowa":
        "Rozmowa głosowa",
    "Sesja w terminalu":
        "Sesja w terminalu",
    "Praca twórcza":
        "Praca twórcza",
    "Gry spoza Steama":
        "Gry spoza Steama",
    "Duplikowanie ekranu":
        "Duplikowanie ekranu",
    "Długi build / render":
        "Długi build / render",
    "Pora obiadu":
        "Pora obiadu",
    "Zwróć true, gdy warunek jest spełniony (wtedy reguła działa), w przeciwnym razie false.":
        "Zwróć true, gdy warunek jest spełniony (wtedy reguła działa), w przeciwnym razie false.",
    "Nastawy: linie „property nazwa : wartość” na początku (lista tekstów, liczba, true/false, tekst).":
        "Nastawy: linie „property nazwa : wartość” na początku (lista tekstów, liczba, true/false, tekst).",
}
