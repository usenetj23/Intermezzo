import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import IOKit.hidsystem

// MARK: - Natural-break detection: Event Monitor
//
// A listen-only Quartz event tap that records the timestamp of the last real
// user event. This is the "Event Monitor" method; "Event Source" polling
// (CGEventSource) remains as the fallback when the tap cannot be created
// (no Accessibility authorization). "None" disables idle detection entirely.

@MainActor
final class IdleEventMonitor {
    // The tap callback runs on the main run loop (the source is added to
    // .commonModes), so these are safe to touch from the callback.
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var reArmFailures = 0
    private var lastStartAttempt = Date.distantPast
    private var askedSystem = false
    /// Updated from the tap callback (main run loop mode .common).
    nonisolated(unsafe) private var lastActivity = Date()

    var isRunning: Bool { tap != nil }

    /// Seconds since the last keyboard or click event (from the tap) or mouse move or scroll (polled).
    /// Mouse moves and scrolling arrive at 60–120 Hz, so the tap does not listen for them: polling
    /// the HID state once per heartbeat is free, while a tap callback wakes the app on every event.
    func idleSeconds() -> TimeInterval {
        let tapped = Date().timeIntervalSince(lastActivity)
        let moved = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let scrolled = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .scrollWheel)
        let dragged = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged)
        return min(tapped, moved, scrolled, dragged)
    }

    /// Try to (re)create the tap. Returns false when unauthorized — the
    /// caller keeps using CGEventSource polling instead.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        // Throttle retries — without Input Monitoring the tap cannot be
        // created, and the heartbeat would knock on this door every second.
        let now = Date()
        if now.timeIntervalSince(lastStartAttempt) < 120 { return false }
        lastStartAttempt = now
        lastActivity = Date()
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // The honest gate: without Input Monitoring the tap is created but
        // macOS keeps it disabled (zombie re-arm loop). Ask for the REAL
        // permission — IOHIDRequestAccess pops the system prompt and
        // registers the CURRENT binary, so the checkbox actually matches.
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            if !askedSystem {
                askedSystem = true
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                Trace.log("Input Monitoring not granted — system prompt requested")
            }
            return false
        }
        // Listen-only taps get disabled by macOS on slow callbacks; the
        // disable notice arrives THROUGH the tap itself. Re-arm in place —
        // that is the canonical pattern (polling tapIsEnabled from outside
        // is unreliable and produced a teardown/re-create loop).
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .headInsertEventTap,
                                              options: .listenOnly,
                                              eventsOfInterest: mask,
                                              callback: { _, type, event, refcon in
            if type == CGEventType(rawValue: 0xFFFFFFFE)   // tapDisabledByTimeout
                || type == CGEventType(rawValue: 0xFFFFFFFF) { // tapDisabledByUserInput
                if let refcon {
                    let monitor = Unmanaged<IdleEventMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    monitor.reArmFromCallback()
                }
                return nil
            }
            if let refcon {
                let monitor = Unmanaged<IdleEventMonitor>.fromOpaque(refcon)
                    .takeUnretainedValue()
                monitor.stampActivity()
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else {
            Trace.log("event tap unavailable (Input Monitoring denied?)")
            return false
        }
        tap = newTap
        // A CFMachPort is not a run-loop source: the earlier unsafeBitCast added the port itself,
        // so the callback never ran, keyboard/click activity was never stamped, and macOS kept
        // disabling the clogged tap (the "re-armed" line every 30 s).
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            tap = nil
            Trace.log("event tap run-loop source unavailable")
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        Trace.log("event tap started")
        return true
    }

    /// Called from the tap callback when macOS disables us (timeout).
    /// Re-enable in place; after repeated stalls tear the tap down so the
    /// Event Source polling path takes over until the user re-grants.
    nonisolated func stampActivity() {
        lastActivity = Date()
        if !deliveredOnce {
            deliveredOnce = true
            Trace.log("event tap delivering events")
        }
    }

    nonisolated(unsafe) private var deliveredOnce = false

    nonisolated func reArmFromCallback() {
        guard let tapRef = tap else { return }
        if CGEvent.tapIsEnabled(tap: tapRef) { return }
        CGEvent.tapEnable(tap: tapRef, enable: true)
        if !CGEvent.tapIsEnabled(tap: tapRef) {
            reArmFailures += 1
            if reArmFailures >= 3 {
                CFMachPortInvalidate(tapRef)
                tap = nil
                reArmFailures = 0
            }
        }
    }

    /// Heartbeat watchdog (every 30 ticks): nothing usually happens here —
    /// stalls are handled in reArmFromCallback. This catches the silent case
    /// where the port exists but stopped delivering events.
    func reenableIfNeeded() {
        guard let tapRef = tap else { return }
        if !CGEvent.tapIsEnabled(tap: tapRef) {
            CGEvent.tapEnable(tap: tapRef, enable: true)
            Trace.log("event tap re-armed")
        }
    }
}

// MARK: - Sleep Guard

/// Keeps the Mac awake for the duration of a break so nobody "skips" it by
/// letting the machine sleep.
@MainActor
final class SleepGuard {
    /// The break is one more reason for `KeepAwakeController` to hold the Mac (one place owns the assertions).
    func begin(reason: String) {
        Trace.log("sleep guard ON: \(reason)")
        KeepAwakeController.shared.setBreakHold(true)
    }

    func end() {
        Trace.log("sleep guard OFF")
        KeepAwakeController.shared.setBreakHold(false)
    }
}

// MARK: - Duplicate copy detection

/// Finds additional bundles with OUR identifier elsewhere on disk
/// (including the Trash) and warns once a day. Two copies on one Mac cause
/// the wrong helper to be launched.
enum DuplicateScanner {
    static func findOtherCopies(excluding ownBundle: URL?) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == 'com.automit.Intermezzo'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let ownPath = ownBundle?.path
        return text.split(separator: "\n").map(String.init)
            .filter { !$0.isEmpty }
            .filter { path in
                guard let ownPath else { return true }
                // Only the actually-running bundle itself is not a duplicate;
                // a byte-identical copy elsewhere IS the duplicate we warn about.
                return path != ownPath
            }
    }
}
