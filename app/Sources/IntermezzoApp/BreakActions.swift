import AppKit
import AVFoundation
import NaturalLanguage
import IntermezzoKit

// MARK: - Break Action execution (Actions page backend).
//
// Actions scheduled at
// three timing points — Before Due (offset), After Start, After Any End
// (completed OR skipped). Everything runs fire-and-forget off the main
// actor's clock; a failing action must never disturb the break.

@MainActor
final class BreakActionController {

    private var items: [BreakActionItem] = []
    /// Before Due fires once per approaching break (see ApproachLatch).
    private var beforeDue = ApproachLatch<UUID>()
    private var playingSounds: [NSSound] = []
    private var rememberedVolume: (percent: Int, muted: Bool)?
    private var musicWasPlayingByUs = false

    private let notify: (String, String) -> Void
    private let flashPulse: (String) -> Void

    init(notify: @escaping (String, String) -> Void,
         flashPulse: @escaping (String) -> Void) {
        self.notify = notify
        self.flashPulse = flashPulse
    }

    // MARK: Heartbeat

    /// Before-Due point: fires each enabled action once per approaching break.
    func tick(now: Date, timeUntilBreak: TimeInterval?, onBreak: Bool, paused: Bool) {
        items = loadItems()
        guard !onBreak, !paused else { return }
        for item in items where item.enabled && item.kind != .fadeoutSound {
            guard item.when == .beforeDue else { continue }
            guard beforeDue.enter(item.id, timeLeft: timeUntilBreak,
                                  window: TimeInterval(item.offsetSeconds)) else { continue }
            let offset = TimeInterval(item.offsetSeconds)
            let lead = max(0, (timeUntilBreak ?? 0))
            schedule(after: max(0, offset - lead)) { [weak self] in
                self?.fire(item)
            }
        }
    }

    /// After Start point: fire matching actions now, the After-Fade-In ones
    /// once the overlay has fully faded in, honoring their offset.
    func breakDidStart() {
        items = loadItems()
        beforeDue.reset()
        Trace.log("breakDidStart: \(items.count) action(s)")
        for item in items where item.enabled && item.when == .afterStart {
            schedule(after: TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                self?.fire(item)
            }
        }
        for item in items where item.enabled && item.when == .afterFadeIn {
            schedule(after: breakFadeDuration + TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                self?.fire(item)
            }
        }
    }

    /// End of a break. `completed` distinguishes natural finish from
    /// postpone/skip — Before Fade Out fires on both, Before/After Finish
    /// only on completion, After Postpone only on a skipped break, and
    /// After Any End on both.
    func breakDidEnd(completed: Bool) {
        items = loadItems()
        Trace.log("breakDidEnd(completed=\(completed)): \(items.count) action(s)")
        for item in items where item.enabled {
            switch item.when {
            case .beforeFadeOut:
                schedule(after: TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                    self?.fire(item)
                }
            case .beforeFinish, .afterFinish:
                guard completed else { continue }
                schedule(after: breakFadeDuration + TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                    self?.fire(item)
                }
            case .afterPostpone:
                guard !completed else { continue }
                schedule(after: breakFadeDuration + TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                    self?.fire(item)
                }
            case .afterAnyEnd:
                schedule(after: breakFadeDuration + TimeInterval(max(0, item.offsetSeconds))) { [weak self] in
                    self?.fire(item)
                }
            default:
                break
            }
        }
        // A finished break arms the before-due window for the next cycle.
        beforeDue.reset()
    }

    /// Fire every enabled action registered at one timing point right away
    /// (used by the Rules engine when a rule skips a break → afterPostpone).
    func fireNow(when point: BreakActionWhen) {
        for item in loadItems() where item.enabled && item.when == point {
            fire(item)
        }
    }

    /// When Button Clicked point: the control panel calls this for its
    /// custom buttons; only `buttonClicked` actions matching the title run.
    func fireButtonAction(title: String) {
        items = loadItems()
        for item in items where item.enabled && item.when == .buttonClicked && item.title == title {
            fire(item)
        }
    }

    // MARK: Scheduling

