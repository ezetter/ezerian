import Foundation
import simd

/// Furnishings for taverns, inns, shops, temples and homes. Tall pieces stand
/// against the north wall, whose face is the tile's top edge (y = 0).
enum FurnitureArt {
    static let oak = Paint(0x8A5A30, .wood(0), jitter: 0.05)
    static let oakY = Paint(0x8A5A30, .wood(1), jitter: 0.05)
    static let dark = Paint(0x5A3620, .wood(0), jitter: 0.05)
    static let darkY = Paint(0x5A3620, .wood(1), jitter: 0.05)
    static let red = Paint(0xA82424, .cloth)
    static let blue = Paint(0x2A3A9A, .cloth)
    static let iron = Paint(0x34343A, .metal, shine: 0.35)
    static let pewter = Paint(0xA0A4AC, .metal, shine: 0.5)
    static let stone = Paint(0x9A968E, .stone)
    static let candle = Paint(0xF0EAD8, jitter: 0.02)

    static func recipe(_ f: Feature) -> Recipe? {
        switch f {
        case .table: return Recipe(variants: 2) { _, v, _ in table(marble: v == 1) }
        case .tableMug: return Recipe(variants: 2) { _, v, _ in withMugs(table(marble: v == 1)) }
        case .tableFood: return Recipe(variants: 2) { _, v, _ in withFood(table(marble: v == 1)) }
        case .tableCandle: return Recipe(variants: 2, frames: 4) { _, v, fr in withCandle(table(marble: v == 1), frame: fr) }
        case .chair: return Recipe(variants: 4) { _, v, _ in chair(facingEast: v % 2 == 0, cushion: v < 2 ? red : blue) }
        case .stool: return Recipe { _, _, _ in stool() }
        case .bed: return Recipe(variants: 3) { _, v, _ in bed(blanket: [0x3A6A2A, 0x9A2A2A, 0x2A4A9A][v]) }
        case .barrel: return Recipe { _, _, _ in barrel() }
        case .keg: return Recipe { _, _, _ in keg() }
        case .counter: return Recipe(variants: 4) { _, v, _ in counter(left: v & 1 != 0, right: v & 2 != 0) }
        case .fireplace: return Recipe(frames: 4) { _, _, fr in fireplace(frame: fr) }
        case .bookshelf: return Recipe(variants: 2) { r, _, _ in bookshelf(&r, goods: false) }
        case .shelf: return Recipe(variants: 2) { r, _, _ in bookshelf(&r, goods: true) }
        case .chest: return Recipe { _, _, _ in chest() }
        case .candelabra: return Recipe(frames: 4) { _, _, fr in candelabra(frame: fr) }
        case .anvil: return Recipe { _, _, _ in anvil() }
        case .forge: return Recipe(frames: 4) { _, _, fr in forge(frame: fr) }
        case .crate: return Recipe { _, _, _ in crate() }
        case .sack: return Recipe(variants: 2) { r, _, _ in sack(&r) }
        case .pew: return Recipe(variants: 4) { _, v, _ in pew(left: v & 1 != 0, right: v & 2 != 0) }
        case .altar: return Recipe(frames: 4) { _, _, fr in altar(frame: fr) }
        case .throne: return Recipe { _, _, _ in throne() }
        case .plant: return Recipe(variants: 2) { r, _, _ in plant(&r) }
        case .wardrobe: return Recipe { _, _, _ in wardrobe() }
        case .weaponRack: return Recipe { _, _, _ in weaponRack() }
        case .nightstand: return Recipe(frames: 4) { _, _, fr in nightstand(frame: fr) }
        case .harpsichord: return Recipe { _, _, _ in harpsichord() }
        case .cauldron: return Recipe(frames: 4) { _, _, fr in cauldron(frame: fr) }
        default: return nil
        }
    }

    static func table(marble: Bool) -> Model {
        var m = Model()
        for (x, y) in [(Float(5), Float(8)), (27, 8), (5, 24), (27, 24)] { m.box(x - 1.2, y - 1.2, 0, x + 1.2, y + 1.2, 11, dark) }
        m.box(4, 7, 9, 28, 25, 11.5, dark)
        m.box(3, 6, 11.5, 29, 26, 13, oak)
        if marble { m.box(5, 8, 13, 27, 24, 13.4, Paint(0x8A8E92, .stone, jitter: 0.1, shine: 0.3)) }
        return m
    }

