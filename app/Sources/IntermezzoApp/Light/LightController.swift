import AppKit
import CoreGraphics
import CoreLocation
import IntermezzoKit

enum LightKeys {
    static let enabled = "lightEnabled"
    static let profile = "lightProfile"
    static let dayK = "lightDayK"
    static let sunsetK = "lightSunsetK"
    static let bedtimeK = "lightBedtimeK"
    static let wakeMinutes = "lightWakeMinutes"
    static let manualLocation = "lightLocation"
    static let weather = "lightWeather"
    static let fadeSeconds = "lightFadeSeconds"
    /// How fast the colour may follow the day, in kelvin per minute.
    static let followRate = "lightFollowRate"
    /// This Mac only: not synchronised (see SyncPolicy).
    static let disabledUntil = "lightDisabledUntil"
    /// Leave a display neutral while a full-screen window (film, game) is on it.
    static let skipFullscreen = "lightSkipFullscreen"
    /// Comma-separated apps whose window keeps its display neutral (photo and video editors).
    static let excludedApps = "lightExcludedApps"
    /// Let the Mac's light sensor (lux) adjust the colour and the dimming.
    static let ambient = "lightAmbient"
    /// Colour of the room's lamps in kelvin, chosen by hand (the Mac cannot measure it); 0 = unknown.
    static let roomLampK = "lightRoomK"
    /// Lamp colour at work (-1 = same as the other one).
    static let roomLampKWork = "lightRoomKWork"
    /// The hand-drawn day of the "Custom" profile: 24 hourly kelvin values ("6500,6500,…").
    static let customCurve = "lightCustomCurve"
    /// The ready-made profile the drawn day was last started from (shown as a note; the chart is drawn above).
    static let customBase = "lightCustomBase"
}

/// Writes a colour temperature to every display through its gamma table (the public CoreGraphics
/// standard gamma-table route) and puts the system's colours back.
@MainActor
final class GammaDisplays {
    private struct Table { var r: [Float]; var g: [Float]; var b: [Float] }
    private var originals: [CGDirectDisplayID: Table] = [:]
    private(set) var unsupported: [String] = []

    private func activeDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }?.localizedName ?? "#\(id)"
    }

    /// Back to the system colours.
    func restore() {
        CGDisplayRestoreColorSyncSettings()
    }

    /// Reads the displays' own tables (calibration included) so that scaling keeps them.
    func refreshOriginals() {
        restore()
        knownDisplaySet = Set(activeDisplays())
        originals.removeAll()
        unsupported.removeAll()
        for id in activeDisplays() {
            let capacity = CGDisplayGammaTableCapacity(id)
            guard capacity > 0 else { unsupported.append(name(of: id)); continue }
            var r = [Float](repeating: 0, count: Int(capacity))
            var g = r, b = r
            var samples: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &samples) == .success, samples > 0 else {
                unsupported.append(name(of: id))
                continue
            }
            let n = Int(samples)
            originals[id] = Table(r: Array(r.prefix(n)), g: Array(g.prefix(n)), b: Array(b.prefix(n)))
        }
    }

    var ids: [CGDirectDisplayID] { Array(originals.keys) }

    /// Displays were plugged, unplugged or renumbered since the tables were read.
    private var knownDisplaySet: Set<CGDirectDisplayID> = []
    func displaySetChanged() -> Bool { Set(activeDisplays()) != knownDisplaySet }

    /// Display frames in the global space, for matching windows to displays.
    func frames() -> [DisplayFrame] {
        activeDisplays().map { DisplayFrame(id: $0, bounds: CGDisplayBounds($0)) }
    }

    func apply(kelvin: (CGDirectDisplayID) -> Double) {
        if originals.isEmpty { refreshOriginals() }
        for (id, table) in originals {
            let m = ColorTemperature.multipliers(kelvin: kelvin(id))
            let r = table.r.map { $0 * Float(m.r) }
            let g = table.g.map { $0 * Float(m.g) }
            let b = table.b.map { $0 * Float(m.b) }
            if CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b) != .success {
                if !unsupported.contains(name(of: id)) { unsupported.append(name(of: id)) }
            }
        }
    }
}

