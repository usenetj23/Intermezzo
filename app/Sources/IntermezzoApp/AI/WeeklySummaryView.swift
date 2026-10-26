import SwiftUI
import AppKit
import IntermezzoKit

/// A short weekly review written by the model from numbers this app has already worked out.
/// Shown only while the AI features are on. The text of a day is kept, so it is not asked for twice.
struct WeeklySummaryView: View {
    let samples: [BreakSample]

    @AppStorage(AIKeys.enabled) private var enabled = false
    @ObservedObject private var service = AIService.shared
    @State private var text = ""
    @State private var message = ""

    private static let keyPrefix = "aiWeekly."

    private var digest: WeeklyDigest { WeeklyDigest.build(samples: samples, now: Date()) }

    /// One answer per day, provider and language.
    private var cacheKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(Self.keyPrefix)\(formatter.string(from: Date())).\(service.kind.rawValue).\(service.languageCode)"
    }

    var body: some View {
        if enabled {
            Section("Podsumowanie tygodnia (AI)") {
                if !text.isEmpty {
                    Text(text).textSelection(.enabled)
                    Text("Wygenerowane przez AI, może się mylić.").settingsNote()
                }
                HStack {
                    Button(service.isBusy ? "Pracuję…" : (text.isEmpty ? "Podsumuj tydzień" : "Odśwież")) { summarize() }
                        .disabled(service.isBusy || digest.isEmpty || service.availability() != .ready)
                    if service.isBusy { Button("Przerwij") { service.cancel() } }
                    if !text.isEmpty {
                        Button("Skopiuj") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                }
                .controlSize(.small)
                if digest.isEmpty {
                    Text("Brak przerw z ostatnich dni.").settingsNote()
                } else if case .unavailable(let reason) = service.availability() {
                    Text(reason).settingsNote()
                }
                if !message.isEmpty {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
            .onAppear { text = UserDefaults.standard.string(forKey: cacheKey) ?? "" }
        }
    }

    private func summarize() {
        message = ""
        let request = WeeklyDigest.prompt(digest: digest, language: service.languageCode)
        let key = cacheKey
        Task {
            do {
                let answer = try await service.run(request).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { message = AIError.badResponse("empty").message; return }
                text = answer
                let defaults = UserDefaults.standard
                for old in defaults.dictionaryRepresentation().keys where old.hasPrefix(Self.keyPrefix) { defaults.removeObject(forKey: old) }
                defaults.set(answer, forKey: key)
            } catch let error as AIError {
                message = error.message
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
