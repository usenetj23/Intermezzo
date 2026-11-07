import AppIntents
import IntermezzoKit

// Intermezzo's actions for the Shortcuts app: conditions (answers for an "If"), values and commands.
// They run inside the app and read the same state that `state.json` and the notifications publish. The
// descriptions of these actions reach Shortcuts only through `Metadata.appintents`, which
// scripts/generate_app_intents_metadata.sh writes into the app bundle (SwiftPM does not).

/// What the intents reach in the running app.
@MainActor
enum IntentBridge {
    static var state: AutomationState? { AutomationBus.shared.state }

    static func run(_ command: AutomationCommand) throws {
        guard let delegate = AppDelegate.shared else { throw IntermezzoIntentError.notReady }
        delegate.run(command)
    }
}

enum IntermezzoIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: return "Intermezzo jeszcze się nie uruchomiło"
        }
    }
}

enum BreakKindOption: String, AppEnum {
    case short, long

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Rodzaj przerwy"
    static let caseDisplayRepresentations: [BreakKindOption: DisplayRepresentation] = [
        .short: "Krótka",
        .long: "Długa",
    ]
}

/// The timer in one word, with the values Shortcuts offers in an "If" (instead of text to type from memory).
enum TimerStateOption: String, AppEnum {
    case running, paused, onBreak

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stan timera"
    static let caseDisplayRepresentations: [TimerStateOption: DisplayRepresentation] = [
        .running: "Odlicza",
        .paused: "Wstrzymany",
        .onBreak: "Trwa przerwa",
    ]
}

/// What opened the work zone.
enum WorkZoneSourceOption: String, AppEnum {
    case calendar, vpn, wifi, place, lan, focus

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Źródło strefy pracy"
    static let caseDisplayRepresentations: [WorkZoneSourceOption: DisplayRepresentation] = [
        .calendar: "Kalendarz",
        .vpn: "VPN",
        .wifi: "Wi-Fi",
        .place: "Zapisane miejsce",
        .lan: "LAN z Rejestru pracy",
        .focus: "Skupienie jako praca",
    ]
}

/// The whole state as one thing with named properties: "Get Details of Intermezzo state" lists them, like the
/// properties of a VPN, so nothing has to be typed from memory.
struct IntermezzoStateEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stan Intermezzo"
    static let defaultQuery = IntermezzoStateQuery()

    var id: String { "current" }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Stan Intermezzo", subtitle: "\(timer.rawValue)")
    }

    @Property(title: "Timer") var timer: TimerStateOption
    @Property(title: "Trwa przerwa") var onBreak: Bool
    @Property(title: "W strefie pracy") var inWorkZone: Bool
    @Property(title: "Źródła strefy pracy") var workZoneSources: [WorkZoneSourceOption]
    @Property(title: "Trwa spotkanie") var inMeeting: Bool
    @Property(title: "Włączone Skupienie") var focusActive: Bool
    @Property(title: "Bezczynność") var away: Bool
    @Property(title: "Ekran zablokowany") var screenLocked: Bool
    @Property(title: "Połączony VPN") var vpnConnected: Bool
    @Property(title: "Rodzaj następnej przerwy") var nextBreakKind: BreakKindOption
    @Property(title: "Sekundy do następnej przerwy") var secondsUntilBreak: Int
    @Property(title: "Początek następnej przerwy") var nextBreakAt: Date?
    @Property(title: "Koniec trwającej przerwy") var breakEndsAt: Date?

    init() {
        self.init(state: nil)
    }

    init(state: AutomationState?) {
        timer = TimerStateOption(rawValue: state?.timer ?? "paused") ?? .paused
        onBreak = state?.onBreak ?? false
        inWorkZone = state?.inWorkZone ?? false
        workZoneSources = (state?.workZoneSources ?? []).compactMap(WorkZoneSourceOption.init(rawValue:))
        inMeeting = state?.inMeeting ?? false
        focusActive = state?.focusActive ?? false
        away = state?.away ?? false
        screenLocked = state?.screenLocked ?? false
        vpnConnected = state?.vpnConnected ?? false
        nextBreakKind = BreakKindOption(rawValue: state?.nextBreakKind ?? "short") ?? .short
        secondsUntilBreak = state?.nextBreakAt.map { max(0, Int($0.timeIntervalSinceNow.rounded())) } ?? -1
        nextBreakAt = state?.nextBreakAt
        breakEndsAt = state?.breakEndsAt
    }
}

struct IntermezzoStateQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [IntermezzoStateEntity] {
        identifiers.contains("current") ? [IntermezzoStateEntity(state: IntentBridge.state)] : []
    }

    @MainActor func suggestedEntities() async throws -> [IntermezzoStateEntity] {
        [IntermezzoStateEntity(state: IntentBridge.state)]
    }
}

struct GetStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Pobierz stan Intermezzo"
    static let description = IntentDescription("Zwraca cały stan Intermezzo jako jedną rzecz: w skrócie wybierzesz z listy jej właściwości (timer, strefa pracy, spotkanie, Skupienie, VPN…), tak jak przy akcji VPN.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntermezzoStateEntity> {
        .result(value: IntermezzoStateEntity(state: IntentBridge.state))
    }
}

// MARK: - Conditions (answers for "If")

struct IsOnBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy trwa przerwa"
    static let description = IntentDescription("Odpowiada, czy na ekranie jest teraz przerwa Intermezzo.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.onBreak ?? false)
    }
}

