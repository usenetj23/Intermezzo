import Foundation

public enum AIAvailability: Equatable, Sendable {
    case ready
    case disabled
    case unavailable(String)
}

/// Set when the time limit, not the user, stopped a request.
@MainActor
private final class TimeoutFlag {
    var fired = false
}

/// Runs one request at a time against the provider the app chooses, with a time limit and cancellation. It
/// builds no provider and makes no call while the AI features are off or unavailable. The app owns the choices
/// (which provider, is it on) and passes them in, which keeps this part testable.
@MainActor
public final class AIRunner {
    public private(set) var isBusy = false

    private let timeout: TimeInterval
    private let isEnabled: () -> Bool
    private let availability: () -> AIAvailability
    private let makeProvider: () throws -> AIProvider
    private let onBusyChange: (Bool) -> Void
    private var running: Task<String, Error>?

    public init(timeout: TimeInterval, isEnabled: @escaping () -> Bool, availability: @escaping () -> AIAvailability,
                makeProvider: @escaping () throws -> AIProvider, onBusyChange: @escaping (Bool) -> Void = { _ in }) {
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.availability = availability
        self.makeProvider = makeProvider
        self.onBusyChange = onBusyChange
    }

    public func run(_ request: AIRequest) async throws -> String {
        guard isEnabled() else { throw AIError.disabled }
        guard !isBusy else { throw AIError.unavailable(kitL("Poprzednie zapytanie jeszcze trwa.")) }
        if case .unavailable(let reason) = availability() { throw AIError.unavailable(reason) }
        let provider = try makeProvider()
        setBusy(true)
        let work = Task { try await provider.complete(request) }
        running = work
        let flag = TimeoutFlag()
        let limit = Task { [work, timeout] in
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            flag.fired = true
            work.cancel()
        }
        defer {
            limit.cancel()
            running = nil
            setBusy(false)
        }
        do {
            return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        } catch let error as AIError {
            // Our own time limit cancels the request, which a provider reports as a cancellation.
            throw flag.fired && error == .cancelled ? AIError.timeout : error
        } catch is CancellationError {
            throw flag.fired ? AIError.timeout : AIError.cancelled
        } catch {
            throw AIError.network(error.localizedDescription)
        }
    }

    public func cancel() {
        running?.cancel()
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onBusyChange(busy)
    }
}
