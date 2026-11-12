import Foundation
import IOKit
import IntermezzoKit

/// The brightest white each connected monitor declares in its EDID (HDR static metadata). Most SDR monitors
/// do not declare it; the user can type it per monitor. Read from the IORegistry, where the display drivers
/// publish the EDID, on a background queue; anything unreadable is simply "unknown".
@MainActor
final class DisplayEDID: ObservableObject {
    static let shared = DisplayEDID()

    /// Published so the monitor rows show a value as soon as the background scan has it.
    @Published private(set) var maxNitsByKey: [MonitorKey: Double] = [:]
    /// A display just plugged in may publish its EDID a moment later: an empty scan is repeated once.
    private var retryLeft = true
    private static let retryDelay: UInt64 = 5_000_000_000
    private var requested = false
    /// Only the newest scan's result is kept (displays can change while one runs).
    private var generation = 0

    /// Declared maximum for a kind of monitor, or nil when it does not say (or the first scan is still running).
    func maxNits(for key: MonitorKey) -> Double? {
        if !requested { refresh() }
        return maxNitsByKey[key]
    }

    /// Reads all EDIDs again (after displays were plugged or unplugged), off the main thread.
    func refresh() {
        retryLeft = true
        scanInBackground()
    }

    private func scanInBackground() {
        requested = true
        generation += 1
        let scan = generation
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run { DisplayEDID.shared.publish(found, scan: scan) }
        }
    }

    private func publish(_ found: [MonitorKey: Double], scan: Int) {
        guard scan == generation else { return }
        if found.isEmpty, retryLeft {
            retryLeft = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.retryDelay)
                guard scan == DisplayEDID.shared.generation else { return }
                DisplayEDID.shared.scanInBackground()
            }
        }
        guard found != maxNitsByKey else { return }
        LightLog.detail("edid: declared max nits \(found.map { "\($0.key.id)=\(Int($0.value))" })")
        maxNitsByKey = found
    }

    // MARK: Reading (any thread)

    /// Services that carry a display's EDID: the display ports on Apple silicon, the display connection
    /// (and the AppleDisplay below it) on Intel. Their children are searched too.
    private nonisolated static let serviceClasses = ["IOPortTransportStateDisplayPort", "IOPortTransportStateHDMI",
                                                    "DCPAVServiceProxy", "IODisplayConnect"]
    /// "EDID" on Apple silicon, "IODisplayEDID" on Intel.
    private nonisolated static let edidKeys = ["EDID", "IODisplayEDID"]

    private nonisolated static func scan() -> [MonitorKey: Double] {
        var found: [MonitorKey: Double] = [:]
        for edid in serviceClasses.flatMap(edids(ofClass:)) {
            guard let key = EDIDInfo.key(edid), found[key] == nil, let nits = EDIDInfo.maxLuminance(edid) else { continue }
            found[key] = nits
        }
        return found
    }

    private nonisolated static func edids(ofClass name: String) -> [[UInt8]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[UInt8]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            for key in edidKeys {
                let options = IOOptionBits(kIORegistryIterateRecursively)
                if let data = IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString,
                                                              kCFAllocatorDefault, options) as? Data {
                    result.append(Array(data))
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }
}
