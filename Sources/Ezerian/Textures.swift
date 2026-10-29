import Foundation
import simd

/// Surface materials of the terrain, walls and roofs. Each has a 256x256 texture
/// (several frames when it moves) addressed by two bytes, so it wraps for free.
enum Mat: UInt8, CaseIterable {
    case void
    case grass, forestFloor, scrub, hillGrass, dirt, sand, swamp, field
    case water, deepWater, foam
    case cobble, woodFloor, flagstone, brickFloor, carpetBlue, carpetRed, carpetBorder, marble, deck
    case rockTop, rockFace, caveFloor, caveTop, caveFace
    case stoneFace, stoneCap, brickFace, timberFace, logFace, woodCap
    case shingle, slate, thatch, tile, eave
    case door, window, stainedGlass
    case bank, sandBank, rail

    var frames: Int {
        switch self {
        case .water, .deepWater, .foam: return 8
        default: return 1
        }
    }

    /// Overlays (doors, windows) are pictures on a wall face; where they are clear
    /// the wall shows through.
    var isOverlay: Bool { self == .door || self == .window || self == .stainedGlass }
}

/// Every material's texture in one contiguous block: texel (u, v) of slot s lives at
/// s << 16 | v << 8 | u.
final class TextureBank {
    static let shared = TextureBank()

    let data: UnsafeMutablePointer<UInt32>
    private(set) var firstSlot = [Int](repeating: 0, count: 256)
    let slotCount: Int

    private init() {
        var slots = 0
        for m in Mat.allCases {
            firstSlot[Int(m.rawValue)] = slots
            slots += m.frames
        }
        slotCount = slots
        data = .allocate(capacity: slots << 16)
        data.initialize(repeating: 0, count: slots << 16)
        let jobs = Mat.allCases
        let base = data
        let first = firstSlot
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            let m = jobs[i]
            var rng = SplitMix64(seed: 0xE2E7_1A9 &+ UInt64(m.rawValue) &* 7919)
            let frames = Painter.paint(m, &rng)
            for (f, canvas) in frames.enumerated() {
                let px = canvas.pixels()
                let dst = base + ((first[Int(m.rawValue)] + f) << 16)
                px.withUnsafeBufferPointer { src in dst.update(from: src.baseAddress!, count: 65536) }
            }
        }
    }

    @inline(__always)
    func slot(_ m: Mat, frame: Int = 0) -> Int { firstSlot[Int(m.rawValue)] + frame % m.frames }

    @inline(__always)
    func texel(_ m: Mat, _ u: Int, _ v: Int, frame: Int = 0) -> UInt32 {
        data[(slot(m, frame: frame) << 16) | ((v & 255) << 8) | (u & 255)]
    }
}

/// A square, wrapping painting surface.
struct Canvas {
    let n: Int
    var c: [Col]
    var a: [Float]

    init(_ n: Int = 256, _ fill: Col, alpha: Float = 1) {
        self.n = n
        c = Array(repeating: fill, count: n * n)
        a = Array(repeating: alpha, count: n * n)
    }

    @inline(__always) func idx(_ x: Int, _ y: Int) -> Int { (y & (n - 1)) * n + (x & (n - 1)) }

    subscript(x: Int, y: Int) -> Col {
        get { c[idx(x, y)] }
        set { c[idx(x, y)] = newValue; a[idx(x, y)] = 1 }
    }

    mutating func blend(_ x: Int, _ y: Int, _ col: Col, _ t: Float) {
        let i = idx(x, y)
        c[i] = mix(c[i], col, t)
    }

    mutating func mul(_ x: Int, _ y: Int, _ f: Float) { c[idx(x, y)] *= f }

    /// Sets an opaque pixel only inside the 0..<w, 0..<h picture area (for overlays).
    mutating func put(_ x: Int, _ y: Int, _ col: Col) {
        guard x >= 0, y >= 0, x < n, y < n else { return }
        c[y * n + x] = col
        a[y * n + x] = 1
    }

    func pixels() -> [UInt32] {
        (0..<(n * n)).map { pack(c[$0], alpha: a[$0] > 0.5 ? 255 : 0) }
    }
}

extension SplitMix64 {
    mutating func float() -> Float { Float(double()) }
    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * float() }
}

/// Wrapping fractal noise over a 256x256 texture, normalised to 0...1.
func fbmField(_ rng: inout SplitMix64, _ cells: [Int], _ weights: [Float], size: Int = 256) -> [Float] {
    var out = [Float](repeating: 0, count: size * size)
    for (k, cell) in cells.enumerated() {
        let pn = PeriodicNoise(size: size, cells: cell, rng: &rng)
        let w = weights[k]
        for y in 0..<size {
            for x in 0..<size { out[y * size + x] += w * Float(pn.value(x, y)) }
        }
    }
    var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
    for v in out { lo = min(lo, v); hi = max(hi, v) }
    let span = max(0.0001, hi - lo)
    return out.map { ($0 - lo) / span }
}

/// Wrapping Voronoi cells: distance to the nearest and second-nearest seed, and
/// the nearest seed's index and position.
struct Voronoi {
    let n: Int
    var f1: [Float], f2: [Float], id: [Int32]
    var seeds: [SIMD2<Float>]

