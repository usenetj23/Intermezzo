import XCTest
@testable import IntermezzoKit

final class SettingsCatalogTests: XCTestCase {
    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "SettingsCatalogTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private let current: [String: SettingValue] = ["cycleMinutes": .number(30), "strictMode": .flag(false), "lightProfile": .text("recommended")]

    private func parse(_ text: String, current: [String: SettingValue]? = nil) -> SettingsProposal {
        SettingsAssistant.parse(text, current: current ?? self.current)
    }

    func testCatalogHasNoForbiddenKeys() {
        let forbidden = ["path", "hotkey", "vpn", "wifi", "geo", "sync", "script"]
        var seen = Set<String>()
        for entry in SettingsCatalog.entries {
            XCTAssertTrue(seen.insert(entry.key).inserted, "duplicate \(entry.key)")
            XCTAssertFalse(forbidden.contains { entry.key.lowercased().contains($0) }, entry.key)
            XCTAssertFalse(entry.descriptionPL.isEmpty || entry.descriptionEN.isEmpty, entry.key)
        }
        XCTAssertGreaterThan(SettingsCatalog.entries.count, 20)
    }

    func testDefaultsFitTheirOwnKind() {
        for entry in SettingsCatalog.entries {
            XCTAssertNotNil(SettingsAssistant.validated(entry.defaultValue, for: entry), "\(entry.key) default \(entry.defaultValue)")
        }
    }

