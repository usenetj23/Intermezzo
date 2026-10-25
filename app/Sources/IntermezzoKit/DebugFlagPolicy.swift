import Foundation

/// Allow-list for `intermezzo://debug/flag?k=…&v=…`. Any web page can open an
/// `intermezzo://` URL, so the route may touch ONLY the rendering-diagnostic
/// flags it was made for (read in `WeatherFX.fogDirect`). Every other key —
/// feature flags, `focusShortcutsEnabled`, `focusShortcut.*`, `strictMode`,
/// stored data — is refused. Exact, case-sensitive match; no prefixes.
public enum DebugFlagPolicy {
    public static let allowedKeys: Set<String> = ["fxNoFog", "fxNoTrails", "fxNoImg"]

    public static func isAllowed(key: String) -> Bool {
        allowedKeys.contains(key)
    }
}
