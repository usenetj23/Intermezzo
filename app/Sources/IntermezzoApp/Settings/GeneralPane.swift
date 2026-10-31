import SwiftUI
import SwiftData
import AppKit
import Carbon.HIToolbox
import ServiceManagement
import CoreLocation
import UserNotifications
import IOKit.hidsystem
import IntermezzoKit

struct GeneralPane: View {
    @AppStorage(Keys.autostart) private var autostart = true
    @AppStorage(Keys.autoStartTimer) private var autoStartTimer = true
    @AppStorage(Keys.idleDetection) private var idleDetection = true
    @AppStorage(Keys.idleThresholdSeconds) private var idleThresholdSeconds = 60
    @AppStorage("awayUnconfirmedMinutes") private var awayUnconfirmedMinutes = 10
    @AppStorage("awayCreditsBreak") private var awayCreditsBreak = true
    @AppStorage(Keys.idleResetAfterMinutes) private var idleResetAfterMinutes = 5
    @AppStorage(NaturalBreakKeys.enabled) private var naturalLog = 0
    @AppStorage(NaturalBreakKeys.minMinutes) private var naturalMinutes = 0
    @AppStorage(Keys.enforceWorkingHours) private var enforceWorkingHours = false
    @AppStorage("perDayHours") private var perDayHours = false
    @AppStorage("weekHours") private var weekHoursData = Data()
    @AppStorage(Keys.workStartMinutes) private var workStartMinutes = 480
    @AppStorage(Keys.workEndMinutes) private var workEndMinutes = 1080
    @AppStorage(Keys.workDaysMask) private var workDaysMask = 31
    @AppStorage(Keys.meetingDetection) private var meetingDetection = true
    @AppStorage(Keys.videoDetection) private var videoDetection = true
    @AppStorage("calendarAwareBreaks") private var calendarAwareBreaks = false
    @AppStorage(Keys.calendarWorkDetection) private var calendarWorkDetection = false
    @AppStorage(Keys.holidayGuard) private var holidayGuard = false
    @AppStorage(Keys.holidayKeywords) private var holidayKeywords = "urlop, święto, swieto, wakacje, vacation, holiday, chorobowe, l4"
    @AppStorage(Keys.vacationMode) private var vacationMode = false
    @AppStorage(Keys.vacationDays) private var vacationDays = 7
    @AppStorage(Keys.vacationUntil) private var vacationUntil = 0.0
    @AppStorage(Keys.vpnDetection) private var vpnDetection = false
    @AppStorage(Keys.focusDetection) private var focusDetection = false
    @AppStorage(Keys.vpnNames) private var vpnNames = "work"
    @AppStorage(Keys.wifiDetection) private var wifiDetection = false
    @AppStorage(Keys.wifiNames) private var wifiNames = ""
    @AppStorage(Keys.geoDetection) private var geoDetection = false
    @State private var showWorkPlaceMap = false
    @AppStorage(Keys.geoLat) private var geoLat = 0.0
    @AppStorage(Keys.geoLon) private var geoLon = 0.0
    @AppStorage(Keys.geoRadiusM) private var geoRadiusM = 300.0
    @ObservedObject private var work = WorkDetector.shared
    @AppStorage(AIKeys.enabled) private var aiEnabled = false
    @State private var showAssistant = false
    @State private var undoCount = SettingsHistory.count(in: .standard)
    @AppStorage(Keys.menuBarCountdown) private var menuBarCountdown = true
    @AppStorage(Keys.menuBarCountdownNotch) private var menuBarCountdownNotch = false
    @AppStorage(Keys.menuBarColoredIcon) private var menuBarColoredIcon = false
    @AppStorage(Keys.focusWorkZone) private var focusWorkZone = false

    private func undoAssistant() {
        SettingsHistory.popLast(from: .standard)?.restore(into: .standard)
        undoCount = SettingsHistory.count(in: .standard)
    }

    private var dayNames: [String] { [String(localized: "Mon"), String(localized: "Tue"), String(localized: "Wed"),
                             String(localized: "Thu"), String(localized: "Fri"), String(localized: "Sat"),
                             String(localized: "Sun")] }

