import XCTest
@testable import IntermezzoKit

final class ProjectSensorMatchTests: XCTestCase {
    private func rule(_ p: String, _ project: String) -> ProjectSensorRule {
        ProjectSensorRule(pattern: p, project: project)
    }

    func testFirstMatchingRuleWins() {
        let rules = [rule("alpha", "A"), rule("alp", "B")]
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "/x/alpha", rules: rules), "A")
    }
    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "MyRepo", rules: [rule("myrepo", "P")]), "P")
    }
    func testNoMatchGivesNil() {
        XCTAssertNil(ProjectSensorMatch.suggest(output: "zzz", rules: [rule("a", "P")]))
    }
    func testEmptyOutputGivesNil() {
        XCTAssertNil(ProjectSensorMatch.suggest(output: "  \n", rules: [rule("a", "P")]))
    }
    func testEmptyPatternIgnored() {
        let rules = [rule("", "X"), rule("  ", "Y"), rule("a", "Z")]
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "abc", rules: rules), "Z")
        XCTAssertNil(ProjectSensorMatch.suggest(output: "abc", rules: [rule("", "X")]))
    }
    func testRegexMetacharactersAreLiteral() {
        XCTAssertNil(ProjectSensorMatch.suggest(output: "abc", rules: [rule(".*", "P")]))
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "a.*b", rules: [rule(".*", "P")]), "P")
    }
    func testNotDiacriticInsensitive() {
        XCTAssertNil(ProjectSensorMatch.suggest(output: "zolc", rules: [rule("żółć", "P")]))
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "ŻÓŁĆ", rules: [rule("żółć", "P")]), "P")
    }
    func testMultilineOutput() {
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "a\nrepo\nb", rules: [rule("repo", "P")]), "P")
    }
    func testVeryLongOutputIsCapped() {
        let long = String(repeating: "x", count: 1_000_000) + "needle"
        XCTAssertNil(ProjectSensorMatch.suggest(output: long, rules: [rule("needle", "P")]))
        XCTAssertEqual(ProjectSensorMatch.suggest(output: "needle" + long, rules: [rule("needle", "P")]), "P")
    }
    func testRuleDecodeIsTolerant() throws {
        let r = try JSONDecoder().decode(ProjectSensorRule.self, from: Data("{}".utf8))
        XCTAssertEqual(r.pattern, ""); XCTAssertEqual(r.project, "")
    }
}

final class SensorScriptPathTests: XCTestCase {
    private var root: URL!
    private var folder: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sensor-\(UUID().uuidString)")
        folder = root.appendingPathComponent("Sensors")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func make(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "return \"\"".write(to: url, atomically: true, encoding: .utf8)
    }

