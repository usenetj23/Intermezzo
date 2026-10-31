import AppKit
import SwiftUI
import IntermezzoKit

/// Borderless windows refuse key status by default; the overlay hosts a
/// clickable Skip button, so the overlay windows must accept key.
extension NSScreen {
    /// The CoreGraphics display id (stable while the display is connected).
    var displayNumber: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// The overlay covers its whole screen, menu bar included: AppKit must not push it below the menu bar
    /// or onto another screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// One point of the recent-break trend chart drawn on the overlay.
struct BreakMarker: Identifiable {
    let id = UUID()
    var minutesAgo: Double
    var wasSkipped: Bool
    var durationSeconds: Int
    /// Relative weight of the break (a long one counts for more than a short one).
    var weight: Double = 1
    var startedAt: Date = Date()
    var outcome: BreakOutcome = .completed
    /// The break on screen right now (no outcome yet).
    var isRunning = false
    var postponeMinutes = 0
    var startedManually = false
}

/// Fullscreen break overlay: real background blur (NSVisualEffectView) plus
/// a dark dim layer, on EVERY screen, across EVERY Space. While presented the
/// Dock and menu bar are locked (presentationOptions) so there is no system
/// reaction when the pointer touches screen edges.
@MainActor
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var countdownTimer: Timer?
    private var endsAt: Date?
    private var kind: BreakKind = .short
    private var totalSeconds: TimeInterval = 300
    private var progressText: String?
    private var exerciseHeadline: String?
    private var exerciseDetail: String?
    private var trend: [BreakMarker] = []
    private var textThemeSnapshot: TextThemeSnapshot?
    private var imageThemeSnapshot: ImageThemeSnapshot?
    private var customButtonTitles: [String] = []
    private var shownAt: Date = Date()
    /// A scene preview: click-through, no Dock/menu-bar lock, never touches the engine.
    private var isPreview = false
    private var policy = BreakStyleSettings.policy
    private var snoozesLeft: Int?
    private var style = BreakStyleSettings.motivation
    /// Bumped on every show/dismiss so a pending reveal never outlives its break.
    private var showToken = 0
    /// Windows are built invisibly on every screen first; this lets blur, themes and
    /// weather layers finish their first render before all screens fade in together.
    private static let settleSeconds: TimeInterval = 0.7
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    private var spaceObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
    private let onSkip: () -> Void
    private let onExtend: (Int) -> Void
    var onButtonClick: (String) -> Void = { _ in }
    /// Occasional Messages tip shown on the break screen (nil = nothing).
    var messageHint: String?
    var onMessageOpen: () -> Void = {}

    var isPresenting: Bool { !windows.isEmpty }