    init(_ rng: inout SplitMix64, cells: Int, jitter: Float = 0.8, size: Int = 256) {
        n = size
        let cs = Float(size) / Float(cells)
        seeds = (0..<(cells * cells)).map { i in
            let cx = Float(i % cells), cy = Float(i / cells)
            return SIMD2((cx + 0.5 + (rng.float() - 0.5) * jitter) * cs, (cy + 0.5 + (rng.float() - 0.5) * jitter) * cs)
        }
        f1 = .init(repeating: 0, count: size * size)
        f2 = .init(repeating: 0, count: size * size)
        id = .init(repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let gx = Int(Float(x) / cs), gy = Int(Float(y) / cs)
                var d1 = Float.greatestFiniteMagnitude, d2 = d1
                var best: Int32 = 0
                for oy in -2...2 {
                    for ox in -2...2 {
                        let cx = gx + ox, cy = gy + oy
                        let wx = floorMod(cx, cells), wy = floorMod(cy, cells)
                        let s = seeds[wy * cells + wx]
                        let sx = s.x + Float(cx - wx) * cs, sy = s.y + Float(cy - wy) * cs
                        let d = ((Float(x) + 0.5 - sx) * (Float(x) + 0.5 - sx) + (Float(y) + 0.5 - sy) * (Float(y) + 0.5 - sy)).squareRoot()
                        if d < d1 { d2 = d1; d1 = d; best = Int32(wy * cells + wx) } else if d < d2 { d2 = d }
                    }
                }
                f1[y * size + x] = d1
                f2[y * size + x] = d2
                id[y * size + x] = best
            }
        }
    }
}

/// The procedural painter behind every material.
enum Painter {
    static func paint(_ m: Mat, _ rng: inout SplitMix64) -> [Canvas] {
        switch m {
        case .void: return [Canvas(256, hex(0x000000))]
        case .grass: return [grass(&rng)]
        case .hillGrass: return [grass(&rng, dark: hex(0x434F26), mid: hex(0x5A6630), light: hex(0x7A8244), rocky: true)]
        case .scrub: return [scrub(&rng)]
        case .forestFloor: return [forestFloor(&rng)]
        case .dirt: return [dirt(&rng)]
        case .sand: return [sand(&rng)]
        case .swamp: return [swamp(&rng)]
        case .field: return [field(&rng)]
        case .water: return water(&rng, deep: false)
        case .deepWater: return water(&rng, deep: true)
        case .foam: return foam(&rng)
        case .cobble: return [cobble(&rng)]
        case .woodFloor: return [planks(&rng, light: hex(0x7A4A24), dark: hex(0x52301A), width: 8, vertical: false)]
        case .deck: return [planks(&rng, light: hex(0x9A6A38), dark: hex(0x6E4422), width: 8, vertical: true)]
        case .flagstone: return [flagstone(&rng)]
        case .brickFloor: return [bricks(&rng, w: 16, h: 8, colors: [0xA8481E, 0xB4542A, 0x9A3E1A, 0xB0502A], mortar: 0x5A2410)]
        case .carpetBlue: return [carpet(&rng, base: hex(0x17238A), line: hex(0x2A3AA8))]
        case .carpetRed: return [carpet(&rng, base: hex(0x961418), line: hex(0xB02A26))]
        case .carpetBorder: return [carpetBorder(&rng)]
        case .marble: return [marble(&rng)]
        case .rockTop: return [rockTop(&rng)]
        case .rockFace: return [rockFace(&rng, base: hex(0x6E6A62), dark: hex(0x3E3A36), light: hex(0x9A968C))]
        case .caveFloor: return [caveFloor(&rng)]
        case .caveTop: return [Canvas(256, hex(0x030202))]
        case .caveFace: return [rockFace(&rng, base: hex(0x7A4A22), dark: hex(0x3A1E0A), light: hex(0xA8703A))]
        case .stoneFace: return [stoneBlocks(&rng)]
        case .stoneCap: return [granite(&rng, base: hex(0x56524E))]
        case .brickFace: return [bricks(&rng, w: 10, h: 4, colors: [0xA44A24, 0xB2582C, 0x8E3C1C, 0xBA6234], mortar: 0x4A3A30)]
        case .timberFace: return [timber(&rng)]
        case .logFace: return [logs(&rng)]
        case .woodCap: return [planks(&rng, light: hex(0x6A4426), dark: hex(0x4A2E18), width: 4, vertical: false)]
        case .shingle: return [shingles(&rng, base: hex(0xA4622C), dark: hex(0x5A3010), rowH: 6, minW: 6, maxW: 10)]
        case .slate: return [shingles(&rng, base: hex(0x5E6874), dark: hex(0x2A3038), rowH: 5, minW: 9, maxW: 14)]
        case .thatch: return [thatch(&rng)]
        case .tile: return [clayTiles(&rng)]
        case .eave: return [planks(&rng, light: hex(0x5A3820), dark: hex(0x3A2212), width: 4, vertical: false)]
        case .door: return [door(&rng)]
        case .window: return [window(&rng, stained: false)]
        case .stainedGlass: return [window(&rng, stained: true)]
        case .bank: return [bank(&rng, base: hex(0x5E3A1C))]
        case .sandBank: return [bank(&rng, base: hex(0x9A7448))]
        case .rail: return [planks(&rng, light: hex(0x8A5A2E), dark: hex(0x5A3818), width: 4, vertical: false)]
        }
    }

