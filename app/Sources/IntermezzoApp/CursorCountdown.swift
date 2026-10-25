import AppKit

/// UserDefaults keys for the cursor reminder's button visibility
/// ("hide Delay/Skip" discipline switches).
enum ReminderKeys {
    static let hideSkip = "reminderHideSkip"
    static let hideDelay = "reminderHideDelay"
}

/// Two-part cursor reminder:
///
///  * **Disc** — a small 44 pt ring with the MM:SS countdown that rides next
///    to the mouse. It is repositioned from the *mouse event stream*
///    (`addGlobalMonitorForEvents`), not the 1 s engine tick, so it glides
///    with the pointer instead of jumping once per second.
///  * **Card** — a compact notification with buttons (Teraz / +1 / +5 / Pomiń).
///    It is PINNED to the bottom-right corner of the screen that contains the
///    cursor when it appears. It never chases the mouse, so its buttons are
///    actually clickable. The disc stays visible alongside the card — its only
///    job is "a break is coming", in case the card was dismissed.
///
/// Both panels are non-activating: their buttons never steal keyboard focus.
/// While a break is running (or breaks are paused) everything is hidden —
/// the fullscreen overlay owns the screen then.
final class CursorCountdownController: NSObject {
    var onStart: () -> Void = {}
    var onSnooze1: () -> Void = {}
    var onSnooze5: () -> Void = {}
    var onSkip: () -> Void = {}

    // MARK: Disc (follows the cursor)
    private var discPanel: NSPanel?
    private var disc: DiscCountdownView?

    // MARK: Card (pinned to a screen corner)
    private var cardPanel: NSPanel?
    private var cardHeadline: NSTextField?
    private var cardTime: NSTextField?
    private var cardButtons: [NSButton] = []

    private var dismissedCycle = false      // user hit ✕ — stay hidden until next cycle
    private var openByClick = false         // disc clicked — open card early
    private var cardOnScreenID: CGDirectDisplayID?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastFollow: TimeInterval = 0
    private var lastShown = false
    /// Screen frames, refreshed when the display set changes (not read on every mouse event).
    private var screenFrames: [NSRect] = NSScreen.screens.map(\.frame)
    private var screensObserver: Any?
    /// Moving a window is a round trip to the window server; 30 moves a second still look smooth for a
    /// 44 pt disc and cost less than half of the previous 70.
    private static let followInterval: TimeInterval = 1.0 / 30.0

    init(onStart: @escaping () -> Void,
         onSnooze1: @escaping () -> Void,
         onSnooze5: @escaping () -> Void,
         onSkip: @escaping () -> Void = {}) {
        super.init()
        self.onStart = onStart
        self.onSnooze1 = onSnooze1
        self.onSnooze5 = onSnooze5
        self.onSkip = onSkip
    }

    // MARK: Updates from the engine tick

    /// `text == nil` means: paused or a live break running — hide everything.
    func update(text: String?, headline: String? = nil, urgent: Bool = false,
                progress: Double = 0) {
        guard let text else {
            openByClick = false
            if lastShown { hide() }
            return
        }
        // A fresh cycle (progress back near zero) re-arms after a ✕ dismissal.
        if dismissedCycle && progress < 0.02 { dismissedCycle = false }
        if dismissedCycle && !openByClick {
            if lastShown { hide() }
            return
        }
        lastShown = true
        installMouseFollow()

        ensureDisc()
        disc?.text = text
        disc?.progress = min(1.0, max(0.0, progress))
        repositionDisc()
        discPanel?.orderFront(nil)

        if urgent || openByClick {
            showCard(headline: headline ?? String(localized: "Za chwilę przerwa"))
            cardTime?.stringValue = text
        } else {
            openByClick = false
            cardPanel?.orderOut(nil)
        }
    }

    func hide() {
        lastShown = false
        removeMouseFollow()
        openByClick = false
        discPanel?.orderOut(nil)
        cardPanel?.orderOut(nil)
    }

    // MARK: Disc

    private func ensureDisc() {
        if discPanel != nil { return }
        let size: CGFloat = 44
        let panel = makePanel(size: NSSize(width: size, height: size))
        let view = DiscCountdownView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.onTap = { [weak self] in
            guard let self else { return }
            if self.cardPanel?.isVisible == true {
                self.openByClick = false
                self.cardPanel?.orderOut(nil)
            } else {
                self.openByClick = true
            }
        }
        panel.contentView = view
        discPanel = panel
        disc = view
    }

