import Foundation

// Brightness per display ("peer displays"): the built-in screen and every monitor are equal rows, each
// with its own source, multiplier and limits. In the automatic (nits) mode macOS keeps driving the
// built-in screen with its own algorithm; the monitors then get the same luminance in nits:
//
//   level_ext = clamp( nits_builtIn_now / maxNits_ext × scale%, min%, max% )
//
// Without a reference (lid closed, a Mac without a built-in screen, no reading) the monitors fall back to
// the brightness equaliser. Pure logic only; the app reads the screens.

/// Where one display's brightness comes from.
public enum BrightnessSource: String, Codable, CaseIterable, Sendable {
    /// The general choice: follow the built-in screen in the nits mode, otherwise the equaliser.
    case automatic
    /// Always the hourly and room equaliser.
    case equalizer
    /// The brightness of this display is not managed.
    case off

    /// A value written by a newer version must not make the whole monitor profile unreadable.
    public init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(BrightnessSource.init(rawValue:)) ?? .automatic
    }
}

/// What an EDID (the block a monitor describes itself with) says about the monitor.
public enum EDIDInfo {
    private static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    private static let blockSize = 128

    /// Vendor (big-endian, bytes 8-9) and product (little-endian, bytes 10-11), as CoreGraphics reports them.
    public static func key(_ edid: [UInt8]) -> MonitorKey? {
        guard edid.count >= blockSize, Array(edid.prefix(8)) == header else { return nil }
        let vendor = UInt32(edid[8]) << 8 | UInt32(edid[9])
        let model = UInt32(edid[11]) << 8 | UInt32(edid[10])
        return MonitorKey(vendor: vendor, model: model)
    }

    /// "Desired content max luminance" from the CTA-861 HDR static metadata block, in nits
    /// (50 × 2^(CV/32)); nil when the monitor does not say (most SDR monitors).
    public static func maxLuminance(_ edid: [UInt8]) -> Double? {
        guard key(edid) != nil else { return nil }
        var offset = blockSize
        while offset + blockSize <= edid.count {
            let block = Array(edid[offset..<(offset + blockSize)])
            if block[0] == 0x02, let value = hdrMaxLuminance(cta: block) { return value }
            offset += blockSize
        }
        return nil
    }

    private static func hdrMaxLuminance(cta block: [UInt8]) -> Double? {
        let end = min(Int(block[2]), block.count)
        var index = 4
        while index < end {
            let tag = block[index] >> 5
            let length = Int(block[index] & 0x1F)
            let payload = index + 1
            // Extended tag 6 = HDR static metadata: [6, EOTFs, descriptors, max CV, max frame-average CV, min CV]
            if tag == 7, length >= 4, payload + 3 < min(end, block.count), block[payload] == 0x06 {
                let code = block[payload + 3]
                return code == 0 ? nil : 50 * pow(2, Double(code) / 32)
            }
            index = payload + length
        }
        return nil
    }
}

/// The built-in screen's luminance. macOS gives several readings; the best available one is used.
public enum BuiltInNits {
    /// macOS's brightness slider is not linear in light. Assumption (one measured point on a MacBook Pro:
    /// slider 0.60 gave a linear 0.278): linear ≈ slider^2.5. Used only when no better reading exists.
    public static let sliderExponent = 2.5

    public static func linear(fromSlider slider: Double) -> Double {
        pow(min(max(slider, 0), 1), sliderExponent)
    }

    /// An IORegistry number in 16.16 fixed point, little-endian (e.g. "user-accessible-max-nits").
    public static func fixed1616(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return Double(raw) / 65536
    }

    /// The panel's SDR luminance limits. `nominal`: macOS's "Max SDR Luminance" (the slider's top in normal
    /// light, 600 on an M5 Max); `ceiling`: the most SDR white reaches when macOS lifts the limit in bright
    /// light (the outdoor mode, 1000 on an M5 Max).
    public struct SDRLimits: Equatable, Sendable {
        public let nominal: Double
        public let ceiling: Double

        public init(nominal: Double, ceiling: Double) {
            self.nominal = nominal
            self.ceiling = max(ceiling, nominal)
        }
    }

