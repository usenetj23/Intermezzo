import AppKit
import IOKit
import IntermezzoKit

/// The Mac's ambient light sensor (the one behind automatic brightness and True Tone), read in lux.
/// There is no public API for it: the value comes from the private DisplayServices framework, loaded
/// at run time, so a macOS update can take it away. Everything here fails quietly into "no reading".
@MainActor
final class AmbientSensor {
    static let shared = AmbientSensor()

    private var client: NSObject?
    private var triedLoading = false
    private var samples: [Double] = []
    private static let keepSamples = 5

    /// The lid is closed (a MacBook used with external displays): the sensor sees nothing useful then.
    static var lidClosed: Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    private func loadClient() -> NSObject? {
        if let client { return client }
        guard !triedLoading else { return nil }
        triedLoading = true
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        guard let type = NSClassFromString("DisplayServicesClient") as? NSObject.Type else {
            Trace.log("ambient light: DisplayServicesClient not available")
            return nil
        }
        client = type.init()
        return client
    }

    /// One reading in lux, or nil when the Mac has no such sensor.
    private func readLux() -> Double? {
        guard let client = loadClient() else { return nil }
        let selector = NSSelectorFromString("copyPropertyForKey:")
        guard client.responds(to: selector),
              let result = client.perform(selector, with: "AggregatedLux") else { return nil }
        // "copy…" returns an owned object.
        return (result.takeRetainedValue() as? NSNumber)?.doubleValue
    }

    /// Takes a reading and returns the median of the last few; nil with the lid closed or without a sensor.
    func smoothedLux() -> Double? {
        if Self.lidClosed {
            samples.removeAll()
            return nil
        }
        if let lux = readLux() {
            samples.append(lux)
            if samples.count > Self.keepSamples { samples.removeFirst(samples.count - Self.keepSamples) }
        }
        return AmbientLight.smoothed(samples)
    }

    func reset() { samples.removeAll() }
}
