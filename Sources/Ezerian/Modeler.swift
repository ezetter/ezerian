import Foundation
import simd

typealias V3 = SIMD3<Float>

// Objects are modelled from simple solids and ray traced into sprites in the same
// oblique projection as the ground: model point (x, y, z) lands on screen at
// (x - z, y - z), relative to the top-left ground corner of the object's tile.
// Characters use a gentler lean, (x - z/2, y - z), so they stay readable.

/// How a solid is coloured.
struct Paint {
    enum Grain { case none, wood(Int), bark, leaves, stone, metal, cloth, straw, fire, water, hair }
    var base: Col
    var grain: Grain = .none
    /// Random variation in brightness per pixel.
    var jitter: Float = 0.06
    var shine: Float = 0
    var glow = false

    init(_ hexColor: UInt32, _ grain: Grain = .none, jitter: Float = 0.06, shine: Float = 0, glow: Bool = false) {
        base = hex(hexColor)
        self.grain = grain
        self.jitter = jitter
        self.shine = shine
        self.glow = glow
    }

    init(col: Col, _ grain: Grain = .none, jitter: Float = 0.06, shine: Float = 0, glow: Bool = false) {
        base = col
        self.grain = grain
        self.jitter = jitter
        self.shine = shine
        self.glow = glow
    }
}

struct Prim {
    enum Shape {
        case box(V3, V3)
        case ellipsoid(V3, V3)
        /// Upright frustum: centre (x, y), radius at the bottom and top, z range.
        case cone(SIMD2<Float>, Float, Float, Float, Float)
        case capsule(V3, V3, Float)
        /// Lying cylinder along x (axis 0) or y (axis 1): centre of the round end in
        /// the other two coordinates, radius, and extent along the axis.
        case lying(Int, SIMD2<Float>, Float, Float, Float)
    }
    var shape: Shape
    var paint: Paint
}

/// A model under construction.
struct Model {
    var prims: [Prim] = []
    /// Screen lean per unit of height (1 for the world, 0.5 for people).
    var leanX: Float = 1
    var outline = true
    var shadow = true
    /// Darkness of the cast shadow.
    var shadowAlpha: Float = 0.28
    var seed: UInt64 = 1

    mutating func box(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ p: Paint) {
        prims.append(Prim(shape: .box(V3(min(x0, x1), min(y0, y1), min(z0, z1)), V3(max(x0, x1), max(y0, y1), max(z0, z1))), paint: p))
    }

    mutating func ball(_ x: Float, _ y: Float, _ z: Float, _ r: Float, _ p: Paint) {
        prims.append(Prim(shape: .ellipsoid(V3(x, y, z), V3(r, r, r)), paint: p))
    }

    mutating func blob(_ x: Float, _ y: Float, _ z: Float, _ rx: Float, _ ry: Float, _ rz: Float, _ p: Paint) {
        prims.append(Prim(shape: .ellipsoid(V3(x, y, z), V3(rx, ry, rz)), paint: p))
    }

    mutating func cyl(_ x: Float, _ y: Float, _ r: Float, _ z0: Float, _ z1: Float, _ p: Paint) {
        prims.append(Prim(shape: .cone(SIMD2(x, y), r, r, z0, z1), paint: p))
    }

    mutating func cone(_ x: Float, _ y: Float, _ r0: Float, _ r1: Float, _ z0: Float, _ z1: Float, _ p: Paint) {
        prims.append(Prim(shape: .cone(SIMD2(x, y), r0, r1, z0, z1), paint: p))
    }

    mutating func rod(_ a: V3, _ b: V3, _ r: Float, _ p: Paint) {
        prims.append(Prim(shape: .capsule(a, b, r), paint: p))
    }

    /// A cylinder lying along x from x0 to x1, its axis at (y, z).
    mutating func logX(_ y: Float, _ z: Float, _ r: Float, _ x0: Float, _ x1: Float, _ p: Paint) {
        prims.append(Prim(shape: .lying(0, SIMD2(y, z), r, x0, x1), paint: p))
    }

