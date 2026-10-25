import AppKit

/// Soft evening "Clock Out" banner — "Time to Switch Off".
/// One centered panel on the main screen; the user can acknowledge
/// ("Zostaję dłużej"), which quiets it for the next 15 minutes.
@MainActor
final class ClockOutController {
    private var window: NSWindow?
    private(set) var onAcknowledge: () -> Void

    init(onAcknowledge: @escaping () -> Void) {
        self.onAcknowledge = onAcknowledge
        ClockOutTarget.shared.controller = self
    }

    func show(title: String, message: String) {
        if window == nil { buildWindow() }
        (window?.contentView?.viewWithTag(2) as? NSTextField)?.stringValue = title
        (window?.contentView?.viewWithTag(3) as? NSTextField)?.stringValue = message
        guard let screen = NSScreen.main else { return }
        let f = window!.frame
        let origin = NSPoint(x: screen.frame.midX - f.width / 2,
                             y: screen.frame.midY - f.height / 2)
        window!.setFrameOrigin(origin)
        window!.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func buildWindow() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                            styleMask: [.titled, .utilityWindow, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)) - 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let effect = NSVisualEffectView(frame: panel.frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]

        let icon = NSTextField(labelWithString: "🌙")
        icon.font = NSFont.systemFont(ofSize: 40)
        icon.alignment = .center
        icon.frame = NSRect(x: 0, y: 150, width: 420, height: 50)
        effect.addSubview(icon)

        let title = NSTextField(labelWithString: String(localized: "Time to Switch Off"))
        title.tag = 2
        title.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        title.alignment = .center
        title.frame = NSRect(x: 10, y: 118, width: 400, height: 28)
        effect.addSubview(title)

        let msg = NSTextField(wrappingLabelWithString: "")
        msg.tag = 3
        msg.font = NSFont.systemFont(ofSize: 13)
        msg.alignment = .center
        msg.textColor = .secondaryLabelColor
        msg.frame = NSRect(x: 30, y: 70, width: 360, height: 44)
        effect.addSubview(msg)

        let button = NSButton(title: String(localized: "Zostaję 15 minut"), target: nil, action: nil)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 130, y: 22, width: 160, height: 32)
        button.target = ClockOutTarget.shared
        button.action = #selector(ClockOutTarget.acknowledge)
        effect.addSubview(button)

        panel.contentView = effect
        window = panel
    }
}

/// Tiny target shim so the button's target isn't the panel itself.
@MainActor
final class ClockOutTarget: NSObject {
    static let shared = ClockOutTarget()
    weak var controller: ClockOutController?
    @objc func acknowledge() {
        guard let controller else { return }
        MainActor.assumeIsolated {
            controller.dismiss()
            controller.notifyAcknowledged()
        }
    }
}

extension ClockOutController {
    func notifyAcknowledged() { onAcknowledge() }
}