    init(onSkip: @escaping () -> Void, onExtend: @escaping (Int) -> Void = { _ in }) {
        self.onSkip = onSkip
        self.onExtend = onExtend
        let wsnc = NSWorkspace.shared.notificationCenter
        spaceObserver = wsnc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPresenting else { return }
                self.reapplyBlockingAndOrder()
            }
        }
        screensObserver = NotificationCenter.default
            .addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                         object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isPresenting else { return }
                    self.teardownWindows()
                    self.createWindows()
                    self.reapplyBlockingAndOrder()
                }
            }
    }

    // MARK: - Present / dismiss

    func show(kind: BreakKind, duration: TimeInterval, progressText: String? = nil,
              headline: String? = nil, detail: String? = nil, trend: [BreakMarker] = [],
              textTheme: TextThemeSnapshot? = nil, imageTheme: ImageThemeSnapshot? = nil,
              buttonTitles: [String] = [], messageHint: String? = nil,
              preview: Bool = false,
              onMessageOpen: @escaping () -> Void = {}) {
        dismiss(animated: false)
        self.isPreview = preview || BreakStyleSettings.softBreak
        self.policy = preview ? Strictness.classic.policy : BreakStyleSettings.policy
        self.snoozesLeft = preview ? nil : BreakStyleSettings.snoozesLeft()
        self.style = BreakStyleSettings.motivation
        self.kind = kind
        self.totalSeconds = max(1, duration)
        self.progressText = progressText
        self.exerciseHeadline = headline
        self.exerciseDetail = detail
        self.trend = trend
        self.textThemeSnapshot = textTheme
        self.imageThemeSnapshot = imageTheme
        self.customButtonTitles = buttonTitles
        self.messageHint = messageHint
        self.onMessageOpen = onMessageOpen
        self.shownAt = Date()
        self.endsAt = Date().addingTimeInterval(duration + Self.settleSeconds)
        showToken += 1
        let token = showToken

        // The rain scene refracts the REAL desktop: grab it before our windows cover it.
        if UserDefaults.standard.integer(forKey: GlassKeys.weatherFX) != 0,
           let fx = WeatherController.shared.snapshot?.effect, fx == .rain || fx == .storm {
            RainBackdropStore.shared.captureAll()
        }
        createWindows()
        // Fade the whole overlay in.
        windows.forEach { $0.alphaValue = 0 }
        reapplyBlockingAndOrder()
        if !preview { NSApp.activate(ignoringOtherApps: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleSeconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.showToken, !self.windows.isEmpty else { return }
                self.reveal(duration: duration)
            }
        }
    }

    /// Fades every screen in at the same moment and starts the countdown.
    private func reveal(duration: TimeInterval) {
        endsAt = Date().addingTimeInterval(duration)
        updateLabels(secondsLeft: Int(duration))
        reapplyBlockingAndOrder()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = breakFadeDuration
            windows.forEach { $0.animator().alphaValue = 1 }
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] tmr in
            MainActor.assumeIsolated {
                guard let self, let endsAt = self.endsAt else { tmr.invalidate(); return }
                let left = max(0, Int(endsAt.timeIntervalSinceNow))
                self.updateLabels(secondsLeft: left)
                // Re-assert blocking + window order every tick: survives Spaces
                // switches, Dock re-shows and display reconfiguration.
                if !self.windows.isEmpty {
                    self.reanchorToScreens()
                    self.reapplyBlockingAndOrder()
                }
                if left <= 0 { self.dismiss() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    func dismiss(animated: Bool = true) {
        if !windows.isEmpty {
            NSLog("Intermezzo overlay: dismiss() tearing down %d windows", windows.count)
        }
        showToken += 1
        countdownTimer?.invalidate()
        countdownTimer = nil
        endsAt = nil
        progressText = nil
        guard animated, !windows.isEmpty else {
            teardownWindows()
            restoreSystemUI()
            return
        }
        // Gentle fade-out; teardown happens when the fade completes — with an
        // idempotent fallback timer, because a CA completion that never fires
        // used to strand full-screen overlays on screen (CPU burn forever).
        let dying = windows
        windows.removeAll()
        windowDisplays.removeAll()
        // A fading window must not catch clicks, and must not stay if the fade never completes.
        dying.forEach { $0.ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = breakFadeDuration
            dying.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                self?.closeWindowGroup(dying)
            }
        })
        // Fallback: even if the animation completion is swallowed by the
        // window server, the windows must not outlive the break.
        DispatchQueue.main.asyncAfter(deadline: .now() + breakFadeDuration + 0.6) { [weak self] in
            MainActor.assumeIsolated {
                self?.closeWindowGroup(dying)
            }
        }
        restoreSystemUI()
    }

    /// Idempotent: closes each window at most once (track by identifier).
    private func closeWindowGroup(_ group: [NSWindow]) {
        for w in group where !closedWindows.contains(ObjectIdentifier(w)) {
            closedWindows.insert(ObjectIdentifier(w))
            w.orderOut(nil)
            w.close()
        }
    }
    private var closedWindows: Set<ObjectIdentifier> = []

    // MARK: - Windows

    private func createWindows() {
        // "Glass"/"Frost" = ŻYWE blur tła (NSVisualEffectView, behindWindow).
        // Kapture ekranu jako tło zostawiliśmy za flagą eksperymentalną
        // glassExperimentalShot=1: na macOS 27 beta CGDisplayCreateImage
        // odpala crash telemetry Metal (-[__NSCFNumber length]) przy
        // commicie command buffera — live blur jest stabilny i wygląda lepiej.
        let effect = UserDefaults.standard.string(forKey: GlassKeys.effect) ?? "blur"
        let useShot = UserDefaults.standard.integer(forKey: "glassExperimentalShot") != 0
            && (effect == "glass" || effect == "frost") && ScreenGlass.hasPermission

        for (index, screen) in NSScreen.screens.enumerated() {
            let frame = screen.frame
            if frame.width < 200 || frame.height < 200 { continue }

            let blur: NSView
            if useShot, let shot = ScreenGlass.blurredShot(of: screen,
                                                            radius: effect == "frost" ? 42 : 24,
                                                            frost: effect == "frost") {
                let iv = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
                iv.imageScaling = .scaleAxesIndependently
                iv.image = shot
                if effect == "frost" {
                    // mrożone szkło: biała mgła na wierzchu
                    let veil = NSView(frame: iv.bounds)
                    veil.wantsLayer = true
                    veil.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
                    veil.autoresizingMask = [.width, .height]
                    iv.addSubview(veil)
                }
                blur = iv
            } else {
                let ve = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
                ve.material = kind == .long ? .fullScreenUI : .hudWindow
                ve.blendingMode = .behindWindow
                ve.state = .active
                blur = ve
            }
            blur.autoresizingMask = [.width, .height]

            // Optional user-provided background image (Settings can set
            // `breakBackgroundPath`); drawn between the blur and the text.
            // An Image Theme takes precedence over the single background path.
            if imageThemeSnapshot == nil,
               let path = UserDefaults.standard.string(forKey: "breakBackgroundPath"),
               !path.isEmpty, let image = NSImage(contentsOfFile: path) {
                let iv = NSImageView(frame: blur.bounds)
                iv.autoresizingMask = [.width, .height]
                iv.imageScaling = .scaleProportionallyUpOrDown
                iv.image = image
                blur.addSubview(iv)
            }

            let host = NSHostingView(rootView: makeView(primary: index == 0, screenHeight: frame.height,
                                                         screenFrame: frame))
            host.frame = blur.bounds
            host.autoresizingMask = [.width, .height]
            blur.addSubview(host)

            // contentRect is in global coordinates here; with `screen:` AppKit would read it relative to
            // that screen and park secondary-screen overlays somewhere else until the next tick moved them
            // (one screen started late, one window ended up on the wrong display).
            let window = KeyableWindow(contentRect: frame,
                                        styleMask: [.borderless],
                                        backing: .buffered,
                                        defer: false)
            window.setFrame(frame, display: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                         .fullScreenAuxiliary, .ignoresCycle]
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = isPreview
            window.contentView = blur
            windows.append(window)
            windowDisplays.append(screen.displayNumber)
            Self.everyOverlay.append(Weak(window))
        }
    }

    private func makeView(primary: Bool, screenHeight: CGFloat,
                           screenFrame: NSRect = .zero) -> BreakOverlayView {
        BreakOverlayView(
            kind: kind,
            secondsLeft: Int((endsAt?.timeIntervalSinceNow) ?? 0),
            totalSeconds: Int(totalSeconds),
            progressText: progressText,
            headlineText: exerciseHeadline,
            detailText: exerciseDetail,
            trend: trend,
            showVideo: primary && UserDefaults.standard.integer(forKey: YouTubeThemeKeys.enabled) != 0,
            textTheme: textThemeSnapshot,
            imageTheme: imageThemeSnapshot,
            shownAt: shownAt,
            screenHeight: screenHeight,
            screenFrame: screenFrame,
            onSkip: { [weak self] in self?.skipNow() },
            buttonTitles: customButtonTitles,
            onButton: { [weak self] title in self?.onButtonClick(title) },
            onExtend: { [weak self] minutes in self?.onExtend(minutes) },
            policy: policy,
            snoozesLeft: snoozesLeft,
            style: style,
            messageHint: messageHint,
            onMessageOpen: { [weak self] in self?.onMessageOpen() },
            // Seed from the real cursor position: the secondary monitors must
            // NOT paint the ring/text for a split second before the 0.5 s
            // cursor poll corrects it.
            cursorHere: screenFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation))
    }

    private func teardownWindows() {
        let dying = windows
        windows.removeAll()
        windowDisplays.removeAll()
        dying.forEach {
            $0.ignoresMouseEvents = true
            $0.orderOut(nil)
            $0.close()
        }
    }

    private struct Weak { weak var window: NSWindow?; init(_ w: NSWindow) { window = w } }
    /// Every overlay window ever made, so a stray one can always be found and closed.
    private static var everyOverlay: [Weak] = []
    /// The display each window in `windows` belongs to (same order).
    private var windowDisplays: [UInt32] = []

    /// Closes overlay windows that outlived their break (they were invisible but still caught every click).
    /// Called by the app's watchdog; does nothing while a break is on screen.
    func sweepStrays() {
        let live = Set(windows.map(ObjectIdentifier.init))
        Self.everyOverlay.removeAll { $0.window == nil }
        for entry in Self.everyOverlay {
            guard let w = entry.window, !live.contains(ObjectIdentifier(w)), w.isVisible else { continue }
            Trace.log("overlay: closing a stray window \(Int(w.frame.width))x\(Int(w.frame.height)) at \(Int(w.frame.minX)),\(Int(w.frame.minY))")
            w.ignoresMouseEvents = true
            w.orderOut(nil)
            w.close()
        }
    }

    /// Keep each overlay window exactly on its screen even after a display
    /// reconfiguration (resolution/scale change mid-break).
    private func reanchorToScreens() {
        let screens = NSScreen.screens.filter { $0.frame.width >= 200 && $0.frame.height >= 200 }
        let byDisplay = Dictionary(screens.map { ($0.displayNumber, $0) }, uniquingKeysWith: { first, _ in first })
        guard windows.count == screens.count, windowDisplays.allSatisfy({ byDisplay[$0] != nil }) else {
            // Topology changed while presenting — rebuild cleanly.
            teardownWindows()
            createWindows()
            windows.forEach { $0.alphaValue = 1 }
            return
        }
        // Matched by display, not by list order: the order of NSScreen.screens can change.
        for (window, display) in zip(windows, windowDisplays) {
            guard let screen = byDisplay[display], window.frame != screen.frame else { continue }
            window.setFrame(screen.frame, display: true)
        }
    }

    private func reapplyBlockingAndOrder() {
        guard !windows.isEmpty else { return }
        if isPreview {
            for w in windows { w.orderFront(nil) }
            return
        }
        if savedPresentationOptions == nil {
            savedPresentationOptions = NSApp.presentationOptions
        }
        // Hard-hide Dock + menu bar while the overlay is up: `hideDock`
        // WITHOUT `autoHideDock` means edge hover produces no peek.
        // Only re-set when actually different — pushing the same options
        // every tick triggers display-configuration churn (window leaks).
        let desired: NSApplication.PresentationOptions = [.hideDock, .hideMenuBar]
        if NSApp.presentationOptions != desired {
            NSApp.presentationOptions = desired
        }
        windows.first?.makeKeyAndOrderFront(nil)
        for w in windows.dropFirst() { w.orderFront(nil) }
    }

    private func restoreSystemUI() {
        guard let saved = savedPresentationOptions else { return }
        savedPresentationOptions = nil
        NSApp.presentationOptions = saved
    }

    private func skipNow() {
        dismiss()
        onSkip()
    }

    private func updateLabels(secondsLeft: Int) {
        for w in windows {
            if let host = w.contentView?.subviews.first as? NSHostingView<BreakOverlayView> {
                host.rootView.secondsLeft = secondsLeft
            }
        }
    }
}

