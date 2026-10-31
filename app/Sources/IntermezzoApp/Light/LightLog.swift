import Foundation

/// The Light feature's entries in ~/Library/Logs/Intermezzo/trace.log (all lines start with "light").
/// `event` is for rare things and always written; `detail` is every goal change, fade and screen write with
/// its reason and a millisecond stamp, written only while "Szczegółowy dziennik Światła" is on.
enum LightLog {
    static let key = "lightDebugLog"

    static var detailed: Bool { UserDefaults.standard.bool(forKey: key) }

    private static func stamp() -> String {
        let now = Date().timeIntervalSince1970
        return String(format: ".%03d", Int((now - now.rounded(.down)) * 1000))
    }

    static func event(_ message: @autoclosure () -> String) {
        Trace.log("light: \(message())")
    }

    static func detail(_ message: @autoclosure () -> String) {
        guard detailed else { return }
        Trace.log("light\(stamp()) \(message())")
    }
}
