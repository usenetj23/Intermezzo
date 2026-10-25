import Foundation

public struct RGB: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// The user-picked colour behind the Navy and Glass surfaces.
public enum SurfaceTint {
    /// The navy the old "Glass" theme always used.
    public static let defaultHex = "1C2638"

    public static func rgb(fromHex hex: String) -> RGB? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return RGB(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                   blue: Double(v & 0xFF) / 255)
    }

    public static func resolved(hex: String?) -> RGB {
        hex.flatMap(rgb(fromHex:)) ?? rgb(fromHex: defaultHex) ?? RGB(red: 0.11, green: 0.15, blue: 0.22)
    }

    /// Top colour is the tint itself; the bottom is the same hue, much darker.
    public static func gradient(hex: String?) -> (top: RGB, bottom: RGB) {
        let top = resolved(hex: hex)
        let k = 0.45
        return (top, RGB(red: top.red * k, green: top.green * k, blue: top.blue * k))
    }

    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

/// One-time migration of the stored surface theme after "Glass" was renamed.
public enum SurfaceMigration {
    /// Before the rename, "glass" meant the navy look, which is now "navy"; the new "glass" is truly translucent.
    public static func theme(stored: String?, alreadyMigrated: Bool) -> String? {
        if stored == "carbon" { return "navy" }          // removed theme
        guard !alreadyMigrated, stored == "glass" else { return stored }
        return "navy"
    }
}
