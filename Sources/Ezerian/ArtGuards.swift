import Foundation
import simd

/// The town watch, as in the painted portraits: five ranks, each a man or a woman
/// with their own face. Watchmen in leather and kettle hats with spears; serjeants
/// in mail and the red tabard; men-at-arms in half plate, the blue tabard and sallets,
/// with halberds; captains in studded brigandine and a dark cloak, sword at the hip;
/// and the knights of the watch in gilded plate. The tabards bear the town's tower.
enum GuardArt {
    static let ranks = 5

    /// What the rank is called, for a man or a woman.
    static func title(_ rank: Int, female: Bool) -> String {
        switch rank {
        case 0: return female ? "watchwoman" : "watchman"
        case 1: return "serjeant of the watch"
        case 2: return female ? "woman-at-arms" : "man-at-arms"
        case 3: return "captain of the watch"
        default: return "knight of the watch"
        }
    }

    enum Hat { case none, kettle, sallet, plumed }
    enum Body { case leather, mail, halfPlate, brigandine, gilded }
    enum Arm { case spear, halberd, sword }

    struct Kit {
        var skin: UInt32
        var hair: UInt32
        var beard = false
        var moustache = false
        var braid = false
        var bun = false
        var grey = false
        var hat: Hat
        var body: Body
        var tabard: UInt32?
        var scarf: UInt32?
        var cloak: UInt32?
        var arm: Arm
    }

    static let red: UInt32 = 0x7A1E26, blue: UInt32 = 0x26305E, navy: UInt32 = 0x1E2438

    /// Each rank's man and woman, as painted.
    static func kit(_ rank: Int, female: Bool) -> Kit {
        switch (rank, female) {
        case (0, false): return Kit(skin: 0xE8B48A, hair: 0x6A4422, hat: .kettle, body: .leather, scarf: 0x2E4A6A, arm: .spear)
        case (0, true): return Kit(skin: 0xD49A6E, hair: 0x3A2414, braid: true, hat: .kettle, body: .leather, scarf: 0x2E4A6A, arm: .spear)
        case (1, false): return Kit(skin: 0x5A3A26, hair: 0x1A1410, beard: true, hat: .kettle, body: .mail, tabard: red, scarf: red, arm: .spear)
        case (1, true): return Kit(skin: 0xF0C8A0, hair: 0xD8B868, hat: .kettle, body: .mail, tabard: red, scarf: red, arm: .spear)
        case (2, false): return Kit(skin: 0xC08A60, hair: 0x1A1410, moustache: true, hat: .sallet, body: .halfPlate, tabard: blue, scarf: navy, arm: .halberd)
        case (2, true): return Kit(skin: 0x4A2E1E, hair: 0x1A1410, braid: true, hat: .sallet, body: .halfPlate, tabard: blue, scarf: navy, arm: .halberd)
        case (3, false): return Kit(skin: 0xD8A27A, hair: 0x8A8680, beard: true, grey: true, hat: .none, body: .brigandine, cloak: navy, arm: .sword)
        case (3, true): return Kit(skin: 0xC89070, hair: 0x7A7672, grey: true, hat: .none, body: .brigandine, cloak: navy, arm: .sword)
        case (_, false): return Kit(skin: 0xE0B890, hair: 0x1A1410, hat: .plumed, body: .gilded, tabard: blue, arm: .halberd)
        default: return Kit(skin: 0xF0C8A8, hair: 0x9A3A1E, bun: true, hat: .none, body: .gilded, tabard: blue, arm: .halberd)
        }
    }

