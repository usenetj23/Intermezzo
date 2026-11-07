import Foundation

/// What Intermezzo publishes about itself for automation (the state file, the notifications, the Shortcuts actions
/// and `intermezzo://state`). Plain values only: nothing the person typed (event titles, network names) is in it.
public struct AutomationState: Codable, Equatable, Sendable {
    public var appVersion: String = ""
    /// "running", "paused" or "onBreak".
    public var timer: String = "paused"
    /// Why the timer is held, sorted (see `PauseReason`): "manual", "userAway", "outsideWorkingHours", "inMeeting"...
    public var pauseReasons: [String] = []
    /// When the next break starts, while the timer runs.
    public var nextBreakAt: Date?
    /// "short" or "long".
    public var nextBreakKind: String = "short"
    /// The break on screen: "short" or "long", and when it ends.
    public var breakKind: String?
    public var breakEndsAt: Date?
    /// Whether the Mac is in the work zone; nil when no zone source is switched on.
    public var inWorkZone: Bool?
    /// Whether it is within the working hours; nil when the hours are not enforced (or a vacation or holiday applies).
    public var inWorkingHours: Bool?
    /// Which zone sources match: "calendar", "vpn", "wifi", "place", "lan", "focus".
    public var workZoneSources: [String] = []
    public var inMeeting = false
    public var watchingVideo = false
    public var focusActive = false
    /// Names of the Focus modes that are on.
    public var focusModes: [String] = []
    /// No input for the idle time: the timer is held.
    public var away = false
    public var screenLocked = false
    public var vpnConnected = false
    public var lightOn = false
    public var lightKelvin: Int?
    public var keepAwake = false
    public var updatedAt = Date(timeIntervalSince1970: 0)

    public init() {}

    /// Equal apart from the time stamp: a refreshed stamp alone is not a change.
    public func sameContent(as other: AutomationState) -> Bool {
        var a = self, b = other
        a.updatedAt = b.updatedAt
        return a == b
    }

    public var onBreak: Bool { timer == "onBreak" }
    public var running: Bool { timer == "running" }

    public func jsonData(pretty: Bool = true) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }

    public func jsonString(pretty: Bool = true) -> String {
        String(decoding: jsonData(pretty: pretty), as: UTF8.self)
    }

    public static func decode(_ data: Data) -> AutomationState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AutomationState.self, from: data)
    }
}

/// Something that happened, named for automation. Break events come straight from the engine; the rest are read
/// from the difference between two states.
public enum AutomationEvent: String, CaseIterable, Sendable {
    case breakBegan, breakCompleted, breakSkipped, breakPostponed
    case timerPaused, timerResumed
    case zoneEntered, zoneLeft
    case meetingBegan, meetingEnded
    case focusOn, focusOff
    case awayBegan, awayEnded
    case screenLocked, screenUnlocked
    case vpnConnected, vpnDisconnected

    /// The events a change from `old` to `new` means. Breaks are not here (the engine reports them).
    public static func diff(from old: AutomationState, to new: AutomationState) -> [AutomationEvent] {
        var events: [AutomationEvent] = []
        if old.timer == "running", new.timer == "paused" { events.append(.timerPaused) }
        if old.timer == "paused", new.timer == "running" { events.append(.timerResumed) }
        if old.inWorkZone == false, new.inWorkZone == true { events.append(.zoneEntered) }
        if old.inWorkZone == true, new.inWorkZone == false { events.append(.zoneLeft) }
        if !old.inMeeting, new.inMeeting { events.append(.meetingBegan) }
        if old.inMeeting, !new.inMeeting { events.append(.meetingEnded) }
        if !old.focusActive, new.focusActive { events.append(.focusOn) }
        if old.focusActive, !new.focusActive { events.append(.focusOff) }
        if !old.away, new.away { events.append(.awayBegan) }
        if old.away, !new.away { events.append(.awayEnded) }
        if !old.screenLocked, new.screenLocked { events.append(.screenLocked) }
        if old.screenLocked, !new.screenLocked { events.append(.screenUnlocked) }
        if !old.vpnConnected, new.vpnConnected { events.append(.vpnConnected) }
        if old.vpnConnected, !new.vpnConnected { events.append(.vpnDisconnected) }
        return events
    }

    /// The Break Actions trigger that runs when this event happens; nil for the break events, which have
    /// their own timing points.
    public var trigger: BreakActionWhen? {
        switch self {
        case .breakBegan, .breakCompleted, .breakSkipped, .breakPostponed: return nil
        case .timerPaused: return .timerPaused
        case .timerResumed: return .timerResumed
        case .zoneEntered: return .zoneEntered
        case .zoneLeft: return .zoneLeft
        case .meetingBegan: return .meetingBegan
        case .meetingEnded: return .meetingEnded
        case .focusOn: return .focusOn
        case .focusOff: return .focusOff
        case .awayBegan: return .awayBegan
        case .awayEnded: return .awayEnded
        case .screenLocked: return .screenLocked
        case .screenUnlocked: return .screenUnlocked
        case .vpnConnected: return .vpnConnected
        case .vpnDisconnected: return .vpnDisconnected
        }
    }
}

/// When an action may run, whatever its trigger: the work zone, a meeting, the lock screen, and a pause between runs.
public struct ActionConditions: Codable, Equatable, Sendable {
    public enum Zone: String, Codable, CaseIterable, Sendable {
        case any, inside, outside
    }

    public var zone: Zone = .any
    public var notInMeeting = false
    public var screenUnlocked = false
    /// Least seconds between two runs of the action; 0 = no limit.
    public var cooldownSeconds = 0

    public init() {}

    public var isDefault: Bool { self == ActionConditions() }

    private enum CodingKeys: String, CodingKey { case zone, notInMeeting, screenUnlocked, cooldownSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zone = (try? c.decodeIfPresent(Zone.self, forKey: .zone)) ?? .any
        notInMeeting = (try? c.decodeIfPresent(Bool.self, forKey: .notInMeeting)) ?? false
        screenUnlocked = (try? c.decodeIfPresent(Bool.self, forKey: .screenUnlocked)) ?? false
        cooldownSeconds = max(0, (try? c.decodeIfPresent(Int.self, forKey: .cooldownSeconds)) ?? 0)
    }

    /// Whether the action may run now. A condition that needs the state fails when there is none yet, and "inside"
    /// or "outside" the zone fails when no zone source is switched on (the zone is not known then).
    public func allows(state: AutomationState?, lastRun: Date?, now: Date) -> Bool {
        if cooldownSeconds > 0, let last = lastRun, now.timeIntervalSince(last) < TimeInterval(cooldownSeconds) {
            return false
        }
        if isDefault { return true }
        guard let state else { return !(zone != .any || notInMeeting || screenUnlocked) }
        switch zone {
        case .any: break
        case .inside: if state.inWorkZone != true { return false }
        case .outside: if state.inWorkZone != false { return false }
        }
        if notInMeeting, state.inMeeting { return false }
        if screenUnlocked, state.screenLocked { return false }
        return true
    }
}

/// What a Shortcut run by Intermezzo gets as its input (a JSON file): why it ran and the state at that moment.
public struct AutomationPayload: Codable, Equatable, Sendable {
    /// The trigger the action is set to ("zoneEntered", "afterStart", "test"...).
    public var trigger: String
    /// The event that fired it, when there is one ("breakBegan", "zoneEntered"...).
    public var event: String?
    public var state: AutomationState?

    public init(trigger: String, event: String? = nil, state: AutomationState? = nil) {
        self.trigger = trigger
        self.event = event
        self.state = state
    }

    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }
}
