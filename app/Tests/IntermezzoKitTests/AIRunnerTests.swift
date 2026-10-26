import XCTest
@testable import IntermezzoKit

@MainActor
final class AIRunnerTests: XCTestCase {
    private final class CountingProvider: AIProvider, @unchecked Sendable {
        var calls = 0
        var delayNanoseconds: UInt64 = 0
        var failure: Error?

        func complete(_ request: AIRequest) async throws -> String {
            calls += 1
            if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
            if let failure { throw failure }
            return "answer"
        }
    }

    private struct Boom: Error {}

    private let request = AIRequest(system: "s", user: "u")
    private var busyChanges: [Bool] = []
    private var providerBuilds = 0

    private func runner(_ provider: CountingProvider, enabled: Bool = true, availability: AIAvailability = .ready,
                        timeout: TimeInterval = 5, buildError: Error? = nil) -> AIRunner {
        busyChanges = []
        providerBuilds = 0
        return AIRunner(timeout: timeout, isEnabled: { enabled }, availability: { availability },
                        makeProvider: { [unowned self] in
                            providerBuilds += 1
                            if let buildError { throw buildError }
                            return provider
                        },
                        onBusyChange: { [unowned self] in busyChanges.append($0) })
    }

    private func expect(_ error: AIError, from work: () async throws -> String, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await work()
            XCTFail("expected \(error)", file: file, line: line)
        } catch let thrown as AIError {
            XCTAssertEqual(thrown, error, file: file, line: line)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    func testDisabledNeverBuildsOrCallsAProvider() async {
        let provider = CountingProvider()
        let r = runner(provider, enabled: false)
        await expect(.disabled) { try await r.run(request) }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(providerBuilds, 0)
        XCTAssertTrue(busyChanges.isEmpty)
    }

    func testUnavailableNeverCallsAProvider() async {
        let provider = CountingProvider()
        let r = runner(provider, availability: .unavailable("no model"))
        await expect(.unavailable("no model")) { try await r.run(request) }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(providerBuilds, 0)
    }

    func testSuccessReturnsTheAnswerAndResetsBusy() async throws {
        let provider = CountingProvider()
        let r = runner(provider)
        let answer = try await r.run(request)
        XCTAssertEqual(answer, "answer")
        XCTAssertFalse(r.isBusy)
        XCTAssertEqual(busyChanges, [true, false])
        XCTAssertEqual(provider.calls, 1)
    }

    func testASecondRequestWhileBusyIsRefused() async throws {
        let provider = CountingProvider()
        provider.delayNanoseconds = 300_000_000
        let r = runner(provider)
        let first = Task { try await r.run(request) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(r.isBusy)
        do {
            _ = try await r.run(request)
            XCTFail("a second request must be refused")
        } catch let error as AIError {
            guard case .unavailable = error else { return XCTFail("got \(error)") }
        }
        let firstAnswer = try await first.value
        XCTAssertEqual(firstAnswer, "answer")
        XCTAssertEqual(provider.calls, 1)
        XCTAssertFalse(r.isBusy)
    }

    func testTheTimeLimitReportsATimeoutAndFreesTheRunner() async {
        let provider = CountingProvider()
        provider.delayNanoseconds = 2_000_000_000
        let r = runner(provider, timeout: 0.05)
        await expect(.timeout) { try await r.run(request) }
        XCTAssertFalse(r.isBusy)
    }

    func testCancellingReportsCancelledNotATimeout() async throws {
        let provider = CountingProvider()
        provider.delayNanoseconds = 2_000_000_000
        let r = runner(provider)
        let work = Task { try await r.run(request) }
        try await Task.sleep(nanoseconds: 50_000_000)
        r.cancel()
        do {
            _ = try await work.value
            XCTFail("expected a cancellation")
        } catch let error as AIError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertFalse(r.isBusy)
    }

    func testProviderErrorsPassThroughAndOtherErrorsBecomeNetworkErrors() async {
        let failing = CountingProvider()
        failing.failure = AIError.unauthorized
        let r = runner(failing)
        await expect(.unauthorized) { try await r.run(request) }
        XCTAssertFalse(r.isBusy)
        let odd = CountingProvider()
        odd.failure = Boom()
        let r2 = runner(odd)
        do {
            _ = try await r2.run(request)
            XCTFail("expected an error")
        } catch let error as AIError {
            guard case .network = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("an AIError was expected")
        }
        XCTAssertFalse(r2.isBusy)
    }

    func testAProviderThatCannotBeBuiltFailsCleanly() async {
        let provider = CountingProvider()
        let r = runner(provider, buildError: AIError.invalidEndpoint)
        await expect(.invalidEndpoint) { try await r.run(request) }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertFalse(r.isBusy)
        XCTAssertTrue(busyChanges.isEmpty)
    }
}
