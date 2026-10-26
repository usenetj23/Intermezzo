import AppKit
import IntermezzoKit

enum BetterDisplayKeys {
    /// This Mac only (the "betterDisplay" prefix is local in SyncPolicy): the app exists per Mac.
    static let dim = "betterDisplayDim"
    static let dimPercent = "betterDisplayDimPercent"
    static let trueTone = "betterDisplayTrueTone"
    /// While an exception keeps one display neutral, switch off the BetterDisplay group that links the displays.
    static let unlinkGroup = "betterDisplayUnlinkGroup"
    static let state = "betterDisplayState"
}

/// Optional link to BetterDisplay for what a gamma table cannot do: real (DDC) dimming of the monitors in
/// the evening and switching True Tone off while the Light feature runs. Everything is off by default,
/// invisible when BetterDisplay is not installed, and undone when Light is turned off or the app quits.
@MainActor
final class BetterDisplayLight: ObservableObject {
    static let shared = BetterDisplayLight()

    enum Link: Equatable {
        case notInstalled, notRunning, noAnswer, connected
    }

    @Published private(set) var link: Link = .notInstalled
    @Published private(set) var devices: [BetterDisplayDevice] = []
    @Published private(set) var note = ""

    private let defaults = UserDefaults.standard
    private var state: BetterDisplayState
    private var busy = false
    /// Displays whose brightness the user changed by hand; left alone until the evening ends.
    private var yielded: Set<String> = []
    /// What the last pass worked out; an identical pass is skipped for a while (every query is a round trip
    /// to BetterDisplay and often a DDC read on the monitor).
    private var lastPassKey = ""
    private var lastPassAt = Date.distantPast
    private static let recheckInterval: TimeInterval = 3 * 60
    private var lastSaved: Data?
    /// A display whose evening look is being previewed: the regular pass leaves it alone until it is back.
    private var previewed: (id: Int, original: Double)?
    /// True Tone was looked at during this active spell (asked once, not every 30 s).
    private var trueToneChecked = false

