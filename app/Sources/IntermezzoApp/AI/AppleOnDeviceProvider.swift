import Foundation
import IntermezzoKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The model built into macOS (Apple Intelligence). Nothing leaves the Mac. It needs macOS 26 or newer.
struct AppleOnDeviceProvider: AIProvider {
    static func availability() -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable(String(localized: "ten Mac nie obsługuje Apple Intelligence"))
                case .appleIntelligenceNotEnabled: return .unavailable(String(localized: "Apple Intelligence jest wyłączona w Ustawieniach systemowych"))
                case .modelNotReady: return .unavailable(String(localized: "model Apple jeszcze się pobiera"))
                @unknown default: return .unavailable(String(localized: "model Apple jest niedostępny"))
                }
            }
        }
        #endif
        return .unavailable(String(localized: "wymaga macOS 26 lub nowszego z Apple Intelligence"))
    }

    func complete(_ request: AIRequest) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .unavailable(let reason) = Self.availability() { throw AIError.unavailable(reason) }
            do {
                let session = LanguageModelSession(instructions: request.system)
                return try await session.respond(to: request.user).content
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                throw AIError.badResponse(error.localizedDescription)
            }
        }
        #endif
        throw AIError.unavailable(String(localized: "wymaga macOS 26 lub nowszego z Apple Intelligence"))
    }
}