    static func withMugs(_ t: Model) -> Model {
        var m = t
        for (x, y) in [(Float(10), Float(12)), (21, 19)] {
            m.cyl(x, y, 1.7, 13, 17, pewter)
            m.cyl(x, y, 1.3, 17, 17.2, Paint(0xC08A30))
            m.box(x + 1.5, y - 0.5, 14, x + 2.8, y + 0.5, 16, pewter)
        }
        m.cyl(16, 14, 3.2, 13, 13.5, Paint(0xE8E4DA, shine: 0.3))
        return m
    }

    static func withFood(_ t: Model) -> Model {
        var m = t
        m.cyl(12, 15, 4, 13, 13.6, Paint(0xE8E4DA, shine: 0.3))
        m.blob(12, 15, 15, 3, 2.2, 1.8, Paint(0xB86A2A))
        m.cyl(21, 18, 3.6, 13, 13.6, Paint(0xE8E4DA, shine: 0.3))
        m.ball(21, 18, 14.8, 1.6, Paint(0xD8B030))
        m.blob(23, 12, 14.2, 2.4, 1.2, 1, Paint(0xC88A40))
        return m
    }

    static func withCandle(_ t: Model, frame: Int) -> Model {
        var m = t
        m.cyl(16, 16, 2.2, 13, 14, pewter)
        m.cyl(16, 16, 0.9, 14, 19, candle)
        StructureArt.flames(&m, 16, 16, 19, size: 1.2, frame: frame)
        return m
    }

    static func chair(facingEast: Bool, cushion: Paint) -> Model {
        var m = Model()
        for (x, y) in [(Float(10), Float(10)), (22, 10), (10, 24), (22, 24)] { m.box(x - 1, y - 1, 0, x + 1, y + 1, 8, dark) }
        m.box(9, 9, 7, 23, 25, 9, oak)
        m.box(10, 10, 9, 22, 24, 9.8, cushion)
        let bx: Float = facingEast ? 8.5 : 21.5
        m.box(bx, 9, 9, bx + 2, 25, 21, oakY)
        m.box(bx + (facingEast ? 0.8 : -0.4), 11, 12, bx + (facingEast ? 2.4 : 1.2), 23, 19, cushion)
        return m
    }

    static func stool() -> Model {
        var m = Model()
        for (x, y) in [(Float(12), Float(13)), (20, 13), (16, 21)] { m.rod(V3(x, y, 0), V3(16, 17, 7), 0.9, dark) }
        m.cyl(16, 17, 5.5, 7, 9, oak)
        return m
    }

    /// A bed two tiles long, drawn from the head tile.
    static func bed(blanket: UInt32) -> Model {
        var m = Model()
        m.box(3, 1, 0, 29, 4, 17, darkY)
        m.box(3, 3, 0, 29, 60, 6, dark)
        m.box(4, 4, 6, 28, 59, 10, Paint(0xEEEAE0, .cloth))
        m.blob(16, 10, 10.5, 9, 4, 2, Paint(0xFAF8F0, .cloth))
        m.box(4, 20, 9.8, 28, 59, 11, Paint(blanket, .cloth))
        m.box(3.5, 20, 6, 4.2, 59, 10.6, Paint(col: hex(blanket) * 0.8))
        m.box(27.8, 20, 6, 28.5, 59, 10.6, Paint(col: hex(blanket) * 0.8))
        m.box(3, 58, 0, 29, 61, 11, darkY)
        return m
    }

    static func barrel() -> Model {
        var m = Model()
        m.cone(16, 17, 7.5, 7.5, 0, 18, Paint(0x8A5A2E, .wood(2), jitter: 0.06))
        m.cone(16, 17, 8.3, 8.3, 7, 11, Paint(0x8A5A2E, .wood(2), jitter: 0.06))
        for z: Float in [2.5, 14] { m.cyl(16, 17, 8.1, z, z + 1.6, iron) }
        m.cyl(16, 17, 6.8, 18, 18.3, Paint(0xA87A44, .wood(0)))
        return m
    }

    static func keg() -> Model {
        var m = Model()
        for x: Float in [9, 23] { m.box(x - 1.5, 9, 0, x + 1.5, 25, 4, dark) }
        m.logY(16, 10.5, 7, 5, 28, Paint(0x8A5A2E, .wood(1), jitter: 0.06))
        m.logY(16, 10.5, 7.6, 10, 21, Paint(0x9A6834, .wood(1), jitter: 0.06))
        for y: Float in [7.5, 24.5] { m.logY(16, 10.5, 7.4, y, y + 1.4, iron) }
        m.logY(16, 10.5, 5.6, 28, 28.4, Paint(0xA87A44, .wood(0)))
        m.box(15, 28, 8, 17, 30.5, 9.5, Paint(0xC8A040, .metal, shine: 0.5))
        return m
    }