struct IsTimerRunningIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy timer przerw działa"
    static let description = IntentDescription("Odpowiada, czy timer przerw odlicza (nie jest wstrzymany ani na przerwie).", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.running ?? false)
    }
}

struct IsInWorkZoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy Mac jest w strefie pracy"
    static let description = IntentDescription("Odpowiada, czy pasuje któreś ze źródeł strefy pracy (kalendarz, VPN, Wi-Fi, miejsce, LAN, Skupienie). Bez włączonych źródeł odpowiedź to nie.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.inWorkZone ?? false)
    }
}

struct IsInMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy trwa spotkanie"
    static let description = IntentDescription("Odpowiada, czy Intermezzo wykrywa trwające spotkanie (Zoom, Teams, Webex).", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.inMeeting ?? false)
    }
}

struct IsFocusOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy włączone jest Skupienie"
    static let description = IntentDescription("Odpowiada, czy włączony jest jakikolwiek tryb Skupienia (wymaga Pełnego dostępu do dysku).", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.focusActive ?? false)
    }
}

struct IsIdleIntent: AppIntent {
    static let title: LocalizedStringResource = "Czy Mac jest bezczynny"
    static let description = IntentDescription("Odpowiada, czy od dłuższego czasu nie było ruchu myszą ani klawiaturą i timer jest wstrzymany.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: IntentBridge.state?.away ?? false)
    }
}

// MARK: - Values

struct TimerStateIntent: AppIntent {
    static let title: LocalizedStringResource = "Stan timera Intermezzo"
    static let description = IntentDescription("Zwraca stan timera: odlicza, wstrzymany albo trwa przerwa. W „Jeśli” wybierzesz wartość z listy.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<TimerStateOption> {
        .result(value: TimerStateOption(rawValue: IntentBridge.state?.timer ?? "") ?? .paused)
    }
}

struct SecondsUntilBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Sekundy do następnej przerwy"
    static let description = IntentDescription("Zwraca liczbę sekund do następnej przerwy albo -1, gdy timer nie odlicza.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let at = IntentBridge.state?.nextBreakAt else { return .result(value: -1) }
        return .result(value: max(0, Int(at.timeIntervalSinceNow.rounded())))
    }
}

struct NextBreakKindIntent: AppIntent {
    static let title: LocalizedStringResource = "Rodzaj następnej przerwy"
    static let description = IntentDescription("Zwraca rodzaj następnej przerwy: krótka albo długa.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<BreakKindOption> {
        .result(value: BreakKindOption(rawValue: IntentBridge.state?.nextBreakKind ?? "") ?? .short)
    }
}

struct StateJSONIntent: AppIntent {
    static let title: LocalizedStringResource = "Pełny stan Intermezzo (JSON)"
    static let description = IntentDescription("Zwraca cały stan jako tekst JSON, do użycia z akcją „Pobierz słownik z danych wejściowych”.", categoryName: "Stan")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: IntentBridge.state?.jsonString(pretty: false) ?? "{}")
    }
}

// MARK: - Commands

struct StartBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Rozpocznij przerwę"
    static let description = IntentDescription("Rozpoczyna krótką albo długą przerwę teraz.", categoryName: "Sterowanie")

    @Parameter(title: "Rodzaj przerwy", default: .short) var kind: BreakKindOption

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(kind == .long ? .startLong : .startShort)
        return .result()
    }
}

struct SkipBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Pomiń przerwę"
    static let description = IntentDescription("Pomija bieżącą lub najbliższą przerwę.", categoryName: "Sterowanie")

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(.skip)
        return .result()
    }
}

struct PostponeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Odrocz przerwę"
    static let description = IntentDescription("Odracza najbliższą przerwę o podaną liczbę minut.", categoryName: "Sterowanie")

    @Parameter(title: "Minuty", default: 5) var minutes: Int

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(.postpone(minutes: max(1, minutes)))
        return .result()
    }
}

struct PauseTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Wstrzymaj timer przerw"
    static let description = IntentDescription("Wstrzymuje timer przerw do wznowienia.", categoryName: "Sterowanie")

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(.pause)
        return .result()
    }
}

struct ResumeTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Wznów timer przerw"
    static let description = IntentDescription("Wznawia timer przerw.", categoryName: "Sterowanie")

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(.resume)
        return .result()
    }
}

struct ResetTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Zresetuj timer przerw"
    static let description = IntentDescription("Zeruje cykl i liczy do następnej przerwy od nowa.", categoryName: "Sterowanie")

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(.reset)
        return .result()
    }
}

struct SetLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Włącz lub wyłącz Światło"
    static let description = IntentDescription("Włącza albo wyłącza dopasowanie barwy ekranu do pory dnia.", categoryName: "Sterowanie")

    @Parameter(title: "Włączone", default: true) var enabled: Bool

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(enabled ? .lightOn : .lightOff)
        return .result()
    }
}

struct SetKeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Włącz lub wyłącz czuwanie"
    static let description = IntentDescription("Włącza albo wyłącza czuwanie: Mac nie zaśnie, dopóki jest włączone.", categoryName: "Sterowanie")

    @Parameter(title: "Włączone", default: true) var enabled: Bool

    @MainActor func perform() async throws -> some IntentResult {
        try IntentBridge.run(enabled ? .awakeOn : .awakeOff)
        return .result()
    }
}
