import XCTest
@testable import IntermezzoKit

final class PomodoroProjectTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// One completed record of `seconds` on `project` (the run starts at `end - seconds`).
    private func completed(_ ledger: PomodoroLedger, project: String, seconds: Int, day: Int = 20) -> PomodoroLedger {
        var l = ledger.addingTask(title: "T \(project) \(seconds)", estimate: 1, project: project)
        let id = l.tasks.last!.id
        let end = date(day, 12)
        l = l.starting(taskID: id, minutes: 25, at: end.addingTimeInterval(-Double(seconds)))
        return l.completing(at: end)
    }

    func testNewTaskProjectCreatesProjectEntry() {
        let l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "  Alpha ")
        XCTAssertEqual(l.projects.map(\.name), ["Alpha"])
        XCTAssertEqual(l.projects[0].colorHex, "#5AD9A0")
        XCTAssertEqual(l.projects[0].currency, "PLN")
        XCTAssertFalse(l.projects[0].billable)
        XCTAssertNil(l.projects[0].hourlyRate)

        // Same name (any case) does not create a second entry; no project creates none.
        let again = l.addingTask(title: "B", estimate: 1, project: "alpha").addingTask(title: "C", estimate: 1)
        XCTAssertEqual(again.projects.count, 1)
    }

    func testRenameRewritesTasksAndRecords() throws {
        var l = completed(PomodoroLedger(), project: "Alpha", seconds: 1500)
        let id = try XCTUnwrap(l.project(named: "Alpha")?.id)
        l = try XCTUnwrap(l.renamingProject(id: id, to: " Beta "))
        XCTAssertEqual(l.projects.map(\.name), ["Beta"])
        XCTAssertEqual(l.tasks.map(\.project), ["Beta"])
        XCTAssertEqual(l.records.map(\.project), ["Beta"])
        XCTAssertEqual(l.project(named: "BETA")?.id, id)
    }

    func testRenameToExistingNameIsRejected() throws {
        let l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "Alpha")
            .addingTask(title: "B", estimate: 1, project: "Beta")
        let beta = try XCTUnwrap(l.project(named: "Beta"))
        XCTAssertNil(l.renamingProject(id: beta.id, to: "alpha"))
        XCTAssertNil(l.renamingProject(id: beta.id, to: "   "))
        XCTAssertEqual(l.tasks.map(\.project), ["Alpha", "Beta"])
        // Changing only the case of its own name is allowed.
        XCTAssertEqual(l.renamingProject(id: beta.id, to: "BETA")?.projects.map(\.name).sorted(), ["Alpha", "BETA"])
    }

    func testEarningsOnlyForBillableWithRate() throws {
        var l = PomodoroLedger()
        l = completed(l, project: "Paid", seconds: 7200)
        l = completed(l, project: "Free", seconds: 7200)
        l = completed(l, project: "NoRate", seconds: 7200)
        l = l.upsertingProject(try updated(l, "Paid") { $0.billable = true; $0.hourlyRate = 150 })
        l = l.upsertingProject(try updated(l, "Free") { $0.billable = false; $0.hourlyRate = 100 })
        l = l.upsertingProject(try updated(l, "NoRate") { $0.billable = true })

        let e = l.earnings(from: date(20, 0), to: date(21, 0))
        XCTAssertEqual(e, ["PLN": 300])
        XCTAssertTrue(l.earnings(from: date(21, 0), to: date(22, 0)).isEmpty)
    }

    func testEarningsSplitByCurrency() throws {
        var l = PomodoroLedger()
        l = completed(l, project: "Pl", seconds: 3600)
        l = completed(l, project: "Eu", seconds: 1800)
        l = l.upsertingProject(try updated(l, "Pl") { $0.billable = true; $0.hourlyRate = 100 })
        l = l.upsertingProject(try updated(l, "Eu") { $0.billable = true; $0.hourlyRate = 80; $0.currency = "EUR" })

        let e = l.earnings(from: date(20, 0), to: date(21, 0))
        XCTAssertEqual(e["PLN"] ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(e["EUR"] ?? 0, 40, accuracy: 0.001)
    }

    func testOldLedgerBackfillsProjectsFromTaskNames() throws {
        let json = """
        {"tasks":[{"id":"\(UUID().uuidString)","title":"x","estimate":1,"project":"Alpha"},
                  {"id":"\(UUID().uuidString)","title":"y","estimate":2,"project":"alpha"},
                  {"id":"\(UUID().uuidString)","title":"z","estimate":1}],
         "records":[],"voided":[]}
        """
        let l = PomodoroLedger.decode(Data(json.utf8))
        XCTAssertEqual(l.tasks.count, 3)
        XCTAssertEqual(l.projects.map(\.name), ["Alpha"])
        XCTAssertEqual(l.projects[0].colorHex, "#5AD9A0")
        // Round trip keeps the entries.
        let back = PomodoroLedger.decode(PomodoroLedger.encode(l))
        XCTAssertEqual(back, l)
    }

    func testArchivedProjectHiddenFromActive() throws {
        var l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "Zed")
            .addingTask(title: "B", estimate: 1, project: "Alpha")
            .addingTask(title: "C", estimate: 1, project: "Old")
        XCTAssertEqual(l.activeProjects.map(\.name), ["Alpha", "Old", "Zed"])
        l = l.upsertingProject(try updated(l, "Old") { $0.archived = true })
        XCTAssertEqual(l.activeProjects.map(\.name), ["Alpha", "Zed"])
        XCTAssertEqual(l.projects.count, 3)
    }

    func testUpsertWithNewNameRewritesTasksRecordsAndKeepsEntry() throws {
        var l = completed(PomodoroLedger(), project: "Alpha", seconds: 600)
        var p = try XCTUnwrap(l.project(named: "Alpha"))
        p.name = "Gamma"
        p.client = "ACME"
        l = l.upsertingProject(p)
        XCTAssertEqual(l.projects.map(\.name), ["Gamma"])
        XCTAssertEqual(l.projects[0].client, "ACME")
        XCTAssertEqual(l.tasks.map(\.project), ["Gamma"])
        XCTAssertEqual(l.records.map(\.project), ["Gamma"])
        // A clashing new name changes nothing.
        let two = l.addingTask(title: "x", estimate: 1, project: "Other")
        var q = try XCTUnwrap(two.project(named: "Other"))
        q.name = "gamma"
        XCTAssertEqual(two.upsertingProject(q), two)
    }

    func testDiacriticsDistinguishProjectsButCaseDoesNot() {
        let l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "Żaba")
            .addingTask(title: "B", estimate: 1, project: "Zaba")
            .addingTask(title: "C", estimate: 1, project: "Łąka")
            .addingTask(title: "D", estimate: 1, project: "Laka")
            .addingTask(title: "E", estimate: 1, project: "żaba")
        XCTAssertEqual(l.projects.count, 4)
        XCTAssertNotEqual(l.project(named: "Żaba")?.id, l.project(named: "Zaba")?.id)
        XCTAssertEqual(l.project(named: "żaba")?.name, "Żaba")
        XCTAssertEqual(l.tasks.last?.project, "Żaba")
    }

    func testAddingTaskStoresCanonicalProjectSpelling() {
        let l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "Alpha")
            .addingTask(title: "B", estimate: 1, project: " alpha ")
        XCTAssertEqual(l.tasks.map(\.project), ["Alpha", "Alpha"])
        XCTAssertEqual(l.projects.count, 1)
    }

    func testCurrencyIsNormalizedToUppercaseAndShareOneBucket() throws {
        var l = PomodoroLedger()
        l = completed(l, project: "A", seconds: 3600)
        l = completed(l, project: "B", seconds: 3600)
        l = l.upsertingProject(try updated(l, "A") { $0.billable = true; $0.hourlyRate = 100; $0.currency = "pln" })
        l = l.upsertingProject(try updated(l, "B") { $0.billable = true; $0.hourlyRate = 50; $0.currency = "PLN" })
        XCTAssertEqual(l.project(named: "A")?.currency, "PLN")
        XCTAssertEqual(l.earnings(from: date(20, 0), to: date(21, 0)), ["PLN": 150])
    }

    func testRenameRewritesRunningPomodoro() throws {
        var l = PomodoroLedger().addingTask(title: "A", estimate: 1, project: "Alpha")
        l = l.starting(taskID: l.tasks[0].id, minutes: 25, at: date(20))
        let id = try XCTUnwrap(l.project(named: "Alpha")?.id)
        l = try XCTUnwrap(l.renamingProject(id: id, to: "Beta"))
        XCTAssertEqual(l.current?.project, "Beta")
    }

    private func updated(_ l: PomodoroLedger, _ name: String, _ change: (inout PomodoroProject) -> Void) throws -> PomodoroProject {
        var p = try XCTUnwrap(l.project(named: name))
        change(&p)
        return p
    }
}

