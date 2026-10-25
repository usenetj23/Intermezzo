import XCTest
@testable import IntermezzoKit

final class DebugReportSafetyTests: XCTestCase {
    private let temp = NSTemporaryDirectory()

    private func report(_ raw: String?) -> URL? {
        DebugOutputPath.validated(raw, defaultName: "r.pdf", allowedExtensions: ["pdf", "csv"],
                                  allowedRoots: DebugOutputPath.reportRoots(temporaryDirectory: temp))
    }

    func testReportRootsAreThePerUserTempDirOnly() {
        XCTAssertEqual(DebugOutputPath.reportRoots(temporaryDirectory: temp), [temp])
        XCTAssertNil(report("/tmp/x.pdf"))
        XCTAssertNil(report("/private/tmp/x.csv"))
        XCTAssertNotNil(report(temp + "x.pdf"))
        XCTAssertEqual(report(nil)?.deletingLastPathComponent().standardizedFileURL.path,
                       URL(fileURLWithPath: temp).standardizedFileURL.path)
    }

    func testRenderRootsKeepSharedTmp() {
        let roots = DebugOutputPath.renderRoots(temporaryDirectory: temp)
        XCTAssertEqual(Set(roots), Set(["/tmp", "/private/tmp", temp]))
        XCTAssertEqual(roots.last, temp, "nil out= defaults into the temp dir")
    }

    func testRestrictToOwnerSetsMode0600() throws {
        let f = URL(fileURLWithPath: temp).appendingPathComponent("perm-\(UUID().uuidString).pdf")
        try Data("x".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        try DebugOutputPath.restrictToOwner(f)
        let mode = try FileManager.default.attributesOfItem(atPath: f.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testRenderSizeIsClamped() {
        XCTAssertEqual(DebugRenderLimits.dimension("100000", default: 1400), 4096)
        XCTAssertEqual(DebugRenderLimits.dimension("1", default: 1400), 64)
        XCTAssertEqual(DebugRenderLimits.dimension("-5", default: 1400), 64)
        XCTAssertEqual(DebugRenderLimits.dimension("nan", default: 1400), 1400)
        XCTAssertEqual(DebugRenderLimits.dimension("inf", default: 1400), 1400)
        XCTAssertEqual(DebugRenderLimits.dimension(nil, default: 800), 800)
        XCTAssertEqual(DebugRenderLimits.dimension("1200", default: 800), 1200)
    }

    func testRenderSecondsAreClamped() {
        XCTAssertEqual(DebugRenderLimits.seconds("1e9", default: 20), DebugRenderLimits.maxSeconds)
        XCTAssertEqual(DebugRenderLimits.seconds("-3", default: 20), 0)
        XCTAssertEqual(DebugRenderLimits.seconds(nil, default: 20), 20)
        XCTAssertEqual(DebugRenderLimits.seconds("nan", default: 20), 20)
        XCTAssertEqual(DebugRenderLimits.seconds("12.5", default: 20), 12.5)
    }

    func testExclusiveRunRefusesWhileRunningAndDuringCooldown() {
        var gate = ExclusiveRun(cooldown: 2)
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(gate.tryBegin(now: t0))
        XCTAssertFalse(gate.tryBegin(now: t0.addingTimeInterval(1)), "still running")
        gate.finish(now: t0.addingTimeInterval(5))
        XCTAssertFalse(gate.tryBegin(now: t0.addingTimeInterval(6)), "cooldown")
        XCTAssertTrue(gate.tryBegin(now: t0.addingTimeInterval(7.5)))
    }
}
