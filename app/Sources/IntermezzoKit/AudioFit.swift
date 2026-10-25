import Foundation

/// How a relaxation track of a given length behaves over a break of a given length.
public enum AudioFit: Equatable, Sendable {
    /// Track is at least as long as the break; `excess` seconds are never heard.
    case coversBreak(excess: TimeInterval)
    /// Track is shorter but loops; it plays `times` passes (last one is cut).
    case loops(times: Int)
    /// Track is shorter and does not loop; silence for the last `silentFor` seconds.
    case endsEarly(silentFor: TimeInterval)
    /// Length could not be read.
    case unknown

    /// `true` when the whole break is filled with sound.
    public var isFine: Bool {
        switch self {
        case .coversBreak, .loops: return true
        case .endsEarly, .unknown: return false
        }
    }

    public static func evaluate(trackSeconds: TimeInterval?, breakSeconds: TimeInterval, loop: Bool) -> AudioFit {
        guard let track = trackSeconds, track > 0 else { return .unknown }
        if track >= breakSeconds { return .coversBreak(excess: track - breakSeconds) }
        if loop { return .loops(times: Int((breakSeconds / track).rounded(.up))) }
        return .endsEarly(silentFor: breakSeconds - track)
    }

    /// `m:ss` (or `h:mm:ss` from one hour up); negative input clamps to zero.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
