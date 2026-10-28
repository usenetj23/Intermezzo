import Foundation

/// The state of the timer in one word, for colouring the menu-bar icon.
public enum StatusTint: String, Equatable, Sendable {
    case running
    case onBreak
    /// Held by a situation (meeting, video, Focus, rule, idle).
    case held
    /// Outside the working hours or the work zone, or on vacation.
    case outside
    case manual
}

/// What one factor does to the break timer right now.
public enum GateVerdict: String, Equatable, Sendable {
    /// Pauses the timer.
    case blocking
    /// Switched on and satisfied: lets the timer run.
    case passing
    /// Switched off, not applicable, or switched on without a match (one match is enough in the work zone).
    case inactive
}

/// Where a factor sits on the way from the clock to the timer.
public enum GateGroup: String, CaseIterable, Sendable {
    case schedule
    case zone
    case detection
    case user

    public var title: String {
        switch self {
        case .schedule: return kitL("Harmonogram")
        case .zone: return kitL("Strefa pracy")
        case .detection: return kitL("Wykrywanie")
        case .user: return kitL("Ty")
        }
    }
}

/// One thing that can pause (or let through) the break timer, with the reason in plain words.
public struct GateFactor: Identifiable, Equatable, Sendable {
    public let id: String
    public let group: GateGroup
    public let title: String
    public let verdict: GateVerdict
    public let detail: String
    /// Shown for orientation only: it does not change the timer (for example the work-log LAN, which breaks do not read).
    public let informational: Bool
    /// Settings pane that controls this factor (a pane id the app understands), if it has one.
    public let link: String?

    public init(id: String, group: GateGroup, title: String, verdict: GateVerdict, detail: String,
                informational: Bool = false, link: String? = nil) {
        self.link = link
        self.id = id
        self.group = group
        self.title = title
        self.verdict = verdict
        self.detail = detail
        self.informational = informational
    }
}

/// Every factor plus where the timer ended up.
public struct GateReport: Equatable, Sendable {
    public var factors: [GateFactor] = []
    public var running = false
    public var onBreak = false

    public init(factors: [GateFactor] = [], running: Bool = false, onBreak: Bool = false) {
        self.factors = factors
        self.running = running
        self.onBreak = onBreak
    }

    public func items(_ verdict: GateVerdict) -> [GateFactor] {
        factors.filter { $0.verdict == verdict }
    }

    /// Factors that really pause the timer (informational ones never do).
    public var blockers: [GateFactor] {
        factors.filter { $0.verdict == .blocking && !$0.informational }
    }

    /// The worst verdict in a group, for the chain: blocking beats passing beats inactive.
    public func verdict(of group: GateGroup) -> GateVerdict {
        let own = factors.filter { $0.group == group && !$0.informational }
        if own.contains(where: { $0.verdict == .blocking }) { return .blocking }
        if own.contains(where: { $0.verdict == .passing }) { return .passing }
        return .inactive
    }

    /// One word for the menu-bar icon colour.
    public var tint: StatusTint {
        if onBreak { return .onBreak }
        if running { return .running }
        let held = blockers
        if held.isEmpty || held.allSatisfy({ $0.id == "manual" }) { return .manual }
        if held.contains(where: { ["hours", "zone", "vacation", "holiday"].contains($0.id) }) { return .outside }
        return .held
    }

    public var headline: String {
        if onBreak { return kitL("Trwa przerwa") }
        if running { return kitL("Timer działa") }
        let n = blockers.count
        if n == 0 { return kitL("Timer wstrzymany") }
        return kitL("Timer wstrzymany: %lld %@", n, kitL(Self.reasons(n)))
    }

    /// Polish plural of "powód".
    static func reasons(_ n: Int) -> String {
        if n == 1 { return "powód" }
        let last = n % 10
        let tens = n % 100
        if (2...4).contains(last) && !(12...14).contains(tens) { return "powody" }
        return "powodów"
    }
}
