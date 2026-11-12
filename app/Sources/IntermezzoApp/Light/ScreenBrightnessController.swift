import AppKit
import CoreGraphics
import IntermezzoKit

enum BrightnessKeys {
    /// The brightness equaliser is on (off by default: nothing changes for existing users).
    static let enabled = "lightBrightnessEQ"
    /// Brightness for each hour of the day, 24 percentages ("100,100,…").
    static let dayCurve = "lightBrightnessCurve"
    /// How the room's light scales it, one percentage per band of `LuxBrightnessCurve.luxPoints`.
    static let luxCurve = "lightLuxCurve"
    /// This Mac only (see SyncPolicy): the built-in screen's brightness before the equaliser touched it and the
    /// value the equaliser set last (`SavedBrightness`; older versions stored just the number).
    static let builtInOriginal = "lightBuiltInOriginal"
    /// The nits mode: the monitors follow the luminance of the built-in screen, which macOS drives.
    static let automatic = "lightBrightnessAuto"
}

/// The brightness equaliser: works out the level from the hour and the room, glides the built-in screen
/// to it through DisplayServices and tells the BetterDisplay pass what external monitors should get.
/// Like the evening dimming it remembers the original brightness, gives it back when switched off, paused
/// or at quit, and steps aside for an hour when the user moves the brightness by hand.
@MainActor
final class ScreenBrightnessController: ObservableObject {
    static let shared = ScreenBrightnessController()

    /// The level the equaliser wants right now (nil while it is not active), for the Settings pane.
    @Published private(set) var level: Double?
    @Published private(set) var builtInNote = ""

    private let defaults = UserDefaults.standard
    private let display = BuiltInDisplay.shared
    /// What the equaliser wrote last; kept in UserDefaults at the end of each glide (see `persist`).
    private var lastSet: Double?
    /// For the hand-over from the evening dimming: the equaliser's own last write is no manual change.
    var lastWritten: Double? { lastSet }
    private var heldSince: Date?
    private var target: Double?
    /// Gliding back to the original brightness; the original is forgotten once there.
    private var restoring = false
    private var rampTimer: Timer?
    private var rampSteps = 0
    /// One second of a glide.
    private static let persistEverySteps = 10
    private static let rampInterval = 0.1
    /// At most this much per second: a 20 % change takes about 7 s, a full sweep about half a minute.
    private static let rampSpeed = 0.03
    /// Smaller changes of the goal are not acted on (the sensor wobbles).
    private static let deadband = 0.01

    private init() {
        lastSet = SavedBrightness(plist: UserDefaults.standard.object(forKey: BrightnessKeys.builtInOriginal))?.lastSet
    }

    var isEnabled: Bool { defaults.bool(forKey: BrightnessKeys.enabled) }

    var dayCurve: BrightnessDayCurve {
        BrightnessDayCurve.decode(defaults.string(forKey: BrightnessKeys.dayCurve)) ?? .standard
    }

    var luxCurve: LuxBrightnessCurve {
        LuxBrightnessCurve.decode(defaults.string(forKey: BrightnessKeys.luxCurve)) ?? .standard
    }

    func save(_ curve: BrightnessDayCurve) {
        defaults.set(curve.encoded, forKey: BrightnessKeys.dayCurve)
    }

    func save(_ curve: LuxBrightnessCurve) {
        defaults.set(curve.encoded, forKey: BrightnessKeys.luxCurve)
    }

    private var saved: SavedBrightness? {
        SavedBrightness(plist: defaults.object(forKey: BrightnessKeys.builtInOriginal))
    }

    private var original: Double? {
        get { saved?.original }
        set { store(newValue.map { SavedBrightness(original: $0, lastSet: lastSet) }) }
    }

    /// Writes the original with the last value set (only when it changed: every write wakes all observers).
    private func persist() {
        guard let original else { return }
        store(SavedBrightness(original: original, lastSet: lastSet))
    }

