import Foundation

/// Which curated exercises a library sync inserts into the user's store.
public enum ExerciseLibrarySync {
    /// Bump together with a new `introduced` entry when `ExerciseLibrary` gains exercises.
    public static let currentVersion = 2

    /// Library ids added in each version after the first.
    public static let introduced: [Int: [String]] = [
        2: ["breath-box", "breath-slow-exhale", "breath-shoulders-drop"],
    ]

    /// - Fresh install (`storedVersion <= 0`) or `force`: every library entry not already present.
    /// - Upgrade: only the entries introduced after `storedVersion`, so a library
    ///   exercise the user deleted stays deleted.
    /// - Up to date: nothing.
    /// Matching is by `name` (the store's de-dup key).
    public static func entriesToAdd(storedVersion: Int, force: Bool, existingNames: Set<String>,
                                    library: [LibraryExercise] = ExerciseLibrary.all) -> [LibraryExercise] {
        let missing = library.filter { !existingNames.contains($0.name) }
        if force || storedVersion <= 0 { return missing }
        guard storedVersion < currentVersion else { return [] }
        let newIDs = Set(((storedVersion + 1)...currentVersion).flatMap { introduced[$0] ?? [] })
        return missing.filter { newIDs.contains($0.id) }
    }
}
