import AppKit
import Carbon.HIToolbox

// The macOS SDK keeps the RegisterEventHotKey symbol in HIToolbox but does
// not expose its prototype to Swift — declare it manually (C ABI).
@_silgen_name("RegisterEventHotKey")
private func RegisterEventHotKeyShim(_ inHotKeyCode: UInt32,
                                     _ inHotKeyModifiers: UInt32,
                                     _ inHotKeyID: EventHotKeyID,
                                     _ inTarget: EventTargetRef?,
                                     _ inOptions: UInt32,
                                     _ outHotKeyRef: UnsafeMutablePointer<EventHotKeyRef?>) -> OSStatus

@_silgen_name("UnregisterEventHotKey")
private func UnregisterEventHotKeyShim(_ inHotKeyRef: EventHotKeyRef?) -> OSStatus

/// A configurable global hotkey: keyCode + Carbon modifier mask, stored as
/// "keyCode|carbonModifiers" in UserDefaults (editable in Settings).
struct HotkeySpec: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += HotkeySpec.keyName(keyCode)
        return s
    }

    static func parse(_ raw: String?) -> HotkeySpec? {
        guard let raw, let sep = raw.firstIndex(of: "|") else { return nil }
        guard let k = UInt32(raw[..<sep]),
              let m = UInt32(raw[raw.index(after: sep)...]) else { return nil }
        return HotkeySpec(keyCode: k, carbonModifiers: m)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"; case kVK_Space: return String(localized: "Space")
        default: return String(localized: "Key \(Int(code))")
        }
    }
}

/// Global keyboard shortcuts (Carbon RegisterEventHotKey — works sandbox-free).
/// Defaults: ⌃⌥B short break, ⌃⌥L long break, ⌃⌥S skip, ⌃⌥P pause/resume.
/// The remaining actions have no default — assign them in Settings.
/// All are user-editable in Settings; changes apply immediately.
@MainActor
final class HotkeyController {
    private var refs: [EventHotKeyRef?] = []
    private var lastSpecsSignature = ""
    private var observer: NSObjectProtocol?

    var onStartShort: () -> Void = {}
    var onStartLong: () -> Void = {}
    var onSkip: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onPostpone: () -> Void = {}
    var onPauseAll: () -> Void = {}
    var onResumeAll: () -> Void = {}
    var onResetAll: () -> Void = {}
    var onStopSound: () -> Void = {}

    func install() {
        var evtSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData else { return noErr }
            let me = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            MainActor.assumeIsolated {
                Trace.log("hotkey pressed id=\(hkID.id)")
                switch hkID.id {
                case 1: me.onStartShort()
                case 2: me.onStartLong()
                case 3: me.onSkip()
                case 4: me.onTogglePause()
                case 5: me.onPostpone()
                case 6: me.onPauseAll()
                case 7: me.onResumeAll()
                case 8: me.onResetAll()
                case 9: me.onStopSound()
                default: break
                }
            }
            return noErr
        }, 1, &evtSpec, Unmanaged.passUnretained(self).toOpaque(), nil)

        reload()
        // Re-register live whenever the user edits a shortcut in Settings.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        // Belt & braces: re-verify the specs every few seconds. The signature
        // guard makes this a cheap no-op unless something actually changed,
        // and it also picks up `defaults write`-style external edits that
        // didChangeNotification can miss when made from another process.
        let pollTimer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        pollTimer.tolerance = 3.0
        RunLoop.main.add(pollTimer, forMode: .common)
    }

    /// (Re-)register all hotkeys from their UserDefaults specs.
    func reload() {
        let d = UserDefaults.standard
        let signatures = [Keys.hotkeyShort, Keys.hotkeyLong, Keys.hotkeySkip, Keys.hotkeyPause,
                          Keys.hotkeyPostpone, Keys.hotkeyPauseAll, Keys.hotkeyResumeAll,
                          Keys.hotkeyReset, Keys.hotkeyStopSound]
            .map { d.string(forKey: $0) ?? "" }
            .joined(separator: ";")
        guard signatures != lastSpecsSignature else { return }
        lastSpecsSignature = signatures

        refs.compactMap { $0 }.forEach { _ = UnregisterEventHotKeyShim($0) }
        refs.removeAll()

        // id 1–4 get shipped defaults (written once on first launch); the
        // rest stay unassigned until the user records a shortcut.
        let defaults: [(key: String, id: UInt32, fallbackKey: UInt32?)] = [
            (Keys.hotkeyShort, 1, UInt32(kVK_ANSI_B)),
            (Keys.hotkeyLong, 2, UInt32(kVK_ANSI_L)),
            (Keys.hotkeySkip, 3, UInt32(kVK_ANSI_S)),
            (Keys.hotkeyPause, 4, UInt32(kVK_ANSI_P)),
            (Keys.hotkeyPostpone, 5, nil),
            (Keys.hotkeyPauseAll, 6, nil),
            (Keys.hotkeyResumeAll, 7, nil),
            (Keys.hotkeyReset, 8, nil),
            (Keys.hotkeyStopSound, 9, nil),
        ]
        let fallbackMods = UInt32(controlKey | optionKey)
        for entry in defaults {
            if d.string(forKey: entry.key) == nil, let fk = entry.fallbackKey {
                d.set("\(fk)|\(fallbackMods)", forKey: entry.key)
            }
            guard let spec = HotkeySpec.parse(d.string(forKey: entry.key)) else { continue }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x4452_4700) + entry.id, id: entry.id)
            let status = RegisterEventHotKeyShim(spec.keyCode, spec.carbonModifiers,
                                                 hkID, GetEventDispatcherTarget(), 0, &ref)
            Trace.log("register hotkey id=\(entry.id) key=\(spec.keyCode) mods=\(spec.carbonModifiers) status=\(status)")
            if status == noErr { refs.append(ref) }
        }
    }
}
