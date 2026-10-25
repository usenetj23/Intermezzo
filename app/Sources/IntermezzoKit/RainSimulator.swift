import Foundation

/// Small deterministic RNG so the simulation is testable.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
}

public struct RainDrop: Equatable {
    public var id: Int
    public var x: Float
    public var y: Float
    public var r: Float
    public var vy: Float = 0
    public var sliding = false
    var vx: Float = 0
    var timer: Float = 0
    var travelled: Float = 0

    public init(id: Int, x: Float, y: Float, r: Float) {
        self.id = id; self.x = x; self.y = y; self.r = r
        self.timer = 1
    }
}

public struct TrailDroplet: Equatable {
    public var x: Float, y: Float, r: Float
    var shrink: Float
}

public struct MicroDroplet: Equatable {
    public var x: Float, y: Float
    public var target: Float
    public var radius: Float
}

/// Rain-on-glass simulation in view points (y grows downward), modelled on
/// raindrop-fx: drops rest, creep and slide in stop-and-go jerks, shrink as
/// they run, leave small droplets behind and wipe the mist along the path.
public struct RainSimulator {
    public let width: Float
    public let height: Float
    public var intensity: Float
    public var storm: Bool
    /// Horizontal wind (km/h) — a small sideways drift of sliding drops.
    public var windKmh: Float = 0

    public private(set) var drops: [RainDrop] = []
    public private(set) var trail: [TrailDroplet] = []
    public private(set) var micro: [MicroDroplet] = []
    /// Wipes made during the last `step` (x, y, radius) — consumed by the renderer.
    public private(set) var erasers: [(x: Float, y: Float, r: Float)] = []

    private var rng: SplitMix64
    private var nextID = 1
    private var spawnClock: Float = 0

    public var dropLimit: Int { Int(80 * max(0.2, intensity) * (storm ? 1.4 : 1)) }

    public init(width: Float, height: Float, intensity: Float, storm: Bool, seed: UInt64 = 1) {
        self.width = width; self.height = height
        self.intensity = intensity; self.storm = storm
        self.rng = SplitMix64(seed: seed)
        let count = min(1800, Int(width * height / 1100))
        micro.reserveCapacity(count)
        for _ in 0..<count {
            micro.append(MicroDroplet(x: rng.range(0, width), y: rng.range(0, height),
                                      target: 0.8 + 2.2 * pow(rng.unit(), 2.2),
                                      radius: 0.8 + 2.2 * pow(rng.unit(), 2.2)))
        }
    }

    public mutating func inject(_ drop: RainDrop) { drops.append(drop) }

    public mutating func step(dt rawDt: Float) {
        let dt = min(max(rawDt, 0), 0.1)             // never integrate a huge step in one go
        erasers.removeAll(keepingCapacity: true)
        spawn(dt)
        stepDrops(dt)
        mergeOverlappingDrops()
        stepTrail(dt)
        stepMicro(dt)
    }

    private mutating func spawn(_ dt: Float) {
        guard intensity > 0 else { return }
        spawnClock += dt * (storm ? 6.0 : 3.4) * intensity
        while spawnClock >= 1 {
            spawnClock -= 1
            guard drops.count < dropLimit else { continue }
            let r = 3.5 + 14 * pow(rng.unit(), 1.6)
            var d = RainDrop(id: nextID, x: rng.range(0, width), y: rng.range(-4, height * 0.9), r: r)
            d.timer = rng.range(0.4, 3.0)
            nextID += 1
            drops.append(d)
        }
    }

