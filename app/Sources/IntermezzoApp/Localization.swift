import AppKit
import Foundation
import IntermezzoKit
import SwiftUI

/// Looks `key` up in the app's own Localizable.strings (en/pl). A key without a translation is
/// returned as written, so partially translated areas still read correctly.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .main, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// Language choice and relaunch (the language is read once per launch).
enum LanguageSwitch {
    private static let appleLanguagesKey = "AppleLanguages"

    static var current: AppLanguage {
        AppLanguage.current(appleLanguages: UserDefaults.standard.stringArray(forKey: appleLanguagesKey))
    }

    static func apply(_ language: AppLanguage) {
        if let languages = language.appleLanguages {
            UserDefaults.standard.set(languages, forKey: appleLanguagesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        }
    }

    /// Quits and opens a fresh copy a moment later.
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// "Oczy · Wzrok w dal" -> both halves translated.
func localizedExerciseName(_ name: String) -> String {
    let parts = name.components(separatedBy: " · ")
    return parts.map { L($0) }.joined(separator: " · ")
}

extension Text {
    /// For strings that arrive in a `String` variable (enum titles, notes): looked up like a literal.
    init(localized key: String) {
        self.init(LocalizedStringKey(key))
    }
}