    private init() {
        state = BetterDisplayState.decode(UserDefaults.standard.data(forKey: BetterDisplayKeys.state))
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: BetterDisplayProtocol.bundleIdentifier) != nil
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: BetterDisplayProtocol.bundleIdentifier).isEmpty
    }

    private var dimEnabled: Bool { defaults.bool(forKey: BetterDisplayKeys.dim) }
    private var trueToneEnabled: Bool { defaults.bool(forKey: BetterDisplayKeys.trueTone) }
    private var unlinkEnabled: Bool { defaults.bool(forKey: BetterDisplayKeys.unlinkGroup) }
    /// The general maximum dimming; a monitor's own setting replaces it for that monitor.
    var globalDimPercent: Int { defaults.object(forKey: BetterDisplayKeys.dimPercent) as? Int ?? 20 }

    // MARK: Messages

    private final class Once {
        var done = false
    }

    /// One request and its answer; nil when BetterDisplay does not answer within 3 s.
    private func send(_ command: String, _ parameters: [(String, String?)]) async -> BetterDisplayResponse? {
        let uuid = UUID().uuidString
        let json = BetterDisplayProtocol.requestJSON(uuid: uuid, command: command, parameters: parameters)
        let center = DistributedNotificationCenter.default()
        return await withCheckedContinuation { (continuation: CheckedContinuation<BetterDisplayResponse?, Never>) in
            let once = Once()
            var token: NSObjectProtocol?
            func finish(_ value: BetterDisplayResponse?) {
                guard !once.done else { return }
                once.done = true
                if let token { center.removeObserver(token) }
                continuation.resume(returning: value)
            }
            token = center.addObserver(forName: .init(BetterDisplayProtocol.responseName), object: nil, queue: .main) { note in
                guard let text = note.object as? String, let response = BetterDisplayProtocol.decodeResponse(text),
                      response.uuid == uuid else { return }
                finish(response)
            }
            center.postNotificationName(.init(BetterDisplayProtocol.requestName), object: json, userInfo: nil,
                                        deliverImmediately: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }

    /// A request nobody waits for (used while the app quits).
    private func post(_ command: String, _ parameters: [(String, String?)]) {
        let json = BetterDisplayProtocol.requestJSON(uuid: UUID().uuidString, command: command, parameters: parameters)
        DistributedNotificationCenter.default().postNotificationName(
            .init(BetterDisplayProtocol.requestName), object: json, userInfo: nil, deliverImmediately: true)
    }

    // MARK: Connection

    func checkConnection() async {
        guard Self.isInstalled else { link = .notInstalled; return }
        guard isRunning else { link = .notRunning; return }
        guard let response = await send("get", [("identifiers", nil)]), response.result else {
            link = .noAnswer
            return
        }
        devices = BetterDisplayProtocol.parseDevices(payload: response.payload ?? "")
        link = .connected
    }

    // MARK: Driving

    /// Called from the light schedule every 30 s. `active` is false while Light is off or paused.
    /// `neutral` are displays an exception keeps untouched for now; `untouched` the ones the user left alone for good.
    /// `factorFor` gives each display's brightness factor (1 = no dimming), the room's light included.
    func update(active: Bool, neutral: Set<UInt32>, untouched: Set<UInt32>, factorFor: @escaping (UInt32) -> Double) {
        guard Self.isInstalled, !busy else { return }
        let wantsDim = dimEnabled && active
        let wantsTrueTone = trueToneEnabled && active
        guard wantsDim || wantsTrueTone || !state.isEmpty else { return }
        guard isRunning else { return }
        let factors = devices.map { "\($0.displayID):\(Int((factorFor(UInt32($0.displayID)) * 100).rounded()))" }
        let key = "\(wantsDim)|\(wantsTrueTone)|\(factors)|\(neutral.sorted())|\(untouched.sorted())"
        if key == lastPassKey, Date().timeIntervalSince(lastPassAt) < Self.recheckInterval { return }
        lastPassKey = key
        lastPassAt = Date()
        if !wantsTrueTone { trueToneChecked = false }
        busy = true
        Task {
            defer { busy = false }
            if !wantsDim, !(state.originalBrightness.isEmpty && state.disabledGroups.isEmpty) { await restoreBrightness() }
            if !wantsTrueTone, state.trueToneWasOn { await restoreTrueTone() }
            if wantsDim { await dim(factorFor: factorFor, neutral: neutral, untouched: untouched) }
            if wantsTrueTone { await switchTrueToneOff() }
        }
    }

    /// Shows a display's evening brightness for `seconds`, then gives the old one back. Only while the
    /// dimming is switched on and BetterDisplay answers; otherwise nothing happens (the colour still previews).
    func previewDim(displayID: Int, factor: Double, seconds: Double) async {
        guard dimEnabled, Self.isInstalled, isRunning, factor < 0.995, previewed == nil,
              let original = await brightness(of: displayID) else { return }
        previewed = (displayID, original)
        defer { previewed = nil }
        guard await setBrightness(original * factor, of: displayID) else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        _ = await setBrightness(original, of: displayID)
    }

    /// Written only when it changed: every write wakes all UserDefaults observers (sync, hotkeys, light).
    private func save() {
        let data = (state.isEmpty && state.lastSetBrightness.isEmpty) ? nil : state.encoded()
        guard data != lastSaved else { return }
        lastSaved = data
        if let data {
            defaults.set(data, forKey: BetterDisplayKeys.state)
        } else {
            defaults.removeObject(forKey: BetterDisplayKeys.state)
        }
    }

    private func brightness(of id: Int) async -> Double? {
        let response = await send("get", [("displayID", String(id)), ("brightness", nil)])
        guard response?.result == true else { return nil }
        return BetterDisplayProtocol.number(response?.payload)
    }

    private func setBrightness(_ value: Double, of id: Int) async -> Bool {
        let clamped = min(max(value, 0.05), 1)
        return await send("set", [("displayID", String(id)), ("brightness", String(format: "%.3f", clamped))])?.result == true
    }

    private func dim(factorFor: (UInt32) -> Double, neutral: Set<UInt32>, untouched: Set<UInt32>) async {
        if devices.isEmpty { await checkConnection() }
        // Linked displays move together, so a display that must stay different needs the group switched off.
        // Only while the evening is dimming: otherwise the group would be switched off and on every pass.
        let evening = devices.contains { factorFor(UInt32($0.displayID)) < 0.995 }
        let differing = Set(devices.filter { !untouched.contains(UInt32($0.displayID)) }
            .map { Int((factorFor(UInt32($0.displayID)) * 100).rounded()) }).count > 1
        if unlinkEnabled, evening, !neutral.isEmpty || !untouched.isEmpty || differing, state.disabledGroups.isEmpty {
            await disableGroups()
        }
        // Displays that BetterDisplay keeps in step with another one are left to that one.
        let managed = devices.filter { state.followerOf[String($0.displayID)] == nil }
        // Read everything first: a set on one display can move its linked partner.
        var snapshot: [Int: Double] = [:]
        for device in managed {
            if previewed?.id == device.displayID { continue }
            // A display left alone is not even asked, unless we dimmed it earlier and must give its brightness back.
            if untouched.contains(UInt32(device.displayID)), state.originalBrightness[String(device.displayID)] == nil { continue }
            if let value = await brightness(of: device.displayID) { snapshot[device.displayID] = value }
        }
        var handled = Set<Int>()
        for device in managed {
            let id = device.displayID
            let key = String(id)
            guard !handled.contains(id), let current = snapshot[id] else { continue }
            let target = neutral.contains(UInt32(id)) || untouched.contains(UInt32(id)) ? 1 : factorFor(UInt32(id))

            if target >= 0.995 {
                yielded.remove(key)
                if let original = state.originalBrightness[key] {
                    let last = state.lastSetBrightness[key] ?? current
                    if !EveningDimming.userChanged(current: current, lastSet: last) {
                        _ = await setBrightness(original, of: id)
                    }
                    state.originalBrightness[key] = nil
                    state.lastSetBrightness[key] = nil
                }
                continue
            }
            if yielded.contains(key) { continue }
            if let last = state.lastSetBrightness[key], EveningDimming.userChanged(current: current, lastSet: last) {
                // Someone changed the brightness by hand: do not fight them.
                state.originalBrightness[key] = nil
                state.lastSetBrightness[key] = nil
                yielded.insert(key)
                continue
            }
            let original = state.originalBrightness[key] ?? current
            let wanted = original * target
            guard EveningDimming.needsUpdate(target: wanted, lastSet: state.lastSetBrightness[key]) else { continue }
            if state.originalBrightness[key] == nil { state.originalBrightness[key] = original }
            guard await setBrightness(wanted, of: id) else { continue }
            state.lastSetBrightness[key] = wanted

            // Did another display move with it?
            var after: [Int: Double] = [:]
            for other in managed where other.displayID != id && !handled.contains(other.displayID)
                && !untouched.contains(UInt32(other.displayID)) {
                if let value = await brightness(of: other.displayID) { after[other.displayID] = value }
            }
            for follower in BetterDisplayLinks.followers(leader: id, wanted: wanted, before: snapshot, after: after) {
                state.followerOf[String(follower)] = key
                state.originalBrightness[String(follower)] = nil
                state.lastSetBrightness[String(follower)] = nil
                handled.insert(follower)
                Trace.log("betterdisplay: display \(follower) follows display \(id)")
            }
        }
        // The evening is over: forget which displays were linked (the user may change that).
        if state.originalBrightness.isEmpty {
            state.followerOf = [:]
            await releaseGroups()
        }
        save()
    }

    // MARK: Groups

    private func groupNames() async -> [String] {
        let response = await send("get", [("type", "displayGroup"), ("identifiers", nil)])
        guard response?.result == true else { return [] }
        return BetterDisplayProtocol.parseGroupNames(payload: response?.payload ?? "")
    }

    /// Switches off the groups that are on, so that displays can be dimmed one by one; they come back
    /// when the evening's dimming ends (see `releaseGroups`).
    private func disableGroups() async {
        for name in await groupNames() {
            guard await send("get", [("name", name), ("enabled", nil)])?.payload == "on" else { continue }
            if await send("set", [("name", name), ("enabled", "off")])?.result == true {
                state.disabledGroups.append(name)
                Trace.log("betterdisplay: group \(name) switched off for an exception")
            }
        }
        guard !state.disabledGroups.isEmpty else { return }
        state.unlinkFollowers()
        save()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    private func releaseGroups() async {
        for name in state.disabledGroups {
            _ = await send("set", [("name", name), ("enabled", "on")])
            Trace.log("betterdisplay: group \(name) switched on again")
        }
        state.disabledGroups = []
    }

    private func restoreBrightness() async {
        for (key, original) in state.originalBrightness {
            guard let id = Int(key), let current = await brightness(of: id) else { continue }
            let last = state.lastSetBrightness[key] ?? current
            if !EveningDimming.userChanged(current: current, lastSet: last) {
                _ = await setBrightness(original, of: id)
            }
        }
        state.originalBrightness = [:]
        state.lastSetBrightness = [:]
        state.followerOf = [:]
        yielded = []
        await releaseGroups()
        save()
    }

    private func switchTrueToneOff() async {
        guard !state.trueToneWasOn, !trueToneChecked else { return }
        trueToneChecked = true
        let answer = await send("get", [("trueTone", nil)])
        guard answer?.result == true, answer?.payload == "on" else { return }
        if await send("set", [("trueTone", "off")])?.result == true {
            state.trueToneWasOn = true
            note = ""
            save()
        } else {
            note = String(localized: "BetterDisplay nie wyłączył True Tone (ta funkcja wymaga wersji Pro).")
        }
    }

    private func restoreTrueTone() async {
        trueToneChecked = false
        _ = await send("set", [("trueTone", "on")])
        state.trueToneWasOn = false
        save()
    }

    /// At quit: put things back without waiting for answers.
    func shutdown() {
        guard Self.isInstalled, isRunning else { return }
        if let previewed { post("set", [("displayID", String(previewed.id)), ("brightness", String(format: "%.3f", min(max(previewed.original, 0.05), 1)))]) }
        for (key, original) in state.originalBrightness {
            guard let id = Int(key) else { continue }
            post("set", [("displayID", String(id)), ("brightness", String(format: "%.3f", min(max(original, 0.05), 1)))])
        }
        for name in state.disabledGroups { post("set", [("name", name), ("enabled", "on")]) }
        if state.trueToneWasOn { post("set", [("trueTone", "on")]) }
        state = BetterDisplayState()
        lastSaved = nil
        defaults.removeObject(forKey: BetterDisplayKeys.state)
        // Let the notifications leave the process before it exits.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}