    private mutating func stepDrops(_ dt: Float) {
        let gravity: Float = storm ? 2200 : 1500
        var alive: [RainDrop] = []
        alive.reserveCapacity(drops.count)
        for var d in drops {
            d.timer -= dt
            if d.sliding {
                d.vy = min(d.vy + gravity * dt, 120 + d.r * 22)
                let dy = d.vy * dt
                let startY = d.y
                d.y += dy
                // Lazy meander: a damped random sideways velocity plus the wind.
                d.vx = (d.vx + rng.range(-90, 90) * dt) * (1 - min(1, 2.2 * dt))
                d.x += (d.vx + windKmh * 0.9) * dt
                d.travelled += dy
                // Mass (≈ area) is lost while running — the drop shrinks and finally vanishes,
                // which is what keeps every streak short and finite.
                let massLoss = (24 + 0.38 * d.r * d.r) * (storm ? 1.25 : 1) * dt
                d.r = (max(0, d.r * d.r - massLoss)).squareRoot()
                // Wipe the whole segment travelled this step, not just its end point:
                // a fast drop would otherwise leave a line of separate beads.
                let spacing = max(1.5, d.r * 0.4)
                let stamps = min(48, max(1, Int((dy / spacing).rounded(.up))))
                for k in 1...stamps {
                    let f = Float(k) / Float(stamps)
                    erasers.append((d.x, startY + dy * f, d.r * 0.95))
                }
                if d.travelled > max(14, d.r * 3.2) {
                    d.travelled = 0
                    trail.append(TrailDroplet(x: d.x + rng.range(-1, 1), y: d.y - d.r,
                                              r: d.r * rng.range(0.28, 0.5),
                                              shrink: rng.range(0.10, 0.22)))
                }
                if d.timer <= 0 {                                         // stop for a moment
                    d.sliding = false; d.vy = 0
                    d.timer = rng.range(0.35, 2.4)
                }
            } else if d.timer <= 0 {
                let slip: Float = d.r >= 10 ? (storm ? 0.9 : 0.7) : d.r >= 6.5 ? (storm ? 0.35 : 0.18) : 0.02
                if rng.unit() < slip {
                    d.sliding = true; d.vy = 40
                    d.timer = rng.range(0.15, 0.7)
                } else {
                    d.timer = rng.range(0.5, 2.5)
                }
            }
            if d.y < height + d.r + 4, d.r > 2.4, d.x > -20, d.x < width + 20, d.y.isFinite {
                alive.append(d)
            }
        }
        drops = alive
    }

    /// Drops that touch merge: the heavier one absorbs the lighter, momentum is conserved.
    private mutating func mergeOverlappingDrops() {
        guard drops.count > 1 else { return }
        var i = 0
        while i < drops.count {
            var j = i + 1
            while j < drops.count {
                let dx = drops[i].x - drops[j].x, dy = drops[i].y - drops[j].y
                let reach = (drops[i].r + drops[j].r) * 0.7
                if dx * dx + dy * dy < reach * reach {
                    let mi = drops[i].r * drops[i].r, mj = drops[j].r * drops[j].r
                    let m = mi + mj
                    var merged = drops[mi >= mj ? i : j]
                    merged.x = (drops[i].x * mi + drops[j].x * mj) / m
                    merged.y = (drops[i].y * mi + drops[j].y * mj) / m
                    merged.vy = (drops[i].vy * mi + drops[j].vy * mj) / m
                    merged.vx = (drops[i].vx * mi + drops[j].vx * mj) / m
                    merged.r = m.squareRoot()
                    merged.sliding = drops[i].sliding || drops[j].sliding
                    if merged.sliding, merged.timer < 0.2 { merged.timer = 0.3 }
                    drops[i] = merged
                    drops.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
    }

    private mutating func stepTrail(_ dt: Float) {
        trail = trail.compactMap { var t = $0; t.r -= t.shrink * dt * 4; return t.r > 0.6 ? t : nil }
    }

    private mutating func stepMicro(_ dt: Float) {
        // grow toward the target; a few droplets per second are born anew elsewhere
        for i in micro.indices { micro[i].radius = min(micro[i].target, micro[i].radius + dt * 1.2) }
        // A sliding drop collects the condensation on its path.
        for e in erasers {
            let reach = e.r * 1.05
            for i in micro.indices where micro[i].radius > 0 {
                let dx = micro[i].x - e.x, dy = micro[i].y - e.y
                if dx * dx + dy * dy < reach * reach { micro[i].radius = 0; micro[i].target = 0 }
            }
        }
        let refresh = Int(40 * dt) + (rng.unit() < 40 * dt - Float(Int(40 * dt)) ? 1 : 0)
        guard !micro.isEmpty else { return }
        for _ in 0..<refresh {
            let i = Int(rng.next() % UInt64(micro.count))
            micro[i] = MicroDroplet(x: rng.range(0, width), y: rng.range(0, height),
                                    target: 0.8 + 2.2 * pow(rng.unit(), 2.2), radius: 0)
        }
    }
}
