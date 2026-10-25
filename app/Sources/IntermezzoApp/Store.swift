import Foundation
import SwiftData

/// Single shared store for the app. Both the AppKit delegate stack and the
/// SwiftUI Settings scene (HistoryView @Query) use this exact container so
/// `@Query` always finds a model context in the environment.
enum Store {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: BreakRecord.self, Exercise.self, WorkSessionRecord.self)
        } catch {
            fatalError("Could not open Intermezzo store: \(error)")
        }
    }()
}
