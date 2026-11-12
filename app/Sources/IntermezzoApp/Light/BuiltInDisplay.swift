import AppKit
import CoreGraphics
import IOKit
import IntermezzoKit

/// The brightness of the Mac's own screen. There is no public API for it: the functions come from the
/// private DisplayServices framework (the same one the ambient light sensor is read through), looked up
/// at run time, so a macOS update can take them away. Everything here fails quietly into "not available".
@MainActor
final class BuiltInDisplay {
    static let shared = BuiltInDisplay()
    static let fallbackMaxNits = 500.0

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getter: GetBrightness?
    private var setter: SetBrightness?
    private var triedLoading = false

    private func load() -> (GetBrightness, SetBrightness)? {
        if let getter, let setter { return (getter, setter) }
        guard !triedLoading else { return nil }
        triedLoading = true
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else {
            Trace.log("brightness: DisplayServices brightness functions not available")
            return nil
        }
        let loaded = (unsafeBitCast(get, to: GetBrightness.self), unsafeBitCast(set, to: SetBrightness.self))
        getter = loaded.0
        setter = loaded.1
        return loaded
    }

    /// The built-in screen while it is on (nil with the lid closed or on a desktop Mac).
    var displayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// The brightness can be read and written on this Mac (the functions exist and the screen answers).
    var isAvailable: Bool { displayID.map { brightness(of: $0) != nil } ?? false }

    func brightness(of id: CGDirectDisplayID) -> Double? {
        guard let (get, _) = load() else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0, value.isFinite else { return nil }
        return Double(min(max(value, 0), 1))
    }

    // MARK: Luminance (read only; used by the nits mode, where macOS keeps driving this screen)

    private typealias GetLinear = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private var linearGetter: GetLinear?
    private var triedLinear = false

    /// The brightness in linear light (0...1), when DisplayServices offers it.
    func linearBrightness(of id: CGDirectDisplayID) -> Double? {
        if !triedLinear {
            triedLinear = true
            if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
               let symbol = dlsym(handle, "DisplayServicesGetLinearBrightness") {
                linearGetter = unsafeBitCast(symbol, to: GetLinear.self)
            }
        }
        guard let linearGetter else { return nil }
        var value: Float = 0
        guard linearGetter(id, &value) == 0, value.isFinite, value >= 0 else { return nil }
        return Double(min(value, 1))
    }

    /// The backlight's own reading on Apple silicon (IORegistry AppleARMBacklight → IODisplayParameters →
    /// BrightnessMilliNits → value), in milli-nits.
    func backlightMilliNits() -> Double? {
        withBacklight { service in
            guard let parameters = IORegistryEntryCreateCFProperty(service, "IODisplayParameters" as CFString,
                                                                   kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let milli = parameters["BrightnessMilliNits"] as? [String: Any],
                  let value = (milli["value"] as? NSNumber)?.doubleValue else { return nil }
            return value
        }
    }

    private static let maxNitsKey = "user-accessible-max-nits" as CFString
    /// A property of the hardware: read once.
    private var limitsRead = false
    private var limits: BuiltInNits.SDRLimits?

    /// The panel's SDR limits from "user-accessible-max-nits" (16.16). On an M5 Max the "backlight" node says
    /// 600 (what macOS reports as Max SDR Luminance, the nominal top) and "backlight-override" says 1000 (the
    /// top in bright light, the outdoor mode). macOS offers no other readable "Max SDR Luminance" property.
    func sdrLimits() -> BuiltInNits.SDRLimits? {
        if !limitsRead {
            limitsRead = true
            let nodes = Self.deviceTreeMaxNits()
            let backlight = nodes["backlight"] ?? Self.backlightParentMaxNits()
            limits = BuiltInNits.sdrLimits(backlight: backlight, declared: Array(nodes.values))
            if let limits { LightLog.detail("brightness: built-in SDR \(Int(limits.nominal)) nits, up to \(Int(limits.ceiling))") }
        }
        return limits
    }

    private static func maxNitsData(of entry: io_registry_entry_t) -> [UInt8]? {
        (IORegistryEntryCreateCFProperty(entry, maxNitsKey, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data).map(Array.init)
    }

    /// The nodes right below the device-tree root (where "backlight" and "backlight-override" live), by name.
    private static func deviceTreeMaxNits() -> [String: [UInt8]] {
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/")
        guard root != 0 else { return [:] }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var found: [String: [UInt8]] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let data = maxNitsData(of: entry) { found[name(of: entry)] = data }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return found
    }

    private static func name(of entry: io_registry_entry_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }

    /// The backlight driver's parent (the "backlight" node), in case the device tree is named differently.
    private static func backlightParentMaxNits() -> [UInt8]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        return maxNitsData(of: parent)
    }

    private func withBacklight<T>(_ body: (io_service_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return body(service)
    }

    /// How far above SDR white the screen can show HDR right now (1 = none).
    func currentHeadroom(of id: CGDirectDisplayID) -> Double? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }.map { Double($0.maximumExtendedDynamicRangeColorComponentValue) }
    }

    /// The built-in screen's SDR white in nits now (see `BuiltInNits.sdrNits`), with the maximum used for it.
    /// The panel's SDR limits as used: a value typed in the monitor profile is the nominal maximum (the
    /// registry's outdoor ceiling still applies above it); older MacBooks without a reading: about 500 nits.
    func effectiveLimits(manualMax: Double?) -> BuiltInNits.SDRLimits {
        let read = sdrLimits()
        let nominal = manualMax ?? read?.nominal ?? Self.fallbackMaxNits
        return BuiltInNits.SDRLimits(nominal: nominal, ceiling: read?.ceiling ?? nominal)
    }

    /// The built-in screen's SDR white in nits now and the maximum in effect: the nominal one, or the outdoor
    /// ceiling once the measured white is above the nominal. Measured values are cut only at the ceiling.
    func sdrNits(of id: CGDirectDisplayID, manualMax: Double?) -> (nits: Double?, maxNits: Double?) {
        let limits = effectiveLimits(manualMax: manualMax)
        let nits = BuiltInNits.sdrNits(backlightMilliNits: backlightMilliNits(), headroom: currentHeadroom(of: id),
                                       linear: linearBrightness(of: id), slider: brightness(of: id),
                                       maxNits: limits.nominal, ceiling: limits.ceiling)
        return (nits, BuiltInNits.effectiveMax(limits, measuredNits: nits))
    }

    @discardableResult
    func setBrightness(_ value: Double, of id: CGDirectDisplayID) -> Bool {
        guard let (_, set) = load(), value.isFinite else { return false }
        let ok = set(id, Float(min(max(value, 0), 1))) == 0
        if !ok { Trace.log("brightness: the built-in screen refused \(String(format: "%.3f", value))") }
        return ok
    }
}