    private func store(_ next: SavedBrightness?) {
        guard next != saved else { return }
        if let next { defaults.set(next.plist, forKey: BrightnessKeys.builtInOriginal) } else {
            defaults.removeObject(forKey: BrightnessKeys.builtInOriginal)
        }
    }

    /// After the screens wake or change, the panel may come back at another level: what we set last no longer
    /// tells a manual change apart, so the next comparison is skipped (no hold is started for it) and the next
    /// reading becomes the last value (see `drive`). Only the in-memory value is dropped: the saved one still
    /// guards a restore after a restart until a fresh one is written.
    func displaysChanged() {
        guard lastSet != nil else { return }
        LightLog.detail("brightness: displays woke or changed, last value forgotten")
        lastSet = nil
    }

    /// The evening dimming lets go of the built-in screen and hands over its original (it may already be dimmed
    /// when the equaliser first read it).
    func adopt(original handedOver: Double) {
        guard let next = BrightnessHandover.adopted(own: original, handedOver: handedOver), next != original else { return }
        LightLog.detail("brightness: built-in original \(String(format: "%.3f", next)) handed over by the evening dimming")
        original = next
    }

    /// What the light schedule hands to the BetterDisplay pass.
    struct Plan {
        /// The equaliser is active (it replaces the evening dimming).
        let equalizer: Bool
        /// A display's goal, or nil when it is not the equaliser's (the evening dimming decides then).
        let goal: (UInt32) -> DisplayBrightnessGoal?
    }

    /// What one display gets now, for the monitor rows in Settings.
    struct DisplayStatus: Equatable {
        let level: Double?
        let kind: PeerBrightness.Kind
        /// An exception (full-screen window, excluded app) keeps it as it is for now.
        let heldByException: Bool
    }

    /// Per display, while the equaliser is active.
    @Published private(set) var statuses: [CGDirectDisplayID: DisplayStatus] = [:]
    /// The built-in screen's SDR white in nits and the maximum used for it, while the nits mode is on.
    @Published private(set) var builtInNits: Double?
    @Published private(set) var builtInMaxNits: Double?

    /// The nits mode: macOS drives the built-in screen, the monitors follow its luminance.
    var isAutomatic: Bool { isEnabled && defaults.bool(forKey: BrightnessKeys.automatic) }

    /// Called from the light schedule every 30 s. Returns each display's goal for the BetterDisplay pass; while the
    /// equaliser is off only the built-in screen can still be its own (until its original brightness is back).
    /// `frozen`: a preview is running, nothing is moved. `leftAlone`: displays the user or an exception keeps as they are.
    func update(lightEnabled: Bool, paused: Bool, frozen: Bool, lux: Double?, leftAlone: Set<UInt32>,
                now: Date = Date()) -> Plan {
        let active = lightEnabled && !paused && isEnabled
        let base = active
            ? ScreenBrightness.level(minuteOfDay: ScreenBrightness.minuteOfDay(now), lux: lux, day: dayCurve, room: luxCurve)
            : nil
        if level != base { level = base }
        let builtInID = display.displayID
        let automatic = active && isAutomatic
        let reference = automatic ? readReference(builtInID) : nil
        guard let base else {
            publish(statuses: [:])
            // Only switching the feature off ends a manual hold; a pause keeps it (see ManualHold).
            if !lightEnabled || !isEnabled { heldSince = nil }
            if !frozen, let builtInID { restore(id: builtInID) }
            showNote("")
            // Still giving the built-in screen back: the evening dimming must not read or drive it meanwhile.
            let keeps = BrightnessHandover.keepsBuiltIn(equalizerActive: false, hasOriginal: original != nil, restoring: restoring)
            let kept = keeps ? builtInID : nil
            return Plan(equalizer: false, goal: { id in CGDirectDisplayID(id) == kept ? .elsewhere : nil })
        }
        let resolve = resolver(base: base, automatic: automatic, builtInID: builtInID, nits: reference)
        let registry = MonitorRegistry.shared
        publish(statuses: Dictionary(registry.groups.flatMap(\.displayIDs).map { id in
            let r = resolve(id)
            return (id, DisplayStatus(level: r.goal.wanted(original: 1), kind: r.kind, heldByException: leftAlone.contains(id)))
        }, uniquingKeysWith: { first, _ in first }))
        showNote(automaticNote(automatic: automatic, builtInID: builtInID, nits: reference))
        // DisplayServices (or, in the nits mode, macOS) owns the built-in screen: BetterDisplay forgets it
        // without writing, so two mechanisms never drive it at once.
        let ownedBuiltIn = builtInID.flatMap { display.brightness(of: $0) != nil ? $0 : nil }
        if !frozen, let id = builtInID {
            if case .level(let wanted) = resolve(id).goal, !leftAlone.contains(id) {
                drive(id: id, to: wanted, now: now)
            } else {
                restore(id: id)
            }
        }
        return Plan(equalizer: true, goal: { id in
            CGDirectDisplayID(id) == ownedBuiltIn ? .elsewhere : resolve(CGDirectDisplayID(id)).goal
        })
    }

