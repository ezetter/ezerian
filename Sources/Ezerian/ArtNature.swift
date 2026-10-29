import Foundation
import simd

/// Trees, bushes, rocks and flowers, modelled for the ray tracer. Each takes a
/// random stream so every variant grows a little differently.
enum NatureArt {
    static let bark = Paint(0x5A3A22, .bark, jitter: 0.08)
    static let darkBark = Paint(0x3E2A1A, .bark, jitter: 0.08)
    static let stone = Paint(0x8E8A84, .stone, jitter: 0.06)

    static func leaves(_ hexColor: UInt32, _ rng: inout SplitMix64) -> Paint {
        Paint(col: hex(hexColor) * rng.range(0.88, 1.1), .leaves, jitter: 0.05)
    }

    /// A rounded crown of leaf clusters around (cx, cy, cz).
    static func crown(_ m: inout Model, _ rng: inout SplitMix64, cx: Float, cy: Float, cz: Float,
                      spread: Float, count: Int, rMin: Float, rMax: Float, colors: [UInt32]) {
        for k in 0..<count {
            let a = rng.range(0, 2 * .pi), d = spread * rng.float().squareRoot()
            let x = cx + cos(a) * d, y = cy + sin(a) * d * 0.9
            let z = cz + rng.range(-0.5, 0.6) * spread * 0.55 + (k < 3 ? spread * 0.25 : 0)
            m.ball(x, y, z, rng.range(rMin, rMax), leaves(rng.pick(colors), &rng))
        }
    }

    static func oak(_ rng: inout SplitMix64, colors: [UInt32] = [0x3E7A26, 0x4A8A2C, 0x356A20, 0x56922E]) -> Model {
        var m = Model()
        m.seed = rng.next()
        let tx: Float = 17, ty: Float = 19
        m.cone(tx, ty, 3.8, 2.6, 0, 14, bark)
        for _ in 0..<3 {
            let a = rng.range(0, 2 * .pi)
            m.rod(V3(tx, ty, 10), V3(tx + cos(a) * 7, ty + sin(a) * 6, 17 + rng.range(0, 3)), 1.4, bark)
        }
        crown(&m, &rng, cx: tx - 1, cy: ty - 1, cz: 22, spread: 11.5, count: 18, rMin: 5.8, rMax: 8.8, colors: colors)
        return m
    }

    static func blossom(_ rng: inout SplitMix64) -> Model {
        var m = oak(&rng, colors: [0xE07A9A, 0xF0A0B8, 0xD86488, 0xF6C4D0])
        for _ in 0..<10 {
            m.ball(rng.range(6, 26), rng.range(8, 28), rng.range(22, 32), 0.9, Paint(0xFFF0F4, jitter: 0.02))
        }
        return m
    }

    static func apple(_ rng: inout SplitMix64) -> Model {
        var m = oak(&rng, colors: [0x3E7A26, 0x4A8A2C, 0x46802A])
        for _ in 0..<12 {
            let a = rng.range(0, 2 * .pi), d = rng.range(5, 13)
            m.ball(16 + cos(a) * d, 18 + sin(a) * d, rng.range(20, 30), 1.3, Paint(0xD02A1E, shine: 0.5))
        }
        return m
    }

    static func pine(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        let tx: Float = 16, ty: Float = 18
        let g = leaves(rng.pick([0x1E4A24, 0x24552A, 0x1A4220]), &rng)
        let g2 = Paint(col: g.base * 1.18, .leaves, jitter: 0.05)
        m.cyl(tx, ty, 2.4, 0, 9, darkBark)
        let h = rng.range(0.9, 1.1)
        m.cone(tx, ty, 12, 3, 5, 17 * h, g)
        m.cone(tx, ty, 10, 2, 13 * h, 25 * h, g2)
        m.cone(tx, ty, 7.5, 1, 20 * h, 32 * h, g)
        m.cone(tx, ty, 4.5, 0, 27 * h, 39 * h, g2)
        return m
    }

    static func birch(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        let tx: Float = 16, ty: Float = 19
        m.cone(tx, ty, 2.2, 1.6, 0, 22, Paint(0xE8E4D8, .bark, jitter: 0.05))
        for z in stride(from: Float(3), to: 20, by: 5) { m.box(tx - 2.3, ty - 2.3, z, tx + 2.3, ty + 2.3, z + 0.9, Paint(0x2A2622)) }
        crown(&m, &rng, cx: tx, cy: ty, cz: 25, spread: 8, count: 13, rMin: 4.2, rMax: 6.8, colors: [0x7AA23A, 0x8CB244, 0x6A9232])
        return m
    }