    /// A cylinder lying along y from y0 to y1, its axis at (x, z).
    mutating func logY(_ x: Float, _ z: Float, _ r: Float, _ y0: Float, _ y1: Float, _ p: Paint) {
        prims.append(Prim(shape: .lying(1, SIMD2(x, z), r, y0, y1), paint: p))
    }

    mutating func add(_ other: Model, dx: Float = 0, dy: Float = 0, dz: Float = 0) {
        let off = V3(dx, dy, dz)
        for var p in other.prims {
            switch p.shape {
            case let .box(a, b): p.shape = .box(a + off, b + off)
            case let .ellipsoid(c, r): p.shape = .ellipsoid(c + off, r)
            case let .cone(c, r0, r1, z0, z1): p.shape = .cone(c + SIMD2(dx, dy), r0, r1, z0 + dz, z1 + dz)
            case let .capsule(a, b, r): p.shape = .capsule(a + off, b + off, r)
            case let .lying(axis, c, r, a0, a1):
                let shift = axis == 0 ? (SIMD2(dy, dz), dx) : (SIMD2(dx, dz), dy)
                p.shape = .lying(axis, c + shift.0, r, a0 + shift.1, a1 + shift.1)
            }
            prims.append(p)
        }
    }
}

/// Turns models into sprites.
enum Modeler {
    static let light = simd_normalize(V3(-0.45, -0.55, 0.72))
    static let shadowLight = simd_normalize(V3(-0.24, -0.3, 1))

    private struct Hit {
        var t: Float
        var n: V3
        var prim: Int
    }

