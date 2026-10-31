import Foundation
import IntermezzoKit
import EventKit
import CoreLocation
import CoreWLAN
import Combine

/// "Work zone" detector. Calendar events, VPN connection (by name), Wi-Fi
/// network (by SSID) and GPS location act as ACTIVATORS: when any of them
/// is switched on, breaks only run while at least one matches (working on a
/// "praca" calendar, VPN "work" dialed in, office Wi-Fi, office location).
/// All activators off = breaks always run. Focus keeps its own PAUSE meaning.
/// Everything is polled and throttled; results are plain booleans.
final class WorkDetector: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let store = EKEventStore()
    private var accessAsked = false
    private var accessOK = false {
        didSet { calendarAuthorized = accessOK }
    }

    /// Calendar (EventKit) access granted — Settings renders a green check.
    @Published private(set) var calendarAuthorized = false

    // MARK: - Published state (Settings pane renders green checks from this)

    /// Calendar currently shows an event whose title matches a keyword.
    @Published private(set) var calendarMatch = false
    /// The event that matched, "title (calendar)", for Diagnostics.
    @Published private(set) var calendarMatchSummary = ""
    /// A VPN from the configured name list is connected.
    @Published private(set) var vpnMatch = false
    /// Currently connected VPN names (from scutil), for display.
    @Published private(set) var vpnConnectedNames: [String] = []
    /// Connected Wi-Fi SSID matches the configured list.
    @Published private(set) var wifiMatch = false
    /// Live SSID (empty when unknown / no permission).
    @Published private(set) var currentSSID = ""
    /// Inside the configured radius of the saved location.
    @Published private(set) var geoMatch = false
    /// Distance in meters to the saved location, -1 when unknown.
    @Published private(set) var geoDistanceM: Double = -1
    /// Location authorization (for permission status row).
    @Published private(set) var locationAuthorized = false

    // MARK: - Configuration (pushed by the coordinator from UserDefaults)

    var keywords: [String] = []
    /// Which events count as work: calendar, titles and kinds of event (see CalendarRule).
    var calendarRules: [CalendarRule] = []
    var calendarEnabled = false {
        didSet { if calendarEnabled && !accessAsked { requestAccess() } }
    }
    var vpnEnabled = false
    var vpnNames: [String] = []
    var wifiEnabled = false
    var wifiNames: [String] = []
    var geoEnabled = false
    var geoCenter: CLLocationCoordinate2D?
    var geoRadiusMeters: CLLocationDistance = 300
    /// Holiday guard: events titled "urlop / vacation / …" today → no breaks.
    var holidayEnabled = false {
        didSet { if holidayEnabled && !accessAsked { requestAccess() } }
    }
    var holidayKeywords: [String] = []
    @Published private(set) var holidayToday = false
    private var lastHolidayFetch = Date.distantPast

    private var lastCalFetch = Date.distantPast
    private var lastAuthRefresh = Date.distantPast

    /// Single instance shared between the coordinator and the Settings pane.
    static let shared = WorkDetector()
    private var lastEnvProbe = Date.distantPast
    private var lastGeoRequest = Date.distantPast
    private var probing = false

    // MARK: - Calendar access

    func requestAccess() {
        guard !accessAsked else { return }
        accessAsked = true
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { [weak self] ok, _ in
                DispatchQueue.main.async { self?.accessOK = ok }
            }
        } else {
            store.requestAccess(to: .event) { [weak self] ok, _ in
                DispatchQueue.main.async { self?.accessOK = ok }
            }
        }
    }

    /// Any of the whitelists actually switched on?
    var hasActivators: Bool {
        calendarEnabled || vpnEnabled || wifiEnabled || geoEnabled
    }

    /// Where the enabled work-zone options put the Mac: Wi-Fi or saved place = office, a VPN alone = remote.
    /// nil = none of them matches. Calendar is not presence.
    /// A Focus mode marked as work is on (set by the coordinator). It says nothing about where you are, so alone it counts as remote.
    var focusAtWork = false

    var presencePlace: WorkPlace? {
        if (wifiEnabled && wifiMatch) || (geoEnabled && geoMatch) { return .office }
        if vpnEnabled && vpnMatch { return .remote }
        if focusAtWork { return .remote }
        return nil
    }

    /// Called from the 1-second heartbeat; internally throttled.
    func poll(now: Date) {
        if now.timeIntervalSince(lastAuthRefresh) > 10 {
            lastAuthRefresh = now
            refreshAuthorization()
        }
        if (calendarEnabled || holidayEnabled) && accessOK
            && now.timeIntervalSince(lastCalFetch) > 45 {
            lastCalFetch = now
            fetchCalendar(now: now)
            if holidayEnabled { fetchHoliday(now: now) }
        } else if !calendarEnabled && !holidayEnabled {
            calendarMatch = false
            holidayToday = false
        }
        if (vpnEnabled || wifiEnabled) && !probing
            && now.timeIntervalSince(lastEnvProbe) > 20 {
            lastEnvProbe = now
            probeEnvironment()
        }
        if geoEnabled {
            if !locationAuthorized && !geoAsked { requestLocationAccess() }
            if locationAuthorized, geoCenter != nil,
               now.timeIntervalSince(lastGeoRequest) > 150 {
                lastGeoRequest = now
                locationManager.requestLocation()
            }
        }
    }

    // MARK: - Calendar

    /// Whole-day scan: does today carry a vacation/holiday event?
    private func fetchHoliday(now: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        if now.timeIntervalSince(lastHolidayFetch) < 300 { return }
        lastHolidayFetch = now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        holidayToday = events.contains { ev in
            guard let title = ev.title?.lowercased() else { return false }
            return holidayKeywords.contains { !$0.isEmpty && title.contains($0) }
        }
    }

    private func fetchCalendar(now: Date) {
        let start = now.addingTimeInterval(-2 * 60)
        let end = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var summary = ""
        for ev in store.events(matching: predicate) {
            // Your answer to the invitation; an event without guests has none and counts as accepted.
            let answer = ev.attendees?.first { $0.isCurrentUser }?.participantStatus
            let info = CalendarEventInfo(calendarID: ev.calendar?.calendarIdentifier ?? "", title: ev.title ?? "",
                                         isAllDay: ev.isAllDay, isBusy: ev.availability != .free,
                                         isDeclined: answer == .declined,
                                         isUnconfirmed: answer == .pending || answer == .tentative)
            if CalendarRules.firstMatch(calendarRules, info) != nil {
                summary = "\(info.title) (\(ev.calendar?.title ?? ""))"
                break
            }
        }
        let hit = !summary.isEmpty
        if calendarMatch != hit { calendarMatch = hit }
        if calendarMatchSummary != summary { calendarMatchSummary = summary }
    }

    /// A calendar the user can pick in a rule.
    struct CalendarChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let source: String
    }

    /// Event calendars of every account; empty until Calendar access is granted.
    func availableCalendars() -> [CalendarChoice] {
        guard accessOK else { return [] }
        return store.calendars(for: .event)
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - VPN / Wi-Fi probes (background queue)

    private func probeEnvironment() {
        probing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let names = vpnEnabled ? Self.connectedVPNNames() : []
            let ssid = self.wifiEnabled ? (CWWiFiClient.shared().interface()?.ssid() ?? "") : ""
            let wMatch: Bool
            if self.wifiEnabled {
                let list = self.wifiNames.map { $0.lowercased() }
                wMatch = !ssid.isEmpty && list.contains { $0 == ssid.lowercased() }
            } else {
                wMatch = false
            }
            let vMatch: Bool
            if self.vpnEnabled {
                if self.vpnNames.isEmpty {
                    vMatch = !names.isEmpty
                } else {
                    vMatch = names.contains { live in
                        self.vpnNames.contains { pat in
                            !pat.isEmpty && (live.lowercased().contains(pat.lowercased())
                                || pat.lowercased().contains(live.lowercased()))
                        }
                    }
                }
            } else {
                vMatch = false
            }
            DispatchQueue.main.async {
                // Unchanged values are not published again: every publish redraws General and Work log.
                if self.vpnConnectedNames != names { self.vpnConnectedNames = names }
                if self.vpnMatch != vMatch { self.vpnMatch = vMatch }
                if self.currentSSID != ssid { self.currentSSID = ssid }
                if self.wifiMatch != wMatch { self.wifiMatch = wMatch }
                self.probing = false
            }
        }
    }

    /// Names of currently-connected personal VPN connections ("scutil --nc list").
    /// Falls back to the default-route probe (name unknown) when scutil fails.
    /// `scutil` is a process launch; its answer is reused while the tunnel interfaces stay the same
    /// (at most 2 minutes). Both the break work zone and the work log ask for it.
    private static let vpnCacheLock = NSLock()
    nonisolated(unsafe) private static var vpnCache: (signature: String, at: Date, names: [String])?

    static func connectedVPNNames() -> [String] {
        let signature = WorkZoneProbe.interfaces().tunnels
        vpnCacheLock.lock()
        if let cached = vpnCache, cached.signature == signature, Date().timeIntervalSince(cached.at) < 120 {
            vpnCacheLock.unlock()
            return cached.names
        }
        vpnCacheLock.unlock()
        let names = askScutilForVPNs()
        vpnCacheLock.lock()
        vpnCache = (signature, Date(), names)
        vpnCacheLock.unlock()
        return names
    }

    private static func askScutilForVPNs() -> [String] {
        guard let out = runProcess("/usr/sbin/scutil", ["--nc", "list"]) else {
            return defaultRouteVPN() ? ["?"] : []
        }
        var names = VPNList.connectedNames(fromScutil: out)
        if names.isEmpty {
            // scutil sees nothing — try the routing table as last resort.
            if defaultRouteVPN() { names = ["?"] }
        }
        return names
    }

    /// Default route running over a VPN tunnel (utun2+/tap/ipsec/ppp).
    static func defaultRouteVPN() -> Bool {
        guard let out = runProcess("/usr/sbin/route", ["-n", "get", "default"]) else { return false }
        for rawLine in out.split(separator: "\n") {
            let line = rawLine.lowercased().trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("interface:") else { continue }
            let name = line.replacingOccurrences(of: "interface:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("tap") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return true }
            // utun0/utun1 are system links (AWDL etc.); real VPN tunnels sit above them.
            if name.hasPrefix("utun"), let n = Int(name.dropFirst(4)), n >= 2 { return true }
        }
        return false
    }

    // MARK: - Location / geofence

    private let locationManager = CLLocationManager()
    private var geoAsked = false
    private var lastFix: CLLocation?
    private var pendingLocationCompletion: ((CLLocationCoordinate2D) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        refreshAuthorization()
    }

    /// Read both grants from the system. The delegate callbacks only fire on
    /// CHANGES, and the calendar callback only after we asked, so an already
    /// granted permission would otherwise look "not granted" until then.
    func refreshAuthorization() {
        locationAuthorized = PermissionCenter.location(locationManager.authorizationStatus) == .granted
        accessOK = PermissionCenter.calendar(EKEventStore.authorizationStatus(for: .event)) == .granted
    }

    private func requestLocationAccess() {
        guard !geoAsked else { return }
        geoAsked = true
        locationManager.requestWhenInUseAuthorization()
    }

    /// Settings → Permissions: show the system prompt (only works while undetermined).
    func requestLocationAuthorization() {
        geoAsked = true
        locationManager.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.locationAuthorized = PermissionCenter.location(status) == .granted
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        lastFix = loc
        guard let center = geoCenter else {
            deliverPending(loc)
            return
        }
        let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let dist = loc.distance(from: from)
        geoDistanceM = dist
        geoMatch = dist <= geoRadiusMeters
        deliverPending(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Bez lokalizacji — activator po prostu nie matchinguje; zero crashy.
    }

    private func deliverPending(_ loc: CLLocation) {
        guard let completion = pendingLocationCompletion else { return }
        pendingLocationCompletion = nil
        completion(loc.coordinate)
    }

    /// "Ustaw obecną pozycję": oddaje aktualne współrzędne (fix < 10 min,
    /// inaczej requestLocation). Wywołane z głównego wątku.
    func captureCurrentLocation(_ completion: @escaping (CLLocationCoordinate2D) -> Void) {
        pendingLocationCompletion = completion
        if !geoAsked { requestLocationAccess() }
        if let fix = lastFix, Date().timeIntervalSince(fix.timestamp) < 600 {
            deliverPending(fix)
        } else {
            lastGeoRequest = Date()
            locationManager.requestLocation()
        }
    }

    // MARK: - Rules-engine helpers

    /// Throttled "is there an event right now whose title contains text?"
    /// Used by the Rules engine (calendarText kind). Result cached per text
    /// for 45 s; access is requested lazily on first use.
    private var ruleCalCache: [String: (Date, Bool)] = [:]
    func calendarEventMatches(_ text: String, now: Date) -> Bool {
        let needle = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return false }
        if !accessAsked { requestAccess() }
        if !accessOK { return ruleCalCache[needle]?.1 ?? false }
        if let cached = ruleCalCache[needle], now.timeIntervalSince(cached.0) < 45 {
            return cached.1
        }
        let start = now.addingTimeInterval(-2 * 60)
        let end = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        let hit = events.contains { ($0.title?.lowercased() ?? "").contains(needle) }
        ruleCalCache[needle] = (now, hit)
        return hit
    }

    /// Is a (non all-day, "busy") calendar event running now or starting within
    /// `minutes`? Cached 20 s. Used by "calendar-aware breaks".
    private var busyCache: (Date, Bool)?
    func calendarBusy(within minutes: Int, now: Date) -> Bool {
        if !accessAsked { requestAccess() }
        guard accessOK else { return false }
        if let c = busyCache, now.timeIntervalSince(c.0) < 20 { return c.1 }
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(TimeInterval(minutes * 60)),
                                                 calendars: nil)
        let busy = store.events(matching: predicate).contains { !$0.isAllDay && $0.availability != .free }
        busyCache = (now, busy)
        return busy
    }

    /// Busy (non all-day, not "free") calendar events overlapping [from, to) — for the day forecast.
    func busyIntervals(from: Date, to: Date) -> [DateInterval] {
        guard accessOK, to > from else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.availability != .free }
            .map { DateInterval(start: max($0.startDate, from), end: min($0.endDate, to)) }
            .filter { $0.duration > 0 }
    }

    enum WifiState { case noInterface, off, on }

    /// Whether the Mac's Wi-Fi is switched on. A Mac has no GPS: its position comes from the Wi-Fi networks around,
    /// so with Wi-Fi off there is usually no position at all.
    static func wifiState() -> WifiState {
        guard let interface = CWWiFiClient.shared().interface() else { return .noInterface }
        return interface.powerOn() ? .on : .off
    }

    /// Which Focus modes exist and which are on, from the files macOS keeps for Focus.
    /// nil when they cannot be read (macOS asks for Full Disk Access for that folder).
    struct FocusSnapshot: Equatable {
        var active: [FocusMode]
        var known: [FocusMode]
    }

    static func focusSnapshot() -> FocusSnapshot? {
        let base = NSHomeDirectory() + "/Library/DoNotDisturb/DB/"
        guard let assertions = FileManager.default.contents(atPath: base + "Assertions.json") else { return nil }
        let names = FileManager.default.contents(atPath: base + "ModeConfigurations.json")
            .map(FocusModes.names(configurations:)) ?? [:]
        func mode(_ id: String) -> FocusMode { FocusMode(id: id, name: FocusModes.displayName(for: id, names: names)) }
        let active = FocusModes.activeModeIDs(assertions: assertions).map(mode)
        let knownIDs = Set(names.keys).union(FocusModes.builtInNames.keys).union(active.map(\.id))
        let known = knownIDs.map(mode).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return FocusSnapshot(active: active, known: known)
    }

    /// Focus/DND live state (used by Rules engine + Focus toggle).
    static func detectFocus() -> Bool {
        let path = NSHomeDirectory() + "/Library/DoNotDisturb/DB/Assertions.json"
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains("\"coreFocusFilterState\" : 1")
            || text.contains("\"coreFocusFilterState\":1")
    }

    static func runProcess(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