    func testParseValidProposal() {
        let proposal = parse(#"{"changes":[{"key":"cycleMinutes","value":45},{"key":"strictMode","value":true}],"explanation":"x"}"#)
        XCTAssertEqual(proposal.changes.count, 2)
        XCTAssertEqual(proposal.changes[0], ProposedChange(key: "cycleMinutes", old: .number(30), new: .number(45)))
        XCTAssertEqual(proposal.changes[1].new, .flag(true))
        XCTAssertEqual(proposal.explanation, "x")
    }

    func testParseRejectsUnknownKeyWrongTypeAndRange() {
        let text = #"{"changes":[{"key":"breakStartScriptPath","value":"/x"},{"key":"cycleMinutes","value":"abc"},{"key":"cycleMinutes","value":100000},{"key":"lightProfile","value":"custom"},{"key":"strictMode","value":1}]}"#
        let proposal = parse(text)
        XCTAssertTrue(proposal.changes.isEmpty)
        XCTAssertEqual(Set(proposal.skipped.map(\.key)), ["breakStartScriptPath", "cycleMinutes", "lightProfile", "strictMode"])
        XCTAssertEqual(proposal.skipped.count, 4)
    }

    func testParseAcceptsWholeNumbersGivenAsDecimals() {
        XCTAssertEqual(parse(#"{"changes":[{"key":"cycleMinutes","value":45.0}]}"#).changes.first?.new, .number(45))
        XCTAssertTrue(parse(#"{"changes":[{"key":"cycleMinutes","value":45.5}]}"#).changes.isEmpty)
    }

    func testParseDiscreteAndChoiceValues() {
        XCTAssertEqual(parse(#"{"changes":[{"key":"flashIntervalMinutes","value":15},{"key":"lightProfile","value":"classic"}]}"#).changes.count, 2)
        XCTAssertTrue(parse(#"{"changes":[{"key":"flashIntervalMinutes","value":7}]}"#).changes.isEmpty)
    }

    func testParseRejectsDuplicatedKeysAndDropsNoOps() {
        let proposal = parse(#"{"changes":[{"key":"cycleMinutes","value":40},{"key":"cycleMinutes","value":50},{"key":"strictMode","value":false}]}"#)
        XCTAssertTrue(proposal.changes.isEmpty)
        XCTAssertEqual(proposal.skipped.map(\.key), ["cycleMinutes"])
        let unknownTwice = parse(#"{"changes":[{"key":"nope","value":1},{"key":"nope","value":2}]}"#)
        XCTAssertEqual(unknownTwice.skipped.map(\.key), ["nope"])
    }

    func testParseGarbageGivesEmptyProposal() {
        for text in ["", "nie wiem", "{", "[1,2,3]", #"{"changes":"cycleMinutes"}"#, #"{"changes":[1,"a",null]}"#] {
            let proposal = parse(text)
            XCTAssertTrue(proposal.changes.isEmpty, text)
        }
        let flood = "[" + (0..<500).map { _ in #"{"key":"cycleMinutes","value":40}"# }.joined(separator: ",") + "]"
        XCTAssertLessThanOrEqual(parse(flood).changes.count, SettingsCatalog.entries.count)
    }

    func testParseAcceptsJSONInsideProseAndBareArray() {
        let text = "Oczywiście, oto propozycja:\n```json\n{\"changes\":[{\"key\":\"cycleMinutes\",\"value\":45}]}\n```\nMiłej pracy!"
        XCTAssertEqual(parse(text).changes.count, 1)
        XCTAssertEqual(parse(#"[{"key":"cycleMinutes","value":45}]"#).changes.count, 1)
    }

    func testPromptContainsOnlyCatalogAndCurrentValues() {
        let request = SettingsAssistant.prompt(request: "chcę dłuższe przerwy", current: current, language: "pl")
        XCTAssertTrue(request.user.contains("chcę dłuższe przerwy"))
        XCTAssertTrue(request.user.contains("cycleMinutes"))
        XCTAssertTrue(request.user.contains("30"))
        for forbidden in ["/Users/", "hotkey", "Path", "vpn", "wifi"] {
            XCTAssertFalse((request.system + request.user).contains(forbidden), forbidden)
        }
        XCTAssertTrue(request.system.lowercased().contains("json"))
        XCTAssertTrue(request.system.lowercased().contains("medical"))
        XCTAssertNotNil(request.jsonSchema.flatMap { JSONExtract.firstJSON(in: $0) })
        let en = SettingsAssistant.prompt(request: "x", current: current, language: "en")
        XCTAssertNotEqual(en.user, request.user)
    }

    func testCurrentReadsStoredValuesAndDefaults() {
        let d = defaults()
        d.set(45, forKey: "cycleMinutes")
        d.set(1, forKey: "playSound")
        let values = SettingsCatalog.current(in: d)
        XCTAssertEqual(values["cycleMinutes"], .number(45))
        XCTAssertEqual(values["playSound"], .flag(true))
        XCTAssertEqual(values["strictMode"], .flag(false))
        XCTAssertEqual(values["lightProfile"], .text("recommended"))
    }

    func testApplyWritesTypedValues() {
        let d = defaults()
        SettingsCatalog.apply([ProposedChange(key: "cycleMinutes", old: nil, new: .number(50)),
                               ProposedChange(key: "strictMode", old: nil, new: .flag(true)),
                               ProposedChange(key: "lightProfile", old: nil, new: .text("classic"))], to: d)
        XCTAssertEqual(d.integer(forKey: "cycleMinutes"), 50)
        XCTAssertTrue(d.bool(forKey: "strictMode"))
        XCTAssertEqual(d.string(forKey: "lightProfile"), "classic")
    }

    func testSnapshotRoundTripIncludingUnset() {
        let d = defaults()
        d.set(30, forKey: "cycleMinutes")
        let snapshot = SettingsSnapshot.capture(keys: ["cycleMinutes", "strictMode"], from: d, now: Date())
        d.set(60, forKey: "cycleMinutes")
        d.set(true, forKey: "strictMode")
        snapshot.restore(into: d)
        XCTAssertEqual(d.integer(forKey: "cycleMinutes"), 30)
        XCTAssertNil(d.object(forKey: "strictMode"))
    }

    func testHistoryKeepsLastFiveAndPopsNewestFirst() {
        let d = defaults()
        for i in 1...7 {
            SettingsHistory.push(SettingsSnapshot(takenAt: Date(timeIntervalSince1970: Double(i)), values: ["k": .number(i)]), to: d)
        }
        XCTAssertEqual(SettingsHistory.count(in: d), 5)
        XCTAssertEqual(SettingsHistory.popLast(from: d)?.values["k"], .some(.number(7)))
        XCTAssertEqual(SettingsHistory.count(in: d), 4)
        let again = UserDefaults(suiteName: "SettingsCatalogTests.testHistoryKeepsLastFiveAndPopsNewestFirst()")!
        XCTAssertEqual(SettingsHistory.popLast(from: again)?.values["k"], .some(.number(6)))
        d.set(Data("zzz".utf8), forKey: SettingsHistory.key)
        XCTAssertEqual(SettingsHistory.count(in: d), 0)
        XCTAssertNil(SettingsHistory.popLast(from: d))
    }

    // MARK: cross-field checks and ranges

    private let work: [String: SettingValue] = ["shortBreakSeconds": .number(300), "longBreakSeconds": .number(900),
                                                "workStartMinutes": .number(480), "workEndMinutes": .number(1080),
                                                "enforceWorkingHours": .flag(false), "workDaysMask": .number(31)]

    func testShortBreakLongerThanLongIsSkipped() {
        let lowerLong = parse(#"{"changes":[{"key":"longBreakSeconds","value":100}]}"#, current: work)
        XCTAssertTrue(lowerLong.changes.isEmpty)
        XCTAssertEqual(lowerLong.skipped.map(\.key), ["longBreakSeconds"])
        let both = parse(#"{"changes":[{"key":"shortBreakSeconds","value":600},{"key":"longBreakSeconds","value":60}]}"#, current: work)
        XCTAssertTrue(both.changes.isEmpty)
        XCTAssertEqual(Set(both.skipped.map(\.key)), ["shortBreakSeconds", "longBreakSeconds"])
        let fine = parse(#"{"changes":[{"key":"shortBreakSeconds","value":120},{"key":"longBreakSeconds","value":600}]}"#, current: work)
        XCTAssertEqual(fine.changes.count, 2)
    }

    func testWorkStartAfterEndIsSkipped() {
        XCTAssertTrue(parse(#"{"changes":[{"key":"workStartMinutes","value":1100}]}"#, current: work).changes.isEmpty)
        XCTAssertEqual(parse(#"{"changes":[{"key":"workStartMinutes","value":600},{"key":"workEndMinutes","value":1200}]}"#, current: work).changes.count, 2)
        XCTAssertTrue(parse(#"{"changes":[{"key":"workEndMinutes","value":480}]}"#, current: work).changes.isEmpty)
    }

    func testNoWorkingDaysWithEnforcedHoursIsSkipped() {
        let both = parse(#"{"changes":[{"key":"workDaysMask","value":0},{"key":"enforceWorkingHours","value":true}]}"#, current: work)
        XCTAssertTrue(both.changes.isEmpty)
        XCTAssertEqual(Set(both.skipped.map(\.key)), ["workDaysMask", "enforceWorkingHours"])
        XCTAssertEqual(parse(#"{"changes":[{"key":"workDaysMask","value":0}]}"#, current: work).changes.count, 1)
    }

    func testIdleThresholdRangeMatchesTheScreens() {
        let state: [String: SettingValue] = ["idleThresholdSeconds": .number(120)]
        XCTAssertTrue(parse(#"{"changes":[{"key":"idleThresholdSeconds","value":3600}]}"#, current: state).changes.isEmpty)
        XCTAssertEqual(parse(#"{"changes":[{"key":"idleThresholdSeconds","value":900}]}"#, current: state).changes.count, 1)
        XCTAssertEqual(parse(#"{"changes":[{"key":"idleThresholdSeconds","value":60}]}"#, current: state).changes.count, 1)
        XCTAssertTrue(parse(#"{"changes":[{"key":"idleThresholdSeconds","value":30}]}"#, current: state).changes.isEmpty)
    }
}
