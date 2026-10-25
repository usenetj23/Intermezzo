import Foundation

/// Which break content the overlay shows and where it came from.
public struct BreakContentChoice: Equatable {
    public enum Source: Equatable {
        /// An exercise assigned to this break kind (the user's own or a library row).
        case assigned
        /// Picked from the session that just finished (`SessionBreakAdvisor`).
        case sessionAware
        /// The built-in tip rotation.
        case rotation
    }

    public let content: BreakContent
    public let source: Source

    public init(content: BreakContent, source: Source) {
        self.content = content
        self.source = source
    }

    /// Decides the break content.
    ///
    /// - Flag off: a random assigned exercise, else the rotation (unchanged behaviour).
    /// - Flag on: a CUSTOM assigned exercise (one the user wrote) wins; library rows are
    ///   seeded as assigned, so they never block the advice. Otherwise the advice; when it
    ///   is `.rotation` or resolves to nothing, the flag-off path applies.
    ///
    /// The closures are only called when needed (the advisor reads the ledger and the
    /// weather; `customAssigned`/`anyAssigned` return a random pick).
    public static func choose(sessionAwareEnabled: Bool,
                              customAssigned: () -> BreakContent?,
                              anyAssigned: () -> BreakContent?,
                              advice: () -> SessionAdvice,
                              resolve: (SessionAdvice) -> BreakContent?,
                              rotation: () -> BreakContent) -> BreakContentChoice {
        if sessionAwareEnabled {
            if let mine = customAssigned() { return BreakContentChoice(content: mine, source: .assigned) }
            let advised = advice()
            if advised != .rotation, let picked = resolve(advised) {
                return BreakContentChoice(content: picked, source: .sessionAware)
            }
        }
        if let assigned = anyAssigned() { return BreakContentChoice(content: assigned, source: .assigned) }
        return BreakContentChoice(content: rotation(), source: .rotation)
    }

    /// The every-third-break weather tip replaces the instructions, keeping the headline.
    /// Never for session-aware content: its headline names an exercise whose steps
    /// would otherwise be swapped for unrelated weather text.
    public func applyingWeatherTip(_ tip: String?) -> BreakContent {
        guard let tip, source != .sessionAware else { return content }
        return BreakContent(headline: content.headline, detail: tip)
    }
}

extension ExerciseLibrary {
    /// True for a name of the curated library (`LibraryExercise.name`); false for
    /// an exercise the user created.
    public static func isLibraryName(_ name: String) -> Bool { libraryNames.contains(name) }

    private static let libraryNames = Set(all.map(\.name))
}