    /// Place the disc just below-right of the pointer tip, clamped on-screen.
    private func repositionDisc() {
        guard let panel = discPanel else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = screenFrames.first(where: { NSMouseInRect(mouse, $0, false) }) ?? screenFrames.first else { return }
        let f = panel.frame
        var origin = NSPoint(x: mouse.x + 14, y: mouse.y - f.height - 10)
        origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - f.width - 6)
        origin.y = min(max(origin.y, screen.minY + 6), screen.maxY - f.height - 6)
        if abs(panel.frame.origin.x - origin.x) > 0.5 || abs(panel.frame.origin.y - origin.y) > 0.5 {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: Card

    private func showCard(headline: String) {
        guard cursorScreen() != nil else { return }
        ensureCard()
        cardHeadline?.stringValue = headline
        let hideDelay = UserDefaults.standard.integer(forKey: ReminderKeys.hideDelay) != 0
        let hideSkip = UserDefaults.standard.integer(forKey: ReminderKeys.hideSkip) != 0
        cardButtons.forEach { b in
            switch b.tag {
            case 1: b.isHidden = false                // Teraz
            case 2, 3: b.isHidden = hideDelay        // +1 / +5
            case 4: b.isHidden = hideSkip            // Pomiń
            default: break
            }
        }
        // Pin to the bottom-right corner of the cursor's display. The
        // autolayout content can resize the window AFTER the first pin
        // (330 -> 370 wide), so we re-apply every update — using the
        // panel's CURRENT frame. This never chases the mouse (the target
        // depends only on the screen), it just keeps the card flush on
        // screen (the "ucięta prawa strona" bug).
        if let screen = cursorScreen() {
            let vf = screen.visibleFrame
            let f = cardPanel!.frame
            var x = vf.maxX - f.width - 16
            x = max(x, screen.frame.minX + 8)
            var y = vf.minY + 16
            y = max(y, screen.frame.minY + 8)
            if abs(cardPanel!.frame.origin.x - x) > 0.5 || abs(cardPanel!.frame.origin.y - y) > 0.5 {
                cardPanel!.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        cardPanel?.orderFront(nil)
    }

    private func ensureCard() {
        if cardPanel != nil { return }
        let w: CGFloat = 330, h: CGFloat = 86
        let panel = makePanel(size: NSSize(width: w, height: h))
        panel.hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        let head = NSTextField(labelWithString: String(localized: "Za chwilę przerwa"))
        head.font = .systemFont(ofSize: 11.5, weight: .semibold)
        head.textColor = .labelColor
        head.lineBreakMode = .byTruncatingTail
        head.translatesAutoresizingMaskIntoConstraints = false

        let time = NSTextField(labelWithString: "0:00")
        time.font = .monospacedDigitSystemFont(ofSize: 20, weight: .bold)
        time.textColor = .controlAccentColor
        time.translatesAutoresizingMaskIntoConstraints = false
        cardTime = time

        let left = NSStackView(views: [head, time])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 2
        left.translatesAutoresizingMaskIntoConstraints = false

        func button(_ title: String, _ tag: Int, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.tag = tag
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11, weight: .medium)
            return b
        }
        let startB = button(String(localized: "Teraz"), 1, #selector(cardStart))
        let plus1 = button("+1", 2, #selector(cardPlus1))
        let plus5 = button("+5", 3, #selector(cardPlus5))
        let skipB = button(String(localized: "Pomiń"), 4, #selector(cardSkip))
        let closeB = button("✕", 9, #selector(cardClose))

        let buttons = NSStackView(views: [startB, plus1, plus5, skipB, closeB])
        buttons.orientation = .horizontal
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(left)
        effect.addSubview(buttons)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            left.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 8),
        ])
        cardButtons = [startB, plus1, plus5, skipB]
        cardHeadline = head
        cardPanel = panel
    }

    // MARK: Card actions

    @objc private func cardStart() { openByClick = false; hide(); onStart() }
    @objc private func cardPlus1() { openByClick = false; hide(); onSnooze1() }
    @objc private func cardPlus5() { openByClick = false; hide(); onSnooze5() }
    @objc private func cardSkip() { openByClick = false; hide(); onSkip() }
    @objc private func cardClose() {
        openByClick = false
        dismissedCycle = true
        hide()
    }

    // MARK: Mouse tracking

    /// Mouse monitors exist only while the disc is on screen: every mouse move wakes the app
    /// for each installed monitor, so keeping them always on cost wake-ups all day.
    private func installMouseFollow() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        // Monitors are called on the main thread already: no extra hop per mouse event.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.followTick(event.timestamp)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.followTick(event.timestamp)
            return event
        }
        screenFrames = NSScreen.screens.map(\.frame)
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screenFrames = NSScreen.screens.map(\.frame)
            }
    }

    private func removeMouseFollow() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        if let screensObserver { NotificationCenter.default.removeObserver(screensObserver) }
        screensObserver = nil
    }

    /// Called on every mouse event (throttled to 30 Hz by the event's own timestamp). Does nothing while
    /// the disc is off screen, so idle cost is ~nil.
    private func followTick(_ timestamp: TimeInterval) {
        guard timestamp - lastFollow >= Self.followInterval, let panel = discPanel, panel.isVisible else { return }
        lastFollow = timestamp
        repositionDisc()
    }

    private func cursorScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
    }

    // MARK: Panel factory

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        return panel
    }
}

/// The disc itself: dark translucent circle (readable on ANY background),
/// gray track ring, accent progress arc, MM:SS in the middle. Tap toggles
/// the button card.
final class DiscCountdownView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var progress: Double = 0 { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?

    override func mouseUp(with event: NSEvent) { onTap?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let r = min(bounds.width, bounds.height) / 2 - 2.5

        // Dark base so white text/ring survive bright wallpapers.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
        ctx.fillEllipse(in: NSRect(x: center.x - r, y: center.y - r,
                                    width: r * 2, height: r * 2))

        // Track ring.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        track.lineWidth = 2.5
        track.stroke()

        // Progress arc (clockwise from 12 o'clock).
        if progress > 0.005 {
            let arc = NSBezierPath()
            let end = 90.0 - 360.0 * min(1.0, progress)
            arc.appendArc(withCenter: center, radius: r,
                          startAngle: 90, endAngle: end, clockwise: true)
            NSColor.controlAccentColor.setStroke()
            arc.lineWidth = 2.5
            arc.stroke()
        }

        // Countdown text.
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        str.draw(at: NSPoint(x: center.x - textSize.width / 2,
                             y: center.y - textSize.height / 2))
    }
}
