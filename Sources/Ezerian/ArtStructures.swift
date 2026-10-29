import Foundation
import simd

/// Outdoor structures and things mounted on walls.
enum StructureArt {
    static let wood = Paint(0x8A5A30, .wood(0), jitter: 0.06)
    static let darkWood = Paint(0x5A3820, .wood(0), jitter: 0.06)
    static let stone = Paint(0x9A968E, .stone, jitter: 0.07)
    static let darkStone = Paint(0x6E6A64, .stone, jitter: 0.07)
    static let iron = Paint(0x3A3A40, .metal, shine: 0.3)
    static let gold = Paint(0xD8A830, .metal, shine: 0.6)
    static let straw = Paint(0xC8A450, .straw, jitter: 0.08)

    static let signIcons = ["tavern", "inn", "provisions", "smithy", "armory", "healer"]

    /// Flickering flames for frame `f` of 4 around a point.
    static func flames(_ m: inout Model, _ x: Float, _ y: Float, _ z: Float, size: Float, frame f: Int) {
        let wob: [Float] = [0, 0.6, -0.4, 0.3]
        let w = wob[f % 4]
        m.blob(x, y, z + size * 0.5, size * 0.75, size * 0.75, size * 0.7, Paint(0xE8501A, .fire, glow: true))
        m.blob(x + w * 0.5, y, z + size * (1.1 + w * 0.15), size * 0.5, size * 0.5, size * 0.75, Paint(0xF8A030, .fire, glow: true))
        m.blob(x - w * 0.4, y, z + size * (1.6 + w * 0.2), size * 0.28, size * 0.28, size * 0.5, Paint(0xFFE890, .fire, glow: true))
    }

    static func recipe(_ f: Feature) -> Recipe? {
        switch f {
        case .signpost: return Recipe { _, _, _ in signpost() }
        case .well: return Recipe { _, _, _ in well() }
        case .fountain: return Recipe(frames: 4) { _, _, fr in fountain(frame: fr) }
        case .lampPost: return Recipe { _, _, _ in lampPost() }
        case .fence: return Recipe(variants: 16) { _, v, _ in fence(mask: v) }
        case .gravestone: return Recipe(variants: 2) { r, _, _ in gravestone(&r) }
        case .graveCross: return Recipe { _, _, _ in graveCross() }
        case .shrine: return Recipe(frames: 4) { _, _, fr in shrine(frame: fr) }
        case .campfire: return Recipe(frames: 4) { r, _, fr in campfire(&r, frame: fr) }
        case .haystack: return Recipe(variants: 2) { r, _, _ in haystack(&r) }
        case .wheat: return Recipe(variants: 2) { r, _, _ in wheat(&r) }
        case .cabbage: return Recipe(variants: 2) { r, _, _ in cabbages(&r) }
        case .scarecrow: return Recipe { _, _, _ in scarecrow() }
        case .caveEntrance: return Recipe { _, _, _ in caveMouth() }
        case .ladderUp: return Recipe { _, _, _ in ladder() }
        case .tent: return Recipe { _, _, _ in tent() }
        case .logSeat: return Recipe { _, _, _ in logSeat() }
        case .rubble: return Recipe(variants: 3) { r, _, _ in rubble(&r) }
        case .brokenColumn: return Recipe(variants: 2) { r, _, _ in brokenColumn(&r) }
        case .hangingSign: return Recipe { _, _, _ in hangingSign(icon: "") }
        case .woodpile: return Recipe(variants: 2) { r, _, _ in woodpile(&r) }
        case .beehive: return Recipe { _, _, _ in beehive() }
        case .stocks: return Recipe { _, _, _ in stocks() }
        case .wallTorch: return Recipe(variants: 2, frames: 4) { _, v, fr in torch(east: v == 1, frame: fr) }
        case .banner: return Recipe(variants: 2) { _, v, _ in banner(east: v == 1) }
        case .painting: return Recipe(variants: 6) { r, v, _ in painting(&r, east: v % 2 == 1) }
        default: return nil
        }
    }

    static func signpost() -> Model {
        var m = Model()
        m.cyl(16, 20, 1.4, 0, 24, darkWood)
        m.box(6, 18.6, 15, 26, 21, 22, wood)
        for (z, w) in [(Float(19.5), Float(14)), (17.2, 10)] { m.box(9, 21, z, 9 + w, 21.3, z + 0.9, Paint(0x2A1A0C)) }
        return m
    }

