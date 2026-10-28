import AppKit
import CoreAudio

/// "Intelligence": detects contexts in which a break reminder would
/// be counter-productive and reports them so the coordinator can pause:
///  • in a video call (Zoom / Teams / Webex / Skype in front, or running while the microphone is in use)
///  • watching video (VLC / IINA / mpv / QuickTime, or a browser with a
///    fullscreen window on any display)
/// Poll-driven (called from the heartbeat every few seconds), no private APIs.
@MainActor
final class IntelligenceController {

    private let meetingApps: Set<String> = [
        "zoom.us", "us.zoom.xos", "microsoft teams", "com.microsoft.teams",
        "ciscowebex", "webex", "skype", "com.microsoft.teams2",
    ]
    private let videoApps: Set<String> = [
        "org.videolan.vlc", "io.mpv", "com.colliderli.iina",
        "com.apple.quicktimeplayerx", "movist.pro",
    ]
    private let browserBundles: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac",
        "org.mozilla.firefox", "company.thebrowser.Browser", "com.arc.browser",
    ]

    /// Meeting in progress: any known VC app is active on screen.
    /// Results cached for 4 s — the heartbeat calls this every tick and a
    /// fresh NSWorkspace/window-list scan per second is pure CPU burn.
    private var meetingCacheAt = Date.distantPast
    private var meetingCacheValue = false
    /// Why the last check said what it said, for the Diagnostics pane.
    private(set) var meetingReason = "brak spotkania"
    private var videoCacheAt = Date.distantPast
    private var videoCacheValue = false

    func meetingInProgress(now: Date = Date()) -> Bool {
        if now.timeIntervalSince(meetingCacheAt) < 10 { return meetingCacheValue }
        let v = computeMeetingInProgress()
        meetingCacheAt = now
        meetingCacheValue = v
        return v
    }

    private static let meetingNames = ["zoom", "microsoft teams", "webex", "skype"]

    private func isMeetingApp(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier?.lowercased(), meetingApps.contains(id) { return true }
        if let name = app.localizedName?.lowercased(), Self.meetingNames.contains(name) { return true }
        return false
    }

    /// A call is on when a meeting app is in front, or one is running (a call keeps going behind other
    /// windows) while something captures from the microphone. The microphone is asked only when a meeting
    /// app runs, and only then are the running apps listed.
    private func computeMeetingInProgress() -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication, isMeetingApp(front) {
            meetingReason = "\(front.localizedName ?? "aplikacja spotkań") jest na pierwszym planie"
            return true
        }
        if Self.microphoneInUse(), let app = NSWorkspace.shared.runningApplications.first(where: isMeetingApp) {
            meetingReason = "\(app.localizedName ?? "aplikacja spotkań") działa, a mikrofon jest w użyciu"
            return true
        }
        meetingReason = "brak spotkania"
        return false
    }

    /// Something is capturing from the default input device. Asking needs no microphone permission.
    private static func microphoneInUse() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Video playing: dedicated video player active, or a browser owning a
    /// fullscreen (or nearly-fullscreen) window on any screen.
    func videoInProgress(now: Date = Date()) -> Bool {
        if now.timeIntervalSince(videoCacheAt) < 10 { return videoCacheValue }
        let v = computeVideoInProgress()
        videoCacheAt = now
        videoCacheValue = v
        return v
    }

    private func computeVideoInProgress() -> Bool {
        if let front = NSWorkspace.shared.frontmostApplication,
           let id = front.bundleIdentifier?.lowercased(),
           videoApps.contains(id) {
            return true
        }
        // Browser fullscreen video: check window list for a screen-covering
        // window owned by a browser.
        guard let infoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let screens = NSScreen.screens.map(\.frame)
        for info in infoList {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let dict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let isBrowser = browserBundles.contains { bundle in
                bundle.lowercased().contains(owner.lowercased())
            } || ["Safari", "Google Chrome", "Chrome", "Firefox", "Edge", "Arc"].contains(owner)
            guard isBrowser else { continue }
            let w = dict["Width"] ?? 0, h = dict["Height"] ?? 0
            for s in screens where w >= s.width * 0.95 && h >= s.height * 0.95 {
                return true
            }
        }
        return false
    }

}
