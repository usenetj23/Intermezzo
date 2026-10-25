import AppKit
import Metal
import QuartzCore
import SwiftUI
import IntermezzoKit

// Clouds, fog and sun as one Metal fragment shader (same engine approach as the rain):
//
//  clouds : domain-warped fBm density, lit by sampling the density toward the sun
//           (self-shadowing → bright sun-facing edges, grey bellies, silver lining)
//  fog    : three drifting fBm layers at different speeds/scales, denser near the ground,
//           warm scattering near the sun — rolling mist with visible structure
//  sun    : animated crepuscular rays (noise in polar space), bloom, anamorphic streak and
//           lens-flare ghosts on the sun→centre axis. The sun drifts a little and the flares
//           slide with the mouse (parallax), so nothing is static.
//
// Half-resolution drawable, ≈30 fps, no per-frame work on the CPU besides a few uniforms.

private let skyShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct SkyParams { float4 a; float4 sun; float4 b; float4 tint; float4 c; };
struct VOut { float4 position [[position]]; float2 uv; };

vertex VOut skyVS(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    VOut o;
    o.position = float4(p, 0.0, 1.0);
    o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    return o;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
}
static float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = rot * p * 2.02 + 17.0; a *= 0.5; }
    return v;
}
static float ring(float r, float radius, float width) {
    return smoothstep(width, 0.0, abs(r - radius));
}
static float hexa(float2 p, float r) {
    p = abs(p);
    return smoothstep(r, r * 0.92, max(p.x * 0.866 + p.y * 0.5, p.y));
}
// Signed distance to a regular n-gon (aperture blades), slightly rounded; negative inside.
static float polySDF(float2 p, float r, float n, float rot) {
    float c = cos(rot), s = sin(rot);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    float a = atan2(p.y, p.x) + 3.14159265;
    float seg = 6.2831853 / n;
    float d = cos(floor(0.5 + a / seg) * seg - a) * length(p);
    return d - r;
}
// One flare ghost: soft aperture-shaped disc, brighter rim on the side facing the sun,
// chromatic dispersion, lens dirt, never a hard outline.
static float3 ghost(float2 p, float2 g, float r, float2 toSun, float rot, float seed, float3 tintA, float3 tintB) {
    float2 q = p - g;
    float2 axis = normalize(toSun + 1e-5);
    float3 outc = float3(0.0);
    for (int ch = 0; ch < 3; ch++) {
        float shift = (float(ch) - 1.0) * r * 0.10;               // dispersion along the axis
        float sdf = polySDF(q + axis * shift, r, 6.0, rot) / r;    // −1 centre … 0 edge
        float inner = clamp(-sdf, 0.0, 1.0);
        float edge = smoothstep(0.10, -0.12, sdf);                  // soft border
        float rim = exp(-inner * 5.5);
        float facing = 0.35 + 0.65 * clamp(0.5 + 0.5 * dot(normalize(q + 1e-5), axis), 0.0, 1.0);
        float body = 0.16 * (1.0 - inner) + rim * 0.55 * facing;
        outc[ch] = body * edge;
    }
    float dirt = 0.55 + 0.45 * fbm(q * (3.0 / max(r, 0.01)) + seed * 7.3);
    float3 tint = mix(tintA, tintB, clamp(length(q) / max(r, 0.01), 0.0, 1.0));
    return outc * tint * dirt;
}