    static func counter(left: Bool, right: Bool) -> Model {
        var m = Model()
        let x0: Float = left ? 0 : 3, x1: Float = right ? 32 : 29
        m.box(x0, 9, 0, x1, 23, 12, Paint(0x7A3A1C, .wood(0)))
        m.box(x0, 8, 12, x1, 24, 14.5, Paint(0x8E4A22, .wood(0), shine: 0.35))
        m.box(x0, 10, 14.5, x1, 22, 14.8, Paint(0x5A2810, .wood(0), shine: 0.3))
        for x in stride(from: x0 + 3, to: x1 - 1, by: 7) { m.box(x, 22.8, 2, x + 5, 23.3, 10, Paint(0x6A3018, .wood(1))) }
        return m
    }

    static func fireplace(frame: Int) -> Model {
        var m = Model()
        m.box(2, 0, 0, 30, 9, 30, Paint(0xA04A2A, .stone))
        m.box(0, 0, 18, 32, 11, 21, stone)
        m.box(7, 8.6, 1, 25, 9.4, 15, Paint(0x140C08))
        m.box(6, 9, 0, 26, 13, 1.5, stone)
        m.rod(V3(10, 7, 2), V3(22, 8, 3), 1.4, NatureArt.bark)
        StructureArt.flames(&m, 16, 7.5, 2.5, size: 3.8, frame: frame)
        return m
    }

    static func bookshelf(_ rng: inout SplitMix64, goods: Bool) -> Model {
        var m = Model()
        m.box(2, 0, 0, 30, 9, 27, darkY)
        m.box(3.5, 8.6, 2, 28.5, 9.2, 25.5, Paint(0x2A1A0E))
        let colors: [UInt32] = goods ? [0xC89A50, 0x9A6A3A, 0x6A8A4A, 0xD8C8A0, 0xA0402A] : [0x8A2A1E, 0x2A4A8A, 0x3A6A2A, 0x8A6A2A, 0x5A2A6A, 0x6A3A1E]
        for shelf in 0..<4 {
            let z = 2 + Float(shelf) * 6
            m.box(3, 1, z - 1, 29, 9.4, z, Paint(0x5A3620, .wood(0)))
            var x: Float = 4
            while x < 27 {
                if goods {
                    let w = rng.range(3, 5)
                    if rng.chance(0.5) { m.cyl(x + w / 2, 6, w / 2, z, z + rng.range(3, 5), Paint(rng.pick(colors), shine: 0.3)) }
                    else { m.blob(x + w / 2, 6, z + 2, w / 2, 2, 2, Paint(rng.pick(colors), .cloth)) }
                    x += w + 0.8
                } else {
                    let w = rng.range(1.2, 2.2)
                    m.box(x, 3, z, x + w, 9, z + rng.range(3.6, 5), Paint(rng.pick(colors), jitter: 0.05))
                    x += w + 0.25
                }
            }
        }
        return m
    }

    static func chest() -> Model {
        var m = Model()
        let w = Paint(0x7A4A24, .wood(0))
        m.box(6, 11, 0, 26, 24, 10, w)
        m.box(6, 11, 10, 26, 24, 11, Paint(0x5A3418))
        m.blob(16, 17.5, 11, 10, 6.5, 3, w)
        for x: Float in [9, 22] { m.box(x, 10.8, 0, x + 1.4, 24.3, 13.8, iron) }
        m.box(15, 24, 6, 17, 24.6, 9, Paint(0xD8A830, .metal, shine: 0.6))
        return m
    }

    static func candelabra(frame: Int) -> Model {
        var m = Model()
        let g = Paint(0xC89A34, .metal, shine: 0.6)
        m.cyl(16, 18, 4, 0, 1.5, g)
        m.cyl(16, 18, 0.9, 1.5, 20, g)
        m.rod(V3(10, 18, 20), V3(22, 18, 20), 0.8, g)
        for x: Float in [10, 16, 22] {
            m.cyl(x, 18, 0.9, 20, 24, candle)
            StructureArt.flames(&m, x, 18, 24, size: 1.1, frame: frame + Int(x))
        }
        return m
    }

