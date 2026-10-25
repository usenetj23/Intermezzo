import AppKit
import IOKit.ps
import IOKit.pwr_mgt
import IntermezzoKit

enum AwakeKeys {
    /// This Mac only (see SyncPolicy): what is on right now.
    static let mode = "awakeMode"
    static let until = "awakeUntil"
    /// Preferences, synchronised.
    static let defaultLevel = "awakeDefaultLevel"
    static let batteryFloor = "awakeBatteryFloor"
    static let stopOnLowPower = "awakeStopLowPower"
    static let stopOnThermal = "awakeStopThermal"
    static let withFocus = "awakeWithFocus"
    static let withApps = "awakeWithApps"
    static let apps = "awakeApps"
}

/// Keeps the Mac awake with IOKit power assertions (no extra process, no privileges): on request,
/// during a focus session, while chosen apps run, and during a break. Safety limits (battery,
/// Low Power Mode, heat) release it; the decisions live in `KeepAwakePolicy`.
@MainActor
final class KeepAwakeController: ObservableObject {
    static let shared = KeepAwakeController()

    @Published private(set) var holding: KeepAwakeLevel?
    @Published private(set) var manualLevel: KeepAwakeLevel?
    @Published private(set) var manualUntil: Date?
    @Published private(set) var lastStop: KeepAwakeStop?
    @Published private(set) var activeSources: [String] = []
    @Published private(set) var others: [HoldingProcess] = []
    @Published private(set) var power = PowerConditions(onBattery: false, batteryPercent: nil, lowPowerMode: false, thermal: .nominal)

    private let defaults = UserDefaults.standard
    private var systemAssertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var timer: Timer?
    private var breakHold = false

    // MARK: Settings

    var safety: KeepAwakeSafety {
        KeepAwakeSafety(batteryFloorPercent: defaults.object(forKey: AwakeKeys.batteryFloor) as? Int ?? 20,
                        stopOnLowPowerMode: defaults.object(forKey: AwakeKeys.stopOnLowPower) as? Bool ?? true,
                        stopOnThermal: defaults.object(forKey: AwakeKeys.stopOnThermal) as? Bool ?? true)
    }

    var defaultLevel: KeepAwakeLevel {
        KeepAwakeLevel(rawValue: defaults.string(forKey: AwakeKeys.defaultLevel) ?? "") ?? .system
    }

    private var chosenApps: [String] {
        guard defaults.bool(forKey: AwakeKeys.withApps) else { return [] }
        return KeepAwakeApps.list(fromCommaText: defaults.string(forKey: AwakeKeys.apps) ?? "")
    }

    // MARK: Lifecycle

    /// Called once at launch: picks up a request that was running when the app last quit.
    func start() {
        if let raw = defaults.string(forKey: AwakeKeys.mode), let level = KeepAwakeLevel(rawValue: raw) {
            let until = defaults.double(forKey: AwakeKeys.until)
            manualLevel = level
            manualUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
        }
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        evaluate()
    }

    func shutdown() {
        release(&systemAssertion)
        release(&displayAssertion)
    }

    // MARK: Commands

    func turnOn(level: KeepAwakeLevel? = nil, duration: KeepAwakeDuration = .indefinitely) {
        let chosen = level ?? defaultLevel
        manualLevel = chosen
        manualUntil = duration.end(from: Date())
        lastStop = nil
        persist()
        evaluate()
    }

    func turnOff() {
        manualLevel = nil
        manualUntil = nil
        lastStop = nil
        persist()
        evaluate()
    }

    func toggle() {
        manualLevel == nil ? turnOn() : turnOff()
    }

    /// A break holds the Mac (as before), whatever the safety limits say.
    func setBreakHold(_ on: Bool) {
        breakHold = on
        evaluate()
    }

    private func persist() {
        if let level = manualLevel {
            defaults.set(level.rawValue, forKey: AwakeKeys.mode)
            defaults.set(manualUntil?.timeIntervalSince1970 ?? 0, forKey: AwakeKeys.until)
        } else {
            defaults.removeObject(forKey: AwakeKeys.mode)
            defaults.removeObject(forKey: AwakeKeys.until)
        }
    }

