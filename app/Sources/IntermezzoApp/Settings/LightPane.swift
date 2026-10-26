import SwiftUI
import AppKit
import IntermezzoKit

/// Screen colour by the time of day: cool while the sun is up, warmer after sunset, warmest before sleep.
struct LightPane: View {
    @AppStorage(LightKeys.enabled) private var enabled = false
    @AppStorage(LightKeys.profile) private var profileRaw = LightProfile.recommended.rawValue
    @AppStorage(LightKeys.manualLocation) private var manualLocation = ""
    @AppStorage(LightKeys.weather) private var useWeather = false
    @AppStorage(LightKeys.fadeSeconds) private var fadeSeconds = 20
    @AppStorage(LightKeys.skipFullscreen) private var skipFullscreen = true
    @AppStorage(LightKeys.excludedApps) private var excludedApps = ""
    @AppStorage(BetterDisplayKeys.dim) private var bdDim = false
    @AppStorage(BetterDisplayKeys.dimPercent) private var bdDimPercent = 20
    @AppStorage(BetterDisplayKeys.trueTone) private var bdTrueTone = false
    @AppStorage(BetterDisplayKeys.unlinkGroup) private var bdUnlinkGroup = false
    @AppStorage(LightKeys.ambient) private var useAmbient = false
    @AppStorage(LightKeys.roomLampK) private var roomLampK = 0
    @AppStorage(LightKeys.customBase) private var customBaseRaw = ""
    @ObservedObject private var betterDisplay = BetterDisplayLight.shared
    @State private var runningApps: [String] = []
    @State private var showLocationMap = false
    @ObservedObject private var light = LightController.shared

    private var profile: LightProfile { LightProfile(rawValue: profileRaw) ?? .recommended }