    static func well() -> Model {
        var m = Model()
        m.cyl(16, 17, 11, 0, 9, stone)
        m.cyl(16, 17, 12, 8, 10, darkStone)
        m.cyl(16, 17, 8.5, 10, 10.2, Paint(0x101828))
        for x: Float in [5, 27] { m.box(x - 1.2, 15.8, 10, x + 1.2, 18.2, 26, darkWood) }
        m.rod(V3(5, 17, 22), V3(27, 17, 22), 1.3, wood)
        m.rod(V3(27, 17, 22), V3(30, 17, 19), 0.7, iron)
        m.box(2, 10, 26, 30, 17, 27.5, Paint(0x8A4A2A, .wood(1)))
        m.box(2, 17, 26, 30, 24, 27.5, Paint(0x7A4026, .wood(1)))
        m.box(15.5, 16.5, 12, 16.5, 17.5, 22, Paint(0x6A6A6A))
        m.box(13.5, 15, 10.5, 18.5, 19, 14, Paint(0x6A4426, .wood(2)))
        return m
    }

    static func fountain(frame: Int) -> Model {
        var m = Model()
        m.cyl(16, 16, 15, 0, 6, stone)
        m.cyl(16, 16, 15.6, 5, 7, darkStone)
        m.cyl(16, 16, 13, 7, 7.2, Paint(0x2A5ACC, .water, jitter: 0.1))
        m.cyl(16, 16, 2.6, 6, 17, stone)
        m.cyl(16, 16, 6, 15, 17.5, darkStone)
        m.cyl(16, 16, 5, 17.5, 17.7, Paint(0x3A6AD8, .water))
        let w: [Float] = [0, 0.5, 1, 0.5]
        for k in 0..<6 {
            let a = Float(k) / 6 * 2 * .pi + w[frame % 4] * 0.3
            m.rod(V3(16 + cos(a) * 5.5, 16 + sin(a) * 5.5, 17), V3(16 + cos(a) * 9, 16 + sin(a) * 9, 8), 0.6,
                  Paint(0xA8C8F8, jitter: 0.1, shine: 0.6))
        }
        m.ball(16, 16, 20 + w[frame % 4], 1.4, Paint(0xD0E4FF, shine: 0.8))
        return m
    }

    static func lampPost() -> Model {
        var m = Model()
        m.cyl(16, 20, 2.4, 0, 2, iron)
        m.cyl(16, 20, 0.9, 2, 26, iron)
        m.box(13, 17, 26, 19, 23, 32, Paint(0xFFD870, glow: true))
        for (x, y) in [(Float(13), Float(17)), (19, 17), (13, 23), (19, 23)] { m.box(x - 0.5, y - 0.5, 26, x + 0.5, y + 0.5, 32, iron) }
        m.cone(16, 20, 4.6, 0.5, 32, 35, iron)
        return m
    }

    static func fence(mask: Int) -> Model {
        var m = Model()
        let post = Paint(0x6A4A2C, .wood(2), jitter: 0.07)
        let rail = Paint(0x7A5432, .wood(0), jitter: 0.07)
        m.box(14.5, 14.5, 0, 17.5, 17.5, 13, post)
        for z: Float in [5, 10] {
            if mask & 2 != 0 { m.box(16, 15.2, z, 32, 16.8, z + 1.8, rail) }
            if mask & 8 != 0 { m.box(0, 15.2, z, 16, 16.8, z + 1.8, rail) }
            if mask & 1 != 0 { m.box(15.2, 0, z, 16.8, 16, z + 1.8, Paint(0x7A5432, .wood(1))) }
            if mask & 4 != 0 { m.box(15.2, 16, z, 16.8, 32, z + 1.8, Paint(0x7A5432, .wood(1))) }
        }
        return m
    }

    static func gravestone(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        let g = Paint(col: hex(0x8A8A86) * rng.range(0.9, 1.1), .stone)
        m.box(10, 16, 0, 22, 19, 11, g)
        m.blob(16, 17.5, 11, 6, 1.5, 3, g)
        m.box(12, 19, 6, 20, 19.3, 7, Paint(0x4A4A48))
        m.box(9, 19, 0, 23, 27, 0.8, Paint(0x5A4A30))
        return m
    }