    /// Largest t at which the ray o + t*d is inside the solid, with the normal there.
    private static func intersect(_ shape: Prim.Shape, _ o: V3, _ d: V3) -> (Float, V3)? {
        switch shape {
        case let .box(lo, hi):
            var tn = -Float.greatestFiniteMagnitude, tf = Float.greatestFiniteMagnitude
            var axis = 2
            for a in 0..<3 {
                if abs(d[a]) < 1e-6 {
                    if o[a] < lo[a] || o[a] > hi[a] { return nil }
                    continue
                }
                var t1 = (lo[a] - o[a]) / d[a], t2 = (hi[a] - o[a]) / d[a]
                if t1 > t2 { swap(&t1, &t2) }
                tn = max(tn, t1)
                if t2 < tf { tf = t2; axis = a }
            }
            guard tn <= tf else { return nil }
            var n = V3(0, 0, 0)
            n[axis] = d[axis] > 0 ? 1 : -1
            return (tf, n)
        case let .ellipsoid(c, r):
            let oc = (o - c) / r, dd = d / r
            let a = simd_dot(dd, dd), b = 2 * simd_dot(oc, dd), cc = simd_dot(oc, oc) - 1
            let disc = b * b - 4 * a * cc
            guard disc >= 0 else { return nil }
            let t = (-b + disc.squareRoot()) / (2 * a)
            let p = o + t * d
            return (t, simd_normalize((p - c) / (r * r)))
        case let .cone(c, r0, r1, z0, z1):
            // z = t along our rays (d.z == 1, o.z == 0).
            let s = (r1 - r0) / max(0.001, z1 - z0)
            let a0 = r0 - z0 * s
            let ox = o.x - c.x, oy = o.y - c.y
            let A = d.x * d.x + d.y * d.y - s * s
            let B = 2 * (ox * d.x + oy * d.y - a0 * s)
            let C = ox * ox + oy * oy - a0 * a0
            func inside(_ t: Float) -> Bool {
                let x = ox + t * d.x, y = oy + t * d.y, r = a0 + s * t
                return r >= 0 && x * x + y * y <= r * r + 1e-4
            }
            var candidates: [Float] = [z1]
            if abs(A) > 1e-6 {
                let disc = B * B - 4 * A * C
                if disc >= 0 {
                    let q = disc.squareRoot()
                    candidates.append((-B + q) / (2 * A))
                    candidates.append((-B - q) / (2 * A))
                }
            } else if abs(B) > 1e-6 {
                candidates.append(-C / B)
            }
            var best: Float?
            for t in candidates where t >= z0 - 1e-4 && t <= z1 + 1e-4 && inside(min(t, z1)) {
                let tt = min(t, z1)
                if best == nil || tt > best! { best = tt }
            }
            guard let t = best else { return nil }
            if abs(t - z1) < 1e-3 { return (t, V3(0, 0, 1)) }
            let x = ox + t * d.x, y = oy + t * d.y
            let r = max(0.001, a0 + s * t)
            return (t, simd_normalize(V3(x / r, y / r, -s)))
        case let .lying(axis, c, r, a0, a1):
            // The two coordinates across the axis, and the one along it.
            let (u, w, along) = axis == 0 ? (1, 2, 0) : (0, 2, 1)
            let ou = o[u] - c.x, ow = o[w] - c.y, du = d[u], dw = d[w]
            let A = du * du + dw * dw, B = 2 * (ou * du + ow * dw), C = ou * ou + ow * ow - r * r
            let disc = B * B - 4 * A * C
            guard disc >= 0, A > 1e-6 else { return nil }
            let q = disc.squareRoot()
            var tn = (-B - q) / (2 * A), tf = (-B + q) / (2 * A)
            var capHit = false
            if abs(d[along]) > 1e-6 {
                var s0 = (a0 - o[along]) / d[along], s1 = (a1 - o[along]) / d[along]
                if s0 > s1 { swap(&s0, &s1) }
                tn = max(tn, s0)
                if s1 < tf { tf = s1; capHit = true }
            } else if o[along] < a0 || o[along] > a1 { return nil }
            guard tn <= tf else { return nil }
            if capHit {
                var n = V3(0, 0, 0)
                n[along] = 1
                return (tf, n)
            }
            let p = o + tf * d
            var n = V3(0, 0, 0)
            n[u] = p[u] - c.x
            n[w] = p[w] - c.y
            return (tf, simd_normalize(n))
        case let .capsule(pa, pb, r):
            // Trace from the eye's side inwards, so the first hit is the visible one.
            let T: Float = 300
            let dl = simd_length(d)
            let rd = -d / dl
            let ro = o + T * d
            let ba = pb - pa, oa = ro - pa
            let baba = simd_dot(ba, ba), bard = simd_dot(ba, rd), baoa = simd_dot(ba, oa)
            let rdoa = simd_dot(rd, oa), oaoa = simd_dot(oa, oa)
            let a = baba - bard * bard
            let b = baba * rdoa - baoa * bard
            let c = baba * oaoa - baoa * baoa - r * r * baba
            let h = b * b - a * c
            guard h >= 0 else { return nil }
            var s: Float = -1
            if a > 1e-6 {
                let t = (-b - h.squareRoot()) / a
                let y = baoa + t * bard
                if y > 0 && y < baba { s = t }
            }
            if s < 0 {
                for centre in [pa, pb] {
                    let oc = ro - centre
                    let bb = simd_dot(rd, oc), cc = simd_dot(oc, oc) - r * r
                    let hh = bb * bb - cc
                    if hh > 0 {
                        let t = -bb - hh.squareRoot()
                        if t > 0 && (s < 0 || t < s) { s = t }
                    }
                }
            }
            guard s > 0 else { return nil }
            let p = ro + s * rd
            let k = max(0, min(1, simd_dot(p - pa, ba) / max(baba, 1e-6)))
            return (T - s / dl, simd_normalize(p - pa - k * ba))
        }
    }

