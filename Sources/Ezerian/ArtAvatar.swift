import Foundation
import simd

/// The Avatar at the start of the adventure: blond, unarmed and unarmoured, in a
/// linen shirt, slacks and plain leather shoes. A man or a woman, chosen at the start.
enum AvatarArt {
    static let skin = Paint(0xE8B48A, jitter: 0.03)
    static let hair = Paint(0xF2C83A, .hair, jitter: 0.05, shine: 0.2)
    static let shirt = Paint(0xE4DAC2, .cloth, jitter: 0.04)
    static let shirtShade = Paint(0xC8BCA2, .cloth, jitter: 0.04)
    static let slacks = Paint(0x4E4438, .cloth, jitter: 0.04)
    static let leather = Paint(0x5A3820, jitter: 0.05)
    static let buckle = Paint(0xB89040, .metal, shine: 0.4)

    /// The figure facing south (towards the viewer) in its own frame, centred on
    /// (0, 0); `step` swings the legs (-1, 0 or 1).
    static func figure(female: Bool, step: Int) -> Model {
        var m = Model()
        let swing = Float(step) * 2.4
        let shoulder: Float = female ? 4.1 : 4.6
        // Slacks and shoes.
        for (side, s) in [(-1 as Float, swing), (1 as Float, -swing)] {
            let x = side * (female ? 2.2 : 2.4)
            m.rod(V3(x, s * 0.5, 12.5), V3(x, s, 3), 1.8, slacks)
            m.box(x - 1.6, s - 1.8, 0, x + 1.6, s + 2.4, 2.6, leather)
        }
        if female { m.blob(0, 0, 12.6, 4.4, 3, 2.2, slacks) }
        // Shirt, tucked in under a belt.
        m.blob(0, 0, 18, female ? 4.4 : 5.1, 3.2, 5.6, shirt)
        if female {
            for side: Float in [-1, 1] { m.ball(side * 1.6, 2.2, 19.6, 1.6, shirt) }
        }
        m.blob(0, 0.1, 13.4, female ? 4.2 : 4.6, 3.2, 1.1, leather)
        m.box(-0.8, 3.1, 13, 0.8, 3.5, 13.9, buckle)
        // Open collar.
        m.blob(0, 2.4, 22.6, 1.3, 0.8, 1.4, skin)
        m.ball(-shoulder, 0, 22, 2.1, shirt)
        m.ball(shoulder, 0, 22, 2.1, shirt)
        // Sleeves rolled to the elbow, arms swinging against the legs, hands empty.
        let armSwing = -swing * 0.7
        let ax = shoulder + 1
        m.rod(V3(-ax, 0, 21.5), V3(-ax - 0.4, 0.7 + armSwing * 0.5, 17.6), 1.5, shirtShade)
        m.rod(V3(ax, 0, 21.5), V3(ax + 0.4, 0.5 - armSwing * 0.5, 17.6), 1.5, shirtShade)
        m.rod(V3(-ax - 0.4, 0.7 + armSwing * 0.5, 17.6), V3(-ax - 0.7, 1.5 + armSwing, 14.2), 1.1, skin)
        m.rod(V3(ax + 0.4, 0.5 - armSwing * 0.5, 17.6), V3(ax + 0.6, 1 - armSwing, 14.2), 1.1, skin)
        m.ball(-ax - 0.7, 1.7 + armSwing, 13.5, 1.3, skin)
        m.ball(ax + 0.6, 1.2 - armSwing, 13.5, 1.3, skin)
        // Head and golden hair: cropped for him, falling past the shoulders for her.
        m.ball(0, 0.3, 26.4, 3.3, skin)
        m.blob(0, -0.8, 27.4, 3.7, 3.5, 3.3, hair)
        if female {
            m.blob(0, -2, 23, 3.8, 1.8, 4.6, hair)
            for side: Float in [-1, 1] { m.blob(side * 2.9, -0.4, 24.2, 1.2, 2, 3.4, hair) }
        } else {
            m.blob(0, -1.8, 25.2, 3.4, 1.6, 2, hair)
        }
        m.ball(-1.2, 3.25, 26.5, 0.45, Paint(0x2A1A10))
        m.ball(1.2, 3.25, 26.5, 0.45, Paint(0x2A1A10))
        return m
    }

    /// Head and shoulders for the portrait in the side panel, built facing the viewer
    /// (towards +z, straight up out of the picture).
    static func portrait(female: Bool) -> Model {
        var m = Model()
        m.leanX = 0
        m.shadow = false
        let wide: Float = female ? 0.9 : 1
        // Shirt with an open collar.
        m.blob(0, 40, 0, 25 * wide, 14, 11, shirt)
        m.ball(-19 * wide, 33, 3, 9, shirtShade)
        m.ball(19 * wide, 33, 3, 9, shirtShade)
        m.blob(0, 21, 2, 6, 6, 6, skin)
        m.blob(0, 28, 9.6, 2.4, 5, 1.4, skin)
        for side: Float in [-1, 1] { m.blob(side * 4.6, 27, 10.6, 3.4, 2.4, 1, Paint(0xF0E8D6, .cloth)) }
        if female {
            // Long hair, falling in front of the shoulders.
            m.blob(-12, 16, -1, 6, 15, 6.5, hair)
            m.blob(12, 16, -1, 6, 15, 6.5, hair)
            m.blob(-13 * wide, 31, 8.5, 4.6, 9, 3.2, hair)
            m.blob(13 * wide, 31, 8.5, 4.6, 9, 3.2, hair)
        } else {
            // Cropped short above the ears.
            m.blob(-11, 3, 0, 4, 5, 5.5, hair)
            m.blob(11, 3, 0, 4, 5, 5.5, hair)
        }
        m.blob(0, -1, 1, 14.5, 15, 10, hair)
        m.blob(0, 5, 6, 11.5 * (female ? 0.95 : 1), 13.5, 10.5, skin)
        m.blob(0, -7, 11, 11, 5.5, 5.5, hair)
        for x: Float in [-4.6, 4.6] {
            m.blob(x, 4.5, 15.8, 2.3, 1.4, 0.6, Paint(0xF8F4EC))
            m.ball(x, 4.6, 16.2, 1.2, Paint(0x2A4A8A))
            if female {
                m.box(x - 2.4, 1.5, 15.5, x + 2.4, 2.1, 16.2, Paint(0xB08A30))
            } else {
                m.box(x - 2.6, 1.2, 15.5, x + 2.6, 2.1, 16.2, Paint(0xB08A30))
            }
        }
        m.blob(0, 8.5, 16.4, female ? 1.5 : 1.8, 3.2, 1.6, Paint(0xD8A07A, jitter: 0.03))
        if female {
            m.blob(0, 13.7, 15.4, 3, 0.9, 0.7, Paint(0xB8484A))
        } else {
            m.box(-3.2, 13.2, 15, 3.2, 14.2, 15.6, Paint(0x9A3A30))
        }
        return m
    }

    /// The figure turned to face a direction, standing in the middle of its tile.
    static func model(female: Bool, facing: Direction, step: Int) -> Model {
        // A little larger than life, so the hero stands out on the map.
        Posing.stand(figure(female: female, step: step), facing: facing, scale: V3(repeating: 1.16))
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
