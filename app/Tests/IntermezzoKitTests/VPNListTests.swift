import XCTest
@testable import IntermezzoKit

final class VPNListTests: XCTestCase {
    private let list = """
    Available network connection services in the current set (*=enabled):
    * (Connected)      00000000-0000-4000-8000-000000000001 VPN (com.wireguard.macos) "Home"                            [VPN:com.wireguard.macos]
    * (Disconnected)   00000000-0000-4000-8000-000000000002 PPP --> L2TP       "VPN Office Backup"              [PPP:L2TP]
    * (Connected)      00000000-0000-4000-8000-000000000003 PPP --> L2TP       "VPN Office"                     [PPP:L2TP]
    * (Connecting)     00000000-0000-4000-8000-000000000004 VPN (com.wireguard.macos) "Lab"                            [VPN:com.wireguard.macos]
    """

    func testWireGuardAndL2TPConnectionsAreFound() {
        XCTAssertEqual(VPNList.connectedNames(fromScutil: list), ["Home", "VPN Office"])
    }

    func testNothingConnected() {
        let idle = list.replacingOccurrences(of: "(Connected)", with: "(Disconnected)")
        XCTAssertEqual(VPNList.connectedNames(fromScutil: idle), [])
    }
}