    private static func bounds(_ shape: Prim.Shape) -> (V3, V3) {
        switch shape {
        case let .box(lo, hi): return (lo, hi)
        case let .ellipsoid(c, r): return (c - r, c + r)
        case let .cone(c, r0, r1, z0, z1):
            let r = max(r0, r1)
            return (V3(c.x - r, c.y - r, z0), V3(c.x + r, c.y + r, z1))
        case let .capsule(a, b, r):
            return (simd_min(a, b) - V3(repeating: r), simd_max(a, b) + V3(repeating: r))
        case let .lying(axis, c, r, a0, a1):
            return axis == 0 ? (V3(a0, c.x - r, c.y - r), V3(a1, c.x + r, c.y + r))
                : (V3(c.x - r, a0, c.y - r), V3(c.x + r, a1, c.y + r))
        }
    }

    /// Ray traces a model into a sprite whose anchor is the model's origin.
    static func render(_ m: Model) -> Sprite {
        guard !m.prims.isEmpty else { return Sprite(w: 1, h: 1) }
        let d = V3(m.leanX, 1, 1)
        var minX = Float.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minX
        for p in m.prims {
            let (lo, hi) = bounds(p.shape)
            for cx in [lo.x, hi.x] { for cy in [lo.y, hi.y] { for cz in [lo.z, hi.z] {
                let sx = cx - m.leanX * cz, sy = cy - cz
                minX = min(minX, sx); maxX = max(maxX, sx); minY = min(minY, sy); maxY = max(maxY, sy)
            } } }
        }
        let x0 = Int(minX.rounded(.down)) - 2, y0 = Int(minY.rounded(.down)) - 2
        let x1 = Int(maxX.rounded(.up)) + 2, y1 = Int(maxY.rounded(.up)) + 2
        var s = Sprite(w: x1 - x0, h: y1 - y0, ax: -x0, ay: -y0)
        var rng = SplitMix64(seed: m.seed)
        var hitPrim = [Int](repeating: -1, count: s.w * s.h)
        for py in 0..<s.h {
            for px in 0..<s.w {
                let o = V3(Float(px + x0) + 0.5, Float(py + y0) + 0.5, 0)
                var best: Hit?
                for (k, p) in m.prims.enumerated() {
                    if let (t, n) = intersect(p.shape, o, d), best == nil || t > best!.t { best = Hit(t: t, n: n, prim: k) }
                }
                let i = py * s.w + px
                guard let hit = best else { continue }
                let paint = m.prims[hit.prim].paint
                let pos = o + hit.t * d
                s.px[i] = pack(shade(paint, pos, hit.n, &rng))
                s.depth[i] = hit.t
                s.glow[i] = paint.glow
                hitPrim[i] = hit.prim
            }
        }
        if m.outline { ink(&s, hitPrim) }
        return s
    }

    /// Lighting and surface texture for one pixel.
    private static func shade(_ p: Paint, _ pos: V3, _ n: V3, _ rng: inout SplitMix64) -> Col {
        var base = p.base * (1 + (rng.float() - 0.5) * 2 * p.jitter)
        let h = Hash.unit(77, Int(pos.x * 4), Int(pos.y * 4), Int(pos.z * 4))
        switch p.grain {
        case .none: break
        case let .wood(axis):
            let along = axis == 0 ? pos.y + pos.z * 0.3 : (axis == 1 ? pos.x + pos.z * 0.3 : pos.x + pos.y)
            let g = sin(along * 2.1 + sin(along * 0.37) * 2)
            base *= 0.9 + 0.1 * g
            if g > 0.93 { base *= 0.78 }
        case .bark:
            let g = sin(atan2(n.y, n.x) * 9 + pos.z * 0.4)
            base *= g > 0.55 ? 0.7 : (0.92 + Float(h) * 0.14)
        case .leaves:
            let r = Float(h)
            base *= r < 0.2 ? 0.62 : (r < 0.75 ? 0.95 : 1.22)
            if r > 0.97 { base = mix(base, Col(0.9, 0.95, 0.6), 0.4) }
        case .stone:
            base *= 0.86 + Float(h) * 0.28
        case .metal:
            base *= 0.9 + Float(h) * 0.12
        case .cloth:
            base *= (Int(pos.x * 2 + pos.z * 2) % 2 == 0) ? 0.95 : 1.03
        case .straw:
            base *= 0.8 + Float(Hash.unit(5, Int(pos.x * 3), Int(pos.y * 3), Int(pos.z))) * 0.4
        case .fire:
            break
        case .water:
            base *= 0.9 + Float(h) * 0.25
        case .hair:
            base *= 0.85 + 0.25 * (0.5 + 0.5 * sin(pos.x * 3 + pos.y * 2))
        }
        if p.glow { return base }
        let key = max(0, simd_dot(n, light))
        let fill = max(0, n.x) * 0.16 + max(0, n.y) * 0.05
        var lit = 0.46 + 0.62 * key + fill
        lit = (lit * 14).rounded() / 14
        var c = base * lit
        if p.shine > 0 {
            let hv = simd_normalize(light + simd_normalize(V3(1, 1, 1)))
            let sp = pow(max(0, simd_dot(n, hv)), 18) * p.shine
            c += Col(repeating: sp)
        }
        return c
    }

