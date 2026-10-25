import Foundation

/// Lookup in the app bundle's Localizable.strings for text built inside the library.
/// Without a translation (or in tests) the key itself is returned.
func kitL(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .main, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}
