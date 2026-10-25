import Foundation

/// "#RRGGBB" <-> 0...1 components, for storing a project colour as text.
public enum ColorHex {
    /// Components of a "#RRGGBB" / "RRGGBB" string; nil when malformed.
    public static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// "#RRGGBB" (uppercase); components are clamped to 0...1.
    public static func string(r: Double, g: Double, b: Double) -> String {
        func byte(_ x: Double) -> Int { Int((min(1, max(0, x)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