    // MARK: Ground

    static func grass(_ rng: inout SplitMix64, dark: Col = hex(0x3E5422), mid: Col = hex(0x566C2E),
                      light: Col = hex(0x7A8A42), rocky: Bool = false) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32], [1, 0.7, 0.4, 0.25])
        let g = fbmField(&rng, [16, 64, 128], [1, 0.8, 0.5])
        var cv = Canvas(256, mid)
        for i in 0..<65536 {
            let t = f[i]
            var col = t < 0.5 ? mix(dark, mid, t * 2) : mix(mid, light, (t - 0.5) * 2)
            col *= 0.86 + 0.26 * g[i]
            cv.c[i] = col
        }
        // Blades of grass: short strokes leaning every which way, dark at the root.
        for _ in 0..<11000 {
            let x = rng.int(256), y = rng.int(256)
            let len = 2 + rng.int(4)
            let lean = rng.range(-0.7, 0.7)
            let kind = rng.float()
            let base = cv[x, y]
            let tip: Col = kind < 0.45 ? base * 1.42 + Col(0.03, 0.035, 0.0) : (kind < 0.8 ? base * 0.58 : base * 1.15)
            for s in 0..<len {
                let t = Float(s) / Float(len)
                cv.blend(x + Int((lean * Float(s)).rounded()), y - s, mix(base * 0.78, tip, 0.35 + 0.65 * t), 0.9)
            }
        }
        for _ in 0..<1800 { cv.blend(rng.int(256), rng.int(256), dark * 0.7, 0.7) }
        for _ in 0..<500 { cv.blend(rng.int(256), rng.int(256), light * 1.25, 0.7) }
        if rocky {
            for _ in 0..<140 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(1, 2.4), col: hex(0x8A8476)) }
        }
        return cv
    }

    static func scrub(_ rng: inout SplitMix64) -> Canvas {
        var cv = grass(&rng, dark: hex(0x5A5A2A), mid: hex(0x7C7A3C), light: hex(0xA49A56))
        let patches = fbmField(&rng, [8, 16, 32], [1, 0.6, 0.3])
        for i in 0..<65536 where patches[i] > 0.62 {
            cv.c[i] = mix(cv.c[i], hex(0x8A6A3E) * (0.9 + 0.2 * patches[i]), smoothstep(0.62, 0.75, patches[i]) * 0.75)
        }
        for _ in 0..<160 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(0.8, 1.8), col: hex(0x9A8E78)) }
        return cv
    }

    static func forestFloor(_ rng: inout SplitMix64) -> Canvas {
        var cv = grass(&rng, dark: hex(0x26341A), mid: hex(0x384A22), light: hex(0x50602C))
        let litter: [UInt32] = [0x5A4220, 0x6A5228, 0x4A3418, 0x3A4A1E, 0x7A5A2A]
        for _ in 0..<2600 {
            let x = rng.int(256), y = rng.int(256)
            let col = hex(rng.pick(litter)) * rng.range(0.8, 1.15)
            let w = 1 + rng.int(3), h = 1 + rng.int(2)
            for dy in 0..<h { for dx in 0..<w { cv.blend(x + dx, y + dy, col, 0.85) } }
            cv.blend(x + w, y + h, col * 0.5, 0.6)
        }
        return cv
    }

    /// A shaded lump: lit from the upper left, shadowed below right, dark rim.
    static func pebble(_ cv: inout Canvas, _ rng: inout SplitMix64, _ cx: Int, _ cy: Int, r: Float, col: Col) {
        let ri = Int(r.rounded(.up)) + 1
        let tone = rng.range(0.82, 1.15)
        for dy in -ri...ri {
            for dx in -ri...ri {
                let d = (Float(dx * dx + dy * dy)).squareRoot() / r
                if d > 1.05 { continue }
                var c = col * tone * (1 + 0.38 * (-(Float(dx) + Float(dy)) / (r * 1.5)))
                if d > 0.72 && dx + dy > 0 { c *= 0.55 }
                if d > 0.95 { c *= 0.6 }
                cv[cx + dx, cy + dy] = c
            }
        }
    }

    static func dirt(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32, 64], [1, 0.7, 0.5, 0.35, 0.25])
        var cv = Canvas(256, hex(0x7A4A24))
        for i in 0..<65536 { cv.c[i] = mix(hex(0x5A3216), hex(0x8E5628), f[i]) }
        let tones: [UInt32] = [0x8A5226, 0x7A4620, 0x9A6030, 0x6A3C1A, 0xA2683A]
        for _ in 0..<1900 {
            pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(1.1, 3.4), col: hex(rng.pick(tones)))
        }
        for _ in 0..<260 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(0.7, 1.4), col: hex(0x8C8072)) }
        for _ in 0..<2200 { cv.blend(rng.int(256), rng.int(256), hex(0x3A200C), 0.6) }
        return cv
    }

    static func sand(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32], [1, 0.6, 0.35, 0.2])
        var cv = Canvas(256, hex(0xC8955A))
        for i in 0..<65536 { cv.c[i] = mix(hex(0xB08048), hex(0xD4A464), f[i]) }
        for _ in 0..<5200 { cv.blend(rng.int(256), rng.int(256), hex(0x9A6A3A), 0.55) }
        for _ in 0..<3600 { cv.blend(rng.int(256), rng.int(256), hex(0xE8BC7C), 0.6) }
        for _ in 0..<520 {
            let x = rng.int(256), y = rng.int(256)
            cv.blend(x, y, hex(0xE6B878), 0.8); cv.blend(x + 1, y, hex(0xE6B878), 0.5)
            cv.blend(x + 1, y + 1, hex(0x8A5C30), 0.7)
        }
        for _ in 0..<110 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(1, 2.6), col: hex(0x8E8478)) }
        return cv
    }

    static func swamp(_ rng: inout SplitMix64) -> Canvas {
        var cv = grass(&rng, dark: hex(0x2A3418), mid: hex(0x3E4A24), light: hex(0x56602E))
        let pools = fbmField(&rng, [8, 16, 32], [1, 0.5, 0.3])
        for i in 0..<65536 {
            let p = pools[i]
            if p > 0.55 {
                let t = smoothstep(0.55, 0.62, p)
                cv.c[i] = mix(cv.c[i], hex(0x26302A) * (0.85 + 0.3 * (1 - p)), t)
                if p > 0.56 && p < 0.575 { cv.c[i] = mix(cv.c[i], hex(0x1A2010), 0.7) }
            }
        }
        for _ in 0..<500 {
            let x = rng.int(256), y = rng.int(256)
            if pools[cv.idx(x, y)] > 0.62 { cv.blend(x, y, hex(0x6A8070), 0.6) }
        }
        return cv
    }

    static func field(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [8, 16, 64], [1, 0.5, 0.4])
        var cv = Canvas(256, hex(0x6A4424))
        for y in 0..<256 {
            for x in 0..<256 {
                let row = y % 8
                let ridge: Float = [0.62, 0.8, 1.0, 1.12, 1.08, 0.95, 0.78, 0.6][row]
                cv[x, y] = mix(hex(0x5A3418), hex(0x825428), f[y * 256 + x]) * ridge
            }
        }
        for _ in 0..<2000 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(0.6, 1.5), col: hex(0x8A5A30)) }
        return cv
    }

    /// Blue water with drifting lines of light on the crests, eight looping frames.
    static func water(_ rng: inout SplitMix64, deep: Bool) -> [Canvas] {
        let f = fbmField(&rng, [4, 8, 16], [1, 0.6, 0.3])
        let jag = fbmField(&rng, [16, 32, 64], [1, 0.6, 0.4])
        let dark = deep ? hex(0x0C1C6A) : hex(0x1A36A6)
        let mid = deep ? hex(0x142A86) : hex(0x2248C4)
        let crest = deep ? hex(0x3A5CB4) : hex(0x6890EC)
        let waves: [(Float, Float, Float, Int)] = [(10, 3, 1.0, 1), (-5, 12, 0.7, -1), (14, -6, 0.5, 2)]
        let sparkles: [(Int, Int, Int)] = (0..<320).map { _ in (rng.int(256), rng.int(256), rng.int(8)) }
        return (0..<8).map { frame in
            var cv = Canvas(256, mid)
            let ph = Float(frame) / 8 * 2 * .pi
            for y in 0..<256 {
                for x in 0..<256 {
                    let i = y * 256 + x
                    var s: Float = 0
                    for (a, b, w, k) in waves {
                        s += w * sin(2 * .pi * (a * Float(x) + b * Float(y)) / 256 + ph * Float(k) + jag[i] * 4)
                    }
                    var c = mix(dark, mid, f[i])
                    // Thin bright lines where the swell crests, a darker trough before it.
                    let line = 1 - smoothstep(0.0, 0.16, abs(s - 1.35))
                    c = mix(c, crest, line * 0.8)
                    if s > 0.95 && s < 1.15 { c *= 0.9 }
                    cv.c[i] = c
                }
            }
            for (x, y, phase) in sparkles where (frame - phase + 8) % 8 < 2 {
                cv[x, y] = hex(0xF0F6FF)
                cv.blend(x + 1, y, hex(0xB8D0FF), 0.5)
                cv.blend(x - 1, y, hex(0xB8D0FF), 0.5)
            }
            return cv
        }
    }

    /// Surf along the shore: white lace that comes and goes.
    static func foam(_ rng: inout SplitMix64) -> [Canvas] {
        let f = fbmField(&rng, [16, 32, 64], [1, 0.7, 0.5])
        return (0..<8).map { frame in
            var cv = Canvas(256, hex(0x5A86E8))
            let ph = Float(frame) / 8
            for i in 0..<65536 {
                let v = (f[i] + ph).truncatingRemainder(dividingBy: 1)
                let lace = smoothstep(0.35, 0.5, v) * (1 - smoothstep(0.62, 0.8, v))
                cv.c[i] = mix(hex(0x3E6CE0), hex(0xEAF4FF), lace * 0.9)
            }
            return cv
        }
    }

    // MARK: Floors

    static func cobble(_ rng: inout SplitMix64) -> Canvas {
        let vor = Voronoi(&rng, cells: 21, jitter: 0.75)
        let grain = fbmField(&rng, [32, 64, 128], [1, 0.7, 0.5])
        let tones: [UInt32] = [0x8C847A, 0x7A746E, 0x6A6662, 0x9A9284, 0x5E5C5C, 0x847C70, 0x726E72]
        let stoneTone = (0..<(21 * 21)).map { _ in hex(rng.pick(tones)) * rng.range(0.9, 1.08) }
        var cv = Canvas(256, hex(0xA09888))
        for y in 0..<256 {
            for x in 0..<256 {
                let i = y * 256 + x
                let edge = vor.f2[i] - vor.f1[i]
                if edge < 1.7 {
                    cv.c[i] = mix(hex(0x8E867A), hex(0xB4AC9C), grain[i])
                    continue
                }
                let s = vor.seeds[Int(vor.id[i])]
                var dx = Float(x) + 0.5 - s.x, dy = Float(y) + 0.5 - s.y
                if dx > 128 { dx -= 256 } else if dx < -128 { dx += 256 }
                if dy > 128 { dy -= 256 } else if dy < -128 { dy += 256 }
                var c = stoneTone[Int(vor.id[i])] * (0.88 + 0.24 * grain[i])
                c *= 1 + 0.32 * (-(dx + dy) / 12)
                if edge < 3.2 { c *= dx + dy > 0 ? 0.62 : 1.12 }
                cv.c[i] = c
            }
        }
        return cv
    }

    static func planks(_ rng: inout SplitMix64, light: Col, dark: Col, width: Int, vertical: Bool) -> Canvas {
        let grain = fbmField(&rng, [8, 32, 64], [1, 0.6, 0.4])
        var cv = Canvas(256, light)
        var boards: [[(start: Int, tone: Float)]] = []
        precondition(256 % width == 0, "plank width must divide the texture")
        for _ in 0..<(256 / width) {
            var row: [(Int, Float)] = []
            var x = rng.int(60)
            let first = x
            while x < first + 256 {
                row.append((x, rng.range(0.8, 1.12)))
                x += 36 + rng.int(90)
            }
            boards.append(row)
        }
        for y in 0..<256 {
            for x in 0..<256 {
                let (a, b) = vertical ? (y, x) : (x, y)
                let r = b / width, inRow = b % width
                let row = boards[r]
                var tone: Float = row.last!.tone
                var seam = false
                for (k, bd) in row.enumerated() {
                    let s = floorMod(a - bd.start, 256)
                    let next = k + 1 < row.count ? row[k + 1].start - bd.start : 256 - (bd.start - row[0].start)
                    if s < next { tone = bd.tone; seam = s == 0 || s == next - 1; break }
                }
                let g = grain[(vertical ? x : y) * 256 + (vertical ? y : x)]
                let streak = 0.5 + 0.5 * sin(Float(a) * 0.11 + g * 9 + Float(r) * 1.7)
                var c = mix(dark, light, 0.35 + 0.5 * g) * tone * (0.9 + 0.14 * streak)
                if inRow == 0 { c = dark * 0.45 } else if inRow == 1 { c *= 1.12 } else if inRow == width - 1 { c *= 0.78 }
                if seam && inRow != 0 { c *= 0.5 }
                cv[vertical ? b : a, vertical ? a : b] = c
            }
        }
        // Nail heads near the board ends.
        for (r, row) in boards.enumerated() {
            for bd in row where width >= 6 {
                for off in [2, -3] {
                    let a = bd.start + off, b = r * width + width / 2
                    cv[vertical ? b : a, vertical ? a : b] = dark * 0.4
                }
            }
        }
        return cv
    }

    static func flagstone(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [16, 64, 128], [1, 0.6, 0.5])
        let tones = (0..<256).map { _ in rng.range(0.9, 1.06) }
        var cv = Canvas(256, hex(0xC4C0B6))
        for y in 0..<256 {
            for x in 0..<256 {
                let tx = x / 16, ty = y / 16, lx = x % 16, ly = y % 16
                var c = mix(hex(0xB2AEA4), hex(0xD2CEC4), grain[y * 256 + x]) * tones[ty * 16 + tx]
                if lx == 0 || ly == 0 { c = hex(0x86827A) }
                else if lx == 1 || ly == 1 { c *= 1.08 }
                else if lx == 15 || ly == 15 { c *= 0.84 }
                cv[x, y] = c
            }
        }
        for _ in 0..<1400 { cv.blend(rng.int(256), rng.int(256), hex(0x9A968E), 0.5) }
        return cv
    }

    /// Running-bond bricks, used for floors and (smaller) for walls.
    static func bricks(_ rng: inout SplitMix64, w: Int, h: Int, colors: [UInt32], mortar: UInt32) -> Canvas {
        let grain = fbmField(&rng, [32, 64, 128], [1, 0.7, 0.6])
        let rows = 256 / h, cols = 256 / w
        let tones = (0..<(rows * cols)).map { _ in hex(rng.pick(colors)) * rng.range(0.88, 1.1) }
        var cv = Canvas(256, hex(mortar))
        for y in 0..<256 {
            for x in 0..<256 {
                let r = y / h
                let xs = x + (r % 2 == 1 ? w / 2 : 0)
                let cidx = (xs / w) % cols, lx = xs % w, ly = y % h
                if lx == 0 || ly == 0 { cv[x, y] = hex(mortar) * (0.85 + 0.3 * grain[y * 256 + x]); continue }
                var c = tones[r * cols + cidx] * (0.86 + 0.26 * grain[y * 256 + x])
                if ly == 1 { c *= 1.12 } else if ly == h - 1 { c *= 0.84 }
                if lx == w - 1 { c *= 0.88 }
                cv[x, y] = c
            }
        }
        return cv
    }

    static func carpet(_ rng: inout SplitMix64, base: Col, line: Col) -> Canvas {
        let grain = fbmField(&rng, [32, 128], [1, 0.8])
        var cv = Canvas(256, base)
        for y in 0..<256 {
            for x in 0..<256 {
                var c = base * (0.9 + 0.18 * grain[y * 256 + x])
                if x % 4 == 0 || y % 4 == 0 { c = mix(c, line, 0.55) }
                if (x + y) % 2 == 0 { c *= 0.96 }
                cv[x, y] = c
            }
        }
        return cv
    }

    /// The gold border woven round a carpet; v runs across it (0 = outer edge).
    static func carpetBorder(_ rng: inout SplitMix64) -> Canvas {
        let rows: [UInt32] = [0x4A2E08, 0xD0A63C, 0xF0D47A, 0xC89A32, 0x7A1A14, 0xC89A32, 0x5A3A0C, 0x2A1A06]
        var cv = Canvas(256, hex(0xC89A32))
        for y in 0..<256 {
            for x in 0..<256 {
                let v = min(y, 7)
                var c = hex(rows[v])
                if v == 4 && x % 6 < 3 { c = hex(0xF0D47A) }
                if (x + y) % 3 == 0 { c *= 0.94 }
                cv[x, y] = c
            }
        }
        return cv
    }

    static func marble(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32], [1, 0.6, 0.4, 0.25])
        var cv = Canvas(256, hex(0xDAD6CC))
        for y in 0..<256 {
            for x in 0..<256 {
                let t = f[y * 256 + x]
                let vein = abs(sin((Float(x) + Float(y)) * 2 * .pi / 128 + t * 9))
                var c = mix(hex(0xC6C2B8), hex(0xE8E4DA), t)
                if vein < 0.07 { c = mix(c, hex(0x8E8A84), 0.7 - vein * 6) }
                if x % 32 == 0 || y % 32 == 0 { c *= 0.86 }
                cv[x, y] = c
            }
        }
        return cv
    }

    // MARK: Rock

    static func rockTop(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32, 64], [1, 0.7, 0.5, 0.35, 0.25])
        let moss = fbmField(&rng, [8, 16, 32], [1, 0.6, 0.3])
        let cracks = fbmField(&rng, [8, 16, 32], [1, 0.5, 0.25])
        var cv = Canvas(256, hex(0x8A8680))
        for i in 0..<65536 {
            var c = mix(hex(0x6E6A62), hex(0xA6A298), f[i])
            let crack = abs(cracks[i] - 0.5)
            if crack < 0.01 { c *= 0.7 }
            if moss[i] > 0.58 { c = mix(c, hex(0x56682C) * (0.8 + 0.4 * f[i]), smoothstep(0.58, 0.7, moss[i]) * 0.85) }
            cv.c[i] = c
        }
        for _ in 0..<2200 { cv.blend(rng.int(256), rng.int(256), hex(0xD8D4CA), 0.55) }
        for _ in 0..<2200 { cv.blend(rng.int(256), rng.int(256), hex(0x3A3632), 0.55) }
        return cv
    }

    /// Cliff faces: vertical striations with lit ridges and dark clefts.
    static func rockFace(_ rng: inout SplitMix64, base: Col, dark: Col, light: Col) -> Canvas {
        let f = fbmField(&rng, [8, 16, 32], [1, 0.6, 0.4])
        var columns: [Float] = (0..<256).map { _ in rng.float() }
        for _ in 0..<3 { columns = (0..<256).map { (columns[$0] * 2 + columns[($0 + 1) & 255] + columns[($0 + 255) & 255]) / 4 } }
        var cv = Canvas(256, base)
        for y in 0..<256 {
            for x in 0..<256 {
                let col = columns[(x + Int(f[y * 256 + x] * 6)) & 255]
                var c = mix(dark, light, clamp01(col * 1.4 - 0.15 + (f[y * 256 + x] - 0.5) * 0.5))
                let ridge = columns[(x + 1) & 255] - col
                if ridge > 0.05 { c *= 0.7 } else if ridge < -0.05 { c *= 1.12 }
                if (y + Int(col * 40)) % 9 == 0 { c *= 0.82 }
                cv[x, y] = c
            }
        }
        return cv
    }

    static func caveFloor(_ rng: inout SplitMix64) -> Canvas {
        let f = fbmField(&rng, [4, 8, 16, 32], [1, 0.6, 0.4, 0.3])
        let g = fbmField(&rng, [16, 64], [1, 0.5])
        var cv = Canvas(256, hex(0x8A5A2A))
        for i in 0..<65536 {
            var c = mix(hex(0x74461E), hex(0x9A6630), g[i])
            let band = (f[i] * 9).truncatingRemainder(dividingBy: 1)
            if band < 0.1 { c *= 0.72 } else if band < 0.18 { c *= 1.1 }
            cv.c[i] = c
        }
        for _ in 0..<900 { cv.blend(rng.int(256), rng.int(256), hex(0x4A2A10), 0.6) }
        for _ in 0..<120 { pebble(&cv, &rng, rng.int(256), rng.int(256), r: rng.range(0.6, 1.4), col: hex(0x8A8278)) }
        return cv
    }

    // MARK: Walls

    static func granite(_ rng: inout SplitMix64, base: Col) -> Canvas {
        let f = fbmField(&rng, [16, 64, 128], [1, 0.8, 0.8])
        var cv = Canvas(256, base)
        for i in 0..<65536 { cv.c[i] = base * (0.8 + 0.4 * f[i]) }
        for _ in 0..<9000 { cv.blend(rng.int(256), rng.int(256), base * 0.55, 0.7) }
        for _ in 0..<6000 { cv.blend(rng.int(256), rng.int(256), base * 1.45, 0.6) }
        return cv
    }

    /// Courses of dressed grey stone for wall faces (v is the height up the wall).
    static func stoneBlocks(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [32, 128], [1, 0.9])
        var cv = Canvas(256, hex(0x2C2A28))
        let courseH = 6
        for course in 0..<(256 / courseH) {
            var x = rng.int(14)
            while x < 256 + 14 {
                let len = 9 + rng.int(9)
                let tone = hex(rng.pick([0x5C5A56, 0x52504C, 0x66625C, 0x4A4846, 0x5E5850])) * rng.range(0.9, 1.1)
                for yy in 0..<courseH {
                    for xx in 0..<len {
                        let px = x + xx, py = course * courseH + yy
                        if xx == len - 1 || yy == courseH - 1 { cv[px, py] = hex(0x262422); continue }
                        var c = tone * (0.86 + 0.28 * grain[(py & 255) * 256 + (px & 255)])
                        if yy == courseH - 2 { c *= 1.14 } else if yy == 0 { c *= 0.85 }
                        if xx == 0 { c *= 1.06 }
                        cv[px, py] = c
                    }
                }
                x += len
            }
        }
        for _ in 0..<2600 { cv.blend(rng.int(256), rng.int(256), hex(0x88847C), 0.4) }
        return cv
    }

    /// Half-timbering: rosy plaster panels framed by dark oak posts, rails and braces.
    static func timber(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [16, 64, 128], [1, 0.6, 0.5])
        var cv = Canvas(256, hex(0xE4C6B4))
        for y in 0..<256 {
            for x in 0..<256 {
                let lx = x % 32, v = y % 32
                let i = y * 256 + x
                var c = mix(hex(0xD6B4A2), hex(0xF0D8C8), grain[i])
                let panel = (x / 32) % 2
                let diag = panel == 0 ? abs((lx - 3) - (v - 2) * 26 / 18) : abs((28 - lx) - (v - 2) * 26 / 18)
                let beam = lx < 3 || v < 2 || (v >= 11 && v < 13) || (v >= 21 && v < 24)
                    || (v >= 2 && v < 11 && diag < 2)
                if beam {
                    c = mix(hex(0x4A2E1A), hex(0x6A4428), grain[i])
                    if lx == 0 || v == 21 || v == 11 { c *= 0.7 }
                } else if lx == 3 || v == 2 || v == 13 {
                    c *= 0.82
                }
                cv[x, y] = c
            }
        }
        return cv
    }

    static func logs(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [16, 64, 128], [1, 0.6, 0.6])
        var cv = Canvas(256, hex(0x6A4426))
        for y in 0..<256 {
            for x in 0..<256 {
                let v = y % 6
                let round: Float = [0.55, 0.85, 1.05, 1.12, 1.0, 0.75][v]
                var c = mix(hex(0x5A3A20), hex(0x86603A), grain[y * 256 + x]) * round
                if v == 0 { c *= 0.6 }
                if (x * 7 + y / 6 * 31) % 23 == 0 { c *= 0.7 }
                cv[x, y] = c
            }
        }
        return cv
    }

    // MARK: Roofs (v counts up from the eave)

    static func shingles(_ rng: inout SplitMix64, base: Col, dark: Col, rowH: Int, minW: Int, maxW: Int) -> Canvas {
        let grain = fbmField(&rng, [16, 64, 128], [1, 0.6, 0.6])
        var cv = Canvas(256, base)
        for row in 0..<(256 / rowH) {
            var x = rng.int(maxW)
            let start = x
            while x < start + 256 {
                let w = minW + rng.int(maxW - minW + 1)
                let tone = rng.range(0.82, 1.14)
                for yy in 0..<rowH {
                    for xx in 0..<w {
                        let px = x + xx, py = row * rowH + yy
                        var c = base * tone * (0.86 + 0.28 * grain[(py & 255) * 256 + (px & 255)])
                        // Each row lies over the one nearer the eave: dark under-edge, lit lip.
                        if yy == 0 { c = dark }
                        else if yy == 1 { c *= 1.18 }
                        else { c *= 1.06 - Float(yy) / Float(rowH) * 0.3 }
                        if xx == w - 1 { c = mix(c, dark, 0.7) }
                        cv[px, py] = c
                    }
                }
                x += w
            }
        }
        return cv
    }

    static func thatch(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [16, 64], [1, 0.7])
        var cv = Canvas(256, hex(0xA88A48))
        for i in 0..<65536 { cv.c[i] = mix(hex(0x8E7238), hex(0xC0A058), grain[i]) }
        for _ in 0..<16000 {
            let x = rng.int(256), y = rng.int(256)
            let len = 3 + rng.int(6)
            let col = rng.chance(0.5) ? hex(0xD8BC70) : hex(0x6E5428)
            for s in 0..<len { cv.blend(x, y + s, col, 0.55) }
        }
        for y in 0..<256 where y % 10 == 0 || y % 10 == 1 {
            for x in 0..<256 { cv.mul(x, y, y % 10 == 0 ? 0.55 : 0.8) }
        }
        return cv
    }

    static func clayTiles(_ rng: inout SplitMix64) -> Canvas {
        let grain = fbmField(&rng, [16, 64, 128], [1, 0.6, 0.6])
        var cv = Canvas(256, hex(0xA8442A))
        for y in 0..<256 {
            for x in 0..<256 {
                let u = x % 8, v = y % 10
                let barrel: Float = [0.55, 0.85, 1.05, 1.18, 1.2, 1.1, 0.92, 0.7][u]
                var c = mix(hex(0x903424), hex(0xB85032), grain[y * 256 + x]) * barrel
                if v == 0 { c *= 0.5 } else if v == 1 { c *= 1.15 }
                cv[x, y] = c
            }
        }
        return cv
    }

    // MARK: Pictures on walls (local coordinates: u across the tile, v up the wall)

    static func door(_ rng: inout SplitMix64) -> Canvas {
        var cv = Canvas(256, hex(0), alpha: 0)
        let grain = fbmField(&rng, [16, 64], [1, 0.6])
        for v in 0..<22 {
            for u in 5..<27 {
                if v == 21 || u == 5 || u == 26 { cv.put(u, v, hex(0x2E1A0C)); continue }
                let plank = (u - 6) / 4
                var c = mix(hex(0x5A3418), hex(0x7E4E26), grain[v * 256 + u]) * (0.9 + 0.08 * Float(plank % 2))
                if (u - 6) % 4 == 0 { c *= 0.55 }
                if v == 4 || v == 15 { c = hex(0x3C3C44) }
                if (v == 4 || v == 15) && (u - 6) % 4 == 2 { c = hex(0x9A9AA6) }
                cv.put(u, v, c)
            }
        }
        cv.put(22, 10, hex(0xC8A040)); cv.put(22, 9, hex(0x8A6A20)); cv.put(23, 10, hex(0x6A4A10))
        return cv
    }

    static func window(_ rng: inout SplitMix64, stained: Bool) -> Canvas {
        var cv = Canvas(256, hex(0), alpha: 0)
        let panes: [UInt32] = [0xC8302A, 0x2A48C0, 0xE0B030, 0x2A9040, 0x8A30A0]
        let top = stained ? 21 : 19
        for v in 6..<top {
            for u in 9..<23 {
                let frame = u == 9 || u == 22 || v == 6 || v == top - 1
                var c: Col
                if frame { c = hex(0x3A2412) }
                else if u == 15 || u == 16 || (!stained && v == 12) { c = hex(0x5A3A20) }
                else if stained {
                    c = (u + v) % 4 == 0 ? hex(0x1A1410) : hex(panes[((u - 10) / 3 + (v - 7) / 3 * 2) % panes.count])
                } else {
                    let glint = (u - v + 40) % 9 < 2
                    c = glint ? hex(0xE8F0F4) : mix(hex(0x6E8494), hex(0xA8BCC8), Float(v - 6) / 13)
                }
                cv.put(u, v, c)
            }
        }
        for u in 8..<24 { cv.put(u, 5, hex(0x8A6A48)); cv.put(u, 4, hex(0x4A3018)) }
        return cv
    }

    static func bank(_ rng: inout SplitMix64, base: Col) -> Canvas {
        let f = fbmField(&rng, [16, 64], [1, 0.6])
        var cv = Canvas(256, base)
        for y in 0..<256 {
            for x in 0..<256 {
                cv[x, y] = base * (0.75 + 0.35 * f[y * 256 + x]) * (y % 8 < 2 ? 0.7 : 1)
            }
        }
        return cv
    }
}
