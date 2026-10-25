import AppKit
import Metal
import MetalKit
import QuartzCore
import SwiftUI
import IntermezzoKit

// Photoreal rain on glass — a Metal port of the raindrop-fx technique.
//
//  pass 1  mist map   : 1 = steamy, drops wipe it to 0 along their path (slowly re-fogs)
//  pass 2  drop map   : every drop / droplet is a sphere-cap sprite; rg = surface normal,
//                       b = size, a = coverage
//  pass 3  compose    : steamy pane = blurred scene; inside a drop the scene is REFRACTED
//                       (sampled at an offset along the normal, inverted & magnified),
//                       Lambert + Blinn-Phong lit, rim-darkened
//
// Everything is GPU work at ≈30 fps; the CPU only steps a few dozen drops.

private let rainShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Inst { float2 pos; float radius; float stretch; float size; float p0; float p1; float p2; };
struct Params { float4 a; float4 b; float4 lightDir; float4 diffuse; float4 specular; float4 mistTint; float4 mistAdd; };
struct VOut { float4 position [[position]]; float2 uv; float size; };

vertex VOut dropVS(uint vid [[vertex_id]], uint iid [[instance_id]],
                   constant Inst* inst [[buffer(0)]], constant float2& viewSize [[buffer(1)]]) {
    float2 q = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    Inst I = inst[iid];
    float2 p = I.pos + q * float2(I.radius, I.radius * I.stretch);
    VOut o;
    o.position = float4(p.x / viewSize.x * 2.0 - 1.0, 1.0 - p.y / viewSize.y * 2.0, 0.0, 1.0);
    o.uv = q;
    o.size = I.size;
    return o;
}

// Drop sprite, profile measured from the reference drop texture (the quad is ~5x the visible drop):
//  alpha  = exp(-(d/0.57)^3.3)  — wide soft halo, plateau ≈ 1 in the middle (halos of neighbours add up → merging)
//  R      = linear ramp across x (a pure lens: inverted, evenly magnified view)
//  G      = linear ramp down the lower half, shallow hump above (teardrop-ish)
fragment float4 dropFS(VOut in [[stage_in]]) {
    float2 u = in.uv;
    float sy = u.y < 0.0 ? 0.58 : 0.70;
    float d = length(float2(u.x / 0.57, (u.y - 0.03) / sy));
    float a = exp(-pow(d, 3.3));
    if (a < 0.003) discard_fragment();
    float R = 0.5 + 0.435 * u.x;
    float G = u.y > 0.0 ? 0.494 - 0.47 * u.y
                        : 0.494 + 0.06 * sin(3.14159 * clamp(-u.y / 0.5, 0.0, 1.0));
    return float4(float2(R, G) * a, in.size * a, a);
}

fragment float4 eraseFS(VOut in [[stage_in]]) {
    float r = length(in.uv);
    if (r >= 1.0) discard_fragment();
    return float4(0.0, 0.0, 0.0, smoothstep(1.0, 0.45, r));
}

vertex VOut fullVS(uint vid [[vertex_id]]) {
    float2 p = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);
    VOut o;
    o.position = float4(p, 0.0, 1.0);
    o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
    o.size = 0.0;
    return o;
}

fragment float4 refogFS(VOut in [[stage_in]], constant float& amount [[buffer(0)]]) {
    return float4(amount, amount, amount, amount);
}