final class PomodoroProjectSelectionTests: XCTestCase {
    private func ledger() -> PomodoroLedger {
        PomodoroLedger().upsertingProject(PomodoroProject(name: "Alpha"))
    }

    func testActiveProjectNameDropsRenamedAndArchived() {
        var l = ledger()
        XCTAssertEqual(l.activeProjectName("alpha"), "Alpha")
        let id = l.projects[0].id
        l = l.renamingProject(id: id, to: "Beta")!
        XCTAssertNil(l.activeProjectName("Alpha"))
        var p = l.projects[0]; p.archived = true
        l = l.upsertingProject(p)
        XCTAssertNil(l.activeProjectName("Beta"))
        XCTAssertNil(l.activeProjectName(""))
    }

    func testCreateOrRestoreRestoresArchived() {
        var l = ledger()
        var p = l.projects[0]; p.archived = true
        l = l.upsertingProject(p)
        let r = l.creatingOrRestoringProject(named: " ALPHA ")!
        XCTAssertEqual(r.name, "Alpha")
        XCTAssertEqual(r.ledger.activeProjectName("Alpha"), "Alpha")
        XCTAssertEqual(r.ledger.projects.count, 1)
    }

    func testCreateOrRestoreCreatesAndRejectsBlank() {
        let r = ledger().creatingOrRestoringProject(named: "Gamma")!
        XCTAssertEqual(r.ledger.projects.count, 2)
        XCTAssertNil(ledger().creatingOrRestoringProject(named: "  "))
    }

    func testParseRateRejectsNonFiniteAndHuge() {
        XCTAssertEqual(PomodoroProject.parseRate("12,5"), 12.5)
        XCTAssertNil(PomodoroProject.parseRate("inf"))
        XCTAssertNil(PomodoroProject.parseRate("infinity"))
        XCTAssertNil(PomodoroProject.parseRate("nan"))
        XCTAssertNil(PomodoroProject.parseRate("-1"))
        XCTAssertNil(PomodoroProject.parseRate("1000001"))
        XCTAssertEqual(PomodoroProject.parseRate("1000000"), 1_000_000)
    }
}
