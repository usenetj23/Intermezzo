import XCTest
@testable import IntermezzoKit

final class DebugOutputPathTests: XCTestCase {
    private let roots = ["/tmp", "/private/tmp", NSTemporaryDirectory()]
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: "/tmp/dop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func check(_ raw: String?, ext: Set<String> = ["pdf", "csv"]) -> URL? {
        DebugOutputPath.validated(raw, defaultName: "d.pdf", allowedExtensions: ext, allowedRoots: roots)
    }

    func testAcceptsTmpAndTempDir() {
        XCTAssertNotNil(check("/tmp/x.pdf"))
        XCTAssertNotNil(check("/private/tmp/sub/x.CSV"))
        XCTAssertNotNil(check(NSTemporaryDirectory() + "x.pdf"))
    }

    func testAcceptsOverwriteOfExistingFile() throws {
        let f = scratch.appendingPathComponent("old.pdf")
        try Data("x".utf8).write(to: f)
        XCTAssertNotNil(check(f.path))
    }

    func testNilRawGivesDefaultInTempDir() {
        let url = check(nil)
        XCTAssertEqual(url?.lastPathComponent, "d.pdf")
    }

    func testRejectsUserFilesAndTraversal() {
        XCTAssertNil(check("~/.zshrc"))
        XCTAssertNil(check(NSHomeDirectory() + "/Documents/x.pdf"))
        XCTAssertNil(check("/tmp/../Users/x/y.pdf"))
    }

    func testRejectsWrongExtensionEmptyAndRelative() {
        XCTAssertNil(check("/tmp/x.sh"))
        XCTAssertNil(check("/tmp/x"))
        XCTAssertNil(check(""))
        XCTAssertNil(check("x.pdf"))
        XCTAssertNil(check("tmp/x.pdf"))
    }

    func testRejectsSymlinkedDirectoryPointingOutside() throws {
        let link = scratch.appendingPathComponent("home")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: NSHomeDirectory()))
        XCTAssertNil(check(link.path + "/y.pdf"))
    }

    func testRejectsSymlinkedFilePointingOutside() throws {
        let link = scratch.appendingPathComponent("hosts.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertNil(check(link.path))
    }

    func testRejectsDanglingSymlink() throws {
        let link = scratch.appendingPathComponent("dangling.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: NSHomeDirectory() + "/nonexistent-\(UUID().uuidString).pdf"))
        XCTAssertNil(check(link.path))
    }
}