// MARK: - The overlay content

struct BreakOverlayView: View {
    let kind: BreakKind
    var secondsLeft: Int
    var totalSeconds: Int
    var progressText: String?
    var headlineText: String?
    var detailText: String?
    var trend: [BreakMarker] = []
    var showVideo: Bool = false
    var textTheme: TextThemeSnapshot?
    var imageTheme: ImageThemeSnapshot?
    var shownAt: Date = Date()
    var screenHeight: CGFloat = 1000
    /// Ramka tego monitora — pełne UI (ring/tekst/przyciski) rysujemy tylko
    /// na ekranie, na którym aktualnie jest kursor myszy. Inne monitory
    /// dostają wyłącznie tło (blur + FX + ściemnienie).
    var screenFrame: NSRect = .zero
    let onSkip: () -> Void
    var buttonTitles: [String] = []
    var onButton: (String) -> Void = { _ in }
    var onExtend: (Int) -> Void = { _ in }
    var policy = OverlayPolicy(snoozeLimit: nil, showsSkip: true, escapeSkips: true)
    var snoozesLeft: Int?
    var style = MotivationStyle.streak
    /// Occasional tip banner on the break screen (never pauses the break).
    var messageHint: String?
    var onMessageOpen: () -> Void = {}
    /// Ephemeral feedback toast (e.g. after logging a drink).
    @State private var toast: String?