    static func graveCross() -> Model {
        var m = Model()
        m.box(14.5, 16, 0, 17.5, 19, 18, stone)
        m.box(10, 16, 11, 22, 19, 14, stone)
        m.box(9, 19, 0, 23, 27, 0.8, Paint(0x5A4A30))
        return m
    }

    /// A stepped stone altar bearing a glowing gem, like the shrines of virtue.
    static func shrine(frame: Int) -> Model {
        var m = Model()
        m.box(6, 6, 0, 26, 26, 3, darkStone)
        m.box(8, 8, 3, 24, 24, 6, stone)
        m.box(10, 10, 6, 22, 22, 9, Paint(0xB0ACA4, .stone))
        let pulse: [Float] = [1, 1.1, 1.2, 1.1]
        m.blob(16, 16, 12, 2.4 * pulse[frame % 4], 2.4 * pulse[frame % 4], 3, Paint(0xE040C0, glow: true))
        m.ball(16, 16, 12, 1.2, Paint(0xFFC0F8, glow: true))
        return m
    }

    static func campfire(_ rng: inout SplitMix64, frame: Int) -> Model {
        var m = Model()
        for k in 0..<9 {
            let a = Float(k) / 9 * 2 * .pi
            m.blob(16 + cos(a) * 7, 17 + sin(a) * 6.5, 1.2, 2.2, 2, 1.6, darkStone)
        }
        m.rod(V3(11, 14, 1.5), V3(21, 20, 2.5), 1.3, NatureArt.bark)
        m.rod(V3(21, 14, 1.5), V3(11, 20, 2.5), 1.3, NatureArt.bark)
        flames(&m, 16, 17, 2.5, size: 4.2, frame: frame)
        return m
    }

    static func haystack(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.blob(16, 17, 6, 11, 10, 10, straw)
        m.blob(16, 17, 13, 6, 5.5, 5, straw)
        return m
    }

    static func wheat(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.shadow = false
        m.outline = false
        for row in 0..<5 {
            for k in 0..<9 {
                let x = Float(k) * 3.6 + rng.range(0, 2.5), y = Float(row) * 6.5 + rng.range(1, 4), h = rng.range(8, 11)
                let lean = rng.range(-1, 1)
                m.rod(V3(x, y, 0), V3(x + lean, y, h), 0.5, Paint(0xC8A848))
                m.blob(x + lean, y, h + 1.4, 1.1, 1, 2.4, Paint(col: hex(0xE8C458) * rng.range(0.9, 1.1), .straw))
            }
        }
        return m
    }

    static func cabbages(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        m.shadow = false
        for row in 0..<3 {
            for k in 0..<3 {
                let x = Float(k) * 10 + 6 + rng.range(-1, 1), y = Float(row) * 10 + 6 + rng.range(-1, 1)
                m.blob(x, y, 2.6, 3.6, 3.4, 2.8, Paint(0x6AA040, .leaves, jitter: 0.05))
                m.ball(x, y, 3.6, 2, Paint(0x9AC860, jitter: 0.04))
            }
        }
        return m
    }

    static func scarecrow() -> Model {
        var m = Model()
        m.leanX = 0.5
        m.cyl(16, 18, 1.1, 0, 26, darkWood)
        m.rod(V3(6, 18, 20), V3(26, 18, 20), 1, darkWood)
        m.box(11, 16, 11, 21, 20, 21, Paint(0x6A5A9A, .cloth))
        m.ball(16, 18, 24, 3.2, Paint(0xC8A86A, .straw))
        m.cone(16, 18, 5.5, 0.8, 26, 31, Paint(0x5A4A2A))
        for x: Float in [6, 26] { m.blob(x, 18, 18.5, 1.2, 1.2, 2, straw) }
        return m
    }

    /// A dark mouth in the cliff face, framed by tumbled rock.
    static func caveMouth() -> Model {
        var m = Model()
        m.shadow = false
        m.outline = false
        m.blob(16, 33, 0, 11, 1, 15, Paint(0x070403, jitter: 0.02))
        m.blob(16, 32.6, 0, 13, 1, 17, Paint(0x2A1E14, jitter: 0.04))
        m.blob(5, 34, 2, 4, 3, 3, darkStone)
        m.blob(28, 34, 1.5, 3.5, 3, 2.5, darkStone)
        return m
    }