/// Screen colour that follows the sun, the clock and the wake-up time.
@MainActor
final class LightController: ObservableObject {
    static let shared = LightController()

    @Published private(set) var state: LightState?
    /// For the UI: follows `currentKelvin` in steps of 10 K, so a fade does not redraw the pane ten times a second.
    @Published private(set) var appliedKelvin = 6500.0
    /// What the screens show right now (changes every 0.25 s during a fade).
    private var currentKelvin = 6500.0 {
        didSet { if abs(currentKelvin - appliedKelvin) >= 10 { appliedKelvin = currentKelvin } }
    }
    @Published private(set) var nextEvent: SunEvent?
    @Published private(set) var locationNote = ""
    @Published private(set) var unsupportedDisplays: [String] = []
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var previewing = false
    /// The monitor whose evening look is being previewed, and the kelvin it shows meanwhile.
    @Published private(set) var previewingDisplay: CGDirectDisplayID?
    private var monitorPreviewKelvin = LightSettings.maxKelvin
    private var monitorPreviewTimer: Timer?
    @Published private(set) var lux: Double?
    @Published private(set) var ambientNote = ""
    @Published private(set) var point = GeoPoint(latitude: 52.2, longitude: 21.0)

    private let displays = GammaDisplays()
    private let defaults = UserDefaults.standard
    private let locationFetcher = LocationOneShot()
    private var tickTimer: Timer?
    private var fadeTimer: Timer?
    /// Colour change speed (K/s) of the general value and of each display, for the smooth fade.
    private var currentVelocity = 0.0
    private var shownVelocity: [CGDirectDisplayID: Double] = [:]
    /// A new set of neutral displays must hold this long before it is acted on (a flicker of the probe changes nothing).
    private var pendingNeutral: Set<UInt32>?
    private var pendingNeutralSince = Date.distantPast
    private var neutralRecheck: Timer?
    /// A switch (Light on or off, an exception) fades in the set number of seconds; the drift of the day itself
    /// follows slowly, at most `followRate` kelvin per minute.
    private var quickFade = false
    private var wasActive: Bool?
    private static let neutralHoldSeconds = 4.0
    private var previewTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var firstTick = true
    private var lastReapply = Date.distantPast
    private var requestedLocation = false
    /// What each display shows right now (kelvin); displays in `neutral` fade to 6500.
    private var shown: [CGDirectDisplayID: Double] = [:]
    /// Displays a full-screen window or an excluded app keeps neutral right now.
    private var windowNeutral: Set<UInt32> = []
    /// Neutral for any reason: that window, or the monitor's own "leave alone" switch.
    private var neutral: Set<UInt32> { windowNeutral.union(MonitorRegistry.shared.untouchedDisplays) }
    private var lastForeignFront: FrontWindow?
    private var frontTimer: Timer?
    /// The time zone's reference city, read from zone.tab once per zone.
    private var zoneCache: (zone: String, point: GeoPoint?)?

    // MARK: Settings

    var isEnabled: Bool { defaults.bool(forKey: LightKeys.enabled) }

    var profile: LightProfile {
        LightProfile(rawValue: defaults.string(forKey: LightKeys.profile) ?? "") ?? .recommended
    }

    /// Wake-up time; until the user sets it, an hour before work starts.
    var wakeMinutes: Int {
        if let v = defaults.object(forKey: LightKeys.wakeMinutes) as? Int { return v }
        let work = defaults.object(forKey: Keys.workStartMinutes) as? Int ?? 8 * 60
        return ((work - 60) + 1440) % 1440
    }

    /// The drawn day, when the Custom profile is chosen.
    var customCurve: CustomLightCurve? {
        profile.isCustom ? CustomLightCurve.decode(defaults.string(forKey: LightKeys.customCurve)) : nil
    }

