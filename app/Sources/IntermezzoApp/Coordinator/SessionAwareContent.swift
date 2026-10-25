import Foundation
import SwiftData
import IntermezzoKit

/// UserDefaults keys of the "match the break to the session" feature.
enum SessionAwareKeys {
    /// Int flag, default 0 (off).
    static let enabled = "sessionAwareBreaks"
}

/// Picks break content from the session that just finished (rules of thumb in
/// `SessionBreakAdvisor`); the choice between this and the regular path is
/// `BreakContentChoice.choose`.
extension BreakCoordinator {
    /// The advisor's rule-of-thumb for the session that just finished.
    func sessionAdvice(kind: BreakKind, now: Date) -> SessionAdvice {
        SessionBreakAdvisor.advise(
            last: PomodoroController.shared.ledger.justFinished(at: now),
            continuousScreenMinutes: continuousScreenMinutes(now: now),
            outdoorsWeather: outdoorsTip() != nil,
            kind: kind)
    }

    /// Content for an advice; nil for `.rotation` or when nothing matches.
    func sessionAwareContent(for advice: SessionAdvice, kind: BreakKind) -> BreakContent? {
        switch advice {
        case .rotation:
            return nil
        case .outdoors:
            return outdoorsTip().map { BreakContent(headline: "Świeże powietrze", detail: $0) }
        case .category(let category):
            let pick = SessionBreakAdvisor.pickExercise(category: category, kind: kind,
                                                        from: ExerciseLibrary.all)
            return pick.map { BreakContent(headline: $0.title, detail: $0.detail) }
        }
    }

    /// Minutes since the last finished (not skipped) break today; with no such
    /// break, today's tracked screen time.
    private func continuousScreenMinutes(now: Date) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        var descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { !$0.wasSkipped && $0.endedAt != nil && $0.startedAt >= start },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let ended = (try? context.fetch(descriptor))?.first?.endedAt {
            return max(0, Int(now.timeIntervalSince(ended) / 60))
        }
        return screenTime.seconds(now: now) / 60
    }

    /// The weather-advice text when conditions suit a trip outside (fresh data only).
    private func outdoorsTip() -> String? {
        guard let wx = WeatherController.shared.snapshot, wx.isFresh,
              SessionBreakAdvisor.isOutdoorsWeather(effect: wx.effect, uvIndex: wx.uvIndex,
                                                    temperatureC: wx.temperatureC)
        else { return nil }
        return WeatherAdvice.tip(effect: wx.effect, uvIndex: wx.uvIndex, temperatureC: wx.temperatureC)
    }
}
