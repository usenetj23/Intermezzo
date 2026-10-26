import Foundation
import IntermezzoKit

enum AIKeys {
    static let enabled = "aiEnabled"
    static let provider = "aiProvider"
    static let endpoint = "aiEndpoint"
    static let model = "aiModel"
    /// The one-time explanation of what the AI features send was shown.
    static let noticeShown = "aiNoticeShown"
}

enum AIProviderKind: String, CaseIterable {
    case apple, openai
}

/// The single door to the optional AI features: it picks the provider the user chose, lets one request run at
/// a time, enforces a time limit and can be cancelled. It does nothing while the AI features are switched off.
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()
    static let requestTimeout: TimeInterval = 60
    private static let keychainAccount = "openai"

    @Published private(set) var isBusy = false

    private let defaults = UserDefaults.standard

    var isEnabled: Bool { defaults.bool(forKey: AIKeys.enabled) }

    /// The language the answers should be written in: the interface language of the app.
    var languageCode: String { Bundle.main.preferredLocalizations.first?.hasPrefix("pl") == true ? "pl" : "en" }

    var kind: AIProviderKind {
        AIProviderKind(rawValue: defaults.string(forKey: AIKeys.provider) ?? "") ?? .apple
    }

    private var endpointText: String { defaults.string(forKey: AIKeys.endpoint) ?? "" }
    private var modelName: String { (defaults.string(forKey: AIKeys.model) ?? "").trimmingCharacters(in: .whitespaces) }

    func availability() -> AIAvailability {
        guard isEnabled else { return .disabled }
        switch kind {
        case .apple:
            return AppleOnDeviceProvider.availability()
        case .openai:
            if case .failure(let error) = AIEndpoint.parse(endpointText) { return .unavailable(error.message) }
            return modelName.isEmpty ? .unavailable(String(localized: "Podaj nazwę modelu.")) : .ready
        }
    }

    private func makeProvider() throws -> AIProvider {
        switch kind {
        case .apple:
            return AppleOnDeviceProvider()
        case .openai:
            let key = KeychainStore.read(account: Self.keychainAccount)
            return OpenAICompatibleProvider(endpoint: try AIEndpoint.parse(endpointText).get(), model: modelName,
                                            apiKey: key, timeout: Self.requestTimeout)
        }
    }

    private lazy var runner = AIRunner(
        timeout: Self.requestTimeout,
        isEnabled: { [unowned self] in isEnabled },
        availability: { [unowned self] in availability() },
        makeProvider: { [unowned self] in try makeProvider() },
        onBusyChange: { [unowned self] in isBusy = $0 })

    /// The models the chosen server offers. Only for the OpenAI-compatible provider, and only on a click.
    func listModels() async throws -> [String] {
        guard isEnabled else { throw AIError.disabled }
        guard kind == .openai else { throw AIError.unavailable(String(localized: "Lista modeli dotyczy serwera zgodnego z API OpenAI.")) }
        return try await OpenAICompatibleProvider.listModels(endpoint: try AIEndpoint.parse(endpointText).get(),
                                                             apiKey: KeychainStore.read(account: Self.keychainAccount))
    }

    /// Sends one request. Only ever called from a click on a button of an AI feature.
    func run(_ request: AIRequest) async throws -> String {
        try await runner.run(request)
    }

    func cancel() {
        runner.cancel()
    }
}