    static func ladder() -> Model {
        var m = Model()
        m.shadow = false
        for x: Float in [11, 21] { m.box(x - 1, 20, 0, x + 1, 22, 40, wood) }
        for z in stride(from: Float(4), to: 40, by: 5) { m.box(10, 20.4, z, 22, 21.6, z + 1.2, Paint(0x9A6A3A, .wood(0))) }
        return m
    }

    static func tent() -> Model {
        var m = Model()
        m.cone(16, 17, 13, 0.5, 0, 22, Paint(0xD8C8A0, .cloth))
        m.box(13, 28, 0, 19, 29.5, 9, Paint(0x3A2A1A))
        m.cyl(16, 17, 0.8, 20, 26, darkWood)
        return m
    }

    static func logSeat() -> Model {
        var m = Model()
        m.rod(V3(6, 18, 3.5), V3(26, 18, 3.5), 3.5, NatureArt.bark)
        return m
    }

    static func rubble(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        for _ in 0..<6 {
            m.blob(rng.range(6, 26), rng.range(8, 26), 1.2, rng.range(1.8, 3.4), rng.range(1.6, 3), rng.range(1.2, 2.2), stone)
        }
        return m
    }

    static func brokenColumn(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        let marble = Paint(0xD8D2C4, .stone, jitter: 0.05)
        m.box(9, 10, 0, 23, 24, 3, Paint(0xB8B2A6, .stone))
        m.cyl(16, 17, 5, 3, rng.range(12, 20), marble)
        m.rod(V3(20, 26, 3), V3(30, 30, 3), 3.5, marble)
        return m
    }

    static func hangingSign(icon: String) -> Model {
        var m = Model()
        m.cyl(8, 22, 1.2, 0, 28, darkWood)
        m.rod(V3(8, 22, 26), V3(28, 22, 26), 0.8, iron)
        for x: Float in [14, 25] { m.rod(V3(x, 22, 26), V3(x, 22, 22), 0.25, iron) }
        m.box(11, 21, 12, 28, 23, 22, Paint(0x6A4426, .wood(0)))
        m.box(10.5, 20.8, 11.5, 28.5, 21, 22.5, Paint(0x3A2414))
        let y: Float = 23.1
        switch icon {
        case "tavern":
            m.box(16, y, 14, 21, y + 0.6, 20, Paint(0xD8B040, .metal, shine: 0.4))
            m.box(21, y, 16, 23, y + 0.6, 18.5, Paint(0xD8B040))
            m.box(16, y + 0.2, 19.5, 21, y + 0.8, 21, Paint(0xF4F0E0))
        case "inn":
            m.box(14, y, 14, 25, y + 0.6, 17, Paint(0xE8E4D8))
            m.box(14, y + 0.1, 17, 17, y + 0.7, 19, Paint(0xF8F8F8))
            m.box(17, y + 0.1, 17, 25, y + 0.7, 18, Paint(0x3A5AC0))
        case "provisions":
            m.blob(19.5, y, 17, 4.5, 0.6, 3, Paint(0xC88A40))
            for x: Float in [17, 19.5, 22] { m.box(x, y + 0.4, 16, x + 0.6, y + 0.8, 19, Paint(0x8A5A20)) }
        case "smithy":
            m.box(15, y, 15, 24, y + 0.6, 17.5, Paint(0x4A4A52))
            m.box(17, y, 13.5, 22, y + 0.6, 15, Paint(0x4A4A52))
            m.box(13.5, y, 16, 15, y + 0.6, 17, Paint(0x4A4A52))
        case "armory":
            m.blob(19.5, y, 17, 4, 0.6, 4.5, Paint(0xB02020))
            m.box(19, y + 0.4, 13, 20, y + 0.9, 21, Paint(0xD8D8E0, shine: 0.6))
        case "healer":
            m.box(18.5, y, 13.5, 20.5, y + 0.6, 20.5, Paint(0xD02020))
            m.box(16, y, 16, 23, y + 0.6, 18, Paint(0xD02020))
        default:
            m.box(14, y, 15, 25, y + 0.5, 19, Paint(0xD8C8A0))
        }
        return m
    }