    static func palm(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        var p = V3(16, 20, 0)
        let lean = V3(rng.range(-0.25, 0.25), rng.range(-0.1, 0.25), 1)
        for k in 0..<5 {
            let q = p + lean * 4.8 + V3(Float(k) * 0.1, 0, 0)
            m.rod(p, q, 2.1 - Float(k) * 0.12, Paint(0x8A6A3E, .bark, jitter: 0.08))
            p = q
        }
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi + rng.range(-0.2, 0.2)
            let tip = p + V3(cos(a) * 17, sin(a) * 15, -7)
            let mid = (p + tip) / 2 + V3(0, 0, 3.5)
            m.rod(p, mid, 2.2, leaves(0x4A8A2A, &rng))
            m.rod(mid, tip, 1.7, leaves(0x3E7A22, &rng))
        }
        m.ball(p.x, p.y, p.z - 1, 2.2, Paint(0x6A4A22))
        return m
    }

    static func deadTree(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        let wood = Paint(0x6E6258, .bark, jitter: 0.08)
        let tx: Float = 16, ty: Float = 19
        m.cone(tx, ty, 3, 1.6, 0, 22, wood)
        for k in 0..<5 {
            let a = Float(k) * 1.3 + rng.range(-0.3, 0.3)
            let z0 = rng.range(8, 18)
            let end = V3(tx + cos(a) * rng.range(7, 12), ty + sin(a) * rng.range(6, 10), z0 + rng.range(5, 9))
            m.rod(V3(tx, ty, z0), end, 1.1, wood)
            m.rod(end, end + V3(cos(a + 0.8) * 4, sin(a + 0.8) * 4, 3), 0.6, wood)
        }
        return m
    }

    static func bush(_ rng: inout SplitMix64, berries: UInt32? = nil) -> Model {
        var m = Model()
        m.seed = rng.next()
        crown(&m, &rng, cx: 16, cy: 18, cz: 6, spread: 6.5, count: 9, rMin: 3.6, rMax: 5.4, colors: [0x3E7226, 0x4A8030, 0x36662A])
        if let b = berries {
            for _ in 0..<9 {
                let a = rng.range(0, 2 * .pi), d = rng.range(2, 7)
                m.ball(16 + cos(a) * d, 18 + sin(a) * d, rng.range(6, 11), 0.9, Paint(b, shine: 0.5))
            }
        }
        return m
    }

    static func rock(_ rng: inout SplitMix64, big: Bool) -> Model {
        var m = Model()
        m.seed = rng.next()
        let s: Float = big ? 1.7 : 1
        let tone = Paint(col: hex(0x8C8880) * rng.range(0.85, 1.1), .stone, jitter: 0.07)
        m.blob(16, 18, 2.5 * s, 6 * s, 4.6 * s, 4 * s, tone)
        m.blob(16 + 3 * s, 19 + 1 * s, 2 * s, 3.6 * s, 3.2 * s, 2.8 * s, tone)
        if big { m.blob(12, 16, 4, 5, 4, 5, tone) }
        return m
    }

    static func standingStone(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.blob(16, 18, 13, 5.2, 4.2, 14, Paint(col: hex(0x9A968E) * rng.range(0.9, 1.08), .stone, jitter: 0.06))
        return m
    }

    static func flowers(_ rng: inout SplitMix64, color: UInt32) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        for _ in 0..<7 {
            let x = rng.range(7, 25), y = rng.range(9, 27), h = rng.range(2.5, 5)
            m.rod(V3(x, y, 0), V3(x, y, h), 0.45, Paint(0x3E7226))
            m.ball(x, y, h + 0.6, 1.3, Paint(col: hex(color) * rng.range(0.9, 1.1), shine: 0.2))
        }
        return m
    }

    static func fern(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        for k in 0..<7 {
            let a = Float(k) / 7 * 2 * .pi + rng.range(-0.2, 0.2)
            m.rod(V3(16, 18, 1), V3(16 + cos(a) * 7, 18 + sin(a) * 6, 3.5), 1.1, leaves(0x4A7A2A, &rng))
        }
        return m
    }

    static func mushrooms(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        for _ in 0..<4 {
            let x = rng.range(9, 23), y = rng.range(11, 25)
            m.cyl(x, y, 0.8, 0, 2.5, Paint(0xE8DCC4))
            m.blob(x, y, 3, 2.2, 2.2, 1.2, Paint(rng.chance(0.5) ? 0xC8281E : 0xB08050, shine: 0.3))
        }
        return m
    }

    static func cactus(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        let g = Paint(0x5A8A4A, jitter: 0.06)
        m.rod(V3(16, 18, 0), V3(16, 18, 24), 3.2, g)
        m.rod(V3(16, 18, 9), V3(10, 18, 11), 2, g)
        m.rod(V3(10, 18, 11), V3(10, 18, 17), 2, g)
        m.rod(V3(16, 18, 13), V3(21, 18, 15), 1.8, g)
        m.rod(V3(21, 18, 15), V3(21, 18, 21), 1.8, g)
        return m
    }

    static func reeds(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        for _ in 0..<9 {
            let x = rng.range(8, 24), y = rng.range(10, 26), h = rng.range(8, 14)
            m.rod(V3(x, y, 0), V3(x + rng.range(-1.5, 1.5), y, h), 0.5, Paint(0x6A8A3A))
            if rng.chance(0.5) { m.blob(x, y, h - 1, 0.8, 0.8, 2, Paint(0x6A4222)) }
        }
        return m
    }

    static func lilyPad(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        for _ in 0..<3 {
            m.blob(rng.range(9, 23), rng.range(11, 25), 0.2, 3.5, 3, 0.3, Paint(0x3E8A3A))
        }
        m.ball(16, 18, 1, 1.2, Paint(0xF4E8F0))
        return m
    }

    static func stump(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.cyl(16, 18, 5, 0, 5, bark)
        m.cyl(16, 18, 4.2, 5, 5.3, Paint(0xB08A5A, .wood(2)))
        return m
    }

    static func deadBranch(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.seed = rng.next()
        m.shadow = false
        m.outline = false
        let bone = Paint(0xD8D4C8, jitter: 0.05)
        let a = V3(rng.range(6, 10), rng.range(12, 22), 0.8)
        let b = V3(rng.range(20, 26), rng.range(12, 22), 1)
        m.rod(a, b, 0.9, bone)
        let mid = (a + b) / 2
        m.rod(mid, mid + V3(rng.range(-3, 3), -5, 0.5), 0.6, bone)
        m.rod(mid + V3(3, 0, 0), mid + V3(6, 4, 0.5), 0.6, bone)
        return m
    }
}
