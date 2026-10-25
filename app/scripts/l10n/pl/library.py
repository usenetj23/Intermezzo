# Library area: project sensors, permission messages, text-theme seed, Kit defaults and presets. Polish.
# Key = the literal in the Swift source; every key here must also be in ../en/library.py.
STRINGS = {
    # Project sensors
    "Name of the repository (a folder containing .git) or folder the frontmost Terminal or iTerm window is in. Needs Automation for Terminal/iTerm and System Events.":
        "Nazwa repozytorium (folderu z .git) lub folderu, w którym pracuje okno Terminala albo iTerma na wierzchu. Wymaga Automatyzacji dla Terminala/iTerma i System Events.",
    "Title of the frontmost window of the frontmost app. Needs Automation for System Events and Accessibility.":
        "Tytuł okna na wierzchu w aplikacji na pierwszym planie. Wymaga Automatyzacji dla System Events oraz uprawnienia Dostępności.",
    "Path of the folder shown in the frontmost Finder window. Needs Automation for System Events and Finder.":
        "Ścieżka folderu otwartego w oknie Findera na wierzchu. Wymaga Automatyzacji dla System Events i Findera.",
    "Prints text only.": "Tylko wypisuje tekst.",
    "All sensors (System Events; Terminal/iTerm or Finder for two of them).":
        "Wszystkie czujniki (System Events; dwa z nich także Terminal/iTerm lub Finder).",
    "Front window: document name.": "Okno na wierzchu: nazwa dokumentu.",
    "Running…": "Trwa…",
    "Test sensor": "Testuj czujnik",
    "Select": "Wybierz",
    "Selected": "Wybrany",
    "Not run: the selected sensor is missing or invalid, or one is already running.":
        "Nie uruchomiono: wybrany czujnik nie istnieje lub jest nieprawidłowy albo inny czujnik już działa.",
    "The sensor failed or took longer than %lld s and was stopped.":
        "Czujnik zgłosił błąd albo działał dłużej niż %lld s i został zatrzymany.",
    "The sensor ran and printed nothing.": "Czujnik zadziałał, ale nic nie wypisał.",
    # Script gallery
    "Instalacja nie powiodła się.": "Instalacja nie powiodła się.",
    # Permissions
    "Decisions reset in macOS. Intermezzo sees the new state only after a restart: click Restart, then Allow… on each row. Location and notifications can only be changed in System Settings.":
        "Zgody zresetowane w macOS. Intermezzo zobaczy nowy stan dopiero po ponownym uruchomieniu: kliknij „Uruchom ponownie”, a potem „Zezwól…” w każdym wierszu. Lokalizację i powiadomienia zmienisz tylko w Ustawieniach systemowych.",
    "Could not reset: %@": "Nie udało się zresetować: %@",
    # Text theme seed
    "Wstań prosto i weź 5 powolnych, głębokich oddechów.": "Wstań prosto i weź 5 powolnych, głębokich oddechów.",
    "Unieś ramiona do uszu, przytrzymaj 5 s i opuść — powtórz 5 razy.":
        "Unieś ramiona do uszu, przytrzymaj 5 s i opuść — powtórz 5 razy.",
    "Przechyl głowę delikatnie do prawego ramienia, utrzymaj 15 s. Zmień stronę.":
        "Przechyl głowę delikatnie do prawego ramienia, utrzymaj 15 s. Zmień stronę.",
    "Spleć dłonie za plecami, wypchnij klatkę do przodu i oddychaj głęboko.":
        "Spleć dłonie za plecami, wypchnij klatkę do przodu i oddychaj głęboko.",
    "Przetocz barki do tyłu 10 razy, potem do przodu 10 razy.": "Przetocz barki do tyłu 10 razy, potem do przodu 10 razy.",
    "Usiądź na krześle, skręć tułów w prawo, przytrzymaj 15 s. Zmień stronę.":
        "Usiądź na krześle, skręć tułów w prawo, przytrzymaj 15 s. Zmień stronę.",
    # Break actions, natural breaks, presets (IntermezzoKit)
    "Przerwa": "Przerwa",
    "Zrób przerwę.": "Zrób przerwę.",
    "Posiłek lub dłuższa przerwa": "Posiłek lub dłuższa przerwa",
    "Długa nieobecność": "Długa nieobecność",
    "Break #%lld today · let's keep that streak going": "Dziś przerwa nr %lld · utrzymajmy tę passę",
    "Break #%lld today": "Dziś przerwa nr %lld",
    "Break alert! Let's keep that streak going.": "Czas na przerwę! Utrzymajmy tę passę.",
    "Drink some water": "Napij się wody",
    "Blink a few times": "Pomrugaj kilka razy",
    "Check your posture": "Sprawdź postawę",
    "Śniadanie": "Śniadanie",
    "Obiad": "Obiad",
    "Kolacja": "Kolacja",
    # Work log CSV export
    "Data;Od;Do;Praca;Biuro;Zdalnie;W godzinach;Nadgodziny;Nadgodziny rozliczeniowe;Nadgodziny zdalne;Nadgodziny zdalne rozliczeniowe;Aktywnie przy komputerze;Korekta;Notatki":
        "Data;Od;Do;Praca;Biuro;Zdalnie;W godzinach;Nadgodziny;Nadgodziny rozliczeniowe;Nadgodziny zdalne;Nadgodziny zdalne rozliczeniowe;Aktywnie przy komputerze;Korekta;Notatki",
    "tak": "tak",
}
