import Foundation
import simd

/// The Avatar, as in the old cloth maps: blond, steel-clad, red-cloaked, sword in hand.
enum AvatarArt {
    static let skin = Paint(0xE8B48A, jitter: 0.03)
    static let hair = Paint(0xF2C83A, .hair, jitter: 0.05, shine: 0.2)
    static let steel = Paint(0xB4B8C0, .metal, jitter: 0.04, shine: 0.55)
    static let darkSteel = Paint(0x6E727C, .metal, jitter: 0.05, shine: 0.3)
    static let cape = Paint(0xC0201C, .cloth, jitter: 0.04)
    static let leather = Paint(0x6A4222, jitter: 0.05)
    static let gold = Paint(0xD8A830, .metal, shine: 0.5)
    static let blade = Paint(0xD8DCE4, .metal, jitter: 0.02, shine: 0.8)

    /// The figure facing south (towards the viewer) in its own frame, centred on
    /// (0, 0); `step` swings the legs (-1, 0 or 1).
    static func figure(step: Int) -> Model {
        var m = Model()
        let swing = Float(step) * 2.4
        // Legs and boots.
        for (side, s) in [(-1 as Float, swing), (1 as Float, -swing)] {
            let x = side * 2.4
            m.rod(V3(x, s * 0.5, 12), V3(x, s, 3.2), 1.9, darkSteel)
            m.box(x - 1.9, s - 2.2, 0, x + 1.9, s + 2.6, 3.6, leather)
        }
        // Cape hanging behind, flaring towards the hem.
        m.box(-5.2, -4.4, 9, 5.2, -3, 23, cape)
        m.box(-6.2, -4.8, 4, 6.2, -3.2, 10, cape)
        // Body armour, belt and shoulders.
        m.blob(0, 0, 18, 5.5, 3.6, 5.8, steel)
        m.blob(0, 0.1, 13.4, 4.6, 3.2, 1.3, leather)
        m.ball(-4.6, 0, 22.2, 2.3, steel)
        m.ball(4.6, 0, 22.2, 2.3, steel)
        // Arms, swinging against the legs; the right hand holds the sword.
        let armSwing = -swing * 0.7
        m.rod(V3(-5.6, 0, 21.5), V3(-6.3, 1.5 + armSwing, 14.2), 1.5, steel)
        m.rod(V3(5.6, 0, 21.5), V3(6.2, 1 - armSwing, 14.2), 1.5, steel)
        m.ball(-6.3, 1.8 + armSwing, 13.4, 1.4, skin)
        m.ball(6.2, 1.2 - armSwing, 13.4, 1.4, skin)
        m.rod(V3(-6.3, 2.2 + armSwing, 13.8), V3(-6.6, 4 + armSwing, 15.6), 0.7, gold)
        m.box(-7.2, 1.3 + armSwing, 13, -5.4, 2.8 + armSwing, 13.9, gold)
        m.rod(V3(-6.4, 2.6 + armSwing, 12.6), V3(-7.4, 8 + armSwing, 1.8), 0.8, blade)
        // Head and golden hair.
        m.ball(0, 0.3, 26.4, 3.3, skin)
        m.blob(0, -0.8, 27.4, 3.7, 3.5, 3.3, hair)
        m.blob(0, -2.2, 24, 3.4, 1.6, 3.2, hair)
        m.ball(-1.2, 3.25, 26.5, 0.45, Paint(0x2A1A10))
        m.ball(1.2, 3.25, 26.5, 0.45, Paint(0x2A1A10))
        return m
    }

    /// Head and shoulders for the portrait in the side panel, built facing the viewer
    /// (towards +z, straight up out of the picture).
    static func portrait() -> Model {
        var m = Model()
        m.leanX = 0
        m.shadow = false
        m.blob(0, 36, -8, 31, 16, 8, cape)
        m.blob(0, 40, 0, 25, 14, 11, steel)
        m.ball(-19, 33, 3, 9, steel)
        m.ball(19, 33, 3, 9, steel)
        m.blob(0, 44, 9, 4, 4, 3, gold)
        m.blob(0, 21, 2, 6, 6, 6, skin)
        m.blob(-11, 13, -1, 5.5, 13, 6, hair)
        m.blob(11, 13, -1, 5.5, 13, 6, hair)
        m.blob(0, -1, 1, 14.5, 15, 10, hair)
        m.blob(0, 5, 6, 11.5, 13.5, 10.5, skin)
        m.blob(0, -7, 11, 11, 5.5, 5.5, hair)
        for x: Float in [-4.6, 4.6] {
            m.blob(x, 4.5, 15.8, 2.3, 1.4, 0.6, Paint(0xF8F4EC))
            m.ball(x, 4.6, 16.2, 1.2, Paint(0x2A4A8A))
            m.box(x - 2.6, 1.2, 15.5, x + 2.6, 2.1, 16.2, Paint(0xB08A30))
        }
        m.blob(0, 8.5, 16.4, 1.8, 3.2, 1.6, Paint(0xD8A07A, jitter: 0.03))
        m.box(-3.2, 13.2, 15, 3.2, 14.2, 15.6, Paint(0x9A3A30))
        return m
    }

    /// The figure turned to face a direction, standing in the middle of its tile.
    static func model(facing: Direction, step: Int) -> Model {
        // A little larger than life, so the hero stands out on the map.
        Posing.stand(figure(step: step), facing: facing, scale: V3(repeating: 1.16))
    }
}

/// Turns a figure built facing south about (0, 0) to face any way, scaled
/// (across, front-to-back, up), standing in the middle of its tile.
enum Posing {
    static func stand(_ base: Model, facing: Direction, scale k: V3) -> Model {
        let (c, s): (Float, Float)
        switch facing {
        case .south: (c, s) = (1, 0)
        case .north: (c, s) = (-1, 0)
        case .east: (c, s) = (0, -1)
        case .west: (c, s) = (0, 1)
        }
        func rot(_ p: V3) -> V3 {
            let q = p * k
            return V3(c * q.x - s * q.y + 16, s * q.x + c * q.y + 17, q.z)
        }
        func rotR(_ r: V3) -> V3 {
            let q = r * k
            return abs(c) > 0.5 ? q : V3(q.y, q.x, q.z)
        }
        let kr = (k.x + k.y) / 2
        var m = Model()
        m.leanX = 0.5
        m.shadowAlpha = 0.3
        m.seed = base.seed
        for var p in base.prims {
            switch p.shape {
            case let .box(a, b):
                let ra = rot(a), rb = rot(b)
                p.shape = .box(simd_min(ra, rb), simd_max(ra, rb))
            case let .ellipsoid(cn, r): p.shape = .ellipsoid(rot(cn), rotR(r))
            case let .cone(cn, r0, r1, z0, z1):
                let q = rot(V3(cn.x, cn.y, 0))
                p.shape = .cone(SIMD2(q.x, q.y), r0 * kr, r1 * kr, z0 * k.z, z1 * k.z)
            case let .capsule(a, b, r): p.shape = .capsule(rot(a), rot(b), r * kr)
            case .lying: continue
            }
            m.prims.append(p)
        }
        return m
    }
}
