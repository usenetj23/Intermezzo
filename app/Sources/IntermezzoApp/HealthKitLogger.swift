import AppKit
import HealthKit
import IntermezzoKit

// MARK: - Apple Health bridge (best effort)
//
// Pushes recorded drinks to HealthKit's waterConsumption sample type so the
// totals show up in the Health app on macOS 26+ / paired iPhone. Authorization
// is requested once, lazily, when the first drink is logged. Everything is
// guarded: no HealthKit, no authorization, or an old system simply means the
// drink is only kept in Intermezzo's own local registry.
//
// Garmin Connect and MyFitnessPal are cloud services with no local store —
// Intermezzo does not talk to them (no credentials, no silent uploads).

@MainActor
final class HealthKitLogger {
    static let shared = HealthKitLogger()

    private let store = HKHealthStore()
    private var requested = false

    func logDrink(kind: String, ml: Int) {
        guard #available(macOS 13.0, *) else {
            Trace.log("healthkit: unavailable on this system")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            Trace.log("healthkit: no health data available")
            return
        }
        let type = HKQuantityType(.dietaryWater)
        if !requested {
            requested = true
            store.requestAuthorization(toShare: [type], read: []) { success, error in
                Task { @MainActor in
                    Trace.log("healthkit auth: success=\(success) err=\(error?.localizedDescription ?? "-")")
                }
            }
        }
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            Trace.log("healthkit: not authorized, kept local only")
            return
        }
        let quantity = HKQuantity(unit: HKUnit.literUnit(with: .milli),
                                   doubleValue: Double(ml))
        let sample = HKQuantitySample(type: type, quantity: quantity,
                                      start: Date(), end: Date())
        store.save(sample) { success, error in
            Task { @MainActor in
                Trace.log("healthkit save \(ml)ml \(kind): success=\(success) err=\(error?.localizedDescription ?? "-")")
            }
        }
    }
}