    static func anvil() -> Model {
        var m = Model()
        let a = Paint(0x3E3E46, .metal, shine: 0.45)
        m.box(11, 13, 0, 21, 21, 3, Paint(0x5A3A20, .wood(2)))
        m.box(12.5, 14, 3, 19.5, 20, 9, a)
        m.box(9, 13, 9, 23, 21, 12, a)
        m.rod(V3(23, 17, 10.8), V3(28, 17, 11.5), 1.4, a)
        return m
    }

    static func forge(frame: Int) -> Model {
        var m = Model()
        m.box(2, 0, 0, 30, 14, 12, Paint(0x8A847A, .stone))
        m.box(5, 2, 12, 27, 12, 12.4, Paint(0x2A1A10))
        let glow: [Float] = [1, 0.9, 1.1, 0.95]
        for k in 0..<7 {
            m.ball(8 + Float(k) * 2.7, 6 + Float(k % 3) * 1.8, 12.5, 1.6 * glow[(frame + k) % 4], Paint(k % 2 == 0 ? 0xF07020 : 0xF8B040, glow: true))
        }
        m.box(4, 0, 22, 28, 12, 26, Paint(0x5A5650, .stone))
        m.box(10, 0, 26, 22, 7, 36, Paint(0x6A6660, .stone))
        return m
    }

    static func crate() -> Model {
        var m = Model()
        let w = Paint(0xA07A48, .wood(0))
        m.box(8, 10, 0, 24, 25, 13, w)
        for (a, b) in [(Float(8), Float(9.5)), (22.5, 24)] {
            m.box(a, 9.8, 0, b, 25.2, 13.2, Paint(0x7A5430, .wood(2)))
            m.box(7.8, 9.8, a - 8, 24.2, 25.2, b - 8 + 0.2, Paint(0x7A5430, .wood(0)))
        }
        m.box(7.8, 9.8, 11.5, 24.2, 25.2, 13.2, Paint(0x7A5430, .wood(0)))
        return m
    }

    static func sack(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        let burlap = Paint(0xB8A070, .cloth, jitter: 0.08)
        m.blob(16, 18, 6, 6.5, 6, 6.5, burlap)
        m.blob(16, 18, 12.5, 3, 3, 2, burlap)
        m.cyl(16, 18, 2, 11, 12, Paint(0x6A4A2A))
        return m
    }

    static func pew(left: Bool, right: Bool) -> Model {
        var m = Model()
        let x0: Float = left ? 0 : 3, x1: Float = right ? 32 : 29
        m.box(x0, 10, 7, x1, 22, 9, Paint(0x7A2A1E, .wood(0)))
        m.box(x0, 21, 7, x1, 24, 20, Paint(0x6A2418, .wood(0)))
        if !left { m.box(3, 10, 0, 5, 24, 13, Paint(0x5A1E14, .wood(1))) }
        if !right { m.box(27, 10, 0, 29, 24, 13, Paint(0x5A1E14, .wood(1))) }
        return m
    }

    static func altar(frame: Int) -> Model {
        var m = Model()
        m.box(4, 6, 0, 28, 20, 13, Paint(0xC8C2B4, .stone))
        m.box(3.5, 5.5, 10, 28.5, 20.5, 13.6, Paint(0xF4F0E4, .cloth))
        m.box(13, 20.5, 4, 19, 20.8, 13.6, Paint(0xC8A030))
        m.box(14.5, 11, 13.6, 17.5, 14, 22, Paint(0xD8B040, .metal, shine: 0.6))
        m.box(12, 11, 18, 20, 14, 19.5, Paint(0xD8B040, .metal, shine: 0.6))
        for x: Float in [7, 25] {
            m.cyl(x, 12, 0.9, 13.6, 18, candle)
            StructureArt.flames(&m, x, 12, 18, size: 1.1, frame: frame + Int(x))
        }
        return m
    }

    static func throne() -> Model {
        var m = Model()
        let g = Paint(0xC89A34, .metal, shine: 0.5)
        m.box(6, 6, 0, 26, 26, 10, g)
        m.box(8, 8, 10, 24, 24, 11.5, red)
        m.box(6, 4, 10, 26, 8, 34, g)
        m.box(9, 7.6, 13, 23, 8.4, 31, red)
        for x: Float in [6, 26] { m.box(x - 1.5, 8, 10, x + 1.5, 26, 16, g) }
        return m
    }

