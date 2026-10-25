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
@MainActor
final class MediaPauser {
    static let shared = MediaPauser()

    private var pausedByUs = false
    private var pending: DispatchWorkItem?

    /// Apps that always produce output (equalisers, audio routers): their sound says nothing about media.
    private static let alwaysOnAudio: Set<String> = [
        "com.finetuneapp.FineTune", "com.rogueamoeba.soundsource", "com.rogueamoeba.audiohijack",
        "com.rogueamoeba.Loopback", "com.bitgapp.eqmac", "com.bitgapp.eqMac", "com.existential.BackgroundMusic",
        "com.globaldelight.Boom3D", "com.apple.audio.coreaudiod",
    ]

    private var enabled: Bool { UserDefaults.standard.object(forKey: MediaPauseKeys.enabled) as? Bool ?? true }
    private var resumeEnabled: Bool { UserDefaults.standard.object(forKey: MediaPauseKeys.resume) as? Bool ?? true }

    // MARK: Break hooks

    func breakWillStart() {
        pending?.cancel()
        guard enabled else { return }
        let playing = Self.playingProcesses()
        guard !playing.isEmpty else { return }
        Trace.log("media: pausing for the break (\(playing.map(\.name).joined(separator: ", ")))")
        sendNowPlaying(command: .pause)
        pausedByUs = true
        // Some players ignore the Now Playing command: then the media key, once.
        schedule(after: 1.0) {
            let still = Self.playingProcesses()
            guard !still.isEmpty else { return }
            Trace.log("media: still playing after pause, sending the media key")
            Self.postPlayPauseKey()
        }
    }

    func breakDidEnd() {
        pending?.cancel()
        guard pausedByUs else { return }
        pausedByUs = false
        guard resumeEnabled else { return }
        // After the break screen (and any video on it) is gone.
        schedule(after: 1.5) {
            guard Self.playingProcesses().isEmpty else {
                Trace.log("media: something else plays now, not resuming")
                return
            }
            Trace.log("media: resuming after the break")
            self.sendNowPlaying(command: .play)
            self.schedule(after: 1.2) {
                guard Self.playingProcesses().isEmpty else { return }
                Trace.log("media: did not resume, sending the media key")
                Self.postPlayPauseKey()
            }
        }
    }

    private func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
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
    private func sendNowPlaying(command: NowPlayingCommand) {
        guard let send = Self.sendCommandFunction else {
            if command == .pause { Self.postPlayPauseKey() }
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