    /// From the "user-accessible-max-nits" values in the registry: `backlight` is the backlight node's own
    /// (the nominal one), `declared` all that were found (e.g. also "backlight-override"). Without the
    /// backlight's value the smallest declared one is taken as nominal. Zero and unreadable values are ignored.
    public static func sdrLimits(backlight: [UInt8]?, declared: [[UInt8]]) -> SDRLimits? {
        let valid = { (bytes: [UInt8]) -> Double? in fixed1616(bytes).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        let all = (declared + (backlight.map { [$0] } ?? [])).compactMap(valid)
        guard let nominal = backlight.flatMap(valid) ?? all.min(), let ceiling = all.max() else { return nil }
        return SDRLimits(nominal: nominal, ceiling: ceiling)
    }

    /// The maximum in effect: the nominal one, or the ceiling once the measured white is above the nominal
    /// (macOS has switched to the outdoor mode).
    public static func effectiveMax(_ limits: SDRLimits, measuredNits: Double?) -> Double {
        guard let measured = measuredNits, measured.isFinite, measured > limits.nominal else { return limits.nominal }
        return limits.ceiling
    }

    /// The nits of the screen's SDR white now.
    /// 1. The backlight's own reading (milli-nits). The backlight runs above SDR white by the current EDR
    ///    headroom (so HDR highlights can be brighter), which is divided out.
    /// 2. Otherwise the linear brightness, 3. or the slider through `linear(fromSlider:)`, times `maxNits`
    ///    (the nominal maximum).
    /// A measured value is never above `ceiling` (the outdoor top; `maxNits` when not given), so a bright day
    /// is not cut to the nominal maximum. Nil when nothing usable is known.
    public static func sdrNits(backlightMilliNits: Double?, headroom: Double?, linear: Double?, slider: Double?,
                               maxNits: Double?, ceiling: Double? = nil) -> Double? {
        let positive = { (value: Double?) -> Double? in value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        let cap = positive(maxNits)
        if let milli = backlightMilliNits, milli.isFinite, milli > 0 {
            let divisor = headroom.flatMap { $0.isFinite && $0 > 1 ? $0 : nil } ?? 1
            let nits = milli / 1000 / divisor
            return (positive(ceiling) ?? cap).map { min(nits, $0) } ?? nits
        }
        guard let cap else { return nil }
        if let linear, linear.isFinite { return min(max(linear, 0), 1) * cap }
        if let slider, slider.isFinite { return Self.linear(fromSlider: slider) * cap }
        return nil
    }
}

public enum PeerBrightness {
    /// A monitor that does not tell its maximum: a typical office monitor.
    public static let defaultExternalMaxNits = 350.0
    public static let scaleRange = 25...200
    public static let percentRange = 5...100
    public static let nitsRange = 50...3000

    public enum Kind: Equatable, Sendable {
        /// Hourly and room equaliser.
        case equalizer
        /// The same nits as the built-in screen.
        case followsBuiltIn(nits: Double)
        /// macOS drives it (the built-in screen in the nits mode).
        case apple
        /// The display's own "do not manage the brightness".
        case off
        /// The monitor is left alone altogether.
        case untouched
    }

    public struct Resolution: Equatable, Sendable {
        public let goal: DisplayBrightnessGoal
        public let kind: Kind

        public init(goal: DisplayBrightnessGoal, kind: Kind) {
            self.goal = goal
            self.kind = kind
        }
    }

    /// A level with the display's own multiplier and limits, never below the global floor.
    public static func limited(_ level: Double, profile: MonitorProfile?) -> Double {
        let scale = Double(profile?.brightnessScale ?? 100) / 100
        let high = Double(profile?.brightnessMaxPercent ?? percentRange.upperBound) / 100
        let low = min(Double(profile?.brightnessMinPercent ?? percentRange.lowerBound) / 100, high)
        let scaled = level.isFinite ? level * scale : 1
        return ScreenBrightness.clamp(min(max(scaled, low), high))
    }

    /// The level that gives `maxNits`-bright monitor the built-in screen's luminance (unclamped).
    public static func followLevel(builtInNits: Double?, maxNits: Double) -> Double? {
        guard let nits = builtInNits, nits.isFinite, nits > 0, maxNits.isFinite, maxNits > 0 else { return nil }
        return nits / maxNits
    }

    /// One display's brightness. `automatic`: the nits mode is on; `builtInNits`: the built-in screen's
    /// SDR white now (nil without a reference); `detectedMaxNits`: from the EDID.
    public static func resolve(isBuiltIn: Bool, profile: MonitorProfile?, automatic: Bool, equalizerLevel: Double,
                               builtInNits: Double?, detectedMaxNits: Double?) -> Resolution {
        if profile?.untouched == true { return Resolution(goal: .original, kind: .untouched) }
        let source = profile?.brightnessSource ?? .automatic
        if source == .off { return Resolution(goal: .original, kind: .off) }
        let equalizer = Resolution(goal: .level(limited(equalizerLevel, profile: profile)), kind: .equalizer)
        if isBuiltIn { return automatic ? Resolution(goal: .original, kind: .apple) : equalizer }
        guard automatic, source == .automatic else { return equalizer }
        let maxNits = profile?.maxNits.map(Double.init) ?? detectedMaxNits ?? defaultExternalMaxNits
        guard let follow = followLevel(builtInNits: builtInNits, maxNits: maxNits), let nits = builtInNits else { return equalizer }
        return Resolution(goal: .level(limited(follow, profile: profile)), kind: .followsBuiltIn(nits: nits))
    }
}
