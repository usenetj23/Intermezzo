import XCTest
@testable import IntermezzoKit

final class ExerciseLibraryTests: XCTestCase {
    func testLibraryIsLargeUniqueAndComplete() {
        let all = ExerciseLibrary.all
        XCTAssertGreaterThanOrEqual(all.count, 20)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "names are the de-dup key")
        for e in all {
            XCTAssertFalse(e.title.isEmpty, e.id)
            XCTAssertFalse(e.detail.isEmpty, e.id)
            XCTAssertTrue(e.short || e.long, "\(e.id) is assigned to no break kind")
        }
    }

    func testBothBreakKindsHaveEnoughVariety() {
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.all.filter(\.short).count, 8)
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.all.filter(\.long).count, 10)
    }

    func testCoversAllCategories() {
        let cats = Set(ExerciseLibrary.all.map(\.category))
        XCTAssertEqual(cats, Set(ExerciseCategory.allCases))
    }

    func testShortBreakExercisesFitDefaultOneMinute() {
        // Every short-break exercise must be doable in ~60 s: no "N minutes" instructions.
        for e in ExerciseLibrary.all where e.short {
            XCTAssertFalse(e.detail.contains("minut"), "\(e.id): \(e.detail)")
        }
    }

    func testBreathingCategoryHasExercises() {
        let breathing = ExerciseLibrary.all.filter { $0.category == .breathing }
        XCTAssertEqual(breathing.count, 3)
        XCTAssertEqual(Set(breathing.map(\.id)),
                       ["breath-box", "breath-slow-exhale", "breath-shoulders-drop"])
        XCTAssertEqual(Set(breathing.map(\.id)).count, 3)
        XCTAssertEqual(ExerciseCategory.breathing.title, "Oddech")
        for e in breathing { XCTAssertTrue(e.short && e.long, e.id) }
    }
}
