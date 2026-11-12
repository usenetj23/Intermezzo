import Foundation

/// The arithmetic behind the "equaliser" charts: a row of bands, each holding one value.
enum EqualizerBands {
    /// The value at a moment of the day for 24 hourly bands, `minute` in 0..<1440 (values outside wrap).
    /// Band centres are at h:30; between two centres the value blends with a smoothstep, so there are no steps.
    static func dayValue(_ hourly: [Double], atMinuteOfDay minute: Double) -> Double {
        let count = hourly.count
        guard count > 0 else { return 0 }
        guard minute.isFinite else { return hourly[0] }
        var m = minute.truncatingRemainder(dividingBy: 1440)
        if m < 0 { m += 1440 }
        let position = (m - 30) / 60
        let lower = Int(floor(position))
        let fraction = position - Double(lower)
        let a = hourly[((lower % count) + count) % count]
        let b = hourly[(((lower + 1) % count) + count) % count]
        let t = fraction * fraction * (3 - 2 * fraction)
        return a + (b - a) * t
    }

    /// A drag from one point to another sets every band in between on a straight line, so that a fast
    /// stroke leaves no gaps. Positions are in bands (fractions allowed); bands outside are ignored.
    static func painted(_ values: [Double], fromBand a: Double, value va: Double, toBand b: Double, value vb: Double,
                        snap: (Double) -> Double) -> [Double] {
        guard a.isFinite, b.isFinite, !values.isEmpty else { return values }
        // Clamped before turning into Int (a huge position would trap); the slope still uses a and b.
        let span = Double(values.count)
        let first = Int(floor(min(max(min(a, b), -1), span))), last = Int(floor(min(max(max(a, b), -1), span)))
        var result = values
        for band in first...last where values.indices.contains(band) {
            let t = abs(b - a) < 1e-9 ? 1 : (Double(band) + 0.5 - a) / (b - a)
            result[band] = snap(va + (vb - va) * min(max(t, 0), 1))
        }
        return result
    }

    /// Values snapped to `step` within `range`, cut or padded with `pad` to `count`.
    static func normalized(_ values: [Double], count: Int, pad: Double, range: ClosedRange<Double>, step: Double) -> [Double] {
        let snapped = values.prefix(count).map { snap($0, range: range, step: step) }
        return snapped + Array(repeating: snap(pad, range: range, step: step), count: max(count - snapped.count, 0))
    }

    static func snap(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let finite = value.isFinite ? value : range.upperBound
        let clamped = min(max(finite, range.lowerBound), range.upperBound)
        return (clamped / step).rounded() * step
    }

    static func encode(_ values: [Double]) -> String { values.map { String(Int($0)) }.joined(separator: ",") }

    static func decode(_ text: String?, count: Int) -> [Double]? {
        guard let text else { return nil }
        let numbers = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return numbers.count == count ? numbers : nil
    }
}
