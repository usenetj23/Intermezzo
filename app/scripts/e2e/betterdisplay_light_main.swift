import AppKit
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) { print((ok ? "PASS " : "FAIL ") + what); if !ok { failures += 1 } }
let center = DistributedNotificationCenter.default()
func bd(_ command: String, _ params: [(String, String?)]) -> BetterDisplayResponse? {
    let uuid = UUID().uuidString
    var answer: BetterDisplayResponse?
    let t = center.addObserver(forName: .init(BetterDisplayProtocol.responseName), object: nil, queue: .main) { n in
        if let s = n.object as? String, let r = BetterDisplayProtocol.decodeResponse(s), r.uuid == uuid { answer = r }
    }
    center.postNotificationName(.init(BetterDisplayProtocol.requestName),
        object: BetterDisplayProtocol.requestJSON(uuid: uuid, command: command, parameters: params), userInfo: nil, deliverImmediately: true)
    let end = Date().addingTimeInterval(4)
    while answer == nil && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    center.removeObserver(t); return answer
}
func level(_ id: Int) -> Double { BetterDisplayProtocol.number(bd("get", [("displayID", String(id)), ("brightness", nil)])?.payload) ?? -1 }
func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func groupOn(_ name: String) -> String { bd("get", [("name", name), ("enabled", nil)])?.payload ?? "?" }

let ids = [1, 3, 4]
let original = Dictionary(uniqueKeysWithValues: ids.map { ($0, level($0)) })
let trueTone0 = bd("get", [("trueTone", nil)])?.payload
let group = ProcessInfo.processInfo.environment["BD_GROUP"] ?? "DeskPair"
let group0 = groupOn(group)
print("start: \(original) trueTone=\(trueTone0 ?? "?") group \(group)=\(group0)")
func rescue() {
    if group0 == "on" { _ = bd("set", [("name", group), ("enabled", "on")]) }
    spin(1.2)
    for (id, v) in original where v > 0 { _ = bd("set", [("displayID", String(id)), ("brightness", String(format: "%.3f", v))]) }
    if trueTone0 == "on" { _ = bd("set", [("trueTone", "on")]) }
}
for sig in [SIGINT, SIGTERM] { signal(sig) { _ in rescue(); exit(130) } }

MainActor.assumeIsolated {
    print("== A. light sensor and lid (real app code)")
    let sensor = AmbientSensor.shared
    print("   lid closed: \(AmbientSensor.lidClosed)")
    check(!AmbientSensor.lidClosed, "lid reads as open")
    var readings: [Double] = []
    for _ in 1...60 { if let v = sensor.smoothedLux() { readings.append(v) }; spin(0.05) }
    print("   60 reads, last smoothed lux: \(readings.last.map { String(format: "%.1f", $0) } ?? "nil")")
    check(readings.count == 60 && (readings.last ?? -1) >= 0, "sensor returns a lux value on every read (no crash, no leak-induced failure)")
    let adjusted = AmbientLight.adjustedKelvin(1900, lux: readings.last ?? 54, settings: LightProfile.recommended.settings(wakeMinutes: 390), roomLampK: nil)
    print("   evening 1900 K in this room becomes \(Int(adjusted)) K")

    print("== B. groups")
    check(BetterDisplayProtocol.parseGroupNames(payload: bd("get", [("type", "displayGroup"), ("identifiers", nil)])?.payload ?? "") == [group],
          "the group is listed by name")

    print("== C. exception with the group option: Dell 3 neutral, Dell 4 dimmed independently")
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: BetterDisplayKeys.dim)
    defaults.set(20, forKey: BetterDisplayKeys.dimPercent)
    defaults.set(true, forKey: BetterDisplayKeys.unlinkGroup)
    defaults.set(false, forKey: BetterDisplayKeys.trueTone)
    defaults.removeObject(forKey: BetterDisplayKeys.state)
    let settings = LightProfile.recommended.settings(wakeMinutes: 390)
    let light = BetterDisplayLight.shared
    light.update(kelvin: 1900, settings: settings, active: true, neutral: [3], lux: 54)
    spin(22)
    print("   brightness now: \(ids.map { "\($0)=\(String(format: "%.3f", level($0)))" })  group is \(groupOn(group))")
    check(groupOn(group) == "off", "the group was switched off for the exception")
    check(abs(level(3) - original[3]!) < 0.03, "Dell 3 (full-screen app) keeps its original brightness")
    check(abs(level(4) - original[4]! * 0.8) < 0.04, "Dell 4 is dimmed on its own")
    check(abs(level(1) - original[1]! * 0.8) < 0.05, "the built-in display is dimmed")
    let saved = BetterDisplayState.decode(defaults.data(forKey: BetterDisplayKeys.state))
    check(saved.disabledGroups == [group], "the switched-off group is remembered on disk")

    print("== D. exception over: dimming continues, group comes back only when the evening ends")
    light.update(kelvin: 1900, settings: settings, active: true, neutral: [], lux: 54)
    spin(14)
    check(abs(level(3) - original[3]! * 0.8) < 0.04 && abs(level(4) - original[4]! * 0.8) < 0.04, "both Dells dimmed again, individually")
    check(groupOn(group) == "off", "the group stays off during the evening")

    print("== E. Light off: everything back, group on again")
    light.update(kelvin: 6500, settings: settings, active: false, neutral: [], lux: nil)
    spin(18)
    for id in ids { check(abs(level(id) - original[id]!) < 0.03, "display \(id) back to \(String(format: "%.3f", level(id))) (original \(String(format: "%.3f", original[id]!)))") }
    check(groupOn(group) == "on", "the group is switched on again")
    check(BetterDisplayState.decode(defaults.data(forKey: BetterDisplayKeys.state)).isEmpty, "saved state cleared")

    print("== F. bright room: dimming is weaker")
    defaults.set(false, forKey: BetterDisplayKeys.unlinkGroup)
    light.update(kelvin: 1900, settings: settings, active: true, neutral: [], lux: 600)
    spin(14)
    let expected = 1 - 0.2 * AmbientLight.dimScale(lux: 600)
    print("   600 lx: factor \(String(format: "%.3f", expected))")
    check(abs(level(1) - original[1]! * expected) < 0.05, "dimming at 600 lx is the reduced amount")
    light.update(kelvin: 6500, settings: settings, active: false, neutral: [], lux: nil)
    spin(14)
}
rescue()
spin(3)
print("end: \(Dictionary(uniqueKeysWithValues: ids.map { ($0, level($0)) })) trueTone=\(bd("get", [("trueTone", nil)])?.payload ?? "?") group=\(groupOn(group))")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