    // Two-step skip state: tap reveals options; full skip requires a hold.
    @State private var optionsShown = false
    @State private var retractTask: Task<Void, Never>?
    @State private var messageDismissed = false
    @State private var drinkToast: String?
    @State private var liveWeather: WeatherSnapshot?
    @State var cursorHere = true

    private static let holdDuration: Double = 1.2

    private var snoozesAllowed: Bool { snoozesLeft != 0 }

    /// Czy efekt szyby jest włączony (Glass/Frost) + pogoda włączona.
    private var weatherAllowed: Bool {
        let fx = UserDefaults.standard.string(forKey: GlassKeys.effect) ?? "blur"
        return (fx == "glass" || fx == "frost")
            && UserDefaults.standard.integer(forKey: GlassKeys.weatherFX) != 0
    }

    var body: some View {
        ZStack {
            // Image Theme: personal photo slideshow behind
            // everything else, with optional crossfade.
            if let imageTheme {
                ImageThemeSlides(theme: imageTheme, shownAt: shownAt, screenFrame: screenFrame)
                    .ignoresSafeArea()
            }

            // Optional YouTube theme: video plays on the main screen behind
            // the break text ("YouTube theme").
            if showVideo,
               UserDefaults.standard.integer(forKey: YouTubeThemeKeys.enabled) != 0,
               let raw = UserDefaults.standard.string(forKey: YouTubeThemeKeys.url),
               let embed = youTubeEmbedURL(
                   raw: raw,
                   random: UserDefaults.standard.integer(forKey: YouTubeThemeKeys.startRandom) != 0,
                   offset: UserDefaults.standard.integer(forKey: YouTubeThemeKeys.startOffset)) {
                YouTubePlayView(embedURL: embed,
                                volumePercent: UserDefaults.standard.integer(forKey: YouTubeThemeKeys.volume))
                    .ignoresSafeArea()
            }

            // Dim layer on top of the live blur provided by NSVisualEffectView.
            Color.black.opacity(kind == .long ? 0.55 : 0.35)
                .ignoresSafeArea()
            // Weather FX: deszcz/chmury/burza NA szybie, POD treścią przerwy
            // (tekst i ring muszą zostać czytelne — FX tylko tło).
            // Animowany FX tylko na ekranie z kursorem — na pozostałych (często 4K)
            // był czystym kosztem CPU/RAM: i tak widać tam samą rozmytą szybę.
            if cursorHere, let wx = liveWeather {
                WeatherFXView(effect: wx.effect, windKmh: wx.windKmh)
                    .ignoresSafeArea()
            }

            // Treść przerwy tylko na monitorze z kursorem (śledzone na żywo).
            if cursorHere {
            VStack(spacing: 22) {
                Spacer(minLength: 0)

                if let theme = textTheme {
                    // Text Theme: rotating user texts replace
                    // the headline from the tip bank.
                    TextThemeRotator(theme: theme, shownAt: shownAt, screenHeight: screenHeight)
                } else {
                    Text(headlineText ?? (kind == .long ? String(localized: "LONG BREAK") : String(localized: "TIME FOR A BREAK")))
                        .font(headlineText != nil
                             ? .system(size: 34, weight: .semibold, design: .rounded)
                             : .system(size: 44, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .white.opacity(0.85)],
                                         startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 2)  // twardy cień: bez rozmycia CPU
                }

                // Occasional Messages tip banner (never changes the
                // break itself — tap opens the full article, X dismisses it).
                if let hint = messageHint, !messageDismissed {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow.opacity(0.9))
                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Button {
                            messageDismissed = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture {
                        messageDismissed = true
                        onMessageOpen()
                    }
                }

                // Countdown with an animated progress ring.
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 8)
                        .frame(width: 260, height: 260)
                    // Postęp zmienia się raz na sekundę — bez TimelineView/animacji
                    // (8 fps przerysowywało całą warstwę widoku bez żadnego efektu).
                    Circle()
                        .trim(from: 0, to: progressValue)
                        .stroke(kind == .long ? Color.orange : Color.green,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 260, height: 260)
                    Text(String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60))
                        .font(.system(size: 88, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.95))
                        // Twardy cień zamiast rozmytego + bez animacji cyfr: rozmycie
                        // liczyło się na CPU (vImage, ~40 wątków) w każdej klatce przejścia.
                        .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 3)
                }