    static func plant(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.cone(16, 18, 4.2, 5.5, 0, 8, Paint(0xB0603A))
        m.cyl(16, 18, 4.8, 7.6, 8, Paint(0x3A2414))
        for k in 0..<8 {
            let a = Float(k) / 8 * 2 * .pi + rng.range(-0.3, 0.3)
            let tip = V3(16 + cos(a) * 8, 18 + sin(a) * 7, rng.range(12, 18))
            m.rod(V3(16, 18, 8), tip, 1.1, NatureArt.leaves(0x3E8A2E, &rng))
        }
        return m
    }

    static func wardrobe() -> Model {
        var m = Model()
        m.box(3, 0, 0, 29, 11, 28, darkY)
        m.box(2, 0, 27, 30, 12, 30, Paint(0x4A2C18, .wood(0)))
        m.box(4.5, 10.9, 3, 27.5, 11.1, 25, Paint(0x6A4228, .wood(1)))
        m.box(15.6, 10.8, 3, 16.4, 11.3, 25, Paint(0x2A1A0E))
        for x: Float in [13.5, 18.5] { m.box(x, 11, 13, x + 1, 11.8, 16, Paint(0xD8A830, .metal, shine: 0.6)) }
        return m
    }

    static func weaponRack() -> Model {
        var m = Model()
        m.box(3, 1, 0, 29, 5, 3, dark)
        m.box(3, 1, 24, 29, 5, 26, dark)
        for x: Float in [3, 27] { m.box(x, 1, 0, x + 2, 5, 26, dark) }
        for (k, x) in [Float(8), 13, 18, 23].enumerated() {
            if k % 2 == 0 {
                m.box(x - 0.6, 4, 3, x + 0.6, 5, 24, Paint(0xD0D4DC, .metal, shine: 0.8))
                m.box(x - 2, 4, 18, x + 2, 5.2, 19, Paint(0xC89A34))
            } else {
                m.rod(V3(x, 4.5, 3), V3(x, 4.5, 23), 0.6, Paint(0x8A6A3A))
                m.cone(x, 4.5, 1.4, 0, 23, 27, Paint(0xC0C4CC, .metal, shine: 0.7))
            }
        }
        return m
    }

    static func nightstand(frame: Int) -> Model {
        var m = Model()
        m.box(9, 4, 0, 23, 16, 13, oak)
        m.box(10, 15.8, 6, 22, 16.2, 11, Paint(0x6A4228))
        m.box(15, 16, 8, 17, 16.6, 9, Paint(0xD8A830))
        m.cyl(16, 10, 0.9, 13, 17, candle)
        StructureArt.flames(&m, 16, 10, 17, size: 1.1, frame: frame)
        return m
    }

    static func harpsichord() -> Model {
        var m = Model()
        let w = Paint(0x3A2414, .wood(0), shine: 0.3)
        for (x, y) in [(Float(5), Float(4)), (27, 4), (5, 14), (27, 14)] { m.box(x - 1, y - 1, 0, x + 1, y + 1, 10, w) }
        m.box(3, 1, 10, 29, 16, 15, w)
        m.box(4, 13, 14, 28, 17, 15.5, Paint(0xF4F0E4))
        for x in stride(from: Float(5), to: 27, by: 2.4) { m.box(x, 13, 15.5, x + 1, 15, 16.2, Paint(0x1A1410)) }
        m.box(3, 1, 15, 29, 3, 28, Paint(0x4A2E1A, .wood(0), shine: 0.3))
        m.box(5, 2.8, 17, 27, 3.2, 26, Paint(0xC8A040))
        return m
    }

    static func cauldron(frame: Int) -> Model {
        var m = Model()
        let pot = Paint(0x2A2A2E, .metal, shine: 0.35)
        for k in 0..<3 {
            let a = Float(k) / 3 * 2 * .pi
            m.rod(V3(16 + cos(a) * 6, 17 + sin(a) * 6, 0), V3(16 + cos(a) * 5, 17 + sin(a) * 5, 4), 1, pot)
        }
        m.blob(16, 17, 9, 8.5, 8.5, 6.5, pot)
        m.cyl(16, 17, 8, 13, 14.5, pot)
        m.cyl(16, 17, 6.8, 14.5, 14.7, Paint(0x5AA03A, glow: true))
        let b: [Float] = [0, 1, 2, 1]
        m.ball(14 + b[frame % 4], 16, 15, 1.2, Paint(0x8AD06A, glow: true))
        m.ball(18, 18 - b[frame % 4] * 0.5, 15, 0.9, Paint(0x8AD06A, glow: true))
        return m
    }
}
