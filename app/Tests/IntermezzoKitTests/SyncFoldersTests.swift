import XCTest
@testable import IntermezzoKit

final class SyncFoldersTests: XCTestCase {
    func testCloudTitlesFromStorageFolderNames() {
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "OneDrive-Personal"), "OneDrive (Personal)")
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "OneDrive-Contoso"), "OneDrive (Contoso)")
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "OneDrive"), "OneDrive")
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "Dropbox"), "Dropbox")
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "GoogleDrive-a@b.pl"), "Google Drive (a@b.pl)")
        XCTAssertEqual(SyncFolders.cloudTitle(forStorageFolder: "Box-Box"), "Box")
        XCTAssertNil(SyncFolders.cloudTitle(forStorageFolder: "MacDroid-phone"))
        XCTAssertNil(SyncFolders.cloudTitle(forStorageFolder: ".hidden"))
    }

    func testPathsMigrateFromSingleFolder() {
        XCTAssertEqual(SyncFolders.paths(list: nil, legacy: "/a"), ["/a"])
        XCTAssertEqual(SyncFolders.paths(list: nil, legacy: ""), [])
        XCTAssertEqual(SyncFolders.paths(list: ["/b", "", "/b", "/c"], legacy: "/a"), ["/b", "/c"])
    }

    func testNewestSnapshotPerDevice() {
        let old = SyncSnapshot(deviceID: "m2", deviceName: "Old", writtenAt: Date(timeIntervalSince1970: 10))
        let new = SyncSnapshot(deviceID: "m2", deviceName: "New", writtenAt: Date(timeIntervalSince1970: 20))
        let other = SyncSnapshot(deviceID: "m3", deviceName: "X", writtenAt: Date(timeIntervalSince1970: 5))
        let out = SyncFolders.newestPerDevice([old, other, new])
        XCTAssertEqual(out.map(\.deviceName).sorted(), ["New", "X"])
    }
}
