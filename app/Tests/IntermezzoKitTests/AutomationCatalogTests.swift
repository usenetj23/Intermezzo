import XCTest
@testable import IntermezzoKit

final class AutomationCatalogTests: XCTestCase {
    private func parse(_ url: String) -> AutomationCommand? {
        let parts = url.split(separator: "/").map(String.init)
        return AutomationURL.parse(host: parts.first, path: Array(parts.dropFirst()))
    }

    func testBreakCommands() {
        XCTAssertEqual(parse("break/short"), .startShort)
        XCTAssertEqual(parse("break/micro"), .startShort)
        XCTAssertEqual(parse("break/long"), .startLong)
        XCTAssertEqual(parse("break/normal"), .startLong)
        XCTAssertEqual(parse("break/lunchtime"), .startLong)
        XCTAssertEqual(parse("break"), .startShort)
        XCTAssertEqual(parse("short"), .startShort)
        XCTAssertEqual(parse("long"), .startLong)
    }

    func testPostponeWithAndWithoutKind() {
        XCTAssertEqual(parse("break/short/postpone/2m"), .postpone(minutes: 2))
        XCTAssertEqual(parse("break/long/postpone/1h"), .postpone(minutes: 60))
        XCTAssertEqual(parse("postpone"), .postpone(minutes: 5))
        XCTAssertEqual(parse("snooze/10"), .postpone(minutes: 10))
        XCTAssertEqual(parse("delay/90s"), .postpone(minutes: 2))
        XCTAssertEqual(parse("postpone/1d"), .postpone(minutes: 1440))
        XCTAssertEqual(parse("postpone/zzz"), .postpone(minutes: 5))
    }

    func testPlainCommandsAndAliases() {
        XCTAssertEqual(parse("skip"), .skip)
        XCTAssertEqual(parse("pause"), .pause)
        XCTAssertEqual(parse("resume"), .resume)
        XCTAssertEqual(parse("reset"), .reset)
        XCTAssertEqual(parse("stop-sound"), .stopSound)
        XCTAssertEqual(parse("stopSound"), .stopSound)
        XCTAssertEqual(parse("flash"), .flash)
        XCTAssertEqual(parse("notify"), .notify)
        XCTAssertEqual(parse("panel"), .openPanel)
        XCTAssertEqual(parse("panel-close"), .closePanel)
    }

    func testButtonAndSettings() {
        XCTAssertEqual(parse("button/Water"), .button(title: "Water"))
        XCTAssertEqual(parse("button/Szklanka%20wody"), .button(title: "Szklanka wody"))
        XCTAssertNil(parse("button"))
        XCTAssertEqual(parse("settings"), .settings(pane: nil))
        XCTAssertEqual(parse("settings/workLog"), .settings(pane: "workLog"))
    }

    func testLightCommands() {
        XCTAssertEqual(parse("light/on"), .lightOn)
        XCTAssertEqual(parse("light/off"), .lightOff)
        XCTAssertEqual(parse("light/pause"), .lightPause(minutes: 60))
        XCTAssertEqual(parse("light/pause/30m"), .lightPause(minutes: 30))
        XCTAssertNil(parse("light"))
        XCTAssertNil(parse("light/dance"))
    }

    func testAwakeCommands() {
        XCTAssertEqual(parse("awake/on"), .awakeOn)
        XCTAssertEqual(parse("awake/off"), .awakeOff)
        XCTAssertEqual(parse("awake/toggle"), .awakeToggle)
        XCTAssertEqual(parse("awake/for/2h"), .awakeFor(minutes: 120))
        XCTAssertEqual(parse("awake/for"), .awakeFor(minutes: 60))
        XCTAssertNil(parse("awake"))
    }

    func testUnknownAndDebugAreNotCommands() {
        XCTAssertNil(parse("nonsense"))
        XCTAssertNil(parse("debug/flag"))
    }

    func testEveryCommandKindIsInTheCatalog() {
        func kind(_ c: AutomationCommand) -> String { String(String(describing: c).prefix { $0 != "(" }) }
        let inCatalog = Set(AutomationCatalog.urls.compactMap { parse($0.example) }.map(kind))
        let all: [AutomationCommand] = [.startShort, .startLong, .postpone(minutes: 1), .skip, .pause, .resume, .reset,
                                        .stopSound, .flash, .notify, .openPanel, .closePanel, .button(title: "x"),
                                        .settings(pane: nil), .lightOn, .lightOff, .lightPause(minutes: 1),
                                        .awakeOn, .awakeOff, .awakeToggle, .awakeFor(minutes: 1)]
        XCTAssertEqual(inCatalog, Set(all.map(kind)))
    }

    func testEveryCatalogExampleParsesAndHasText() {
        for entry in AutomationCatalog.urls {
            XCTAssertNotNil(parse(entry.example), entry.example)
            XCTAssertFalse(entry.summary.isEmpty)
            XCTAssertTrue(entry.display.hasPrefix(entry.example.split(separator: "/").first.map(String.init) ?? "?"), entry.display)
        }
    }

    func testShortcutsListCoversAllNineActions() {
        XCTAssertEqual(AutomationCatalog.shortcuts.count, 9)
        XCTAssertEqual(AutomationCatalog.shortcuts.filter { $0.defaultCombo != nil }.count, 4)
    }

    func testExplanationMentionsEveryUrlAndShortcut() {
        let text = AutomationCatalog.explanation()
        for entry in AutomationCatalog.urls { XCTAssertTrue(text.contains("intermezzo://" + entry.display), entry.display) }
        for shortcut in AutomationCatalog.shortcuts { XCTAssertTrue(text.contains(shortcut.title), shortcut.title) }
    }
}
