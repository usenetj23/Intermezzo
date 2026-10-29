import AppKit
import CoreAudio
import IOKit.hidsystem

enum MediaPauseKeys {
    /// Pause what plays (a YouTube video, music) when a break starts. On by default.
    static let enabled = "pauseMediaDuringBreak"
    /// Play it again when the break ends, if nothing else started meanwhile. On by default.
    static let resume = "resumeMediaAfterBreak"
}

/// Pauses media for the break and resumes it afterwards — only what it paused itself.
///
/// What plays is read from CoreAudio (each process's "is running output", public API), so a silent Mac
/// is never sent a play/pause toggle that would start music. Pausing uses the system's Now Playing
/// command (an explicit pause, not a toggle); if the sound does not stop, the media key is sent once.
///
/// The media key goes to whichever app macOS last made "Now Playing" (often Apple Music, which it then starts
/// or even launches). So the key is sent only when a known media app is the one making the sound, never for
/// a call, a notification or a game, and a resume key only while the app we paused is still running.
@MainActor
final class MediaPauser {
    static let shared = MediaPauser()

    private var pausedByUs = false
    /// The media app families we paused (see `families`), for the resume.
    private var pausedFamilies: [Int] = []
    private var pending: DispatchWorkItem?

    /// Apps that always produce output (equalisers, audio routers): their sound says nothing about media.
    private static let alwaysOnAudio: Set<String> = [
        "com.finetuneapp.FineTune", "com.rogueamoeba.soundsource", "com.rogueamoeba.audiohijack",
        "com.rogueamoeba.Loopback", "com.bitgapp.eqmac", "com.bitgapp.eqMac", "com.existential.BackgroundMusic",
        "com.globaldelight.Boom3D", "com.apple.audio.coreaudiod",
    ]

    /// Apps and browsers that register as Now Playing: the media key controls them. Each family lists the bundle
    /// id prefixes of the app and of its helper processes (a browser's sound comes from a helper).
    private static let families: [[String]] = [
        ["com.apple.Music"], ["com.apple.Safari", "com.apple.WebKit"], ["com.apple.TV"], ["com.apple.podcasts"],
        ["com.apple.QuickTimePlayerX"], ["com.spotify.client"], ["com.google.Chrome"], ["org.mozilla.firefox"],
        ["com.microsoft.edgemac"], ["com.brave.Browser"], ["company.thebrowser.Browser"], ["com.operasoftware.Opera"],
        ["com.vivaldi.Vivaldi"], ["org.videolan.vlc"], ["com.colliderli.iina"], ["com.firecore.infuse"],
        ["tv.plex"], ["com.tidal"], ["com.deezer"], ["com.amazon.music"],
    ]

    private static func family(of bundleID: String) -> Int? {
        families.firstIndex { $0.contains { bundleID.hasPrefix($0) } }
    }

