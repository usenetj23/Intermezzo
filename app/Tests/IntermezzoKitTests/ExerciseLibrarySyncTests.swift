import XCTest
@testable import IntermezzoKit

final class ExerciseLibrarySyncTests: XCTestCase {
    private let v2 = Set(["breath-box", "breath-slow-exhale", "breath-shoulders-drop"])
    private var allNames: Set<String> { Set(ExerciseLibrary.all.map(\.name)) }
    private var v1Names: Set<String> {
        Set(ExerciseLibrary.all.filter { !v2.contains($0.id) }.map(\.name))
    }

    func testFreshInstallGetsEverything() {
        let add = ExerciseLibrarySync.entriesToAdd(storedVersion: 0, force: false, existingNames: [])
        XCTAssertEqual(add.count, ExerciseLibrary.all.count)
    }

    func testV1ToV2AddsOnlyTheThreeBreathingExercises() {
        let add = ExerciseLibrarySync.entriesToAdd(storedVersion: 1, force: false, existingNames: v1Names)
        XCTAssertEqual(Set(add.map(\.id)), v2)
    }

    func testDeletedOldLibraryEntryIsNotReAddedOnBump() {
        var existing = v1Names
        let deleted = ExerciseLibrary.all.first { !v2.contains($0.id) }!.name
        existing.remove(deleted)
        let add = ExerciseLibrarySync.entriesToAdd(storedVersion: 1, force: false, existingNames: existing)
        XCTAssertFalse(add.map(\.name).contains(deleted))
        XCTAssertEqual(Set(add.map(\.id)), v2)
    }

    func testSameVersionAddsNothing() {
        let current = ExerciseLibrarySync.currentVersion
        XCTAssertTrue(ExerciseLibrarySync.entriesToAdd(storedVersion: current, force: false,
                                                       existingNames: []).isEmpty)
    }

    func testForceReAddsEverythingMissing() {
        var existing = allNames
        let deleted = ExerciseLibrary.all[0].name
        existing.remove(deleted)
        let add = ExerciseLibrarySync.entriesToAdd(storedVersion: ExerciseLibrarySync.currentVersion,
                                                   force: true, existingNames: existing)
        XCTAssertEqual(add.map(\.name), [deleted])
    }

    func testV2EntryAlreadyPresentIsNotDuplicated() {
        let existing = v1Names.union(ExerciseLibrary.all.filter { $0.id == "breath-box" }.map(\.name))
        let add = ExerciseLibrarySync.entriesToAdd(storedVersion: 1, force: false, existingNames: existing)
        XCTAssertEqual(Set(add.map(\.id)), v2.subtracting(["breath-box"]))
    }

    func testIntroducedTableNamesRealLibraryIds() {
        let ids = Set(ExerciseLibrary.all.map(\.id))
        for (_, introduced) in ExerciseLibrarySync.introduced {
            XCTAssertTrue(Set(introduced).isSubset(of: ids))
        }
        XCTAssertEqual(ExerciseLibrarySync.introduced.keys.max(), ExerciseLibrarySync.currentVersion)
    }
}