    func testAcceptsScriptInsideFolder() throws {
        let f = folder.appendingPathComponent("FrontRepo.applescript"); try make(f)
        XCTAssertNotNil(SensorScriptPath.validated(f.path, folder: folder.path))
    }
    func testRejectsSymlinkPointingOutside() throws {
        let outside = root.appendingPathComponent("evil.applescript"); try make(outside)
        let link = folder.appendingPathComponent("l.applescript")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(SensorScriptPath.validated(link.path, folder: folder.path))
    }
    func testRejectsSymlinkedDirectoryPointingOutside() throws {
        let outsideDir = root.appendingPathComponent("elsewhere")
        try make(outsideDir.appendingPathComponent("x.applescript"))
        let link = folder.appendingPathComponent("sub")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideDir)
        XCTAssertNil(SensorScriptPath.validated(link.appendingPathComponent("x.applescript").path, folder: folder.path))
    }
    func testRejectsSiblingFolderWithSamePrefix() throws {
        let f = root.appendingPathComponent("Sensors-evil/x.applescript"); try make(f)
        XCTAssertNil(SensorScriptPath.validated(f.path, folder: folder.path))
    }
    func testRejectsDotDotTraversal() throws {
        let outside = root.appendingPathComponent("o.applescript"); try make(outside)
        XCTAssertNil(SensorScriptPath.validated(folder.path + "/../o.applescript", folder: folder.path))
    }
    func testRejectsNulNewlineAndTabInPath() throws {
        let f = folder.appendingPathComponent("a.applescript"); try make(f)
        for bad in ["\u{0}", "\n", "\t", "\u{7F}"] {
            XCTAssertNil(SensorScriptPath.validated(folder.path + "/a" + bad + ".applescript", folder: folder.path))
        }
        XCTAssertNotNil(SensorScriptPath.validated(f.path, folder: folder.path))
    }
    func testRejectsSymlinkedSensorsFolder() throws {
        let real = root.appendingPathComponent("RealSensors")
        try make(real.appendingPathComponent("x.applescript"))
        let link = root.appendingPathComponent("LinkSensors")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertNil(SensorScriptPath.validated(link.path + "/x.applescript", folder: link.path))
        XCTAssertFalse(SensorScriptPath.isSafeFolder(link.path))
    }
    func testRejectsSymlinkedParentOfSensorsFolder() throws {
        let realParent = root.appendingPathComponent("RealParent")
        try make(realParent.appendingPathComponent("Sensors/x.applescript"))
        let linkParent = root.appendingPathComponent("LinkParent")
        try FileManager.default.createSymbolicLink(at: linkParent, withDestinationURL: realParent)
        XCTAssertNil(SensorScriptPath.validated(linkParent.path + "/Sensors/x.applescript",
                                                folder: linkParent.path + "/Sensors"))
    }
    func testRejectsRelativeEmptyWrongExtensionOutsideAndDirectory() throws {
        let txt = folder.appendingPathComponent("a.txt"); try make(txt)
        let out = root.appendingPathComponent("o.applescript"); try make(out)
        let dir = folder.appendingPathComponent("d.applescript")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(SensorScriptPath.validated("FrontRepo.applescript", folder: folder.path))
        XCTAssertNil(SensorScriptPath.validated("", folder: folder.path))
        XCTAssertNil(SensorScriptPath.validated(txt.path, folder: folder.path))
        XCTAssertNil(SensorScriptPath.validated(out.path, folder: folder.path))
        XCTAssertNil(SensorScriptPath.validated(dir.path, folder: folder.path))
        XCTAssertNil(SensorScriptPath.validated(folder.appendingPathComponent("missing.applescript").path, folder: folder.path))
    }
}

final class AssigningProjectTests: XCTestCase {
    private func ledger() -> PomodoroLedger {
        var l = PomodoroLedger()
        l = l.creatingOrRestoringProject(named: "Alpha")!.ledger
        l = l.creatingOrRestoringProject(named: "Old")!.ledger
        l = l.addingTask(title: "t", estimate: 1)
        l = l.addingTask(title: "u", estimate: 1, project: "Alpha")
        return l
    }

    func testAssignsActiveProjectOnlyToTaskWithoutOne() {
        let l = ledger(); let id = l.tasks[0].id
        let done = l.assigningProject("alpha", toTask: id)
        XCTAssertEqual(done.tasks[0].project, "Alpha")
        XCTAssertEqual(done.assigningProject("Alpha", toTask: id), done)
    }
    func testUnknownProjectRefused() {
        let l = ledger()
        XCTAssertEqual(l.assigningProject("Nope", toTask: l.tasks[0].id), l)
    }
    func testFinishedTaskRefused() {
        let base = ledger()
        let l = base.finishingTask(base.tasks[0].id)
        XCTAssertEqual(l.assigningProject("Alpha", toTask: l.tasks[0].id), l)
    }
    func testArchivedProjectRefused() {
        var l = ledger()
        var old = l.project(named: "Old")!
        old.archived = true
        l = l.upsertingProject(old)
        XCTAssertEqual(l.assigningProject("Old", toTask: l.tasks[0].id), l)
    }
    func testExistingProjectNotOverridden() {
        let l = ledger()
        XCTAssertEqual(l.assigningProject("Old", toTask: l.tasks[1].id), l)
    }
    func testRunningPomodoroGetsTheProject() {
        var l = ledger()
        let id = l.tasks[0].id
        l = l.starting(taskID: id, minutes: 25, at: Date())
        XCTAssertEqual(l.current?.project, "")
        XCTAssertEqual(l.assigningProject("Alpha", toTask: id).current?.project, "Alpha")
    }
}
