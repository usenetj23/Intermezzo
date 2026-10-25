import Foundation
import SwiftData
import IntermezzoKit

/// Custom break exercise ("Exercises" pane). Assigned exercises
/// show their title/description on the break overlay.
@Model
final class Exercise {
    var name: String
    var title: String
    var detail: String
    var assignToShort: Bool
    var assignToLong: Bool
    var createdAt: Date

    init(name: String, title: String, detail: String,
         assignToShort: Bool, assignToLong: Bool, createdAt: Date = Date()) {
        self.name = name
        self.title = title
        self.detail = detail
        self.assignToShort = assignToShort
        self.assignToLong = assignToLong
        self.createdAt = createdAt
    }
}

enum ExerciseSeed {
    private static let versionKey = "exerciseLibraryVersion"

    /// Adds curated library exercises (matched by name, so nothing the user
    /// edited or added is touched). A fresh install gets the whole library; a
    /// version bump adds only the entries introduced since the stored version
    /// (`ExerciseLibrarySync`), so a deleted entry stays deleted until `force`
    /// ("Przywróć bibliotekę").
    static func syncLibrary(_ context: ModelContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: versionKey)
        guard force || stored < ExerciseLibrarySync.currentVersion else { return }
        let existing = Set(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map(\.name))
        for e in ExerciseLibrarySync.entriesToAdd(storedVersion: stored, force: force, existingNames: existing) {
            context.insert(Exercise(name: e.name, title: e.title, detail: e.detail,
                                    assignToShort: e.short, assignToLong: e.long))
        }
        try? context.save()
        defaults.set(max(stored, ExerciseLibrarySync.currentVersion), forKey: versionKey)
    }
}