    private static func isRunning(family index: Int) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return families[index].contains { id.hasPrefix($0) }
        }
    }

    private var enabled: Bool { UserDefaults.standard.object(forKey: MediaPauseKeys.enabled) as? Bool ?? true }
    private var resumeEnabled: Bool { UserDefaults.standard.object(forKey: MediaPauseKeys.resume) as? Bool ?? true }

    // MARK: Break hooks

    func breakWillStart() {
        pending?.cancel()
        guard enabled else { return }
        let playing = Self.playingProcesses()
        guard !playing.isEmpty else { return }
        let families = Set(playing.compactMap { Self.family(of: $0.bundleID) })
        let musicWasPlaying = playing.contains { $0.bundleID.hasPrefix("com.apple.Music") }
        Trace.log("media: pausing for the break (\(playing.map(\.name).joined(separator: ", ")))")
        guard !families.isEmpty else {
            // Sound that is not a media app (a call, a notification): the media key would go to Apple Music instead.
            Trace.log("media: the sound is not from a media app, nothing sent (a media command can start Apple Music)")
            return
        }
        let musicRunning = Self.musicIsRunning
        sendNowPlaying(command: .pause, allowKey: true)
        Self.closeMusicIfStarted(wasRunning: musicRunning)
        pausedByUs = true
        pausedFamilies = Array(families)
        // Some players ignore the Now Playing command: then the media key, once, while a media app still plays.
        schedule(after: 1.0) {
            let still = Self.playingProcesses().filter { Self.family(of: $0.bundleID) != nil }
            guard !still.isEmpty else { return }
            Trace.log("media: still playing after pause, sending the media key")
            let musicRunning = Self.musicIsRunning
            Self.postPlayPauseKey()
            Self.closeMusicIfStarted(wasRunning: musicRunning)
            // The key can land on Apple Music instead (it is Now Playing but was silent): undo that at once.
            if !musicWasPlaying {
                self.schedule(after: 1.2) {
                    guard Self.playingProcesses().contains(where: { $0.bundleID.hasPrefix("com.apple.Music") }) else { return }
                    Trace.log("media: the key started Apple Music, pausing it again")
                    Self.postPlayPauseKey()
                }
            }
        }
    }

    func breakDidEnd() {
        pending?.cancel()
        guard pausedByUs else { return }
        pausedByUs = false
        let paused = pausedFamilies
        pausedFamilies = []
        guard resumeEnabled else { return }
        // After the break screen (and any video on it) is gone.
        schedule(after: 1.5) {
            guard Self.playingProcesses().isEmpty else {
                Trace.log("media: something else plays now, not resuming")
                return
            }
            Trace.log("media: resuming after the break")
            let musicRunning = Self.musicIsRunning
            self.sendNowPlaying(command: .play, allowKey: false)
            Self.closeMusicIfStarted(wasRunning: musicRunning)
            self.schedule(after: 1.2) {
                guard Self.playingProcesses().isEmpty else { return }
                // The key starts whatever is Now Playing: only when the app we paused is still there.
                guard paused.contains(where: Self.isRunning(family:)) else {
                    Trace.log("media: the paused app is gone, no media key")
                    return
                }
                Trace.log("media: did not resume, sending the media key")
                let musicRunning = Self.musicIsRunning
                defer { Self.closeMusicIfStarted(wasRunning: musicRunning) }
                Self.postPlayPauseKey()
            }
        }
    }

    private func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: Apple Music guard

    private static var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    /// A Now Playing command or the media key has nobody to go to sometimes, and macOS then opens Apple Music.
    /// If it was not running before and is now, quit it again (a polite quit; it was never ours to start).
    private static func closeMusicIfStarted(wasRunning: Bool) {
        guard !wasRunning else { return }
        for delay in [1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let started = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                guard !started.isEmpty else { return }
                Trace.log("media: Apple Music was started by the command, quitting it")
                started.forEach { $0.terminate() }
            }
        }
    }

    // MARK: Who plays

    struct Player {
        let pid: pid_t
        let bundleID: String
        let name: String
    }

    /// Processes sending sound to an output right now, without us and without always-on audio tools.
    static func playingProcesses() -> [Player] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return objects.compactMap { object in
            guard uint32(object, kAudioProcessPropertyIsRunningOutput) != 0 else { return nil }
            let pid = pid_t(bitPattern: uint32(object, kAudioProcessPropertyPID))
            guard pid != own, pid > 0 else { return nil }
            let bundle = bundleID(object) ?? ""
            guard !alwaysOnAudio.contains(bundle) else { return nil }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? (bundle.isEmpty ? "pid \(pid)" : bundle)
            return Player(pid: pid, bundleID: bundle, name: name)
        }
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func bundleID(_ object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    // MARK: Commands

    private enum NowPlayingCommand: UInt32 {
        case play = 0, pause = 1
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let sendCommandFunction: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    /// An explicit play or pause for the system's Now Playing app (private MediaRemote; may be absent).
    private func sendNowPlaying(command: NowPlayingCommand, allowKey: Bool) {
        guard let send = Self.sendCommandFunction else {
            if command == .pause, allowKey { Self.postPlayPauseKey() }
            return
        }
        _ = send(command.rawValue, nil)
    }

    /// The keyboard's play/pause key, as if pressed (a toggle: sent only when we know the state).
    private static func postPlayPauseKey() {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (Int(NX_KEYTYPE_PLAY) << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