                if let progressText {
                    Text(progressText)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }

                if trend.count >= 2, style.showsTrendChart {
                    BreakTrendChart(markers: trend)
                        .frame(maxWidth: 760, minHeight: 116, maxHeight: 116)
                    BreakTrendLegend(markers: trend)
                    if let footer = style.chartFooter {
                        Text(footer)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                if textTheme == nil {
                    Text(detailText ?? String(localized: "Stand up. Look far away. Stretch."))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Custom "When Button Clicked" actions appear here as buttons.
                if !buttonTitles.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(buttonTitles, id: \.self) { title in
                            capsuleButton(title) { onButton(title) }
                        }
                    }
                }

                // Skip lives right under the content, flush at the bottom.
                // No spacer — the top Spacer pushes it all down.
                Group {
                    if !policy.showsSkip {
                        if snoozesAllowed {
                            HStack(spacing: 18) {
                                capsuleButton("+1 min") { onExtend(1) }
                                capsuleButton("+5 min") { onExtend(5) }
                            }
                            .padding(.bottom, 36)
                        }
                    } else if optionsShown {
                        HStack(spacing: 18) {
                            if snoozesAllowed {
                                capsuleButton("+1 min") { onExtend(1) }
                                capsuleButton("+5 min") { onExtend(5) }
                            }
                            holdToSkip
                        }
                        .padding(.bottom, 36)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { optionsShown = true }
                        } label: {
                            Text("Skip »")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 30)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 36)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.top, 40)
            }

            // Toast po zalogowaniu napoju (przycisk Water): co zapisano + stan dzienny.
            // Start poniżej notcha / paska systemowego (~48 px), inaczej tekst wchodzi pod niego.
            VStack {
                if let drinkToast {
                    Text("💧 " + drinkToast)
                        .font(.callout)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Toast: pokaż na 4 s po evencie logowania napoju.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("IntermezzoDrinkLogged"))) { note in
            if let text = note.userInfo?["text"] as? String {
                withAnimation { drinkToast = text }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { if drinkToast == text { drinkToast = nil } }
                }
            }
        }
        // Escape = full skip (keyboard access on the overlay).
        .onExitCommand { if policy.escapeSkips { onSkip() } }
        // Cursor gating: co 0.5 s sprawdzamy, na którym monitorze leży mysz.
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            let inside = screenFrame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation)
            if cursorHere != inside { cursorHere = inside }
        }
        // Poll: pobierz pogodę raz przy starcie, potem odświeżaj co 60 s.
        // The answer of a fetch comes a moment later: look every second until there is one, then every minute
        // (a 60 s wait after the first look left short breaks without weather).
        .task(id: shownAt) {
            guard weatherAllowed else { return }
            var waited = 0.0
            while !Task.isCancelled, waited < 30 * 60 {
                WeatherController.shared.refreshIfNeeded()
                if let s = WeatherController.shared.snapshot, s.isFresh, liveWeather?.fetchedAt != s.fetchedAt {
                    withAnimation(.easeIn(duration: 1.2)) { liveWeather = s }
                }
                let step = liveWeather == nil ? 1.0 : 60.0
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                waited += step
            }
        }
    }

    private var progressValue: Double {
        guard totalSeconds > 0 else { return 0 }
        let done = Double(totalSeconds - secondsLeft)
        return min(1.0, max(0.0, done / Double(totalSeconds)))
    }

    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            NSLog("Intermezzo overlay: capsule tapped: %@", title)
            action()
        }) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Full skip requires holding the button — a mis-click cannot nuke the break.
    private var holdToSkip: some View {
        HoldToSkipButton(duration: Self.holdDuration, onSkip: onSkip)
            .frame(width: HoldButtonView.size.width, height: HoldButtonView.size.height)
    }

    private func retractSoon() {
        retractTask?.cancel()
        retractTask = Task {
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            withAnimation { optionsShown = false }
        }
    }
}
