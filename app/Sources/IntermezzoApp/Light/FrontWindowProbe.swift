import AppKit
import CoreGraphics
import IntermezzoKit

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