fragment float4 skyFS(VOut in [[stage_in]], constant SkyParams& P [[buffer(0)]]) {
    float t = P.a.x;
    int mode = int(P.a.y + 0.5);
    float aspect = P.a.z;
    float wind = P.a.w;
    float2 uv = in.uv;
    float2 p = float2(uv.x * aspect, uv.y);
    float2 sunP = float2(P.sun.x * aspect, P.sun.y);
    float night = P.sun.w;

    if (mode == 0) {                                   // ───────────── clouds
        float2 scale = float2(1.05, 1.9);
        float2 q = p * scale + float2(t * (0.010 + wind * 0.0016), 0.0);
        float w = fbm(q * 0.7 + float2(0.0, t * 0.006));
        float2 qq = q + float2(w * 1.0, w * 0.55);
        float d = fbm(qq);
        float dens = smoothstep(P.b.x, P.b.x + 0.22, d);
        float2 toSun = normalize(sunP - p + 1e-4) * 0.07;
        float d2 = fbm(qq + toSun * scale);
        float lit = clamp(0.55 + (d - d2) * 6.0, 0.0, 1.0);
        float3 shadow = float3(0.42, 0.48, 0.62);
        float3 bright = mix(float3(1.0, 0.97, 0.92), P.tint.rgb, 0.45);
        float3 col = mix(shadow, bright, lit);
        float edge = smoothstep(0.0, 0.10, dens) * (1.0 - smoothstep(0.10, 0.50, dens));
        col += edge * 0.35 * bright * lit;                       // silver lining
        col *= 1.0 - 0.55 * night;
        float horizon = smoothstep(0.98, 0.18, uv.y);           // sky fills most of the frame, thinning downward
        float a = clamp(dens * P.b.y * horizon, 0.0, 1.0);
        return float4(col * a, a);
    }

    if (mode == 1) {                                   // ───────────── fog
        float2 w1 = float2(t * 0.012, t * 0.002);
        float2 w2 = float2(-t * 0.021, t * 0.003);
        float2 w3 = float2(t * 0.007, -t * 0.001);
        float warp = fbm(p * 1.1 + w3 * 3.0);
        float f1 = fbm(p * float2(1.2, 2.0) + w1 + warp * 0.8);
        float f2 = fbm(p * float2(2.6, 3.6) + w2 + 7.0);
        float f3 = fbm(p * float2(0.6, 1.1) + w3 + warp);
        float dens = f1 * 0.55 + f2 * 0.30 + f3 * 0.55;
        dens = smoothstep(0.30, 0.95, dens);
        float ground = mix(0.45, 1.0, smoothstep(0.0, 1.0, uv.y));      // thicker toward the bottom
        float a = clamp(dens * ground * P.b.y, 0.0, 0.88);
        float3 fogC = mix(float3(0.80, 0.84, 0.90), float3(0.95, 0.96, 0.98), f2);
        float sunGlow = exp(-length(p - sunP) * 2.2) * (1.0 - night);
        fogC = mix(fogC, P.tint.rgb, clamp(sunGlow * 0.9, 0.0, 0.8));
        fogC *= 1.0 - 0.45 * night;
        return float4(fogC * a, a);
    }

    // ───────────── sun
    float2 d = p - sunP;
    float r = length(d);
    float ang = atan2(d.y, d.x);
    float3 warm = P.tint.rgb;
    float3 light = float3(0.0);

    // crepuscular rays: noise over the polar angle, slowly evolving, fading with distance
    // sampled on the unit circle (cos, sin) so the noise is continuous across ±π — no seam to the left of the sun
    float2 dir = float2(cos(ang), sin(ang));
    float rays = vnoise(dir * 3.2 + float2(t * 0.05, 7.0)) * 0.65 + vnoise(dir * 7.5 + float2(-t * 0.09, 19.0)) * 0.35;
    rays = pow(rays, 2.4);
    light += warm * rays * exp(-r * 1.9) * 0.95 * (1.0 - night);

    // bloom, core, anamorphic streak
    light += warm * (exp(-r * 6.0) * 0.85 + exp(-r * 1.8) * 0.22);
    light += mix(warm, float3(1.0), 0.7) * smoothstep(0.045, 0.0, r) * 1.2 * (1.0 - 0.4 * night);
    light += mix(warm, float3(1.0), 0.6) * exp(-abs(d.y) * 110.0) * exp(-abs(d.x) * 7.5) * 0.42 * (1.0 - night);

    // lens-flare ghosts along the sun → centre axis: soft aperture-shaped reflections that wobble,
    // breathe and turn slowly; they never form clean circles.
    float2 centre = float2(0.5 * aspect, 0.5);
    float2 axis = centre - sunP;
    float2 perp = normalize(float2(-axis.y, axis.x) + 1e-5);
    float vis = 1.0 - 0.85 * P.c.y;                                  // a leaf in front of the sun dims everything
    float strength = P.c.x * (1.0 - night) * vis;
    const float ks[5] = {0.55, 0.95, 1.35, 1.85, 2.30};
    const float rad[5] = {0.050, 0.095, 0.032, 0.125, 0.062};
    const float gain[5] = {0.85, 0.65, 1.0, 0.45, 0.70};
    const float3 colA[5] = {float3(0.55, 0.85, 1.0), float3(1.0, 0.70, 0.35), float3(1.0, 0.55, 0.85),
                            float3(0.55, 1.0, 0.75), float3(0.70, 0.78, 1.0)};
    const float3 colB[5] = {float3(1.0, 0.80, 0.55), float3(0.85, 0.45, 0.75), float3(0.60, 0.85, 1.0),
                            float3(1.0, 0.85, 0.50), float3(1.0, 0.60, 0.50)};
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 g = sunP + axis * ks[i] + perp * 0.014 * sin(t * (0.35 + 0.11 * fi) + fi * 1.9);   // wander off the axis
        float breathe = 1.0 + 0.07 * sin(t * (0.5 + 0.13 * fi) + fi * 2.3);
        float flicker = 0.80 + 0.20 * vnoise(float2(t * (0.9 + 0.2 * fi), fi * 11.0));
        float rot = t * 0.04 * (fmod(fi, 2.0) < 0.5 ? 1.0 : -1.0) + fi * 0.7;
        light += ghost(p, g, rad[i] * breathe, sunP - g, rot, fi, colA[i], colB[i]) * gain[i] * flicker * strength * 0.9;
    }
    // diffraction spikes at the core and a faint veiling glare
    float spikes = pow(abs(cos(ang * 3.0 + t * 0.03)), 30.0) * exp(-r * 6.5);
    light += mix(warm, float3(1.0), 0.6) * spikes * 0.35 * (1.0 - night);
    light += warm * exp(-r * 0.9) * 0.05 * (1.0 - night);
    light *= mix(1.0, vis, 0.9);
    // a little flicker of the sun itself (heat shimmer / thin cloud)
    light *= 0.94 + 0.06 * vnoise(float2(t * 2.1, 3.0));

    // night: only a cool soft glow
    light = mix(light, float3(0.62, 0.72, 1.0) * (exp(-r * 7.0) * 0.5 + smoothstep(0.03, 0.0, r) * 0.5), night);
    float a = clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0);
    return float4(min(light, float3(a)), a);
}
"""

private struct SkyParams {
    var a: SIMD4<Float>      // time, mode, aspect, windKmh
    var sun: SIMD4<Float>    // sunU, sunV, altitude°, night 0…1
    var b: SIMD4<Float>      // coverage (clouds), opacity, —, —
    var tint: SIMD4<Float>   // warm light colour
    var c: SIMD4<Float>      // flare strength, —, —, —
}

enum SkyMode: Float { case clouds = 0, fog = 1, sun = 2 }

/// Shared between the sun shader and the falling-leaf layer: where the sun is (view fraction, y down)
/// and how much of it is currently covered by leaves (0…1).
@MainActor
enum SunLightState {
    static var sunUV = SIMD2<Float>(0.82, 0.14)
    static var occlusion: Float = 0
}

struct SkyMetalRepresentable: NSViewRepresentable {
    let mode: SkyMode
    var windKmh: Double = 0
    func makeNSView(context: Context) -> SkyMetalView {
        let v = SkyMetalView(mode: mode)
        v.windKmh = windKmh
        return v
    }
    func updateNSView(_ v: SkyMetalView, context: Context) { v.windKmh = windKmh }
}

final class SkyMetalView: NSView {
    let mode: SkyMode
    var windKmh = 0.0

    private var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pso: MTLRenderPipelineState?
    private var link: CADisplayLink?
    private var startTime = CACurrentMediaTime()
    private var fallback: NSView?
    private var mouseUV = SIMD2<Float>(0.5, 0.5)
    private var sunUV = SIMD2<Float>(0.82, 0.14)
    private var altitude: Float = 45
    private var occ: Float = 0
    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(mode: SkyMode) {
        self.mode = mode
        super.init(frame: .zero)
        wantsLayer = true
        if !setup() { useFallback() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    deinit { link?.invalidate() }

    private func setup() -> Bool {
        guard UserDefaults.standard.string(forKey: "skyEngine") != "ca",
              let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(),
              let layer = metalLayer else { return false }
        do {
            let lib = try dev.makeLibrary(source: skyShaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "skyVS")
            d.fragmentFunction = lib.makeFunction(name: "skyFS")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            pso = try dev.makeRenderPipelineState(descriptor: d)
        } catch {
            Trace.log("sky metal: shader failed — \(error)")
            return false
        }
        device = dev; queue = q
        layer.device = dev
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.maximumDrawableCount = 2
        layer.contentsGravity = .resize
        return true
    }

    /// Old Core Animation versions, used when Metal is unavailable.
    private func useFallback() {
        Trace.log("sky metal: unavailable — Core Animation fallback (\(mode))")
        let v: NSView
        switch mode {
        case .clouds: let c = CloudsNSView(); c.windKmh = windKmh; v = c
        case .fog: v = FogNSView()
        case .sun: v = SunSkyNSView()
        }
        v.frame = bounds
        v.autoresizingMask = [.width, .height]
        addSubview(v)
        fallback = v
    }

    // MARK: Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil, fallback == nil else { return }
        updateSun()
        startTime = CACurrentMediaTime()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 40, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func layout() {
        super.layout()
        guard fallback == nil, bounds.width > 100, let layer = metalLayer else { return }
        let s: CGFloat = mode == .sun ? 0.75 : 0.5                     // soft content → half-res is plenty
        let size = CGSize(width: bounds.width * s, height: bounds.height * s)
        if layer.drawableSize != size { layer.drawableSize = size }
    }

    /// Real sun position for the saved location (same mapping as the previous CA sun).
    private func updateSun() {
        let d = UserDefaults.standard
        var alt = 45.0
        var uv = SIMD2<Float>(0.82, 0.14)
        if let lat = d.object(forKey: GlassKeys.lat) as? Double,
           let lon = d.object(forKey: GlassKeys.lon) as? Double {
            let p = Sun.position(date: Date(), latitude: lat, longitude: lon)
            alt = p.altitudeDegrees
            let fx = 0.08 + (min(270, max(90, p.azimuthDegrees)) - 90) / 180 * 0.84
            let fy = max(0.07, 0.80 - max(0, min(60, alt)) / 60 * 0.73)
            uv = SIMD2(Float(fx), Float(fy))
        }
        sunUV = uv
        altitude = Float(alt)
        if mode == .sun { SunLightState.sunUV = uv }
    }

    // MARK: Frame

    @objc private func tick(_ link: CADisplayLink) {
        guard window?.isVisible == true, let layer = metalLayer, let drawable = layer.nextDrawable() else { return }
        trackMouse()
        if let cmd = render(now: CACurrentMediaTime() - startTime, target: drawable.texture) {
            cmd.present(drawable)
            cmd.commit()
        }
    }

    /// Smoothed cursor position inside the window (0…1) — drives the flare parallax.
    private func trackMouse() {
        guard let w = window else { return }
        let m = NSEvent.mouseLocation
        let f = w.frame
        let target = SIMD2<Float>(Float((m.x - f.minX) / max(f.width, 1)), Float(1 - (m.y - f.minY) / max(f.height, 1)))
        mouseUV += (target - mouseUV) * 0.08
    }

    fileprivate func render(now: Double, target: MTLTexture, mouse: SIMD2<Float>? = nil) -> MTLCommandBuffer? {
        guard let queue, let pso, let cmd = queue.makeCommandBuffer() else { return nil }
        let m = mouse ?? mouseUV
        let altN = max(0, min(1, altitude / 60))
        let night: Float = altitude < -2 ? 1 : 0
        // The sun drifts a little and shifts with the pointer: the flare axis moves with it.
        let drift = SIMD2<Float>(Float(sin(now * 0.21)) * 0.006 + (m.x - 0.5) * 0.045,
                                 Float(cos(now * 0.17)) * 0.005 + (m.y - 0.5) * 0.030)
        let warm: SIMD4<Float> = altitude < 8 ? [1.0, 0.45, 0.18, 0]
            : altitude < 22 ? [1.0, 0.68, 0.30, 0]
            : altitude < 40 ? [1.0, 0.84, 0.52, 0] : [1.0, 0.93, 0.74, 0]
        occ += (SunLightState.occlusion - occ) * 0.22            // eased: leaves cross the sun smoothly
        let aspect = Float(bounds.width / max(bounds.height, 1))
        let opacity: Float = mode == .clouds ? 1.0 : mode == .fog ? 0.78 : 1
        var params = SkyParams(
            a: [Float(now), mode.rawValue, aspect, Float(windKmh)],
            sun: [sunUV.x + drift.x, sunUV.y + drift.y, altitude, night],
            b: [0.34 + 0.08 * altN, opacity, 0, 0],      // coverage: higher sun → slightly fewer clouds
            tint: warm,
            c: [mode == .sun ? 1 : 0, occ, 0, 0])
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let e = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        e.setRenderPipelineState(pso)
        e.setFragmentBytes(&params, length: MemoryLayout<SkyParams>.stride, index: 0)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
        return cmd
    }

    // MARK: Offline snapshot (no window, no screen)

    @MainActor
    static func snapshot(mode: SkyMode, size: CGSize, time: Double, wind: Double, mouse: SIMD2<Float>) -> CGImage? {
        let v = SkyMetalView(mode: mode)
        guard v.fallback == nil, let dev = v.device else { return nil }
        v.windKmh = wind
        v.frame = NSRect(origin: .zero, size: size)
        v.updateSun()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width),
                                                         height: Int(size.height), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let target = dev.makeTexture(descriptor: d),
              let cmd = v.render(now: time, target: target, mouse: mouse) else { return nil }
        cmd.commit()
        cmd.waitUntilCompleted()
        let w = Int(size.width), h = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let src = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let layerImage = src.makeImage(),
              let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // stand-in for the live blurred desktop: dusky blue gradient
        if let g = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.20, green: 0.26, blue: 0.36, alpha: 1),
                                                         CGColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1)] as CFArray,
                              locations: [0, 1]) {
            out.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
        }
        out.draw(layerImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out.makeImage()
    }
}