    private func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { work() }
        }
    }

    // MARK: Firing

    /// tick() runs every second; decode only when the stored JSON changed.
    private var cachedRaw: Data?
    private var cachedItems: [BreakActionItem] = []

    private func loadItems() -> [BreakActionItem] {
        let raw = UserDefaults.standard.data(forKey: BreakActionStore.storageKey)
        if let raw, raw == cachedRaw { return cachedItems }
        let items = decodeItems(raw)
        cachedRaw = raw
        cachedItems = items
        return items
    }

    private func decodeItems(_ raw: Data?) -> [BreakActionItem] {
        guard let data = raw, !data.isEmpty else {
            Trace.log("loadItems: NO DATA for \(BreakActionStore.storageKey) (bundleID=\(Bundle.main.bundleIdentifier ?? "?") keyPresent=\(UserDefaults.standard.dictionaryRepresentation().keys.contains(BreakActionStore.storageKey)))")
            return []
        }
        do {
            return try JSONDecoder().decode([BreakActionItem].self, from: data)
        } catch {
            Trace.log("break actions decode FAILED: \(error)")
            return []
        }
    }

    private func fire(_ item: BreakActionItem) {
        Trace.log("FIRE kind=\(item.kind.rawValue) when=\(item.when.rawValue) mode=\(item.volumeMode)")
        switch item.kind {
        case .notification:
            notify(item.title, item.message)

        case .playSound:
            playSound(item)

        case .fadeoutSound:
            fadeOutAll(seconds: max(1, item.fadeSeconds))

        case .flashScreen:
            flashPulse(item.colorHex)

        case .speakText:
            speak(item.speakText)

        case .soundVolume:
            runVolumeAction(item)

        case .musicPause:
            musicPause()

        case .musicPlay:
            musicPlay()

        case .logDrink:
            HydrationStore.record(kind: item.drinkKind, ml: item.amountMl)
            HealthKitLogger.shared.logDrink(kind: item.drinkKind, ml: item.amountMl)
            // Widoczny feedback na overlayu: co i ile zapisano + stan dzienny.
            let summary = HydrationStore.todaySummary()
            let drink = L(item.drinkKind)
            let kinds = summary.byKind.map { "\(L($0.0)) \($0.1) ml" }.joined(separator: ", ")
            NotificationCenter.default.post(name: Notification.Name("IntermezzoDrinkLogged"),
                                          object: nil,
                                          userInfo: ["text": String(localized: "Zapisano \(item.amountMl) ml \(drink) · dziś \(summary.totalMl) ml (\(kinds))")])
            notify("Nawodnienie", "\(item.amountMl) ml: \(drink)")

        case .script:
            runScript(item.scriptPath)
        }
    }

    /// "Stop Sound": silence every sound we started (Play Sound actions).
    func stopAllSounds() {
        let sounds = playingSounds
        playingSounds.removeAll()
        sounds.forEach { $0.stop() }
        if let synth = speechSynthesizer, synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    // MARK: Sounds

    private func playSound(_ item: BreakActionItem) {
        let path = (item.soundName as NSString).expandingTildeInPath
        let sound: NSSound?
        if FileManager.default.fileExists(atPath: path) {
            sound = NSSound(contentsOfFile: path, byReference: true)
        } else {
            sound = NSSound(named: NSSound.Name(item.soundName))
        }
        guard let sound else { return }
        sound.volume = Float(min(100, max(0, item.volumePercent))) / 100.0
        if sound.play() { playingSounds.append(sound) }
    }

    /// Gentle fade: step every tracked sound's volume down, then stop it.
    private func fadeOutAll(seconds: Int) {
        let sounds = playingSounds
        playingSounds.removeAll()
        guard !sounds.isEmpty else { return }
        let steps = max(4, seconds * 5)
        let perStep = TimeInterval(seconds) / Double(steps)
        for sound in sounds {
            let start = sound.volume
            var step = 0
            Timer.scheduledTimer(withTimeInterval: perStep, repeats: true) { t in
                step += 1
                let frac = 1.0 - Double(step) / Double(steps)
                sound.volume = max(0, start * Float(frac))
                if step >= steps || frac <= 0 {
                    t.invalidate()
                    sound.stop()
                }
            }
        }
    }

    // MARK: Speech

    private var speechSynthesizer: AVSpeechSynthesizer?

    private func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let utter = AVSpeechUtterance(string: text)
        utter.rate = 0.45
        // The text is typed by the user in any language: pick the voice from the text itself.
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "pl"
        utter.voice = AVSpeechSynthesisVoice(language: language == "en" ? "en-US" : "pl-PL")
        let synth = speechSynthesizer ?? AVSpeechSynthesizer()
        speechSynthesizer = synth
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(utter)
    }

    // MARK: System volume (AppleScript; fire-and-forget)

    private func runVolumeAction(_ item: BreakActionItem) {
        switch item.volumeMode {
        case "mute":
            // Read first, remember, THEN mute — otherwise we would remember
            // the already-muted state and "restore" could never unmute.
            readVolumeSettings { pct, muted in
                if self.rememberedVolume == nil {
                    self.rememberedVolume = (pct, muted)
                }
                Trace.log("volume mute: remembered \(pct) \(muted)")
                self.runAppleScript("set volume output muted true")
            }
        case "restore":
            Trace.log("volume restore: \(String(describing: rememberedVolume))")
            if let saved = rememberedVolume {
                rememberedVolume = nil
                runAppleScript("set volume output volume \(saved.percent)")
                runAppleScript("set volume output muted \(saved.muted ? "true" : "false")")
            }
        case "set":
            readVolumeSettings { pct, muted in
                if self.rememberedVolume == nil {
                    self.rememberedVolume = (pct, muted)
                }
                self.runAppleScript("set volume output volume \(min(100, max(0, item.volumePercent))) output muted false")
            }
        case "increase":
            adjustVolume(by: min(100, max(1, item.volumePercent)))
        case "decrease":
            adjustVolume(by: -min(100, max(1, item.volumePercent)))
        default:
            break
        }
    }

    /// Read the current output volume/mute state via AppleScript, then
    /// invoke `done` on the main actor. Never blocks, never throws.
    private func readVolumeSettings(_ done: @escaping @MainActor (Int, Bool) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        // Prints e.g. "output volume:13, input volume:50, alert volume:45, output muted:false"
        task.arguments = ["-e", "get volume settings"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { proc in
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            guard let vRange = raw.range(of: "output volume:"),
                  let pct = Int(raw[vRange.upperBound...].prefix(while: { $0.isNumber })) else {
                Trace.log("readVolumeSettings BAD OUTPUT exit=\(proc.terminationStatus) raw=\(raw.debugDescription)")
                return
            }
            let muted = raw.contains("output muted:true")
            Task { @MainActor in done(pct, muted) }
        }
        do { try task.run() } catch { Trace.log("readVolumeSettings RUN FAIL \(error)") }
    }

    private func adjustVolume(by delta: Int) {
        runAppleScript("set volume output volume ((output volume of (get volume settings)) + \(delta))")
    }

    // MARK: Music

    private func musicPause() {
        let script = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing then pause
            end tell
        end if
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] proc in
            // If the guard passed (exit 0) we may have paused playback; arm
            // the resume action so it only plays when we actually paused.
            if proc.terminationStatus == 0 {
                Task { @MainActor in self?.musicWasPlayingByUs = true }
            }
        }
        try? task.run()
    }

    private func musicPlay() {
        guard musicWasPlayingByUs else { return }
        musicWasPlayingByUs = false
        let script = """
        if application "Music" is running then
            tell application "Music"
                if player state is paused then play
            end tell
        end if
        """
        runAppleScript(script)
    }

    // MARK: Generic helpers

    private func runAppleScript(_ source: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private func runScript(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty,
              FileManager.default.fileExists(atPath: expanded) else { return }
        let p = Process()
        if expanded.lowercased().hasSuffix(".scpt") || expanded.lowercased().hasSuffix(".applescript") {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = [expanded]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [expanded]
        }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
