import XCTest
@testable import IntermezzoKit

final class SyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    // MARK: Policy

    func testDeviceLocalKeysAreNotSynced() {
        for key in ["NSWindow Frame Settings", "com_apple_SwiftUI_Settings_selectedTabIndex", "AppleLanguages",
                    "permissionAsked.accessibility", "syncFolderPath", "screenTimeSeconds", "lastDuplicateAlertDate",
                    "relaxAudioPath.long", "breakStartScriptPath", "imageThemeItems",
                    "pomodoroLedger", "snoozeBudget", "tickProfile", "fxNoImg", "hydrationLog", "autostart",
                    "lightDisabledUntil", "weatherLat", "weatherLon", "awakeMode", "awakeUntil",
                    "lightMonitors", "betterDisplayDim", "betterDisplayDimPercent", "betterDisplayTrueTone", "betterDisplayState", "betterDisplayUnlinkGroup"] {
            XCTAssertFalse(SyncPolicy.isSynced(key: key), key)
        }
    }

    func testPreferencesAreSynced() {
        for key in ["workStartMinutes", "workDaysMask", "surfaceTheme", "cycleMinutes", "workLogVpnNames",
                    "workLogNetworkMarks", "hotkeyShort", "breakRulesList", "lightEnabled", "lightProfile", "lightDayK",
                    "lightSunsetK", "lightBedtimeK", "lightWakeMinutes", "lightLocation", "lightWeather", "lightFadeSeconds",
                    "lightSkipFullscreen", "lightExcludedApps", "lightAmbient", "lightRoomK", "awakeDefaultLevel", "awakeBatteryFloor", "awakeStopLowPower", "awakeStopThermal", "awakeWithFocus",
                    "awakeWithApps", "awakeApps"] {
            XCTAssertTrue(SyncPolicy.isSynced(key: key), key)
        }
    }

    // MARK: Settings

    func testNewerSettingWinsPerKey() throws {
        let a = ["surfaceTheme": try SyncSetting(value: "glass", changedAt: at(10)),
                 "cycleMinutes": try SyncSetting(value: 50, changedAt: at(30))]
        let b = ["surfaceTheme": try SyncSetting(value: "animated", changedAt: at(20)),
                 "cycleMinutes": try SyncSetting(value: 25, changedAt: at(5))]
        let merged = SyncMerge.settings([a, b])
        XCTAssertEqual(merged["surfaceTheme"]?.value as? String, "animated")
        XCTAssertEqual(merged["cycleMinutes"]?.value as? Int, 50)
    }

    func testSettingValuesSurviveJSON() throws {
        let original = SyncSnapshot(deviceID: "A", deviceName: "Mac w pracy", writtenAt: at(0),
                                    settings: ["workDaysMask": try SyncSetting(value: 31, changedAt: at(1)),
                                               "marks": try SyncSetting(value: Data([1, 2, 3]), changedAt: at(2))])
        let decoded = try SyncSnapshot.decode(original.encoded())
        XCTAssertEqual(decoded.settings["workDaysMask"]?.value as? Int, 31)
        XCTAssertEqual(decoded.settings["marks"]?.value as? Data, Data([1, 2, 3]))
        XCTAssertEqual(decoded.deviceName, "Mac w pracy")
    }

    // MARK: Work log

    func testWorkIntervalsMergeByNewestEdit() {
        let original = SyncWork(id: "w1", start: at(0), end: at(3600), modifiedAt: at(3600))
        var edited = original
        edited.end = at(5400); edited.isCorrection = true; edited.modifiedAt = at(9000)
        let other = SyncWork(id: "w2", start: at(7200), end: at(9000), place: "remote", modifiedAt: at(9000))
        let merged = SyncMerge.work([[original, other], [edited]])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == "w1" }?.end, at(5400))
    }

    func testDeletionBeatsAnOlderCopy() {
        let alive = SyncWork(id: "w1", start: at(0), end: at(60), modifiedAt: at(100))
        var gone = alive; gone.deleted = true; gone.modifiedAt = at(200)
        XCTAssertEqual(SyncMerge.work([[alive], [gone]]).first?.deleted, true)
        var revived = alive; revived.modifiedAt = at(300)
        XCTAssertEqual(SyncMerge.work([[gone], [revived]]).first?.deleted, false)
    }

    // MARK: Breaks

    func testTheAuthorsCopyOfABreakWins() {
        // Mac B saw the break while it was still running; Mac A (its author) finished it.
        let running = SyncBreak(id: "b1", origin: "A", kind: "short", start: at(0), end: nil, wasSkipped: false)
        var finished = running; finished.end = at(300); finished.outcome = "completed"
        let merged = SyncMerge.breaks([(deviceID: "B", items: [running]), (deviceID: "A", items: [finished])])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].end, at(300))
    }

    // MARK: Pomodoro

    func testPomodoroRecordsAddUpAndThePlanComesFromTheNewerLedger() {
        var work = PomodoroLedger()
        work.records = [record(at(0), "Raport")]
        work = work.addingTask(title: "Raport", estimate: 2)
        var home = PomodoroLedger()
        home.records = [record(at(0), "Raport"), record(at(5000), "Kod")]
        home = home.addingTask(title: "Kod", estimate: 3)
        let merged = work.merged(with: home, otherIsNewer: true)
        XCTAssertEqual(merged.records.map(\.startedAt), [at(0), at(5000)])
        XCTAssertEqual(merged.tasks.map(\.title), ["Kod"])
        XCTAssertEqual(work.merged(with: home, otherIsNewer: false).tasks.map(\.title), ["Raport"])
    }

    func testTheRunningPomodoroStaysLocal() {
        var local = PomodoroLedger()
        local.current = PomodoroRun(taskID: nil, taskTitle: "Raport", minutes: 25, startedAt: at(0), project: "")
        let merged = local.merged(with: PomodoroLedger(), otherIsNewer: true)
        XCTAssertNotNil(merged.current)
    }

    private func record(_ start: Date, _ title: String) -> PomodoroRecord {
        PomodoroRecord(date: start, startedAt: start, taskID: nil, taskTitle: title, project: "", minutes: 25,
                       actualSeconds: 1500, internalInterruptions: 0, externalInterruptions: 0,
                       appSwitches: 0, activeSeconds: 0)
    }
}
