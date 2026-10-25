import AppKit

/// RRGGBB → NSColor helper (shared with the Text/Image theme code paths).
func nsColor(fromHex hex: String) -> NSColor? {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                   green: CGFloat((v >> 8) & 0xFF) / 255.0,
                   blue: CGFloat(v & 0xFF) / 255.0,
                   alpha: 1.0)
}

/// "Flash Reminder": a gentle, brief screen flash at a fixed
/// interval (posture check). Skips while a break is live or while paused,
/// so it never stacks with the fullscreen overlay.
@MainActor
final class FlashReminderController {
    private var lastFlash = Date.distantPast

    /// Called from the coordinator heartbeat once per second.
    func tick(now: Date, canFlash: Bool) {
        guard UserDefaults.standard.integer(forKey: Keys.flashEnabled) != 0, canFlash else { return }
        let minutes = max(1, UserDefaults.standard.integer(forKey: Keys.flashIntervalMinutes))
        guard now.timeIntervalSince(lastFlash) >= TimeInterval(minutes * 60) else { return }
        lastFlash = now
        pulse()
    }

    /// Manual "Play demo".
    func pulse() {
        pulse(colorHex: "FFFFFF")
    }

    /// Flash in a chosen color (Flash Screen action).
    func pulse(colorHex: String) {
        let flashColor = nsColor(fromHex: colorHex) ?? .white
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: [.borderless],
                                  backing: .buffered,
                                  defer: false)
            window.isOpaque = false
            window.backgroundColor = flashColor
            window.hasShadow = false
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            // IMPORTANT: the animation completion handler closes the window
            // and releases its last strong ref; with isReleasedWhenClosed =
            // true the window was over-released → SIGSEGV in objc_release.
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.alphaValue = 0
            window.orderFront(nil)

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 0.8
            }, completionHandler: {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.5
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    window.close()
                })
            })
        }
    }
}