    private func resolver(base: Double, automatic: Bool, builtInID: CGDirectDisplayID?,
                          nits: Double?) -> (CGDirectDisplayID) -> PeerBrightness.Resolution {
        let registry = MonitorRegistry.shared
        return { id in
            let detected = registry.key(ofDisplay: id).flatMap { DisplayEDID.shared.maxNits(for: $0) }
            return PeerBrightness.resolve(isBuiltIn: id == builtInID, profile: registry.profile(forDisplay: id),
                                          automatic: automatic, equalizerLevel: base, builtInNits: nits,
                                          detectedMaxNits: detected)
        }
    }

    /// The built-in screen's luminance, the reference of the nits mode (nil with the lid closed or without a reading).
    private func readReference(_ builtInID: CGDirectDisplayID?) -> Double? {
        guard let id = builtInID else {
            publishNits(nil, max: nil)
            return nil
        }
        let manual = MonitorRegistry.shared.profile(forDisplay: id)?.maxNits.map(Double.init)
        let reading = display.sdrNits(of: id, manualMax: manual)
        publishNits(reading.nits, max: reading.maxNits)
        return reading.nits
    }

    private func automaticNote(automatic: Bool, builtInID: CGDirectDisplayID?, nits: Double?) -> String {
        guard automatic else {
            return builtInID == nil
                ? String(localized: "Wbudowany ekran jest wyłączony (np. zamknięta klapa): jasność zmieniam tylko na monitorach przez BetterDisplay.")
                : ""
        }
        if builtInID == nil {
            return AmbientSensor.lidClosed
                ? String(localized: "Klapa zamknięta: brak odniesienia dla automatu, monitory wracają do korektora.")
                : String(localized: "Ten Mac nie ma wbudowanego ekranu: automat (nity) jest niedostępny, monitory używają korektora.")
        }
        return nits == nil
            ? String(localized: "Nie mogę odczytać jasności wbudowanego ekranu: monitory używają korektora.")
            : ""
    }

    private func publish(statuses next: [CGDirectDisplayID: DisplayStatus]) {
        if statuses != next { statuses = next }
    }

    private func publishNits(_ nits: Double?, max: Double?) {
        let rounded = nits.map { $0.rounded() }
        if builtInNits != rounded { builtInNits = rounded }
        if builtInMaxNits != max { builtInMaxNits = max }
    }

    private func showNote(_ text: String) {
        if builtInNote != text { builtInNote = text }
    }