    var body: some View {
        Form {
            if aiEnabled || undoCount > 0 {
                Section("Asystent ustawień") {
                    if aiEnabled {
                        Button("Asystent ustawień…") { showAssistant = true }.settingsAnchor("general-asystent-ustawien")
                        Text("Opisz własnymi słowami, jak ma działać program, a asystent zaproponuje zmiany do zatwierdzenia.")
                            .settingsNote().settingsAnchor("general-opisz-wlasnymi-slowami-jak-ma-dziala")
                    }
                    // Undo stays available when the AI features are switched off again.
                    if undoCount > 0 {
                        Button("Cofnij ostatnie zmiany asystenta") { undoAssistant() }.settingsAnchor("general-cofnij-ostatnie-zmiany-asystenta")
                    }
                }
            }
            Section("Run Intermezzo") {
                Toggle("Launch when Mac starts", isOn: Binding(
                    get: { autostart },
                    set: { newValue in
                        autostart = newValue
                        if #available(macOS 13, *) {
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { NSSound.beep() }
                        }
                    })).settingsAnchor("general-launch-when-mac-starts")
                Toggle("Start timer automatically on app launch", isOn: $autoStartTimer).settingsAnchor("general-start-timer-automatically-on-app-lau")
                Toggle("Show countdown text in menu bar", isOn: $menuBarCountdown).settingsAnchor("general-show-countdown-text-in-menu-bar")
                Toggle("Pokaż licznik także na ekranie z notchem", isOn: $menuBarCountdownNotch).settingsAnchor("general-pokaz-licznik-takze-na-ekranie-z-not")
                    .disabled(!menuBarCountdown)
                Text("Na MacBooku z notchem pełny pasek menu może schować ikonę razem z licznikiem. Gdy tak się stanie, licznik widać w pływającej pastylce.")
                    .settingsNote().settingsAnchor("general-na-macbooku-z-notchem-pelny-pasek-me")
                Toggle("Koloruj ikonę w pasku menu według stanu timera", isOn: $menuBarColoredIcon).settingsAnchor("general-koloruj-ikone-w-pasku-menu-wedlug-st")
                Text("Zielona: timer działa. Niebieska: trwa przerwa. Pomarańczowa: wstrzymany przez spotkanie, wideo, Focus, regułę lub brak aktywności. Fioletowa: poza godzinami i strefą pracy albo urlop. Szara: wstrzymany ręcznie.")
                    .settingsNote().settingsAnchor("general-zielona-timer-dziala-niebieska-trwa")
            }
            Section("Idle Time") {
                Toggle("Detect inactivity", isOn: $idleDetection).settingsAnchor("general-detect-inactivity")
                if idleDetection {
                    Group {
                        Stepper("Pause timer after \(idleThresholdSeconds / 60) min",
                              value: $idleThresholdSeconds, in: 1...60, step: 60)
                        Toggle("Zalicz nieobecność jako przerwę (krótką albo długą)", isOn: $awayCreditsBreak).settingsAnchor("general-zalicz-nieobecnosc-jako-przerwe-krot")
                        Text("Gdy czas bez ruchu myszą i klawiaturą jest co najmniej tak długi jak następna zaplanowana przerwa, timer zaczyna od nowa tak, jakby przerwa się odbyła. Jeśli następna miała być krótka, a nieobecność trwała tyle co długa przerwa albo dłużej, liczy się jako długa. Krótsze nieobecności nadal obsługuje ustawienie poniżej.")
                            .settingsNote().settingsAnchor("general-gdy-czas-bez-ruchu-mysza-i-klawiatur")
                        Stepper("Bez blokady ekranu: nieobecność od \(awayUnconfirmedMinutes) min", value: $awayUnconfirmedMinutes, in: 2...60)
                        Text("Brak ruchu myszą i klawiaturą przy odblokowanym ekranie może być czytaniem. Timer zatrzymuje się, a nieobecność zalicza jako przerwa dopiero po tylu minutach albo od razu, gdy ekran zostanie zablokowany, uśpiony lub włączy się wygaszacz.")
                            .settingsNote().settingsAnchor("general-brak-ruchu-mysza-i-klawiatura-przy-o")
                        Stepper("Reset timer after \(idleResetAfterMinutes) min away",
                              value: $idleResetAfterMinutes, in: 1...120)
                        Toggle("Zapisuj dłuższą nieobecność jako przerwę naturalną", isOn: Binding(
                            get: { naturalLog != 0 }, set: { naturalLog = $0 ? 1 : 0 })).settingsAnchor("general-zapisuj-dluzsza-nieobecnosc-jako-prz")
                        if naturalLog != 0 {
                            Stepper("od \(naturalMinutes == 0 ? NaturalBreakKeys.defaultMinutes : naturalMinutes) min",
                                    value: Binding(get: { naturalMinutes == 0 ? NaturalBreakKeys.defaultMinutes : naturalMinutes },
                                                   set: { naturalMinutes = $0 }), in: 5...120, step: 5)
                            Text("Obiad, kawa czy spacer to nie ta sama przerwa co przypomnienie z aplikacji. Takie wpisy są liczone osobno w Statystykach (nie zaliczają passy ani nie wchodzą do wykresu) i widać je w historii z ikoną spaceru. Nieobecność powyżej 6 godzin traktuję jako koniec dnia i jej nie zapisuję.")
                                .settingsNote().settingsAnchor("general-obiad-kawa-czy-spacer-to-nie-ta-sama")
                        }
                    }
                    .expertOnly()
                }
            }
            Section("Working Hours") {
                Toggle("Enable working hours", isOn: $enforceWorkingHours)
                    .settingsAnchor("hours")
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        Toggle(dayNames[i], isOn: Binding(
                            get: { (workDaysMask & (1 << i)) != 0 },
                            set: { on in
                                if on { workDaysMask |= (1 << i) } else { workDaysMask &= ~(1 << i) }
                            }))
                            .toggleStyle(.button)
                            .controlSize(.mini)
                    }
                }
                LabeledContent("Work starts at") {
                    TimeInput(minutes: $workStartMinutes)
                }
                LabeledContent("Work ends at") {
                    TimeInput(minutes: $workEndMinutes)
                }
                Text("Przerwy działają w godzinach pracy LUB gdy Mac jest w strefie pracy (wydarzenie w kalendarzu, VPN, Wi-Fi, miejsce albo LAN i karta z Rejestru pracy): nadgodziny, awaria, dzień wolny. Timer stoi dopiero wtedy, gdy nie zachodzi żadne z dwóch.")
                    .settingsNote().settingsAnchor("general-przerwy-dzialaja-w-godzinach-pracy-l")
                Group {
                    Toggle("Różne godziny w poszczególne dni", isOn: $perDayHours).settingsAnchor("general-rozne-godziny-w-poszczegolne-dni")
                    if perDayHours {
                        ForEach(0..<7, id: \.self) { i in
                            if (workDaysMask & (1 << i)) != 0 { dayHoursRow(i) }
                        }
                        Text("Dzień bez zmian używa godzin powyżej.")
                            .settingsNote().settingsAnchor("general-dzien-bez-zmian-uzywa-godzin-powyzej")
                    }
                }
                .expertOnly()
            }
            Section("Holidays & Vacation") {
                Group {
                    Toggle("Holiday guard: no breaks on days with events matching", isOn: $holidayGuard)
                        .settingsAnchor("holiday")
                    if holidayGuard {
                        TextField("urlop, święto, wakacje, vacation, holiday", text: $holidayKeywords)
                        zoneStatus(work.holidayToday ? 1 : 0,
                                   work.holidayToday
                                       ? String(localized: "holiday/vacation event today — breaks held")
                                       : String(localized: "no holiday event today"))
                    }
                    Divider()
                }
                .expertOnly()
                Toggle("Vacation mode — pause everything for N days", isOn: $vacationMode)
                    .settingsAnchor("vacation")
                    .onChange(of: vacationMode) { _, on in
                        if on {
                            vacationUntil = Date().addingTimeInterval(TimeInterval(vacationDays * 86400))
                                .timeIntervalSince1970
                        }
                    }
                if vacationMode {
                    Stepper("Days off: \(vacationDays)", value: $vacationDays, in: 1...60)
                        .onChange(of: vacationDays) { _, days in
                            vacationUntil = Date().addingTimeInterval(TimeInterval(days * 86400))
                                .timeIntervalSince1970
                        }
                }
                Text("Tip: with Calendar detection ON in Intermezzo Intelligence, calendar events REPLACE these fixed hours — a vacation or day off without a matching event keeps breaks asleep.")
                    .settingsNote().settingsAnchor("general-tip-with-calendar-detection-on-in-in")
                    .expertOnly()
            }
            Section("Intermezzo Intelligence") {
                Toggle("Meeting detection: pause when Zoom/Teams/Webex is on", isOn: $meetingDetection)
                    .settingsAnchor("meeting")
                Toggle("Video detection: pause when watching video", isOn: $videoDetection)
                    .settingsAnchor("video")
                Toggle("Kalendarz: odkładaj przerwę, gdy trwa lub zaraz zacznie się spotkanie",
                       isOn: $calendarAwareBreaks).settingsAnchor("general-kalendarz-odkladaj-przerwe-gdy-trwa")
                    .expertOnly()
                Toggle("Focus: pause while Focus / Do Not Disturb is on", isOn: $focusDetection)
                    .settingsAnchor("focus")
                    .expertOnly()
                Group {
                    Toggle("Focus oznaczony jako „praca” liczy się do strefy pracy", isOn: $focusWorkZone).settingsAnchor("general-focus-oznaczony-jako-praca-liczy-sie")
                    FocusRolesView()
                }
                .expertOnly()

                Group {
                    Divider()
                    Text("Work zone — with any option below ON, breaks run only while at least one of the enabled options matches (calendar event, VPN, Wi-Fi or place) or it is within working hours. All OFF = breaks always run.")
                        .settingsNote().settingsAnchor("general-work-zone-with-any-option-below-on-b")

                    Toggle("Calendar: breaks also run during matching events (added to working hours)", isOn: $calendarWorkDetection)
                        .settingsAnchor("zone-calendar")
                    if calendarWorkDetection {
                        CalendarRulesView()
                        if !work.calendarAuthorized {
                            zoneStatus(-1, String(localized: "Access to Calendar not granted — enabling it here also requests it"),
                                       settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                        } else {
                            zoneStatus(work.calendarMatch ? 1 : 0,
                                       work.calendarMatch
                                           ? String(localized: "matching event now — breaks active")
                                           : String(localized: "no matching event in calendar — breaks held"))
                        }
                    }

                    Toggle("VPN: active only while a VPN from the list is connected", isOn: $vpnDetection)
                        .settingsAnchor("zone-vpn")
                    if vpnDetection {
                        TextField("VPN names (comma separated), e.g. work", text: $vpnNames)
                        zoneStatus(work.vpnMatch ? 1 : 0,
                                   work.vpnConnectedNames.isEmpty
                                       ? String(localized: "no VPN connection detected")
                                       : (work.vpnMatch
                                          ? String(localized: "VPN from list connected: \(work.vpnConnectedNames.joined(separator: ", "))")
                                          : String(localized: "VPN connected but not on the list: \(work.vpnConnectedNames.joined(separator: ", "))")))
                    }

                    Toggle("Wi-Fi: active only while connected to a network from the list", isOn: $wifiDetection)
                        .settingsAnchor("zone-wifi")
                    if wifiDetection {
                        TextField("SSIDs (comma separated), e.g. Biuro", text: $wifiNames)
                        if !work.locationAuthorized {
                            zoneStatus(-1, String(localized: "macOS reads the Wi-Fi name only with Location access"),
                                       settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                        } else {
                            zoneStatus(work.wifiMatch ? 1 : 0,
                                       work.currentSSID.isEmpty
                                           ? String(localized: "SSID unknown (not on Wi-Fi?)")
                                           : String(localized: "current network: \(work.currentSSID)"))
                        }
                    }

                    Toggle("Location: active only within radius of a saved place", isOn: $geoDetection)
                        .settingsAnchor("zone-geo")
                    if geoDetection {
                        LabeledContent("Szerokość geograficzna") {
                            TextField("", value: $geoLat, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.editable)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                        LabeledContent("Długość geograficzna") {
                            TextField("", value: $geoLon, format: .number.precision(.fractionLength(4)))
                                .textFieldStyle(.editable)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }
                        Stepper("Promień: \(Int(geoRadiusM)) m", value: $geoRadiusM, in: 50...5000, step: 50)
                        HStack(spacing: 8) {
                            Button("Use current") {
                                WorkDetector.shared.captureCurrentLocation { c in
                                    DispatchQueue.main.async {
                                        geoLat = c.latitude
                                        geoLon = c.longitude
                                    }
                                }
                            }.settingsAnchor("general-use-current")
                            Button("Wybierz na mapie…") { showWorkPlaceMap = true }.settingsAnchor("general-wybierz-na-mapie")
                                .sheet(isPresented: $showWorkPlaceMap) {
                                    LocationMapSheet(
                                        center: GeoPoint(latitude: geoLat, longitude: geoLon),
                                        pin: (geoLat == 0 && geoLon == 0) ? nil : GeoPoint(latitude: geoLat, longitude: geoLon)) {
                                        geoLat = $0.latitude
                                        geoLon = $0.longitude
                                    }
                                }
                        }
                        .controlSize(.small)
                        Text("To miejsce pracy, a nie pozycja Maca: dzięki niemu aplikacja wie, że jesteś w pracy. Pozycję używaną do pogody i wschodu słońca ustawiasz osobno.")
                            .settingsNote().settingsAnchor("general-to-miejsce-pracy-a-nie-pozycja-maca")
                        Button("Ustawienia pozycji do pogody i słońca…") {
                            SettingsPane.go(to: .light, anchor: "light-wybierz-na-mapie")
                        }.settingsAnchor("general-ustawienia-pozycji-do-pogody-i-slonc")
                        .controlSize(.small)
                        if !work.locationAuthorized {
                            zoneStatus(-1, String(localized: "Location access not granted"),
                                       settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                        } else {
                            zoneStatus(work.geoMatch ? 1 : 0,
                                       work.geoDistanceM < 0
                                           ? String(localized: "waiting for first GPS fix…")
                                           : (work.geoMatch
                                              ? String(localized: "\(Int(work.geoDistanceM.rounded())) m from saved place — inside zone")
                                              : String(localized: "\(Int(work.geoDistanceM.rounded())) m from saved place — outside zone")))
                            if work.geoDistanceM < 0, WorkDetector.wifiState() == .off {
                                Label("Mac nie ma GPS i ustala pozycję po Wi-Fi, a ono jest wyłączone, więc to miejsce pracy nie zadziała. Użyj sieci LAN, VPN, kalendarza albo godzin pracy.",
                                      systemImage: "wifi.slash")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .expertOnly()
            }
            Section("Keyboard Shortcuts") {
                HotkeyRecorderRow(Keys.hotkeyShort, title: "Start short break")
                HotkeyRecorderRow(Keys.hotkeyLong, title: "Start long break")
                HotkeyRecorderRow(Keys.hotkeyPostpone, title: "Postpone next break")
                HotkeyRecorderRow(Keys.hotkeySkip, title: "Skip next/current break")
                HotkeyRecorderRow(Keys.hotkeyPauseAll, title: "Pause all indefinitely")
                HotkeyRecorderRow(Keys.hotkeyResumeAll, title: "Resume all breaks")
                HotkeyRecorderRow(Keys.hotkeyPause, title: "Pause / resume timer")
                HotkeyRecorderRow(Keys.hotkeyReset, title: "Reset all breaks")
                HotkeyRecorderRow(Keys.hotkeyStopSound, title: "Stop sound")
                Text("Work from any app. You can also automate via URLs, e.g. intermezzo://break/long, intermezzo://break/short/postpone/2m, intermezzo://postpone/5m, intermezzo://skip, intermezzo://resume (s/m/h/d durations; bare number = minutes).")
                    .settingsNote().settingsAnchor("general-work-from-any-app-you-can-also-autom")
            }
            .expertOnly()
            AutomationSection()
                .expertOnly()
        }
        .formStyle(.grouped)
        .scrollsToSettingsAnchor()
        .sheet(isPresented: $showAssistant, onDismiss: { undoCount = SettingsHistory.count(in: .standard) }) { SettingsAssistantSheet() }
        .onAppear { undoCount = SettingsHistory.count(in: .standard) }
    }
}

// MARK: - Messages

private extension GeneralPane {
    /// state: 1 = w strefie (zielony), 0 = poza (pomarańczowy), -1 = brak uprawnień (czerwony + Grant)
    @ViewBuilder func zoneStatus(_ state: Int, _ text: String, settingsURL: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: state == 1 ? "checkmark.circle.fill"
                    : state == -1 ? "xmark.circle.fill" : "moon.circle")
                .foregroundStyle(state == 1 ? Color.green
                               : state == -1 ? Color.red : Color.orange)
            Text(text)
                .settingsNote()
            Spacer()
            if state == -1, let settingsURL, let url = URL(string: settingsURL) {
                Button("Nadaj uprawnienia…") { NSWorkspace.shared.open(url) }.settingsAnchor("general-nadaj-uprawnienia")
                    .controlSize(.small)
            }
        }
    }

    private var generalWindow: WeekHours.Window { .init(start: workStartMinutes, end: workEndMinutes) }

    /// Saving a day equal to the general window clears its override.
    private func saveDay(_ day: Int, _ window: WeekHours.Window) {
        let hours = WeekHours.decode(weekHoursData)
        weekHoursData = (window == generalWindow ? hours.clearing(day: day) : hours.setting(window, forDay: day)).encoded()
    }

    private func dayHoursRow(_ day: Int) -> some View {
        let current = WeekHours.decode(weekHoursData).window(forDay: day, default: generalWindow)
        return HStack {
            Text(dayNames[day]).frame(width: 36, alignment: .leading)
            TimeInput(minutes: Binding(get: { current.start }, set: { saveDay(day, .init(start: $0, end: current.end)) }))
            Text("–")
            TimeInput(minutes: Binding(get: { current.end }, set: { saveDay(day, .init(start: current.start, end: $0)) }))
        }
    }
}