    var settings: LightSettings {
        if let curve = customCurve { return curve.lightSettings(wakeMinutes: wakeMinutes, sunDriven: profile == .customSun) }
        return profile.settings(wakeMinutes: wakeMinutes).sanitized
    }

    /// The stored drawn day, whichever profile is chosen (nil until one was started).
    var customCurveStored: CustomLightCurve? {
        CustomLightCurve.decode(defaults.string(forKey: LightKeys.customCurve))
    }

    func saveCustomCurve(_ curve: CustomLightCurve) {
        defaults.set(curve.encoded, forKey: LightKeys.customCurve)
        tick()
    }

    /// The Custom profile starts from what another profile does today, so nothing jumps when it is chosen.
    func startCustomCurve(from base: LightProfile) {
        let curve = CustomLightCurve.sampled(settings: base.settings(wakeMinutes: wakeMinutes),
                                             latitude: point.latitude, longitude: point.longitude, date: Date())
        defaults.set(curve.encoded, forKey: LightKeys.customCurve)
        defaults.set(base.rawValue, forKey: LightKeys.customBase)
        tick()
    }

    /// The schedule's colour at a moment (without the room and weather adjustments).
    func scheduleState(at date: Date, point: GeoPoint, cloud: Double?) -> LightState {
        if let curve = customCurve {
            if profile == .customSun {
                return LightSchedule.sunDrivenState(at: date, latitude: point.latitude, longitude: point.longitude,
                                                    curve: curve, settings: settings, cloudCover: cloud)
            }
            return LightSchedule.state(at: date, latitude: point.latitude, longitude: point.longitude, curve: curve)
        }
        return LightSchedule.state(at: date, latitude: point.latitude, longitude: point.longitude,
                                   settings: settings, cloudCover: cloud, calendar: .current)
    }

    /// Even a value saved before the limit existed never gives a blink.
    static let minFadeSeconds = 8
    static let defaultFollowRate = 30

    private var followSpeed: Double {
        let rate = defaults.object(forKey: LightKeys.followRate) as? Int ?? Self.defaultFollowRate
        return Double(min(max(rate, 1), 600)) / 60
    }

    private var fadeSeconds: Double {
        Double(min(max(defaults.object(forKey: LightKeys.fadeSeconds) as? Int ?? 20, Self.minFadeSeconds), 120))
    }

    // MARK: Lifecycle