    static func woodpile(_ rng: inout SplitMix64) -> Model {
        var m = Model()
        let rows: [(Float, Int)] = [(3, 4), (8.5, 3), (14, 2)]
        for (z, n) in rows {
            for k in 0..<n {
                let x = 16 - Float(n - 1) * 3.2 + Float(k) * 6.4
                m.rod(V3(x, 10, z), V3(x, 26, z), 2.9, NatureArt.bark)
                m.cyl(x, 26.6, 2.5, z - 2.5, z + 2.5, Paint(0xC8A070, .wood(2)))
            }
        }
        return m
    }

    static func beehive() -> Model {
        var m = Model()
        m.box(7, 9, 0, 25, 25, 8, Paint(0x9A6430, .wood(0)))
        m.box(6, 8, 8, 26, 26, 9.5, Paint(0x7A4A24))
        for (z, r) in [(Float(10.5), Float(8)), (13.5, 7.4), (16.5, 6.2), (19, 4.6), (21, 2.8)] {
            m.blob(16, 17, z, r, r, 1.9, Paint(0xD8A848, .straw))
        }
        m.box(14.5, 24.4, 9.5, 17.5, 24.8, 11.5, Paint(0x2A1A0A))
        return m
    }

    static func stocks() -> Model {
        var m = Model()
        let w = Paint(0xC07838, .wood(0))
        for x: Float in [6, 26] { m.box(x - 1.5, 15, 0, x + 1.5, 18, 20, w) }
        m.box(4, 14.5, 12, 28, 18.5, 17, w)
        for x: Float in [11, 16, 21] { m.box(x - 1.3, 18.5, 13.5, x + 1.3, 18.8, 15.8, Paint(0x2A1A0A)) }
        m.box(4, 14.5, 14.4, 28, 18.6, 14.7, Paint(0x6A3A18))
        return m
    }

    // MARK: On walls (variant 0 hangs on a south face, 1 on an east face)

    static func torch(east: Bool, frame: Int) -> Model {
        var m = Model()
        m.shadow = false
        if east {
            m.box(32, 15, 11, 33.5, 17, 14, iron)
            m.rod(V3(32.5, 16, 12), V3(35.5, 16, 17), 0.9, darkWood)
            flames(&m, 36, 16, 17.5, size: 2.4, frame: frame)
        } else {
            m.box(15, 32, 11, 17, 33.5, 14, iron)
            m.rod(V3(16, 32.5, 12), V3(16, 35.5, 17), 0.9, darkWood)
            flames(&m, 16, 36, 17.5, size: 2.4, frame: frame)
        }
        return m
    }

    static func banner(east: Bool) -> Model {
        var m = Model()
        m.shadow = false
        let cloth = Paint(east ? 0x2A3AA8 : 0xA82020, .cloth)
        if east {
            m.box(32, 9, 4, 32.8, 23, 22, cloth)
            m.box(32.1, 9, 20.5, 33, 23, 22, gold)
            m.box(32.6, 14, 11, 33.2, 18, 16, gold)
        } else {
            m.box(9, 32, 4, 23, 32.8, 22, cloth)
            m.box(9, 32.1, 20.5, 23, 33, 22, gold)
            m.box(14, 32.6, 11, 18, 33.2, 16, gold)
        }
        return m
    }

    static func painting(_ rng: inout SplitMix64, east: Bool) -> Model {
        var m = Model()
        m.shadow = false
        let sky = Paint(rng.pick([0x6A9AD8, 0xE0A060, 0x4A6AA8]), jitter: 0.05)
        let land = Paint(rng.pick([0x4A7A3A, 0x6A8A3A, 0x8A6A3A]), jitter: 0.08)
        func q(_ a0: Float, _ a1: Float, _ d0: Float, _ d1: Float, _ z0: Float, _ z1: Float, _ p: Paint) {
            if east { m.box(32 + d0, a0, z0, 32 + d1, a1, z1, p) } else { m.box(a0, 32 + d0, z0, a1, 32 + d1, z1, p) }
        }
        q(7, 25, 0, 0.8, 8, 20, gold)
        q(8.5, 23.5, 0.8, 1.1, 14, 18.6, sky)
        q(8.5, 23.5, 0.8, 1.1, 9.4, 14, land)
        q(18, 20, 1.1, 1.3, 15.5, 17.5, Paint(0xF8E8A0, jitter: 0.02))
        return m
    }
}
