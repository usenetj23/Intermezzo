import Foundation

/// A wired network or adapter the user marked as "this is work".
public struct WorkNetworkMark: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// A LAN, by its DHCP fingerprint (whatever adapter is plugged in).
        case lan
        /// One Ethernet adapter, by its own MAC: a dock or USB card that only lives at work.
        case adapter
    }

    public let kind: Kind
    public let value: String
    public var label: String

    public init(kind: Kind, value: String, label: String) {
        self.kind = kind
        self.value = value
        self.label = label
    }

    public static func encode(_ marks: [WorkNetworkMark]) -> Data {
        (try? JSONEncoder().encode(marks)) ?? Data()
    }

    public static func decode(_ data: Data?) -> [WorkNetworkMark] {
        data.flatMap { try? JSONDecoder().decode([WorkNetworkMark].self, from: $0) } ?? []
    }
}

/// Recognising the office over a cable. macOS 27 no longer exposes the router's MAC (the ARP table
/// reads empty), so a LAN is told apart by what its DHCP server hands out: router, mask, domain, DNS.
public enum WiredNetwork {
    public struct Port: Equatable, Sendable {
        public let device: String
        public let name: String
        public let mac: String
    }

    public struct Lease: Equatable, Sendable {
        public var router = ""
        public var subnet = ""
        public var domain = ""
        public var dns: [String] = []

        public init(router: String = "", subnet: String = "", domain: String = "", dns: [String] = []) {
            self.router = router
            self.subnet = subnet
            self.domain = domain.lowercased()
            self.dns = dns
        }

        /// From `ipconfig getpacket <device>`.
        public init(dhcpPacket text: String) {
            func value(_ key: String) -> String? {
                text.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + " (") }
                    .flatMap { $0.split(separator: ":", maxSplits: 1).last }
                    .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " {}")) }
            }
            func list(_ key: String) -> [String] {
                (value(key) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            self.init(router: list("router").first ?? "", subnet: value("subnet_mask") ?? "",
                      domain: value("domain_name") ?? "", dns: list("domain_name_server"))
        }

        public var fingerprint: String {
            [router, subnet, domain, dns.joined(separator: ",")].joined(separator: "|")
        }

        /// A static address (no DHCP) leaves only router and mask, which many networks share.
        public var isStrong: Bool { !domain.isEmpty || !dns.isEmpty }
    }

    /// An active wired connection.
    public struct Link: Equatable, Sendable {
        public let device: String
        public let name: String
        public let mac: String
        public let lease: Lease

        public init(device: String, name: String, mac: String, lease: Lease) {
            self.device = device
            self.name = name
            self.mac = mac
            self.lease = lease
        }
    }

    /// Ethernet-type ports from `networksetup -listallhardwareports`: no Wi-Fi, Bluetooth, bridges
    /// or Thunderbolt IP networking ("Thunderbolt 1"); a dock's "Thunderbolt Ethernet Slot 1" stays.
    public static func wiredPorts(fromHardwarePorts text: String) -> [Port] {
        var ports: [Port] = []
        var name = "", device = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") { name = String(line.dropFirst(14)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Device:") { device = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Ethernet Address:") {
                let mac = String(line.dropFirst(17)).trimmingCharacters(in: .whitespaces).lowercased()
                if isWired(name: name, device: device) { ports.append(Port(device: device, name: name, mac: mac)) }
                name = ""; device = ""
            }
        }
        return ports
    }

    private static func isWired(name: String, device: String) -> Bool {
        let n = name.lowercased()
        guard device.hasPrefix("en") else { return false }
        if n.contains("wi-fi") || n.contains("bluetooth") || n.contains("bridge") { return false }
        if n.range(of: #"^thunderbolt \d+$"#, options: .regularExpression) != nil { return false }
        return true
    }

    /// The first mark matching an active link: the adapter itself, or the LAN it is on.
    public static func match(_ links: [Link], marks: [WorkNetworkMark]) -> WorkNetworkMark? {
        for link in links {
            if let m = marks.first(where: { $0.kind == .adapter && $0.value == link.mac }) { return m }
            if let m = marks.first(where: { $0.kind == .lan && $0.value == link.lease.fingerprint }) { return m }
        }
        return nil
    }
}

/// Connected VPN services from `scutil --nc list`: system IPSec/L2TP and Network Extension VPNs
/// alike (the WireGuard app shows up as `VPN (com.wireguard.macos) "Home"`).
public enum VPNList {
    public static func connectedNames(fromScutil text: String) -> [String] {
        var names: [String] = []
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // "* (Connected)   <GUID> VPN (com.wireguard.macos) "Home"   [VPN:com.wireguard.macos]"
            guard let open = line.firstIndex(of: "("), let close = line.firstIndex(of: ")"), open < close else { continue }
            let state = line[line.index(after: open)..<close].lowercased()
            guard state == "connected" else { continue }
            let parts = line.components(separatedBy: "\"")
            if parts.count >= 2, !parts[1].isEmpty { names.append(parts[1]) }
        }
        return Array(Set(names)).sorted()
    }
}
