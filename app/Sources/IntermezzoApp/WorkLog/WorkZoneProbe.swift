import CoreWLAN
import Darwin
import Foundation
import IntermezzoKit

enum WorkLogKeys {
    static let enabled = "workLogEnabled"
    /// Comma-separated office SSIDs.
    static let wifiNames = "workLogWifiNames"
    /// Comma-separated VPN names (substring match, like the break work zone).
    static let vpnNames = "workLogVpnNames"
    /// Also count office networks that are only in range (needs Location for the scan).
    static let scanInRange = "workLogScanInRange"
    /// JSON `[WorkNetworkMark]`: remembered office LANs and work-only adapters (docks).
    static let networkMarks = "workLogNetworkMarks"
}

/// Is the Mac at work right now? Office Wi-Fi joined, a remembered office LAN or dock on a cable, or
/// (optionally) office Wi-Fi in range = office; a listed VPN away from all that = remote work. Its own lists, so turning the register on never changes break behaviour.
@MainActor
final class WorkZoneProbe {
    struct Reading: Equatable {
        /// nil = outside the work zone. A work VPN while on the office Wi-Fi is still the office.
        var place: WorkPlace?
        var inZone: Bool { place != nil }
        /// What matched, for the pane: "Wi-Fi: Biuro", "VPN: firma", "w zasięgu: Biuro".
        var reason = ""
        var currentSSID = ""
        var connectedVPNs: [String] = []
        /// Active wired connections, for "remember this LAN / adapter" in the pane.
        var wiredLinks: [WiredNetwork.Link] = []
    }

    private(set) var reading = Reading()
    private var lastProbe = Date.distantPast
    private var lastScan = Date.distantPast
    private var lastScanHit: String?
    private var probing = false
    private var wiredPorts: [WiredNetwork.Port] = []
    private var lastPortList = Date.distantPast

    /// A DHCP answer read for a device, reused while the device keeps the same address.
    struct CachedLease: Sendable {
        let ip: String
        let lease: WiredNetwork.Lease
        let at: Date
    }
    private var leases: [String: CachedLease] = [:]
    /// VPN state is asked from `scutil` only when the tunnel interfaces change, or every couple of minutes.
    private var tunnelSignature = ""
    private var lastVPNCheck = Date.distantPast
    private var lastVPNs: [String] = []
    nonisolated private static let leaseMaxAge: TimeInterval = 5 * 60
    nonisolated private static let vpnMaxAge: TimeInterval = 2 * 60

    private static let probeInterval: TimeInterval = 20
    private static let scanInterval: TimeInterval = 5 * 60

    func poll(now: Date) {
        guard !probing, now.timeIntervalSince(lastProbe) >= Self.probeInterval else { return }
        lastProbe = now
        let d = UserDefaults.standard
        let wifi = Self.list(d.string(forKey: WorkLogKeys.wifiNames))
        let vpn = Self.list(d.string(forKey: WorkLogKeys.vpnNames))
        let mayScan = d.integer(forKey: WorkLogKeys.scanInRange) != 0 && !wifi.isEmpty
            && now.timeIntervalSince(lastScan) >= Self.scanInterval
        if mayScan { lastScan = now }
        let previousScanHit = lastScanHit
        let marks = WorkNetworkMark.decode(d.data(forKey: WorkLogKeys.networkMarks))
        // Adapters come and go with the dock; re-list them every few minutes, not every probe.
        let refreshPorts = now.timeIntervalSince(lastPortList) >= Self.scanInterval
        if refreshPorts { lastPortList = now }
        let knownPorts = wiredPorts
        let knownLeases = leases
        let knownTunnels = tunnelSignature
        let vpnAge = now.timeIntervalSince(lastVPNCheck)
        let knownVPNs = lastVPNs
        probing = true
        DispatchQueue.global(qos: .utility).async {
            let ports = refreshPorts ? Self.listWiredPorts() : knownPorts
            // Addresses come from the kernel directly; only a new or changed address costs a process.
            let interfaces = Self.interfaces()
            let (links, newLeases) = Self.activeLinks(ports, addresses: interfaces.ipv4, cache: knownLeases, now: now)
            let lanHit = WiredNetwork.match(links, marks: marks)
            let ssid = CWWiFiClient.shared().interface()?.ssid() ?? ""
            let askVPN = !vpn.isEmpty && (interfaces.tunnels != knownTunnels || vpnAge >= Self.vpnMaxAge)
            let vpns = vpn.isEmpty ? [] : (askVPN ? WorkDetector.connectedVPNNames() : knownVPNs)
            let joined = !ssid.isEmpty && wifi.contains(ssid.lowercased())
            let vpnHit = vpns.first { live in vpn.contains { live.lowercased().contains($0) } }
            // Scan only off the office Wi-Fi: it is the costly probe. A VPN up does not skip it,
            // since an office network in range means the office, not remote work.
            var scanHit = previousScanHit
            if mayScan {
                scanHit = joined || lanHit != nil ? nil : Self.officeNetworkInRange(wifi)
            }
            DispatchQueue.main.async {
                self.probing = false
                self.lastScanHit = scanHit
                self.wiredPorts = ports
                self.leases = newLeases
                self.tunnelSignature = interfaces.tunnels
                if askVPN { self.lastVPNCheck = now }
                self.lastVPNs = vpns
                var r = Reading(currentSSID: ssid, connectedVPNs: vpns, wiredLinks: links)
                if joined { r.place = .office; r.reason = "Wi-Fi: \(ssid)" }
                else if let lanHit { r.place = .office; r.reason = "LAN: \(lanHit.label)" }
                else if let scanHit { r.place = .office; r.reason = String(localized: "w zasięgu: \(scanHit)") }
                else if let vpnHit { r.place = .remote; r.reason = String(localized: "zdalnie, VPN: \(vpnHit)") }
                if r != self.reading {
                    Trace.log("work zone: \(r.inZone ? r.reason : "outside") (Wi-Fi name \(ssid.isEmpty ? "unavailable" : "readable"), \(links.count) wired, \(vpns.count) VPN up)")
                }
                self.reading = r
            }
        }
    }