    private func drive(id: CGDirectDisplayID, to wanted: Double, now: Date) {
        guard let current = display.brightness(of: id) else {
            showNote(String(localized: "Ten Mac nie pozwala zmieniać jasności wbudowanego ekranu: działa tylko na monitorach przez BetterDisplay."))
            return
        }
        if ScreenBrightness.holding(since: heldSince, now: now) {
            showNote(String(localized: "Jasność wbudowanego ekranu zmieniono ręcznie: wracam do korektora po godzinie."))
            return
        }
        heldSince = nil
        if let lastSet, EveningDimming.userChanged(current: current, lastSet: lastSet) {
            yield(at: now)
            return
        }
        restoring = false
        if original == nil {
            original = current
            LightLog.detail("brightness: built-in original \(String(format: "%.3f", current))")
        }
        if lastSet == nil {
            // After a wake-up (or the first time) the reading itself is the reference from now on.
            lastSet = BrightnessHandover.lastSetAfterCheck(lastSet: lastSet, current: current)
            persist()
        }
        guard abs(wanted - (lastSet ?? current)) >= Self.deadband || (target != nil && rampTimer != nil) else { return }
        target = wanted
        startRamp(id: id)
    }

    /// Someone moved the brightness: keep off it for a while, and let their value be the new original.
    private func yield(at now: Date) {
        LightLog.event("brightness: built-in changed by hand, holding for \(Int(ScreenBrightness.manualHoldSeconds / 60)) min")
        stopRamp()
        heldSince = now
        lastSet = nil
        target = nil
        original = nil
        restoring = false
        showNote(String(localized: "Jasność wbudowanego ekranu zmieniono ręcznie: wracam do korektora po godzinie."))
    }

    /// Glides back to the brightness the screen had before (unless the user changed it meanwhile).
    /// A manual hold is left running: an exception, a pause or a preview must not end it.
    private func restore(id: CGDirectDisplayID) {
        guard let original else {
            stopRamp()
            lastSet = nil
            target = nil
            return
        }
        // The saved last value also covers a restart: a screen moved by hand since then keeps its value.
        if !restoring, let current = display.brightness(of: id),
           !SavedBrightness(original: original, lastSet: lastSet).mayRestore(current: current) {
            forget()
            return
        }
        if !restoring { LightLog.detail("brightness: giving the built-in screen back \(String(format: "%.3f", original))") }
        restoring = true
        target = original
        startRamp(id: id)
    }

    private func forget() {
        stopRamp()
        original = nil
        lastSet = nil
        target = nil
        restoring = false
    }

    private func startRamp(id: CGDirectDisplayID) {
        guard rampTimer == nil else { return }
        let timer = Timer(timeInterval: Self.rampInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rampStep(id: id) }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
        rampSteps = 0
        persist()
    }

    private func stopRamp() {
        guard let timer = rampTimer else { return }
        timer.invalidate()
        rampTimer = nil
        persist()
    }

    private func rampStep(id: CGDirectDisplayID) {
        guard let target, let current = display.brightness(of: id) else {
            stopRamp()
            return
        }
        if let lastSet, EveningDimming.userChanged(current: current, lastSet: lastSet) {
            restoring ? forget() : yield(at: Date())
            return
        }
        let next = ScreenBrightness.ramp(from: lastSet ?? current, to: target, maxStep: Self.rampSpeed * Self.rampInterval)
        guard display.setBrightness(next, of: id) else {
            stopRamp()
            return
        }
        lastSet = next
        rampSteps += 1
        // Saved now and then during a glide too (a crash mid-way still leaves a usable last value).
        if rampSteps % Self.persistEverySteps == 0 { persist() }
        guard abs(next - target) < 0.001 else { return }
        stopRamp()
        if restoring { forget() }
    }

    /// At quit: give the original brightness back at once.
    func shutdown() {
        stopRamp()
        guard let original, let id = display.displayID else { return }
        if let current = display.brightness(of: id),
           !SavedBrightness(original: original, lastSet: lastSet).mayRestore(current: current) {
            self.original = nil
            return
        }
        // When the write fails the original is kept, so the next launch can still give it back.
        guard display.setBrightness(original, of: id) else { return }
        self.original = nil
    }
}