    /// Dark outline round the silhouette and along creases where depth jumps.
    private static func ink(_ s: inout Sprite, _ prim: [Int]) {
        let w = s.w, h = s.h
        let px = s.px, depth = s.depth
        let edge = rgb(0x140C08)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if px[i] >> 24 == 0 {
                    var near: Float = -1000
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = ny * w + nx
                        if px[j] >> 24 != 0 && !s.glow[j] { near = max(near, depth[j]) }
                    }
                    if near > -1000 { s.px[i] = edge; s.depth[i] = near - 0.5 }
                } else {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = ny * w + nx
                        if px[j] >> 24 != 0 && depth[j] - depth[i] > 3.5 && prim[j] != prim[i] {
                            s.px[i] = pack(unpack(px[i]) * 0.38)
                            break
                        }
                    }
                }
            }
        }
    }

    /// The model's shadow on flat ground (ground coordinates equal screen ones there).
    static func shadow(_ m: Model) -> Sprite? {
        guard m.shadow, !m.prims.isEmpty else { return nil }
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = -lo
        for p in m.prims {
            let (a, b) = bounds(p.shape)
            lo = simd_min(lo, a); hi = simd_max(hi, b)
        }
        guard hi.z > 1 else { return nil }
        // Ground points whose path towards the light passes through the model.
        let reach = hi.z / shadowLight.z
        let gx0 = Int((lo.x - 1).rounded(.down)), gy0 = Int((lo.y - 1).rounded(.down))
        let gx1 = Int((hi.x - shadowLight.x * reach + 1).rounded(.up)), gy1 = Int((hi.y - shadowLight.y * reach + 1).rounded(.up))
        var s = Sprite(w: max(1, gx1 - gx0), h: max(1, gy1 - gy0), ax: -gx0, ay: -gy0)
        let dir = shadowLight / shadowLight.z
        var any = false
        for y in 0..<s.h {
            for x in 0..<s.w {
                let g = V3(Float(x + gx0) + 0.5, Float(y + gy0) + 0.5, 0)
                for p in m.prims {
                    if case .ellipsoid = p.shape, p.paint.glow { continue }
                    if p.paint.glow { continue }
                    if let (t, _) = intersect(p.shape, g, dir), t > 0.3 {
                        s.px[y * s.w + x] = UInt32(m.shadowAlpha * 255) << 24
                        any = true
                        break
                    }
                }
            }
        }
        // Soften the edge.
        var soft = s.px
        for y in 1..<max(1, s.h - 1) {
            for x in 1..<max(1, s.w - 1) {
                var sum: UInt32 = 0
                for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] { sum += s.px[(y + dy) * s.w + x + dx] >> 24 }
                soft[y * s.w + x] = (sum / 5) << 24
            }
        }
        s.px = soft
        return any ? s : nil
    }
}