    /// A guard facing south (towards the viewer) about (0, 0); `step` swings the legs.
    static func figure(_ rank: Int, female: Bool, step: Int) -> Model {
        let k = kit(rank, female: female)
        var m = Model()
        m.seed = Hash.of(23, rank, female ? 1 : 0)
        let skin = Paint(k.skin, jitter: 0.03)
        let hair = Paint(k.hair, .hair, jitter: 0.05, shine: 0.15)
        let steel = Paint(0xB4B8C0, .metal, jitter: 0.04, shine: 0.55)
        let gold = Paint(0xC8A040, .metal, shine: 0.5)
        let leather = Paint(0x5A3A22, jitter: 0.05)
        let boots = Paint(0x3A2414, jitter: 0.05)
        let quilt = Paint(0xD4C8AC, .cloth, jitter: 0.05)
        let mail = Paint(0x8A8C92, .metal, jitter: 0.12, shine: 0.25)
        let plated = k.body == .halfPlate || k.body == .gilded
        let torso: Paint
        let sleeve: Paint
        switch k.body {
        case .leather: torso = leather; sleeve = quilt
        case .mail: torso = mail; sleeve = mail
        case .halfPlate: torso = steel; sleeve = mail
        case .brigandine: torso = Paint(0x4A3222, jitter: 0.06); sleeve = quilt
        case .gilded: torso = Paint(0xC4C8D0, .metal, jitter: 0.03, shine: 0.65); sleeve = torso
        }
        let swing = Float(step) * 2.4
        // Legs: greaves for the plated, otherwise breeches and boots.
        for (side, s) in [(-1 as Float, swing), (1, -swing)] {
            let x = side * 2.4
            m.rod(V3(x, s * 0.5, 12), V3(x, s, 3.2), 1.9, plated ? steel : Paint(0x4A3A2A, .cloth))
            m.box(x - 1.9, s - 2.2, 0, x + 1.9, s + 2.6, 3.6, boots)
        }
        if let c = k.cloak {
            m.box(-5.6, -4.4, 7, 5.6, -3, 23, Paint(c, .cloth))
            m.box(-6.4, -4.8, 3.5, 6.4, -3.2, 9, Paint(c, .cloth))
        }
        // Body, skirts and tabard.
        m.blob(0, 0, 18, 5.1, 3.5, 5.7, torso)
        m.cone(0, 0, 4.9, 4.3, 9.5, 13.4, k.body == .leather || k.body == .brigandine ? torso : mail)
        if k.body == .brigandine {
            for z: Float in [15, 17.5, 20] { for x: Float in [-2.6, 0, 2.6] { m.ball(x, 3.3, z, 0.45, gold) } }
        }
        if let t = k.tabard {
            let cloth = Paint(t, .cloth, jitter: 0.05)
            m.box(-3, 2.8, 8.6, 3, 3.7, 21.8, cloth)
            m.blob(0, 3.9, 18.4, 1.1, 0.4, 1.5, Paint(0xC8AA70))   // the tower
            if k.body == .gilded { m.box(-3.3, 2.7, 8.6, -2.9, 3.8, 21.8, gold); m.box(2.9, 2.7, 8.6, 3.3, 3.8, 21.8, gold) }
        }
        m.blob(0, 0.1, 13.6, 4.8, 3.6, 1.2, leather)
        m.ball(0, 3.6, 13.6, 0.7, gold)
        if let s = k.scarf { m.blob(0, 0.6, 22.8, 3.4, 3, 1.5, Paint(s, .cloth)) }
        // Shoulders and arms; pauldrons for those in plate.
        let shoulder = plated || k.body == .brigandine ? steel : sleeve
        m.ball(-4.7, 0, 22, 2.4, shoulder)
        m.ball(4.7, 0, 22, 2.4, shoulder)
        let armSwing = -swing * 0.5
        m.rod(V3(-5.7, 0, 21.5), V3(-6.3, 1.6, 14.4), 1.5, k.body == .gilded ? steel : sleeve)
        m.rod(V3(5.7, 0, 21.5), V3(6.2, 1 - armSwing, 14.2), 1.5, k.body == .gilded ? steel : sleeve)
        let hand = k.body == .gilded ? steel : Paint(0x4A3020, jitter: 0.05)
        m.ball(-6.3, 1.9, 13.6, 1.4, hand)
        m.ball(6.2, 1.2 - armSwing, 13.4, 1.4, hand)
        // The weapon: a spear or a halberd planted upright, or a sword at the hip.
        switch k.arm {
        case .spear:
            m.rod(V3(-6.3, 1.9, 0.5), V3(-6.3, 1.9, 33), 0.6, Paint(0x6A4A2A, .wood(2)))
            m.rod(V3(-6.3, 1.9, 33), V3(-6.3, 1.9, 37), 0.75, steel)
        case .halberd:
            m.rod(V3(-6.3, 1.9, 0.5), V3(-6.3, 1.9, 34), 0.6, Paint(k.body == .gilded ? 0x1A1A22 : 0x6A4A2A, .wood(2)))
            m.rod(V3(-6.3, 1.9, 34), V3(-6.3, 1.9, 38), 0.6, steel)
            m.box(-9.6, 1.5, 30, -6.6, 2.3, 34, steel)
            if k.body == .gilded { m.blob(-6.3, 1.9, 29, 0.9, 0.9, 1.6, Paint(0x2A3A8A, .cloth)) }
        case .sword:
            m.rod(V3(4.4, 1.2, 13), V3(6.4, 2.6, 4), 0.8, Paint(0x3A2016))
            m.rod(V3(4.2, 1.1, 13.4), V3(3.6, 0.6, 15.4), 0.5, gold)
        }
        // Head, hair and helmet.
        m.ball(0, 0.3, 26.4, 3.3, skin)
        let eye = Paint(0x1A1410)
        m.ball(-1.2, 3.25, 26.6, 0.45, eye)
        m.ball(1.2, 3.25, 26.6, 0.45, eye)
        m.blob(0, -0.8, 27.4, 3.6, 3.4, 3.2, hair)
        if k.beard { m.blob(0, 2.5, 24.2, 2.6, 1.6, 2.2, hair) }
        if k.moustache { m.blob(0, 3.2, 25.4, 1.8, 0.6, 0.6, hair) }
        if k.braid { for (i, z) in [23.6, 21.8, 20, 18.4].enumerated() { m.ball(-0.2, -3.2 - Float(i) * 0.2, Float(z), 1 - Float(i) * 0.1, hair) } }
        if k.bun { m.ball(0, -3.2, 27.2, 1.8, hair) }
        switch k.hat {
        case .none: break
        case .kettle:
            m.blob(0, -0.2, 28.4, 3.8, 3.8, 2.4, steel)
            m.blob(0, -0.2, 27.6, 5.4, 5.4, 0.5, steel)
        case .sallet, .plumed:
            m.blob(0, -0.4, 28.2, 3.9, 3.9, 2.8, steel)
            m.blob(0, -2.8, 26.4, 3.6, 2, 1.6, steel)
            if k.hat == .plumed { m.blob(0, -1.6, 31.4, 0.9, 2.8, 1.6, Paint(0x2A3A9A, .hair)) }
        }
        return m
    }

    static func model(_ rank: Int, female: Bool, facing: Direction, step: Int) -> Model {
        Posing.stand(figure(rank, female: female, step: step), facing: facing, scale: PeopleArt.build(.human))
    }
}