fragment float4 composeFS(VOut in [[stage_in]],
                          texture2d<float> dropTex [[texture(0)]],
                          texture2d<float> sceneTex [[texture(1)]],
                          texture2d<float> blurTex [[texture(2)]],
                          texture2d<float> mistTex [[texture(3)]],
                          constant Params& P [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::mirrored_repeat);
    float2 uv = in.uv;
    float4 d = dropTex.sample(s, uv);
    float fog = mistTex.sample(s, uv).r;

    // pane: fogged = blurred, milky scene; wiped = CLEAR glass showing the sharper scene
    float3 fogCol = blurTex.sample(s, uv).rgb * P.mistTint.rgb + P.mistAdd.rgb;   // fog = blurrier copy of the scene
    float3 clearCol = sceneTex.sample(s, uv).rgb;
    float3 paneCol = mix(clearCol, fogCol, fog);
    float paneA = clamp(mix(P.mistTint.w, 1.0, fog) * P.b.x, 0.0, 1.0);
    float4 outc = float4(paneCol * paneA, paneA);

    if (d.a > 0.002) {
        float a = d.a;
        float2 g = d.rg / a - 0.5;                               // lens ramp, 0 at the centre
        float size = d.b / a;
        float2 off = -g * (P.a.x + P.a.y * size);               // inverted, evenly magnified view of the scene
        float3 refr = sceneTex.sample(s, uv + off).rgb;
        float3 N = normalize(float3(g * 2.0, 1.0));
        float3 L = normalize(P.lightDir.xyz);
        float lam = saturate(dot(N, L));
        float spec = pow(saturate(dot(N, normalize(L + float3(0.0, 0.0, 1.0)))), P.a.w);
        float3 col = refr + (lam - P.a.z) * P.diffuse.rgb + spec * P.specular.rgb;
        float ring = smoothstep(0.90, 0.965, a) * (1.0 - smoothstep(0.965, 0.995, a));
        col *= 1.0 - 0.30 * ring;                               // thin dark meniscus at the edge
        float mask = smoothstep(P.b.z, P.b.w, a);
        outc = float4(col * mask, mask) + outc * (1.0 - mask);
    }

    float fa = clamp(P.b.y, 0.0, 1.0) * 0.38;              // lightning
    outc = float4(outc.rgb * (1.0 - fa) + fa, outc.a * (1.0 - fa) + fa);
    return outc;
}
"""

private struct Inst {
    var pos: SIMD2<Float>
    var radius: Float
    var stretch: Float
    var size: Float
    var p0: Float = 0, p1: Float = 0, p2: Float = 0
}

private struct Params {
    var a: SIMD4<Float>          // refractBase, refractScale, shadowOffset, shininess
    var b: SIMD4<Float>          // mistAlpha, flash, smoothLo, smoothHi
    var lightDir: SIMD4<Float>
    var diffuse: SIMD4<Float>
    var specular: SIMD4<Float>
    var mistTint: SIMD4<Float>
    var mistAdd: SIMD4<Float>
}

struct RainMetalRepresentable: NSViewRepresentable {
    let intensity: Double
    let storm: Bool
    var windKmh: Double

    func makeNSView(context: Context) -> RainMetalView {
        let v = RainMetalView()
        v.intensity = intensity
        v.storm = storm
        v.windKmh = windKmh
        return v
    }

    func updateNSView(_ v: RainMetalView, context: Context) { v.windKmh = windKmh }
}

final class RainMetalView: NSView {
    var intensity = 1.0
    var storm = false
    var windKmh = 0.0

    /// Drawable pixels per point: the screen's own scale, capped (a Retina-sized
    /// drawable costs ~200 MB of GPU memory and the effect is soft anyway).
    private var renderScale: CGFloat { min(window?.backingScaleFactor ?? 1, 1.25) }
    private static let mapScale: Float = 0.75              // drop/mist map px per point
    private static let quadScale: Float = 5                // sprite quad = 5x the visible drop (soft halo around the plateau)

    fileprivate var device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var dropPSO: MTLRenderPipelineState?
    private var erasePSO: MTLRenderPipelineState?
    private var refogPSO: MTLRenderPipelineState?
    private var composePSO: MTLRenderPipelineState?
    private var sceneTex: MTLTexture?
    private var blurTex: MTLTexture?
    private var dropTex: MTLTexture?
    private var mistTex: MTLTexture?
    private var mistNeedsReset = true
    private var backdropIsReal = false

    private var sim: RainSimulator?
    private var link: CADisplayLink?
    private var lastTime = CACurrentMediaTime()
    fileprivate var startTime = CACurrentMediaTime()
    private var nextFlash = CACurrentMediaTime() + 8
    private var flashStart = -10.0
    fileprivate var fallback: RainGlassCAView?
    private var framesLogged = 0

    private var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override var wantsUpdateLayer: Bool { true }
    /// Decoration only — never take clicks from the break controls.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        if !setupMetal() { useFallback() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit { link?.invalidate() }

    // MARK: Setup

    private func setupMetal() -> Bool {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(),
              let layer = metalLayer else { return false }
        do {
            let lib = try dev.makeLibrary(source: rainShaderSource, options: nil)
            func pso(_ vs: String, _ fs: String, _ format: MTLPixelFormat,
                     blend: ((MTLRenderPipelineColorAttachmentDescriptor) -> Void)? = nil) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: vs)
                d.fragmentFunction = lib.makeFunction(name: fs)
                d.colorAttachments[0].pixelFormat = format
                if let blend {
                    d.colorAttachments[0].isBlendingEnabled = true
                    blend(d.colorAttachments[0])
                }
                return try dev.makeRenderPipelineState(descriptor: d)
            }
            dropPSO = try pso("dropVS", "dropFS", .rgba8Unorm) {
                $0.sourceRGBBlendFactor = .oneMinusDestinationColor; $0.destinationRGBBlendFactor = .oneMinusSourceColor
                $0.sourceAlphaBlendFactor = .one; $0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            erasePSO = try pso("dropVS", "eraseFS", .r8Unorm) {
                $0.sourceRGBBlendFactor = .zero; $0.destinationRGBBlendFactor = .oneMinusSourceAlpha
                $0.sourceAlphaBlendFactor = .zero; $0.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            refogPSO = try pso("fullVS", "refogFS", .r8Unorm) {
                $0.sourceRGBBlendFactor = .one; $0.destinationRGBBlendFactor = .one
                $0.sourceAlphaBlendFactor = .one; $0.destinationAlphaBlendFactor = .one
            }
            composePSO = try pso("fullVS", "composeFS", .bgra8Unorm)
        } catch {
            Trace.log("rain metal: shader/pipeline failed — \(error)")
            return false
        }
        device = dev
        queue = q
        layer.device = dev
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.maximumDrawableCount = 2
        layer.contentsGravity = .resize
        return true
    }

    private func useFallback() {
        Trace.log("rain metal: unavailable — Core Animation rain")
        let f = RainGlassCAView()
        f.intensity = intensity; f.storm = storm; f.windKmh = windKmh
        f.frame = bounds
        f.autoresizingMask = [.width, .height]
        addSubview(f)
        fallback = f
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate(); link = nil
        guard window != nil, fallback == nil else { return }
        loadBackdrop()
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 40, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        lastTime = CACurrentMediaTime()
        startTime = lastTime
    }

    fileprivate func loadBackdrop() {
        guard let dev = device else { return }
        let backdrop = MainActor.assumeIsolated { RainBackdropStore.shared.backdrop(for: window?.screen) }
        let loader = MTKTextureLoader(device: dev)
        let opts: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
        sceneTex = try? loader.newTexture(cgImage: backdrop.scene, options: opts)
        blurTex = try? loader.newTexture(cgImage: backdrop.blur, options: opts)
        backdropIsReal = backdrop.isReal
        Trace.log("rain metal: backdrop \(backdrop.isReal ? "captured desktop" : "procedural")")
    }

    override func layout() {
        super.layout()
        guard fallback == nil, bounds.width > 200, bounds.height > 200,
              let layer = metalLayer, let dev = device else { return }
        let drawable = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        if layer.drawableSize != drawable { layer.drawableSize = drawable }

        let mw = Int(bounds.width * CGFloat(Self.mapScale)), mh = Int(bounds.height * CGFloat(Self.mapScale))
        if dropTex?.width != mw || dropTex?.height != mh {
            func target(_ f: MTLPixelFormat) -> MTLTexture? {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: mw, height: mh, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]
                d.storageMode = .private
                return dev.makeTexture(descriptor: d)
            }
            dropTex = target(.rgba8Unorm)
            mistTex = target(.r8Unorm)
            mistNeedsReset = true
            sim = RainSimulator(width: Float(bounds.width), height: Float(bounds.height),
                                intensity: Float(intensity), storm: storm,
                                seed: UInt64(Date().timeIntervalSince1970))
        }
    }

    // MARK: Frame

    @objc private func tick(_ link: CADisplayLink) {
        guard window?.isVisible == true, let layer = metalLayer, let drawable = layer.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - lastTime))
        lastTime = now
        if let cmd = render(dt: dt, now: now, target: drawable.texture) {
            cmd.present(drawable)
            cmd.commit()
        }
    }

    /// One frame: step the simulation and encode the three passes into `target`.
    /// Shared by the live display link and the offline snapshot renderer.
    private func render(dt: Float, now: Double, target: MTLTexture) -> MTLCommandBuffer? {
        guard var simulator = sim, let queue,
              let dropPSO, let erasePSO, let refogPSO, let composePSO,
              let dropTex, let mistTex, let sceneTex, let blurTex,
              let cmd = queue.makeCommandBuffer() else { return nil }
        simulator.windKmh = Float(windKmh)
        simulator.step(dt: dt)
        sim = simulator

        let s = Self.mapScale
        var insts: [Inst] = []
        insts.reserveCapacity(simulator.drops.count + simulator.trail.count + simulator.micro.count)
        for m in simulator.micro where m.radius > 0.15 {
            insts.append(Inst(pos: [m.x * s, m.y * s], radius: m.radius * s * 1.4 * Self.quadScale, stretch: 1, size: 0.05))
        }
        for t in simulator.trail {
            insts.append(Inst(pos: [t.x * s, t.y * s], radius: t.r * s * Self.quadScale, stretch: 1, size: min(1, t.r / 18)))
        }
        for d in simulator.drops {
            let stretch: Float = d.sliding ? 1.0 + min(0.7, d.vy / 520) : 1.14
            insts.append(Inst(pos: [d.x * s, d.y * s], radius: d.r * s * Self.quadScale, stretch: stretch, size: min(1, d.r / 18)))
        }
        let erasers = simulator.erasers.map {
            Inst(pos: [$0.x * s, $0.y * s], radius: $0.r * s * 0.66, stretch: 1.12, size: 0)
        }
        var viewSize = SIMD2<Float>(Float(dropTex.width), Float(dropTex.height))
        if framesLogged < 3 || framesLogged == 90 {
            Trace.log("rain metal frame \(framesLogged): drops=\(simulator.drops.count) trail=\(simulator.trail.count) micro=\(simulator.micro.count) insts=\(insts.count) erasers=\(erasers.count) target=\(target.width)x\(target.height) map=\(dropTex.width)x\(dropTex.height) backdropReal=\(backdropIsReal)")
        }
        framesLogged += 1

        // pass 1: mist (re-fog slowly, then wipe where drops slid)
        let p1 = MTLRenderPassDescriptor()
        p1.colorAttachments[0].texture = mistTex
        p1.colorAttachments[0].storeAction = .store
        if mistNeedsReset {
            p1.colorAttachments[0].loadAction = .clear
            p1.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
            mistNeedsReset = false
        } else {
            p1.colorAttachments[0].loadAction = .load
        }
        if let e = cmd.makeRenderCommandEncoder(descriptor: p1) {
            var amount = 0.0030 * (dt * 30)
            e.setRenderPipelineState(refogPSO)
            e.setFragmentBytes(&amount, length: 4, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if !erasers.isEmpty {
                e.setRenderPipelineState(erasePSO)
                // setVertexBytes is capped at 4 KB — instance data goes through real buffers.
                e.setVertexBuffer(makeBuffer(erasers), offset: 0, index: 0)
                e.setVertexBytes(&viewSize, length: 8, index: 1)
                e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: erasers.count)
            }
            e.endEncoding()
        }

        // pass 2: drop map
        let p2 = MTLRenderPassDescriptor()
        p2.colorAttachments[0].texture = dropTex
        p2.colorAttachments[0].loadAction = .clear
        p2.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        p2.colorAttachments[0].storeAction = .store
        if let e = cmd.makeRenderCommandEncoder(descriptor: p2), !insts.isEmpty {
            e.setRenderPipelineState(dropPSO)
            e.setVertexBuffer(makeBuffer(insts), offset: 0, index: 0)
            e.setVertexBytes(&viewSize, length: 8, index: 1)
            e.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: insts.count)
            e.endEncoding()
        } else {
            cmd.makeRenderCommandEncoder(descriptor: p2)?.endEncoding()
        }

        // pass 3: compose to the (transparent) drawable
        let p3 = MTLRenderPassDescriptor()
        p3.colorAttachments[0].texture = target
        p3.colorAttachments[0].loadAction = .dontCare
        p3.colorAttachments[0].storeAction = .store
        if let e = cmd.makeRenderCommandEncoder(descriptor: p3) {
            var params = makeParams(now: now)
            e.setRenderPipelineState(composePSO)
            e.setFragmentTexture(dropTex, index: 0)
            e.setFragmentTexture(sceneTex, index: 1)
            e.setFragmentTexture(blurTex, index: 2)
            e.setFragmentTexture(mistTex, index: 3)
            e.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        return cmd
    }

    // MARK: Offline snapshot (debug / tuning — creates no window, touches no screen)

    /// Renders `seconds` of rain at `size` points into a PNG-ready image, composited
    /// over a neutral blue-grey stand-in for the live desktop blur.
    @MainActor
    static func snapshot(size: CGSize, seconds: Double, storm: Bool, windKmh: Double) -> CGImage? {
        let v = RainMetalView()
        guard v.fallback == nil, let dev = v.device else { return nil }
        v.storm = storm
        v.windKmh = windKmh
        v.frame = NSRect(origin: .zero, size: size)
        v.layout()                                    // builds the maps + simulator at this size
        v.loadBackdrop()
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                         width: Int(size.width), height: Int(size.height),
                                                         mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let target = dev.makeTexture(descriptor: d) else { return nil }
        let dt: Float = 1.0 / 30.0
        let frames = max(1, Int(seconds * 30))
        v.startTime = 0
        var last: MTLCommandBuffer?
        for i in 0..<frames {
            last = v.render(dt: dt, now: Double(i) * Double(dt) + 6, target: target)   // +6 s: pane fully steamed
            last?.commit()
        }
        last?.waitUntilCompleted()
        let w = Int(size.width), h = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                                      | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let rain = ctx.makeImage(),
              let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        out.setFillColor(CGColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1))   // stand-in for the live blur
        out.fill(CGRect(x: 0, y: 0, width: w, height: h))
        out.draw(rain, in: CGRect(x: 0, y: 0, width: w, height: h))
        return out.makeImage()
    }

    private func makeBuffer(_ items: [Inst]) -> MTLBuffer? {
        items.withUnsafeBytes {
            device?.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
        }
    }

    private func makeParams(now: Double) -> Params {
        let fade = Float(min(1, max(0, (now - startTime) / 5)))          // pane steams up over 5 s
        // real captured desktop → our own pane replaces the live blur; otherwise a light haze over it
        let mist: Float = (backdropIsReal ? 0.92 : 0.62) * fade
        if storm, now >= nextFlash {
            flashStart = now
            nextFlash = now + Double.random(in: 7...15)
        }
        let flashAge = Float(now - flashStart)
        let flash: Float = storm && flashAge < 0.7
            ? max(0, (flashAge < 0.08 ? flashAge / 0.08 : 1 - (flashAge - 0.08) / 0.62))
              * (0.55 + 0.45 * abs(sin(flashAge * 38)))
            : 0
        return Params(
            a: [0.40, 0.60, 0.80, 256],                  // refractBase, refractScale, shadowOffset, shininess
            b: [mist, flash, 0.955, 0.985],              // smooth edge of a drop (alpha threshold)
            lightDir: [-1.0, -1.0, 2.0, 0],
            diffuse: [0.20, 0.20, 0.22, 0],
            specular: [0.10, 0.11, 0.13, 0],
            mistTint: [1.0, 1.0, 1.0, 0.92],             // w = pane opacity where the glass was wiped
            mistAdd: [0.010, 0.012, 0.016, 0])
    }
}