    var body: some View {
        Form {
            Section {
                Toggle("Dostosowuj barwę ekranu do pory dnia", isOn: Binding(
                    get: { enabled }, set: { light.setEnabled($0) }))
                Text("Wieczorem ciepła barwa zmniejsza ilość światła krótkofalowego (ok. 460–480 nm), które najsilniej hamuje melatoninę i przesuwa zegar dobowy. Badania wskazują ten kierunek, ale nie podają jednej „właściwej” temperatury, a równie ważna jest jasność ekranu i pokoju. Profile poniżej to rozsądne kompromisy, nie zalecenie lekarskie.")
                    .settingsNote()
            }
            if enabled {
                nowSection
                scheduleSection
                exceptionsSection
                LightMonitorsSection()
                locationSection.expertOnly()
                ambientSection.expertOnly()
                advancedSection.expertOnly()
                if BetterDisplayLight.isInstalled { betterDisplaySection.expertOnly() }
                Section {
                    Text("Wyłącz Night Shift i True Tone w Ustawieniach systemowych → Ekrany, bo nakładają się na tę funkcję. Ekrany przez DisplayLink, AirPlay i część Sidecar nie obsługują zmiany barwy, a treści HDR mogą ją częściowo omijać. Po zamknięciu aplikacji kolory wracają same; awaryjnie: Intermezzo --reset-light albo adres intermezzo://light/off.")
                        .settingsNote()
                    if !light.unsupportedDisplays.isEmpty {
                        Label("Bez zmiany barwy: \(light.unsupportedDisplays.joined(separator: ", "))",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .readsRunningApps(into: $runningApps)
    }

    // MARK: Now

    private var nowSection: some View {
        Section("Teraz") {
            LabeledContent("Barwa") {
                Text(verbatim: "\(Int(light.appliedKelvin.rounded())) K")
                    .monospacedDigit()
            }
            if let state = light.state {
                LabeledContent("Pora") { Text(phaseName(state.phase)) }
            }
            if let event = light.nextEvent {
                LabeledContent(event.kind == .sunset ? "Zachód słońca" : "Wschód słońca") {
                    HStack(spacing: 6) {
                        Text(event.date, format: .dateTime.hour().minute())
                        Text(event.date, style: .relative).foregroundStyle(.secondary)
                    }
                }
            }
            LightChart(light: light, editable: profile.isCustom)
                .frame(height: profile.isCustom ? 150 : 96)
            if profile.isCustom {
                Text("Przeciągaj po wykresie jak po equalizerze: każdy słupek to jedna godzina doby, a wysokość to barwa (wyżej chłodniej, niżej cieplej). Między godzinami kolor płynnie przechodzi.")
                    .settingsNote()
            }
            if let until = light.pausedUntil {
                HStack {
                    Label("Wstrzymane do \(until.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
                    Spacer()
                    Button("Wznów") { light.resumeNow() }
                }
            }
            HStack {
                if light.pausedUntil == nil {
                    Menu("Wstrzymaj zmianę barwy…") {
                        Button("na godzinę") { light.disable(forMinutes: 60) }
                        Button("do wschodu słońca") { light.disableUntilSunrise() }
                    }
                    .fixedSize()
                }
                Spacer()
                Button(light.previewing ? "Zatrzymaj podgląd" : "Podgląd doby (12 s)") {
                    light.previewing ? light.stopPreview() : light.previewDay()
                }
            }
            .controlSize(.small)
        }
    }

    private func phaseName(_ phase: LightPhase) -> String {
        switch phase {
        case .daytime: return String(localized: "Dzień")
        case .sunset: return String(localized: "Wieczór po zachodzie")
        case .bedtime: return String(localized: "Pora snu")
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section("Harmonogram") {
            Picker("Profil", selection: Binding(
                get: { profileRaw },
                set: { new in
                    if (LightProfile(rawValue: new)?.isCustom ?? false), light.customCurveStored == nil {
                        light.startCustomCurve(from: profile)
                    }
                    profileRaw = new
                })) {
                Text("Zalecane").tag(LightProfile.recommended.rawValue)
                Text("Klasyczne").tag(LightProfile.classic.rawValue)
                Text("Daleko od równika").tag(LightProfile.farFromEquator.rawValue)
                Text("Praca do późna").tag(LightProfile.workingLate.rawValue)
                Text("Własne (wg zegara)").tag(LightProfile.custom.rawValue)
                Text("Własne (wg Słońca)").tag(LightProfile.customSun.rawValue)
            }
            Text(profileNote).settingsNote()
            LabeledContent("Wstaję o") {
                TimeInput(minutes: Binding(
                    get: { light.wakeMinutes },
                    set: { UserDefaults.standard.set($0, forKey: LightKeys.wakeMinutes) }))
            }
            if profile.isCustom {
                Menu("Wykres barwy: zacznij od profilu…") {
                    Button("Zalecane") { light.startCustomCurve(from: .recommended) }
                    Button("Klasyczne") { light.startCustomCurve(from: .classic) }
                    Button("Daleko od równika") { light.startCustomCurve(from: .farFromEquator) }
                    Button("Praca do późna") { light.startCustomCurve(from: .workingLate) }
                }
                .fixedSize()
                Text("Zastępuje wykres barwy z sekcji „Teraz” (barwa godzina po godzinie) wartościami wybranego profilu. Rzeczy, które narysowałeś na wykresie, przepadną.")
                    .settingsNote()
                if let base = LightProfile(rawValue: customBaseRaw), !base.isCustom {
                    Text("Wykres w sekcji „Teraz” zaczęto od profilu „\(profileName(base))”. Możesz go dalej poprawiać palcem po wykresie.")
                        .settingsNote()
                }
            }
        }
    }

    private func profileName(_ profile: LightProfile) -> String {
        switch profile {
        case .recommended: return String(localized: "Zalecane")
        case .classic: return String(localized: "Klasyczne")
        case .farFromEquator: return String(localized: "Daleko od równika")
        case .workingLate: return String(localized: "Praca do późna")
        case .custom: return String(localized: "Własne (wg zegara)")
        case .customSun: return String(localized: "Własne (wg Słońca)")
        }
    }

    private var profileNote: String {
        switch profile {
        case .recommended: return String(localized: "Dzień 6500 K, po zachodzie 3400 K, przed snem do 1900 K. Ocieplanie zaczyna się 2 godziny przed porą snu.")
        case .classic: return String(localized: "Dzień 6500 K i 3400 K wieczorem, bez dalszego ocieplania przed snem.")
        case .farFromEquator: return String(localized: "Dla wysokich szerokości geograficznych: długi zmierzch, łagodniejsze i dłuższe przejście, 2300 K przed snem.")
        case .workingLate: return String(localized: "Pora snu przesunięta o 2,5 godziny: dłuższy wieczór, 2300 K przed snem.")
        case .custom: return String(localized: "Narysowany dzień: barwa o danej godzinie jest dokładnie taka, jak na wykresie, niezależnie od Słońca.")
        case .customSun: return String(localized: "Narysowany dzień, którego siłę kontrolują wschód i zachód słońca, zachmurzenie i światło w pokoju: w dzień ekran jest neutralny, a po zmroku płynnie przechodzi do koloru z wykresu. Wykres mówi, jak ciepło może być o danej godzinie.")
        }
    }

    // MARK: Exceptions

    private var exceptionsSection: some View {
        Section("Wyjątki") {
            Toggle("Nie zmieniaj barw w aplikacjach pełnoekranowych", isOn: $skipFullscreen)
            Text("Dotyczy tylko tego monitora, na którym okno zajmuje cały ekran (film, gra, prezentacja). Pozostałe monitory zostają ocieplone.")
                .settingsNote()
            TextField("Aplikacje bez zmiany barw", text: $excludedApps, prompt: Text(verbatim: "Pixelmator Pro, Final Cut Pro"))
                .textFieldStyle(.editable)
            HStack {
                Menu("Dodaj uruchomioną aplikację…") {
                    ForEach(runningApps, id: \.self) { name in
                        Button(name) { addExcluded(name) }
                    }
                }
                Menu("Dodaj gotowy zestaw…") {
                    Button("Edytory zdjęć, wideo i grafiki") { addPreset("creative") }
                    Button("Odtwarzacze wideo") { addPreset("video") }
                    Button("Gry i launchery") { addPreset("games") }
                }
            }
            .fixedSize()
            Text("Gdy aplikacja z listy jest aktywnym oknem, jej monitor pokazuje normalne kolory, np. przy obróbce zdjęć i wideo. Nazwy oddzielaj przecinkami.")
                .settingsNote()
        }
    }

    private func addPreset(_ id: String) {
        guard let preset = LightExclusionPresets.all.first(where: { $0.id == id }) else { return }
        excludedApps = LightExclusionPresets.adding(preset, to: excludedApps)
    }

    private func addExcluded(_ name: String) {
        var list = KeepAwakeApps.list(fromCommaText: excludedApps)
        if !list.contains(where: { KeepAwakeApps.normalized($0) == KeepAwakeApps.normalized(name) }) { list.append(name) }
        excludedApps = list.joined(separator: ", ")
    }

    // MARK: Ambient light

    private var ambientSection: some View {
        Section("Światło w pokoju") {
            Toggle("Uwzględniaj jasność pokoju z czujnika w Macu", isOn: $useAmbient)
            if useAmbient {
                LabeledContent("Teraz") {
                    if let lux = light.lux {
                        Text("\(Int(lux.rounded())) lx").monospacedDigit()
                    } else {
                        Text("brak odczytu").foregroundStyle(.secondary)
                    }
                }
                if !light.ambientNote.isEmpty {
                    Label(light.ambientNote, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Lampy w pokoju", selection: $roomLampK) {
                Text("Nie wiem").tag(0)
                Text("Ciepłe (ok. 2700 K)").tag(2700)
                Text("Neutralne (ok. 4000 K)").tag(4000)
                Text("Zimne (ok. 5500 K)").tag(5500)
            }
            Text("W jasnym pokoju ocieplanie ekranu jest słabsze, a przyciemnianie przez BetterDisplay mniejsze; w ciemnym działa w pełni. Czujnik jest tylko w MacBooku, odczyt idzie przez prywatny interfejs macOS (może przestać działać po aktualizacji) i znika przy zamkniętej klapie, wtedy działa sam harmonogram. Mac nie mierzy barwy światła, więc kolor lamp wybierasz ręcznie: wieczorem ekran nie będzie wtedy dużo zimniejszy niż lampy.")
                .settingsNote()
        }
    }

    // MARK: BetterDisplay

    private var betterDisplaySection: some View {
        Section("BetterDisplay") {
            LabeledContent("Połączenie") {
                HStack(spacing: 8) {
                    Text(linkText).foregroundStyle(betterDisplay.link == .connected ? Color.green : Color.secondary)
                    Button("Sprawdź") { Task { await betterDisplay.checkConnection() } }.controlSize(.small)
                }
            }
            Toggle("Przyciemniaj monitory wieczorem (sprzętowo)", isOn: $bdDim)
            if bdDim {
                Stepper("Przyciemnij maksymalnie o \(bdDimPercent)%", value: $bdDimPercent, in: 5...EveningDimming.maxDimPercent, step: 5)
            }
            Toggle("Wyłącz True Tone na czas działania Światła", isOn: $bdTrueTone)
            Toggle("Rozłączaj grupę ekranów na czas wyjątku", isOn: $bdUnlinkGroup)
            Text("Grupa BetterDisplay (np. dwa takie same monitory) trzyma ich jasność razem. Gdy jeden monitor ma zostać nieprzyciemniony (pełny ekran, aplikacja z listy wyjątków), grupa jest wyłączana, a po wieczorze włączana z powrotem.")
                .settingsNote()
            if !betterDisplay.note.isEmpty {
                Label(betterDisplay.note, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text("Wymaga włączonego w BetterDisplay dostępu przez CLI i powiadomienia (Ustawienia → Aplikacja → Integracja). Jasność zmienia się sprzętowo (DDC), razem z ocieplaniem, a po wyłączeniu Światła wraca do pierwotnej. Gdy sam zmienisz jasność, aplikacja przestaje jej ruszać do końca wieczoru. Wyłączanie True Tone wymaga BetterDisplay Pro.")
                .settingsNote()
        }
        .task { await betterDisplay.checkConnection() }
    }

    private var linkText: String {
        switch betterDisplay.link {
        case .connected: return String(localized: "działa, ekranów: \(betterDisplay.devices.count)")
        case .notRunning: return String(localized: "BetterDisplay nie jest uruchomiony")
        case .noAnswer: return String(localized: "brak odpowiedzi (włącz integrację w BetterDisplay)")
        case .notInstalled: return String(localized: "nie zainstalowany")
        }
    }

    // MARK: Location and extras

    private var locationSection: some View {
        Section("Lokalizacja") {
            LabeledContent("Źródło") { Text(light.locationNote).foregroundStyle(.secondary) }
            TextField("Współrzędne", text: $manualLocation, prompt: Text(verbatim: "52.4, 22"))
                .textFieldStyle(.editable)
            Button("Wybierz na mapie…") { showLocationMap = true }
                .sheet(isPresented: $showLocationMap) {
                    LocationMapSheet(center: light.point, pin: LightLocation.parse(manualLocation)) {
                        manualLocation = LightLocation.format($0)
                    }
                }
            if !manualLocation.isEmpty, LightLocation.parse(manualLocation) == nil {
                Label("Wpisz szerokość i długość oddzielone przecinkiem, np. 52.4, 22", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            Text("Bez wpisanych współrzędnych aplikacja używa lokalizacji Maca, a gdy jej nie ma, przybliżonego miejsca ze strefy czasowej. Wschód i zachód liczy lokalnie, bez internetu.")
                .settingsNote()
        }
    }

    private var advancedSection: some View {
        Section("Zaawansowane") {
            Toggle("Uwzględniaj zachmurzenie", isOn: $useWeather)
            Text("Pochmurne popołudnie ściemnia się wcześniej. Korzysta z tej samej anonimowej pogody co ekran przerwy (Open-Meteo), bez dodatkowych danych.")
                .settingsNote()
            Stepper("Płynna zmiana: \(fadeSeconds) s", value: $fadeSeconds, in: 1...120, step: 5)
        }
    }
}

/// The day's colour as 24 hourly bands (like an equaliser) with the smooth curve over them. With the
/// Custom profile the bands are dragged with the pointer.
private struct LightChart: View {
    @ObservedObject var light: LightController
    let editable: Bool
    @State private var draft: CustomLightCurve?
    @State private var lastPoint: (band: Double, kelvin: Double)?
    @State private var hint: String?

    private let low = LightSettings.minKelvin
    private let high = LightSettings.maxKelvin

    private func bandValues() -> [Double] {
        if let draft { return draft.hourly }
        if let curve = light.customCurve { return curve.hourly }
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<24).map { hour in
            light.scheduleState(at: start.addingTimeInterval(Double(hour) * 3600 + 1800), point: light.point, cloud: nil).kelvin
        }
    }

    private func smoothKelvin(_ minute: Double, bands: [Double]) -> Double {
        CustomLightCurve(hourly: bands).kelvin(atMinuteOfDay: minute)
    }

    private func y(_ kelvin: Double, _ height: CGFloat) -> CGFloat {
        let t = (kelvin - low) / (high - low)
        return height - 14 - CGFloat(min(max(t, 0), 1)) * (height - 20)
    }

    private func kelvin(atY value: CGFloat, _ height: CGFloat) -> Double {
        let t = Double((height - 14 - value) / (height - 20))
        return low + min(max(t, 0), 1) * (high - low)
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let bands = bandValues()
                let width = size.width / 24
                for (hour, k) in bands.enumerated() {
                    let m = ColorTemperature.multipliers(kelvin: k)
                    let color = Color(red: m.r, green: m.g * 0.96, blue: m.b)
                    let top = y(k, size.height)
                    let rect = CGRect(x: CGFloat(hour) * width + 1, y: top, width: width - 2, height: size.height - 14 - top)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color.opacity(editable ? 0.8 : 0.55)))
                    context.fill(Path(CGRect(x: rect.minX, y: top - 1.5, width: rect.width, height: 3)), with: .color(.white.opacity(0.9)))
                }
                var line = Path()
                let dayStart = Calendar.current.startOfDay(for: Date())
                let drawn = CustomLightCurve(hourly: bands)
                for step in 0...144 {
                    let minute = Double(step) * 10
                    let kelvinHere: Double
                    if light.profile == .customSun {
                        // what the drawn day becomes today: the Sun decides how much of it applies
                        kelvinHere = LightSchedule.sunDrivenState(at: dayStart.addingTimeInterval(minute * 60),
                                                                  latitude: light.point.latitude, longitude: light.point.longitude,
                                                                  curve: drawn, settings: light.settings).kelvin
                    } else {
                        kelvinHere = smoothKelvin(minute, bands: bands)
                    }
                    let p = CGPoint(x: CGFloat(minute / 1440) * size.width, y: y(kelvinHere, size.height))
                    step == 0 ? line.move(to: p) : line.addLine(to: p)
                }
                context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1)
                let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
                let nowX = CGFloat(Double((now.hour ?? 0) * 60 + (now.minute ?? 0)) / 1440) * size.width
                context.stroke(Path { $0.move(to: CGPoint(x: nowX, y: 0)); $0.addLine(to: CGPoint(x: nowX, y: size.height - 14)) },
                               with: .color(.white), lineWidth: 1)
                for hour in [0, 6, 12, 18, 24] {
                    let label = Text(verbatim: hour == 24 ? "24" : String(format: "%02d", hour)).font(.system(size: 9)).foregroundColor(.secondary)
                    context.draw(label, at: CGPoint(x: min(max(CGFloat(hour) * width, 8), size.width - 8), y: size.height - 6))
                }
                context.draw(Text(verbatim: "6500 K").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: 24, y: 8))
                context.draw(Text(verbatim: "1000 K").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: 24, y: size.height - 20))
            }
            .overlay(alignment: .topTrailing) {
                if let hint {
                    Text(verbatim: hint).font(.caption).monospacedDigit().padding(4)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .gesture(editable ? drag(in: proxy.size) : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.12)))
        .accessibilityLabel(Text("Wykres barwy ekranu w ciągu doby"))
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var curve = draft ?? light.customCurve ?? CustomLightCurve(hourly: bandValues())
                let band = min(max(Double(value.location.x / size.width) * 24, 0), 23.999)
                let k = (kelvin(atY: value.location.y, size.height) / CustomLightCurve.step).rounded() * CustomLightCurve.step
                if let last = lastPoint {
                    curve.paint(fromBand: last.band, kelvin: last.kelvin, toBand: band, kelvin: k)
                } else {
                    curve.paint(fromBand: band, kelvin: k, toBand: band, kelvin: k)
                }
                lastPoint = (band, k)
                draft = curve
                hint = String(format: "%02d:00  %d K", Int(band), Int(k))
            }
            .onEnded { _ in
                if let draft { light.saveCustomCurve(draft) }
                draft = nil
                lastPoint = nil
                hint = nil
            }
    }
}
