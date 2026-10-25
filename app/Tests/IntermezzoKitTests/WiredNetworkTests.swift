import XCTest
@testable import IntermezzoKit

final class WiredNetworkTests: XCTestCase {
    private let ports = """

    Hardware Port: Ethernet Adapter (en3)
    Device: en3
    Ethernet Address: 02:11:22:33:44:01

    Hardware Port: USB 10/100/1G/2.5G LAN
    Device: en8
    Ethernet Address: 02:11:22:33:44:02

    Hardware Port: Thunderbolt Bridge
    Device: bridge0
    Ethernet Address: 02:00:00:00:00:00

    Hardware Port: Wi-Fi
    Device: en0
    Ethernet Address: 02:11:22:33:44:03

    Hardware Port: Thunderbolt 1
    Device: en1
    Ethernet Address: 02:11:22:33:44:04

    Hardware Port: Thunderbolt Ethernet Slot 1
    Device: en9
    Ethernet Address: 00:30:93:12:34:56
    """

    private let packet = """
    op = BOOTREPLY
    siaddr = 192.168.1.254
    Options count is 8
    dhcp_message_type (uint8): ACK 0x5
    subnet_mask (ip): 255.255.255.0
    router (ip_mult): {192.168.1.254}
    domain_name_server (ip_mult): {10.255.255.1, 10.255.255.2}
    domain_name (string): office.example
    server_identifier (ip): 192.168.1.254
    end (none):
    """

    func testWiredPortsSkipWiFiBridgesAndThunderboltNetworking() {
        let wired = WiredNetwork.wiredPorts(fromHardwarePorts: ports)
        XCTAssertEqual(wired.map(\.device), ["en3", "en8", "en9"])
        XCTAssertEqual(wired[1].name, "USB 10/100/1G/2.5G LAN")
        XCTAssertEqual(wired[1].mac, "02:11:22:33:44:02")
    }

    func testDHCPPacketBecomesAFingerprint() {
        let lease = WiredNetwork.Lease(dhcpPacket: packet)
        XCTAssertEqual(lease.router, "192.168.1.254")
        XCTAssertEqual(lease.domain, "office.example")
        XCTAssertEqual(lease.dns, ["10.255.255.1", "10.255.255.2"])
        XCTAssertEqual(lease.fingerprint, "192.168.1.254|255.255.255.0|office.example|10.255.255.1,10.255.255.2")
        XCTAssertTrue(lease.isStrong)
    }

    func testStaticAddressGivesAWeakFingerprint() {
        let lease = WiredNetwork.Lease(router: "10.0.0.1", subnet: "255.255.0.0")
        XCTAssertFalse(lease.isStrong)
        XCTAssertEqual(lease.fingerprint, "10.0.0.1|255.255.0.0||")
    }

    func testSameRouterOtherDomainDoesNotMatch() {
        // Home and office both on 192.168.1.254: the DHCP domain/DNS tell them apart.
        let office = WiredNetwork.Lease(dhcpPacket: packet)
        let home = WiredNetwork.Lease(router: "192.168.1.254", subnet: "255.255.255.0",
                                      domain: "home", dns: ["192.168.1.254"])
        let marks = [WorkNetworkMark(kind: .lan, value: office.fingerprint, label: "Biuro LAN")]
        let homeLink = WiredNetwork.Link(device: "en8", name: "USB LAN", mac: "02:11:22:33:44:02", lease: home)
        XCTAssertNil(WiredNetwork.match([homeLink], marks: marks))
        let officeLink = WiredNetwork.Link(device: "en8", name: "USB LAN", mac: "02:11:22:33:44:02", lease: office)
        XCTAssertEqual(WiredNetwork.match([officeLink], marks: marks)?.label, "Biuro LAN")
    }

    func testDockAdapterMatchesByItsOwnAddress() {
        let marks = [WorkNetworkMark(kind: .adapter, value: "00:30:93:12:34:56", label: "Stacja w pracy")]
        let link = WiredNetwork.Link(device: "en9", name: "Thunderbolt Ethernet Slot 1", mac: "00:30:93:12:34:56",
                                     lease: .init(router: "10.1.1.1", subnet: "255.255.255.0"))
        XCTAssertEqual(WiredNetwork.match([link], marks: marks)?.label, "Stacja w pracy")
    }

    func testMarksRoundTripThroughDefaults() {
        let marks = [WorkNetworkMark(kind: .lan, value: "a|b|c|d", label: "Biuro"),
                     WorkNetworkMark(kind: .adapter, value: "00:11:22:33:44:55", label: "Dock")]
        XCTAssertEqual(WorkNetworkMark.decode(WorkNetworkMark.encode(marks)), marks)
        XCTAssertEqual(WorkNetworkMark.decode(nil), [])
        XCTAssertEqual(WorkNetworkMark.decode("garbage".data(using: .utf8)), [])
    }
}
