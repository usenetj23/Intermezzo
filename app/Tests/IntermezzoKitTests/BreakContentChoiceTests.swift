import XCTest
@testable import IntermezzoKit

final class BreakContentChoiceTests: XCTestCase {
    private let custom = BreakContent(headline: "My stretch", detail: "mine")
    private let library = BreakContent(headline: "Library", detail: "lib")
    private let advised = BreakContent(headline: "Oddech w kwadracie", detail: "4-4-4-4")
    private let stock = BreakContent(headline: "Stock", detail: "tip")

    private func choose(flag: Bool, custom: BreakContent?, any: BreakContent?,
                        advice: SessionAdvice, resolved: BreakContent?,
                        adviceAsked: UnsafeMutablePointer<Bool>? = nil) -> BreakContentChoice {
        BreakContentChoice.choose(
            sessionAwareEnabled: flag,
            customAssigned: { custom },
            anyAssigned: { any },
            advice: { adviceAsked?.pointee = true; return advice },
            resolve: { _ in resolved },
            rotation: { self.stock })
    }

    func testFlagOffKeepsOldPathAndNeverAsksTheAdvisor() {
        var asked = false
        let c = choose(flag: false, custom: nil, any: library, advice: .category(.breathing),
                       resolved: advised, adviceAsked: &asked)
        XCTAssertEqual(c, BreakContentChoice(content: library, source: .assigned))
        XCTAssertFalse(asked)
        let none = choose(flag: false, custom: nil, any: nil, advice: .category(.breathing), resolved: advised)
        XCTAssertEqual(none, BreakContentChoice(content: stock, source: .rotation))
    }

    func testFlagOnLibraryAssignmentsDoNotBlockTheAdvice() {
        let c = choose(flag: true, custom: nil, any: library, advice: .category(.breathing), resolved: advised)
        XCTAssertEqual(c, BreakContentChoice(content: advised, source: .sessionAware))
    }

    func testFlagOnCustomAssignedExerciseWins() {
        var asked = false
        let c = choose(flag: true, custom: custom, any: library, advice: .category(.breathing),
                       resolved: advised, adviceAsked: &asked)
        XCTAssertEqual(c, BreakContentChoice(content: custom, source: .assigned))
        XCTAssertFalse(asked)
    }

    func testFlagOnRotationAdviceFallsBackToAssignedThenStock() {
        let c = choose(flag: true, custom: nil, any: library, advice: .rotation, resolved: advised)
        XCTAssertEqual(c, BreakContentChoice(content: library, source: .assigned))
        let none = choose(flag: true, custom: nil, any: nil, advice: .rotation, resolved: advised)
        XCTAssertEqual(none, BreakContentChoice(content: stock, source: .rotation))
    }

    func testFlagOnEmptyPickFallsBackToAssigned() {
        let c = choose(flag: true, custom: nil, any: library, advice: .category(.eyes), resolved: nil)
        XCTAssertEqual(c, BreakContentChoice(content: library, source: .assigned))
    }

    func testWeatherTipNeverReplacesSessionAwareInstructions() {
        let session = BreakContentChoice(content: advised, source: .sessionAware)
        XCTAssertEqual(session.applyingWeatherTip("Pada deszcz"), advised)
        let rotation = BreakContentChoice(content: stock, source: .rotation)
        XCTAssertEqual(rotation.applyingWeatherTip("Pada deszcz"),
                       BreakContent(headline: "Stock", detail: "Pada deszcz"))
        XCTAssertEqual(rotation.applyingWeatherTip(nil), stock)
    }

    func testLibraryNamesAreRecognisedCustomNamesAreNot() {
        XCTAssertTrue(ExerciseLibrary.isLibraryName(ExerciseLibrary.all[0].name))
        XCTAssertFalse(ExerciseLibrary.isLibraryName("My own stretch"))
    }
}
