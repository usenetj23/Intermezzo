import AppKit
import IntermezzoKit

enum UpdateKeys {
    /// On when the person switched the daily check on (off by default: it contacts GitHub).
    static let enabled = "updateCheckEnabled"
    /// This Mac only (see SyncPolicy).
    static let lastCheck = "updateLastCheck"
    static let skipped = "updateSkippedVersion"
    static let notified = "updateNotifiedVersion"
}

/// Tells when a newer release exists on GitHub. It only reads the newest release's description (a plain HTTPS
/// request, no identifier, nothing about the Mac) and never downloads or installs anything.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking
        case upToDate(String)
        case available(ReleaseInfo)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    private var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// A check a while after launch and then every few hours; each one runs only when switched on and due.
    func startAutomaticChecks() {
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard defaults.bool(forKey: UpdateKeys.enabled) else { return }
        let last = defaults.object(forKey: UpdateKeys.lastCheck) as? Double
        guard UpdateCheck.isDue(lastCheck: last.map { Date(timeIntervalSince1970: $0) }, now: Date()) else { return }
        Task { await check(manual: false) }
    }

    /// `manual` is a click on "Check now": it works with the daily check off and always shows its result.
    func check(manual: Bool) async {
        guard state != .checking else { return }
        state = .checking
        defaults.set(Date().timeIntervalSince1970, forKey: UpdateKeys.lastCheck)
        guard let url = URL(string: UpdateCheck.latestReleaseAPI) else { state = .idle; return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Intermezzo-update-check", forHTTPHeaderField: "User-Agent")
        do {
            // No cookies, no cache, nothing kept between checks.
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 {
                state = .upToDate(installedVersion)   // no release published yet
                return
            }
            guard status == 200, let release = UpdateCheck.parse(data) else {
                Trace.log("update check: unexpected answer (HTTP \(status))")
                state = .failed(L("nieoczekiwana odpowiedź GitHub"))
                return
            }
            if UpdateCheck.isNewer(release, than: installedVersion) {
                state = .available(release)
                Trace.log("update check: \(release.tag) is available")
                if !manual { notifyOnce(release) }
            } else {
                state = .upToDate(installedVersion)
            }
        } catch {
            Trace.log("update check failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func skip(_ release: ReleaseInfo) {
        defaults.set(release.version.description, forKey: UpdateKeys.skipped)
        state = .idle
    }

    func open(_ release: ReleaseInfo) {
        NSWorkspace.shared.open(release.url)
    }

    /// One reminder per version, none for a version the person chose to skip.
    private func notifyOnce(_ release: ReleaseInfo) {
        let version = release.version.description
        guard defaults.string(forKey: UpdateKeys.skipped) != version,
              defaults.string(forKey: UpdateKeys.notified) != version else { return }
        defaults.set(version, forKey: UpdateKeys.notified)
        ToastCenter.shared.show(
            title: L("Dostępna nowa wersja"),
            body: L("Intermezzo %@ czeka na stronie wydań. Nic nie jest pobierane ani instalowane samo.", version),
            symbol: "arrow.down.circle",
            actions: [ToastAction(title: L("Zobacz")) { [weak self] in self?.open(release) },
                      ToastAction(title: L("Pomiń tę wersję")) { [weak self] in self?.skip(release) }])
    }
}
