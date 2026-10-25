import AppKit

/// "Intelligence": detects contexts in which a break reminder would
/// be counter-productive and reports them so the coordinator can pause:
///  • in a video call (Zoom / Teams / Webex / Meet / Skype running & visible)
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
    private var videoCacheAt = Date.distantPast
    private var videoCacheValue = false

    func meetingInProgress(now: Date = Date()) -> Bool {
        if now.timeIntervalSince(meetingCacheAt) < 10 { return meetingCacheValue }
        let v = computeMeetingInProgress()
        meetingCacheAt = now
        meetingCacheValue = v
        return v
    }

    /// Only the active app can be "in front", so only that one is asked (walking every running app costs
    /// a LaunchServices round trip per app).
    private func computeMeetingInProgress() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let id = app.bundleIdentifier?.lowercased(), meetingApps.contains(id) { return true }
        if let name = app.localizedName?.lowercased(),
           ["zoom", "microsoft teams", "webex", "skype"].contains(name) { return true }
        return false
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