    /// Forget the scan result when settings change, so the pane reacts at the next probe.
    func invalidate() {
        lastProbe = .distantPast
        lastPortList = .distantPast
        lastScan = .distantPast
        lastScanHit = nil
        leases = [:]
        lastVPNCheck = .distantPast
    }

    nonisolated private static func listWiredPorts() -> [WiredNetwork.Port] {
        WiredNetwork.wiredPorts(fromHardwarePorts:
            WorkDetector.runProcess("/usr/sbin/networksetup", ["-listallhardwareports"]) ?? "")
    }

    /// IPv4 address per interface, and a signature of the VPN-like tunnels that are up (utun2+, ipsec, ppp, tap).
    nonisolated static func interfaces() -> (ipv4: [String: String], tunnels: String) {
        var ipv4: [String: String] = [:]
        var tunnels = Set<String>()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return ([:], "") }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            let up = (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0
            guard up, let addr = entry.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            if family == AF_INET {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    var a = sin.pointee.sin_addr
                    _ = inet_ntop(AF_INET, &a, &buffer, socklen_t(INET_ADDRSTRLEN))
                }
                ipv4[name] = String(cString: buffer)
            }
            if family == AF_INET || family == AF_INET6 {
                let isTunnel = name.hasPrefix("ipsec") || name.hasPrefix("ppp") || name.hasPrefix("tap")
                    || (name.hasPrefix("utun") && (Int(name.dropFirst(4)) ?? 0) >= 2)
                if isTunnel { tunnels.insert(name) }
            }
        }
        return (ipv4, tunnels.sorted().joined(separator: ","))
    }

    /// Ports with an IPv4 address, with what their DHCP server handed out (read again only when the address
    /// changes or the reading is a few minutes old).
    nonisolated private static func activeLinks(_ ports: [WiredNetwork.Port], addresses: [String: String],
                                                cache: [String: CachedLease], now: Date)
        -> ([WiredNetwork.Link], [String: CachedLease]) {
        var fresh: [String: CachedLease] = [:]
        let links = ports.compactMap { port -> WiredNetwork.Link? in
            guard let ip = addresses[port.device], !ip.isEmpty else { return nil }
            let lease: WiredNetwork.Lease
            if let cached = cache[port.device], cached.ip == ip, now.timeIntervalSince(cached.at) < leaseMaxAge {
                lease = cached.lease
                fresh[port.device] = cached
            } else {
                let packet = WorkDetector.runProcess("/usr/sbin/ipconfig", ["getpacket", port.device]) ?? ""
                var read = WiredNetwork.Lease(dhcpPacket: packet)
                if read.router.isEmpty {   // static address: no DHCP packet
                    read.router = WorkDetector.runProcess("/usr/sbin/ipconfig", ["getoption", port.device, "router"])?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                lease = read
                fresh[port.device] = CachedLease(ip: ip, lease: read, at: now)
            }
            return WiredNetwork.Link(device: port.device, name: port.name, mac: port.mac, lease: lease)
        }
        return (links, fresh)
    }

    nonisolated private static func officeNetworkInRange(_ names: [String]) -> String? {
        guard let networks = try? CWWiFiClient.shared().interface()?.scanForNetworks(withName: nil) else { return nil }
        return networks.compactMap(\.ssid).first { names.contains($0.lowercased()) }
    }

    nonisolated static func list(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}
