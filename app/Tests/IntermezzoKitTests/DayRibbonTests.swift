import XCTest
@testable import IntermezzoKit

final class DayRibbonTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func record(from s: Date, to e: Date, project: String = "Alpha") -> PomodoroRecord {
        PomodoroRecord(date: e, startedAt: s, taskID: nil, taskTitle: "t", project: project, minutes: 25,
                       actualSeconds: Int(e.timeIntervalSince(s)), internalInterruptions: 0,
                       externalInterruptions: 0, appSwitches: 0, activeSeconds: 0)
    }

    private func build(_ day: Date? = nil, calendar: Calendar? = nil, p: [PomodoroRecord] = [],
                       b: [RibbonBreak] = [], m: [DateInterval] = []) -> [RibbonSegment] {
        DayRibbon.build(day: day ?? date(20, 12), calendar: calendar ?? cal, pomodoros: p, breaks: b, meetings: m)
    }

    func testEmptyDayGivesNoSegments() {
        XCTAssertEqual(build(), [])
    }

    func testSegmentsSortedAndClippedToDay() {
        let segs = build(
            p: [record(from: date(20, 14), to: date(20, 15)), record(from: date(20, 9), to: date(20, 10))],
            b: [RibbonBreak(start: date(20, 10), end: date(20, 10, 5), skipped: false)],
            m: [DateInterval(start: date(20, 11), end: date(20, 12))])
        XCTAssertEqual(segs.map(\.kind), [.focus, .breakTaken, .meeting, .focus])
        XCTAssertEqual(segs.map(\.start), segs.map(\.start).sorted())
        XCTAssertEqual(segs[0].label, "Alpha")
        XCTAssertEqual(segs[2].label, "")
    }

    func testMeetingWinsOverlapAndSplitsFocus() {
        let segs = build(p: [record(from: date(20, 9), to: date(20, 10))],
                         m: [DateInterval(start: date(20, 9, 20), end: date(20, 9, 40))])
        XCTAssertEqual(segs, [
            RibbonSegment(start: date(20, 9), end: date(20, 9, 20), kind: .focus, label: "Alpha"),
            RibbonSegment(start: date(20, 9, 20), end: date(20, 9, 40), kind: .meeting, label: ""),
            RibbonSegment(start: date(20, 9, 40), end: date(20, 10), kind: .focus, label: "Alpha"),
        ])
    }

    func testBreakBeatsFocusButLosesToMeeting() {
        let segs = build(p: [record(from: date(20, 9), to: date(20, 10))],
                         b: [RibbonBreak(start: date(20, 9, 30), end: date(20, 9, 50), skipped: false)],
                         m: [DateInterval(start: date(20, 9, 40), end: date(20, 9, 45))])
        XCTAssertEqual(segs.map(\.kind), [.focus, .breakTaken, .meeting, .breakTaken, .focus])
        XCTAssertEqual(segs[3].start, date(20, 9, 45))
        XCTAssertEqual(segs[3].end, date(20, 9, 50))
    }

    func testSessionCrossingMidnightIsClipped() {
        let seg = build(date(21, 12), p: [record(from: date(20, 23, 40), to: date(21, 0, 20))])
        XCTAssertEqual(seg, [RibbonSegment(start: date(21, 0), end: date(21, 0, 20), kind: .focus, label: "Alpha")])
        let prev = build(date(20, 12), p: [record(from: date(20, 23, 40), to: date(21, 0, 20))])
        XCTAssertEqual(prev, [RibbonSegment(start: date(20, 23, 40), end: date(21, 0), kind: .focus, label: "Alpha")])
    }

    func testSkippedBreakKeepsItsKind() {
        let segs = build(b: [RibbonBreak(start: date(20, 10), end: date(20, 10, 5), skipped: true),
                             RibbonBreak(start: date(20, 11), end: date(20, 11, 5), skipped: false)])
        XCTAssertEqual(segs.map(\.kind), [.breakSkipped, .breakTaken])
    }

    func testSameKindOverlapsDoNotOverlapInOutput() {
        let segs = build(
            p: [record(from: date(20, 9), to: date(20, 10), project: "A"),
                record(from: date(20, 9, 30), to: date(20, 10, 30), project: "B")],
            m: [DateInterval(start: date(20, 13), end: date(20, 14)),
                DateInterval(start: date(20, 13, 30), end: date(20, 15))])
        for (a, b) in zip(segs, segs.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start) }
        // The later-starting one is trimmed to begin where the earlier one ends.
        XCTAssertEqual(segs.map(\.kind), [.focus, .focus, .meeting, .meeting])
        XCTAssertEqual([segs[1].start, segs[1].end], [date(20, 10), date(20, 10, 30)])
        XCTAssertEqual([segs[2].start, segs[2].end], [date(20, 13), date(20, 14)])
        XCTAssertEqual([segs[3].start, segs[3].end], [date(20, 14), date(20, 15)])
        XCTAssertEqual(segs[0].label, "A")
        XCTAssertEqual(segs[1].label, "B")
    }

    func testSubSecondAndZeroLengthAreDropped() {
        let segs = build(
            p: [record(from: date(20, 9), to: date(20, 9))],
            m: [DateInterval(start: date(20, 10), end: date(20, 10).addingTimeInterval(0.5))])
        XCTAssertEqual(segs, [])
    }

    func testTouchingSegmentsAreKept() {
        let segs = build(p: [record(from: date(20, 9), to: date(20, 10))],
                         b: [RibbonBreak(start: date(20, 10), end: date(20, 10, 5), skipped: false)])
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].end, segs[1].start)
    }

    func testDSTDayUsesCalendarStartOfDay() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-03-08 is a 23-hour day in New York; the next day's focus must not leak in.
        let day = ny.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let nextStart = ny.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0))!
        let rec = record(from: nextStart.addingTimeInterval(-1800), to: nextStart.addingTimeInterval(1800))
        let segs = DayRibbon.build(day: day, calendar: ny, pomodoros: [rec], breaks: [], meetings: [])
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].end, nextStart)
    }

    // MARK: - merged

    private func seg(_ s: Date, _ e: Date, _ k: RibbonKind = .meeting, _ l: String = "") -> RibbonSegment {
        RibbonSegment(start: s, end: e, kind: k, label: l)
    }

    func testMergedJoinsAdjacentSameKindAndLabel() {
        let r = DayRibbon.merged([seg(date(20, 9), date(20, 10)), seg(date(20, 10), date(20, 11))])
        XCTAssertEqual(r, [seg(date(20, 9), date(20, 11))])
    }

    func testMergedKeepsDifferentLabelOrKind() {
        let a = DayRibbon.merged([seg(date(20, 9), date(20, 10), .focus, "A"), seg(date(20, 10), date(20, 11), .focus, "B")])
        XCTAssertEqual(a.count, 2)
        let b = DayRibbon.merged([seg(date(20, 9), date(20, 10), .focus, "A"), seg(date(20, 10), date(20, 11), .meeting)])
        XCTAssertEqual(b.count, 2)
    }

    func testMergedKeepsGapAboveOneSecond() {
        let t = date(20, 10)
        XCTAssertEqual(DayRibbon.merged([seg(date(20, 9), t), seg(t.addingTimeInterval(2), date(20, 11))]).count, 2)
        XCTAssertEqual(DayRibbon.merged([seg(date(20, 9), t), seg(t.addingTimeInterval(1), date(20, 11))]).count, 1)
    }

    func testMergedJoinsOverlappingSameKind() {
        let r = DayRibbon.merged([seg(date(20, 9), date(20, 11)), seg(date(20, 10), date(20, 10, 30))])
        XCTAssertEqual(r, [seg(date(20, 9), date(20, 11))])
    }

    func testMergedEmptyAndOrderPreserved() {
        XCTAssertEqual(DayRibbon.merged([]), [])
        let r = DayRibbon.merged([seg(date(20, 14), date(20, 15), .breakTaken), seg(date(20, 9), date(20, 10), .focus, "A")])
        XCTAssertEqual(r.map(\.start), [date(20, 9), date(20, 14)])
    }
}