    // MARK: Decision

    func evaluate() {
        power = Self.readPower()
        var levels: [KeepAwakeLevel] = []
        var sources: [String] = []

        if let level = manualLevel {
            let request = KeepAwakeRequest(level: level, until: manualUntil)
            switch KeepAwakePolicy.manual(request: request, safety: safety, power: power, now: Date()) {
            case .hold(let held):
                levels.append(held)
                sources.append(String(localized: "na Twoje życzenie"))
            case .release(let reason):
                if let reason { announceStop(reason) }
                manualLevel = nil
                manualUntil = nil
                persist()
            }
        }

        if defaults.bool(forKey: AwakeKeys.withFocus), PomodoroController.shared.isEnabled,
           PomodoroController.shared.ledger.current != nil,
           let level = KeepAwakePolicy.automatic(wanted: .system, safety: safety, power: power) {
            levels.append(level)
            sources.append(String(localized: "trwa sesja skupienia"))
        }

        let apps = chosenApps
        if !apps.isEmpty {
            let running = NSWorkspace.shared.runningApplications.flatMap {
                [$0.localizedName, $0.executableURL?.lastPathComponent].compactMap { $0 }
            }
            if let match = KeepAwakeApps.firstMatch(wanted: apps, running: running),
               let level = KeepAwakePolicy.automatic(wanted: .system, safety: safety, power: power) {
                levels.append(level)
                sources.append(String(localized: "działa \(match)"))
            }
        }

        if breakHold {
            levels.append(.system)
            sources.append(String(localized: "trwa przerwa"))
        }

        activeSources = sources
        hold(KeepAwakePolicy.combine(levels))
    }

    private func announceStop(_ reason: KeepAwakeStop) {
        lastStop = reason
        let body: String
        switch reason {
        case .timerEnded: return
        case .batteryLow: body = String(localized: "Bateria spadła poniżej ustawionego progu, więc Mac może już zasnąć.")
        case .lowPowerMode: body = String(localized: "Włączył się tryb niskiego zużycia energii, więc Mac może już zasnąć.")
        case .thermal: body = String(localized: "Mac mocno się nagrzał, więc czuwanie zostało wyłączone.")
        }
        ToastCenter.shared.show(title: String(localized: "Czuwanie wyłączone"), body: body, symbol: "cup.and.saucer")
    }

    // MARK: Assertions

    private func hold(_ level: KeepAwakeLevel?) {
        holding = level
        switch level {
        case .none:
            release(&systemAssertion)
            release(&displayAssertion)
        case .some(.system):
            acquire(&systemAssertion, kIOPMAssertPreventUserIdleSystemSleep)
            release(&displayAssertion)
        case .some(.systemAndDisplay):
            acquire(&systemAssertion, kIOPMAssertPreventUserIdleSystemSleep)
            acquire(&displayAssertion, kIOPMAssertPreventUserIdleDisplaySleep)
        }
    }

    private func acquire(_ id: inout IOPMAssertionID, _ type: String) {
        guard id == 0 else { return }
        var newID: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Intermezzo keep awake" as CFString, &newID)
        if result == kIOReturnSuccess {
            id = newID
            Trace.log("keep awake: holding \(type)")
        } else {
            Trace.log("keep awake: assertion failed (\(result))")
        }
    }

    private func release(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
        Trace.log("keep awake: released")
    }

    // MARK: Readings

    private static func readPower() -> PowerConditions {
        var onBattery = false
        var percent: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
            let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]) ?? []
            for source in sources {
                guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                      let current = d[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                percent = current * 100 / maximum
            }
        }
        let thermal: ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        return PowerConditions(onBattery: onBattery, batteryPercent: percent,
                               lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, thermal: thermal)
    }

    /// Who else keeps the Mac awake (read-only `pmset -g assertions`), off the main thread.
    func refreshOthers() {
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "assertions"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let list = PmsetAssertions.parse(String(decoding: data, as: UTF8.self), excluding: ownPID)
                .filter { $0.type.hasPrefix("PreventUserIdle") || $0.type == "PreventSystemSleep" || $0.type == "NoIdleSleepAssertion" }
            await MainActor.run { self.others = list }
        }
    }
}
