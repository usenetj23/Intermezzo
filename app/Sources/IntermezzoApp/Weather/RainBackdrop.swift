import AppKit
import Accelerate

/// The scene behind the rain: what the drops refract and what the mist is made of.
/// Real desktop (captured before the overlay appears; needs Screen Recording) or,
/// without permission, a procedural night-city bokeh that looks like the reference.
struct RainBackdrop {
    let scene: CGImage      // lightly blurred — seen through the drops
    let blur: CGImage       // heavily blurred — the steamy pane
    let isReal: Bool
}

@MainActor
final class RainBackdropStore {
    static let shared = RainBackdropStore()
    private var byDisplay: [CGDirectDisplayID: RainBackdrop] = [:]

    /// Capture every display now (call BEFORE the overlay windows are shown).
    func captureAll() {
        byDisplay.removeAll()
        guard CGPreflightScreenCaptureAccess() else {
            Trace.log("rain backdrop: no Screen Recording permission — procedural scene")
            return
        }
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let shot = CGDisplayCreateImage(id),
                  let scene = Self.resample(shot, scale: 4, blurRadius: 1),
                  let blur = Self.resample(shot, scale: 10, blurRadius: 4) else { continue }
            byDisplay[id] = RainBackdrop(scene: scene, blur: blur, isReal: true)
        }
        Trace.log("rain backdrop: captured \(byDisplay.count) display(s)")
    }

    func backdrop(for screen: NSScreen?) -> RainBackdrop {
        if let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
           let real = byDisplay[id] { return real }
        return Self.procedural
    }

    func clear() { byDisplay.removeAll() }

    // MARK: CPU resampling (vImage — no Core Image / Metal involved)

    private static func resample(_ src: CGImage, scale: Int, blurRadius: UInt32) -> CGImage? {
        let w = max(64, src.width / scale), h = max(64, src.height / scale)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let px = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rowBytes = ctx.bytesPerRow
        var a = vImage_Buffer(data: px, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
        guard let tmp = malloc(rowBytes * h) else { return nil }
        defer { free(tmp) }
        var b = vImage_Buffer(data: tmp, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
        let flags = vImage_Flags(kvImageEdgeExtend)
        let k = blurRadius * 2 + 1
        for _ in 0..<2 {
            guard vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, k, k, nil, flags) == kvImageNoError,
                  vImageBoxConvolve_ARGB8888(&b, &a, nil, 0, 0, k, k, nil, flags) == kvImageNoError else { return nil }
        }
        return ctx.makeImage()
    }

    // MARK: Procedural fallback — dusky blue-grey street with warm and cool bokeh lights

    private static let procedural: RainBackdrop = {
        let w = 480, h = 300
        func make(blurred: Bool) -> CGImage {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let sky = CGGradient(colorsSpace: cs, colors: [
                CGColor(red: 0.42, green: 0.54, blue: 0.68, alpha: 1),
                CGColor(red: 0.24, green: 0.32, blue: 0.43, alpha: 1),
                CGColor(red: 0.13, green: 0.17, blue: 0.24, alpha: 1)] as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
            var s: UInt64 = 0xC0FFEE_1234
            func rnd() -> CGFloat {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((s >> 11) & 0xFFFFFF) / CGFloat(1 << 24)
            }
            let palette: [(CGFloat, CGFloat, CGFloat)] = [(1.0, 0.72, 0.38), (0.95, 0.45, 0.30),
                                                          (0.55, 0.78, 1.0), (0.9, 0.95, 1.0)]
            for _ in 0..<(blurred ? 64 : 110) {
                let c = palette[Int(rnd() * 4) % 4]
                let r = (blurred ? 28 : 6) + rnd() * (blurred ? 46 : 20)
                let x = rnd() * CGFloat(w), y = rnd() * CGFloat(h) * 0.97
                if let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: c.0, green: c.1, blue: c.2, alpha: blurred ? 0.34 : 0.62),
                                                                CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0)] as CFArray,
                                      locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
                }
            }
            return ctx.makeImage()!
        }
        return RainBackdrop(scene: make(blurred: false), blur: make(blurred: true), isReal: false)
    }()
}