    /// Called once at launch. Always starts from the system colours, so a screen left tinted by an
    /// earlier crash is corrected here.
    func start() {
        displays.restore()
        MonitorRegistry.shared.refresh()
        installSignalHandlers()
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                LightLog.detail("event: screen parameters changed")
                MonitorRegistry.shared.refresh()
                self?.reapply(rereadOriginals: true)
                // A display that just appeared has no colour of its own yet: give it its goal, not the general one.
                self?.startFade(jump: true)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    LightLog.detail("event: \(name.rawValue)")
                    self?.reapply(rereadOriginals: true)
                }
            }
        }
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExclusions() }
        }
        // A window can go full screen or move to another display without an app switch.
        // Full-screen apps live in their own Space, so a Space change is the main signal; the slow timer
        // only catches a window moved to another display.
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExclusions() }
        }
        let front = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExclusions() }
        }
        front.tolerance = 3
        RunLoop.main.add(front, forMode: .common)
        frontTimer = front
        // A setting changed in the Settings window takes effect at once.
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
    }

    func shutdown() {
        fadeTimer?.invalidate()
        neutralRecheck?.invalidate()
        previewTimer?.invalidate()
        monitorPreviewTimer?.invalidate()
        displays.restore()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.displays.restore()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// A monitor's own settings changed: show them at once (no fade) and let the dimming follow.
    func monitorSettingsChanged() {
        LightLog.detail("event: a monitor's settings changed")
        startFade(jump: true)
        tick()
    }

    // MARK: Pause

    func disable(forMinutes minutes: Int) {
        defaults.set(Date().addingTimeInterval(Double(minutes) * 60).timeIntervalSince1970, forKey: LightKeys.disabledUntil)
        tick()
    }

    /// Pauses until the next sunrise.
    func disableUntilSunrise() {
        var event = nextEvent
        if event?.kind == .sunset, let sunset = event {
            event = LightSchedule.nextSunEvent(after: sunset.date.addingTimeInterval(60),
                                               latitude: point.latitude, longitude: point.longitude)
        }
        let until = event?.date ?? Date().addingTimeInterval(8 * 3600)
        defaults.set(until.timeIntervalSince1970, forKey: LightKeys.disabledUntil)
        tick()
    }

    func resumeNow() {
        defaults.removeObject(forKey: LightKeys.disabledUntil)
        tick()
    }

    func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: LightKeys.enabled)
        if on { defaults.removeObject(forKey: LightKeys.disabledUntil) }
        tick()
    }

    // MARK: Tick

    private var lastSettingsSignature = ""

    private func settingsChanged() {
        let signature = [LightKeys.enabled, LightKeys.profile, LightKeys.dayK, LightKeys.sunsetK, LightKeys.bedtimeK,
                         LightKeys.wakeMinutes, LightKeys.manualLocation, LightKeys.weather, LightKeys.disabledUntil,
                         LightKeys.ambient, LightKeys.roomLampK, LightKeys.roomLampKWork, LightKeys.customCurve, MonitorKeys.profiles]
            .map { "\(defaults.object(forKey: $0) ?? "")" }.joined(separator: "|")
        guard signature != lastSettingsSignature else { return }
        lastSettingsSignature = signature
        LightLog.detail("event: a Light setting changed")
        tick()
    }

    /// The Mac is in the work zone: the work-log zone matched, or Wi-Fi, VPN or the saved place from the break work zone.
    private static var atWork: Bool {
        WorkLogController.shared.zone.inZone || WorkDetector.shared.presencePlace != nil
    }

    /// Lamp colour for the place the Mac is in; the work value applies only when it was set (not -1).
    static func roomLampK(defaults: UserDefaults, atWork: Bool) -> Int {
        let work = defaults.object(forKey: LightKeys.roomLampKWork) as? Int ?? -1
        return atWork && work >= 0 ? work : defaults.integer(forKey: LightKeys.roomLampK)
    }

    func tick() {
        let now = Date()
        let until = defaults.double(forKey: LightKeys.disabledUntil)
        let paused = until > now.timeIntervalSince1970 ? Date(timeIntervalSince1970: until) : nil
        if paused != pausedUntil { pausedUntil = paused }

        let (resolved, note) = resolveLocation()
        let moved = resolved != point
        if moved { point = resolved }
        if locationNote != note { locationNote = note }
        if moved || nextEvent.map({ $0.date <= now }) ?? true {
            nextEvent = LightSchedule.nextSunEvent(after: now, latitude: resolved.latitude, longitude: resolved.longitude)
        }
        if profile.isCustom, customCurve == nil { startCustomCurve(from: .recommended) }
        let schedule = scheduleState(at: now, point: resolved, cloud: cloudCover())
        let measured = measureRoom()
        var current = schedule
        if let measured {
            let lamp = Self.roomLampK(defaults: defaults, atWork: Self.atWork)
            let kelvin = AmbientLight.adjustedKelvin(schedule.kelvin, lux: measured, settings: settings,
                                                     roomLampK: lamp > 0 ? Double(lamp) : nil)
            current = LightState(kelvin: kelvin, phase: schedule.phase, sunElevation: schedule.sunElevation)
        }
        LightLog.detail("tick: schedule \(Int(schedule.kelvin)) K (\(schedule.phase)), lux \(measured.map { String(Int($0)) } ?? "-"), goal \(Int(current.kelvin)) K, shown \(Int(currentKelvin)) K, paused \(pausedUntil != nil), neutral \(neutral.sorted())")
        if current != state { state = current }

        // Turning Light on or off, or pausing it, is a switch, not a drift.
        let active = isEnabled && pausedUntil == nil
        if let was = wasActive, was != active { quickFade = true }
        wasActive = active
        refreshExclusions(fade: false)
        startFade(jump: firstTick)
        let general = current.kelvin
        let lightSettings = settings
        BetterDisplayLight.shared.update(
            active: isEnabled && pausedUntil == nil && !previewing, neutral: neutral,
            untouched: MonitorRegistry.shared.untouchedDisplays,
            factorFor: { id in
                let profile = MonitorRegistry.shared.profile(forDisplay: CGDirectDisplayID(id))
                let own = MonitorLight.dimFactor(kelvin: general, settings: lightSettings,
                                                 globalPercent: BetterDisplayLight.shared.globalDimPercent, profile: profile)
                return AmbientLight.scaledDimFactor(own, lux: measured)
            })
        firstTick = false
    }

    /// Published only when it changed (each publish redraws the Light pane).
    private func showAmbient(lux newLux: Double?, note: String) {
        if lux != newLux { lux = newLux }
        if ambientNote != note { ambientNote = note }
    }

    /// The room's brightness from the Mac's sensor, when the user asks for it and the lid is open.
    private func measureRoom() -> Double? {
        guard isEnabled, defaults.bool(forKey: LightKeys.ambient) else {
            showAmbient(lux: nil, note: "")
            return nil
        }
        if profile == .custom {
            showAmbient(lux: nil, note: String(localized: "Profil „Własne (wg zegara)” nie korzysta z czujnika: wybierz „Własne (wg Słońca)” albo gotowy profil."))
            return nil
        }
        if AmbientSensor.lidClosed {
            AmbientSensor.shared.reset()
            showAmbient(lux: nil, note: String(localized: "Klapa zamknięta: czujnik nie widzi pokoju, działa sam harmonogram."))
            return nil
        }
        guard let value = AmbientSensor.shared.smoothedLux() else {
            showAmbient(lux: nil, note: String(localized: "Ten Mac nie udostępnia czujnika światła: działa sam harmonogram."))
            return nil
        }
        showAmbient(lux: value.rounded(), note: "")
        return value
    }

    /// Cloud cover from the weather the app already fetches, only when the user asks for it.
    private func cloudCover() -> Double? {
        guard defaults.bool(forKey: LightKeys.weather), isEnabled else { return nil }
        WeatherController.shared.refreshIfNeeded(ignoreSetting: true)
        guard let snapshot = WeatherController.shared.snapshot,
              Date().timeIntervalSince(snapshot.fetchedAt) < 3 * 3600 else { return nil }
        return snapshot.cloudCover
    }

    private func resolveLocation() -> (GeoPoint, String) {
        if let manual = defaults.string(forKey: LightKeys.manualLocation), !manual.isEmpty,
           let point = LightLocation.parse(manual) {
            return (point, String(localized: "wpisana ręcznie"))
        }
        func coordinate(_ key: String) -> Double? {
            if let v = defaults.object(forKey: key) as? Double { return v }
            if let s = defaults.string(forKey: key), let v = Double(s) { return v }
            return nil
        }
        if let lat = coordinate(GlassKeys.lat), let lon = coordinate(GlassKeys.lon) {
            return (GeoPoint(latitude: lat, longitude: lon), String(localized: "z lokalizacji Maca"))
        }
        requestLocationIfAllowed()
        let zone = TimeZone.current.identifier
        if zoneCache?.zone != zone {
            let table = (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) ?? ""
            zoneCache = (zone, LightLocation.fromZoneTab(zoneID: zone, table: table))
        }
        if let point = zoneCache?.point {
            return (point, String(localized: "przybliżona, ze strefy czasowej \(zone)"))
        }
        return (GeoPoint(latitude: 0, longitude: 0), String(localized: "nieznana (wpisz współrzędne)"))
    }

    /// Only when the system already allows it: this never opens a permission prompt.
    private func requestLocationIfAllowed() {
        guard !requestedLocation else { return }
        guard PermissionCenter.location(CLLocationManager().authorizationStatus) == .granted else { return }
        requestedLocation = true
        locationFetcher.onLocation = { [weak self] lat, lon in
            Task { @MainActor in
                self?.defaults.set(lat, forKey: GlassKeys.lat)
                self?.defaults.set(lon, forKey: GlassKeys.lon)
                self?.tick()
            }
        }
        locationFetcher.requestOnce()
    }

    // MARK: Applying

    /// What the screens should show when nothing is excluded.
    private func rawGlobalGoal() -> Double {
        (isEnabled && pausedUntil == nil) ? (state?.kelvin ?? LightSettings.maxKelvin) : LightSettings.maxKelvin
    }

    /// The goal moves only when the raw one is clearly elsewhere: the room-light sensor and the slow schedule
    /// wobble by a few dozen kelvin, which the eye cannot see but a redraw can make blink.
    private static let goalDeadband = 40.0
    private var steadyGoal: Double?

    private func globalGoal() -> Double {
        let raw = rawGlobalGoal()
        if let steady = steadyGoal, abs(raw - steady) < Self.goalDeadband, raw < LightSettings.maxKelvin - 0.5 {
            return steady
        }
        if steadyGoal != raw { LightLog.detail("goal: \(steadyGoal.map { String(Int($0)) } ?? "-") -> \(Int(raw)) K") }
        steadyGoal = raw
        return raw
    }

    private func goal(for id: CGDirectDisplayID) -> Double {
        if id == previewingDisplay { return monitorPreviewKelvin }
        if windowNeutral.contains(id) { return LightSettings.maxKelvin }
        return MonitorLight.kelvin(global: globalGoal(), profile: MonitorRegistry.shared.profile(forDisplay: id))
    }

    /// Moves every display to its goal in steps, so that the screen never jumps.
    private func startFade(jump: Bool) {
        if jump || displays.ids.isEmpty {
            steadyGoal = nil
            quickFade = false
            currentKelvin = globalGoal()
            appliedKelvin = currentKelvin
            currentVelocity = 0
            shownVelocity.removeAll()
            displays.ids.forEach { shown[$0] = goal(for: $0) }
            applyNow(force: true, reason: "jump")
            return
        }
        guard fadeTimer == nil else { return }
        let dt = 0.1
        LightLog.detail("fade start: \(quickFade ? "quick" : "slow"), from \(Int(currentKelvin)) K to \(Int(globalGoal())) K")
        // The spring covers most of the way in about a third of the set time and settles gently.
        let timer = Timer(timeInterval: dt, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                // Read each step: a switch can arrive while a slow drift is under way.
                let quick = self.quickFade
                let smoothTime = quick ? self.fadeSeconds / 3 : 20
                let maxSpeed = quick ? Double.infinity : self.followSpeed
                var moving = self.glide(&self.currentKelvin, &self.currentVelocity, to: self.globalGoal(),
                                        smoothTime: smoothTime, maxSpeed: maxSpeed, dt: dt)
                for id in self.displays.ids {
                    var value = self.shown[id] ?? self.currentKelvin
                    var velocity = self.shownVelocity[id] ?? 0
                    if self.glide(&value, &velocity, to: self.goal(for: id), smoothTime: smoothTime, maxSpeed: maxSpeed, dt: dt) { moving = true }
                    self.shown[id] = value
                    self.shownVelocity[id] = velocity
                }
                self.applyNow()
                if !moving {
                    t.invalidate()
                    self.fadeTimer = nil
                    LightLog.detail("fade end at \(Int(self.currentKelvin)) K")
                    self.quickFade = false
                    self.appliedKelvin = self.currentKelvin
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    /// One smooth step toward `target`; returns whether it is still on the way.
    private func glide(_ value: inout Double, _ velocity: inout Double, to target: Double,
                       smoothTime: Double, maxSpeed: Double, dt: Double) -> Bool {
        if SmoothDamp.settled(value: value, target: target, velocity: velocity) {
            value = target
            velocity = 0
            return false
        }
        value = SmoothDamp.step(value: value, target: target, velocity: &velocity, smoothTime: smoothTime, dt: dt,
                                maxSpeed: maxSpeed)
        return true
    }

    /// What was last written to the displays (kelvin in 10 K steps) and when: the same colour is not written
    /// again (each write can make a display blink), except as a reminder every 30 s in case macOS reset it.
    private var lastWritten: [CGDirectDisplayID: Int] = [:]
    private var lastWriteDate = Date.distantPast

    private func applyNow(force: Bool = false, reason: String = "fade") {
        let wanted = Dictionary(uniqueKeysWithValues: displays.ids.map { ($0, Int(((shown[$0] ?? currentKelvin) / 10).rounded())) })
        let unchanged = wanted == lastWritten
        if !force, unchanged, Date().timeIntervalSince(lastWriteDate) < 30 { return }
        let why = force ? reason : (unchanged ? "30 s reminder" : reason)
        LightLog.detail("write (\(why)): \(wanted.sorted { $0.key < $1.key }.map { "#\($0.key)=\($0.value * 10) K" }.joined(separator: " "))")
        lastWritten = wanted
        lastWriteDate = Date()
        let anyTint = displays.ids.contains { (shown[$0] ?? currentKelvin) < LightSettings.maxKelvin - 0.5 }
        if !anyTint && !isEnabled && !previewing {
            displays.restore()
        } else {
            displays.apply(kelvin: { [shown, currentKelvin] in shown[$0] ?? currentKelvin })
        }
        if displays.unsupported != unsupportedDisplays { unsupportedDisplays = displays.unsupported }
    }

    // MARK: Exceptions

    /// Looks at the active window: an excluded app, or a full-screen window, keeps its own display neutral.
    func refreshExclusions(fade: Bool = true) {
        guard isEnabled, pausedUntil == nil, !previewing else {
            if !windowNeutral.isEmpty { windowNeutral = []; if fade { startFade(jump: false) } }
            return
        }
        let excluded = KeepAwakeApps.list(fromCommaText: defaults.string(forKey: LightKeys.excludedApps) ?? "")
        let skipFullscreen = defaults.object(forKey: LightKeys.skipFullscreen) as? Bool ?? true
        guard skipFullscreen || !excluded.isEmpty else {
            // Nothing to look for: no window list at all.
            if !windowNeutral.isEmpty { windowNeutral = []; if fade { startFade(jump: false) } }
            return
        }
        let probe = FrontWindowProbe.current()
        if case .own = probe {} else if case .window(let window) = probe { lastForeignFront = window } else { lastForeignFront = nil }
        let next = LightExclusion.displaysToLeaveNeutral(front: lastForeignFront, displays: displays.frames(),
                                                         excludedApps: excluded, skipFullscreen: skipFullscreen)
        guard next != windowNeutral else {
            pendingNeutral = nil
            return
        }
        // Inertia: act only on a state that has held for a few seconds, so a window that flickers in the
        // probe (a Space switch, a full-screen transition) does not tint and un-tint the screen.
        if pendingNeutral != next {
            pendingNeutral = next
            pendingNeutralSince = Date()
            LightLog.detail("neutral displays candidate \(next.sorted()) (now \(windowNeutral.sorted())), waiting \(Int(Self.neutralHoldSeconds)) s")
        }
        let waited = Date().timeIntervalSince(pendingNeutralSince)
        guard waited >= Self.neutralHoldSeconds else {
            scheduleNeutralRecheck(after: Self.neutralHoldSeconds - waited + 0.3)
            return
        }
        pendingNeutral = nil
        windowNeutral = next
        quickFade = true
        LightLog.event("neutral displays \(next.sorted())")
        if fade { startFade(jump: false) }
    }

    private func scheduleNeutralRecheck(after seconds: TimeInterval) {
        neutralRecheck?.invalidate()
        neutralRecheck = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshExclusions() }
        }
    }

    /// After wake-up, a changed display set or a Space change some apps and drivers reset the tables.
    private func reapply(rereadOriginals: Bool) {
        guard Date().timeIntervalSince(lastReapply) > 2 else { return }
        lastReapply = Date()
        // Reading the tables resets the screen to its own colours for a moment, so it is done only when the
        // set of displays changed; waking up or changing Space just puts our colour back.
        if rereadOriginals && displays.displaySetChanged() {
            Trace.log("light: displays changed, reading their tables again")
            displays.refreshOriginals()
        }
        if isEnabled || previewing { applyNow(force: true, reason: "put back after wake, Space or display change") }
    }

    // MARK: Preview

    /// A 12-second sweep through today (like Nightglow's "Preview 24 hours"), started by a click.
    func previewDay() {
        guard !previewing else { return }
        let (point, _) = resolveLocation()
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        previewing = true
        let began = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                let progress = Date().timeIntervalSince(began) / 12
                if progress >= 1 {
                    self.stopPreview()
                    return
                }
                let moment = start.addingTimeInterval(progress * 86_400)
                let k = self.scheduleState(at: moment, point: point, cloud: nil).kelvin
                self.currentKelvin = k
                let shownKelvin = { (id: CGDirectDisplayID) in
                    MonitorLight.kelvin(global: k, profile: MonitorRegistry.shared.profile(forDisplay: id))
                }
                self.displays.ids.forEach { self.shown[$0] = shownKelvin($0) }
                self.displays.apply(kelvin: shownKelvin)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        previewTimer = timer
    }

    /// Shows one monitor the way it will look at its warmest for a few seconds (colour at once, brightness
    /// when BetterDisplay dims). A monitor that is left alone, or a running day preview, makes it a no-op.
    func previewMonitor(displayID: CGDirectDisplayID, seconds: Double = 6) {
        let profile = MonitorRegistry.shared.profile(forDisplay: displayID)
        guard previewingDisplay == nil, !previewing, profile?.untouched != true, displays.ids.contains(displayID) else { return }
        let evening = settings
        previewingDisplay = displayID
        monitorPreviewKelvin = MonitorLight.kelvin(global: evening.bedtimeK, profile: profile)
        shown[displayID] = monitorPreviewKelvin
        applyNow(force: true)
        let factor = MonitorLight.dimFactor(kelvin: evening.bedtimeK, settings: evening,
                                            globalPercent: BetterDisplayLight.shared.globalDimPercent, profile: profile)
        Task { await BetterDisplayLight.shared.previewDim(displayID: Int(displayID), factor: factor, seconds: seconds) }
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopMonitorPreview() }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorPreviewTimer = timer
    }

    private func stopMonitorPreview() {
        monitorPreviewTimer?.invalidate()
        monitorPreviewTimer = nil
        previewingDisplay = nil
        startFade(jump: true)
    }

    func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewing = false
        startFade(jump: true)
    }
}

/// The active window of the frontmost app, read from the window list (no Screen Recording needed for
/// owner and bounds).
enum FrontWindowProbe {
    enum Result {
        /// Our own window is in front (Settings, break screen): keep what was known.
        case own
        case none
        case window(FrontWindow)
    }

    static func current() -> Result {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .none }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return .own }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return .none }
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            let names = [app.localizedName, app.executableURL?.lastPathComponent,
                         app.bundleURL?.deletingPathExtension().lastPathComponent].compactMap { $0 }
            return .window(FrontWindow(appNames: names, bounds: rect))
        }
        return .none
    }
}
