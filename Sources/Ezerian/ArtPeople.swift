import Foundation
import simd

/// The folk of Ezerian: humans, slender pointed-eared elves, short broad bearded
/// dwarves and big green tusked orcs, each in several looks (0-2 men, 3-5 women).
enum PeopleArt {
    struct Look {
        var race: Race
        var female: Bool
        var skin: UInt32
        var hair: UInt32
        var tunic: UInt32
        var legs: UInt32
        var cape: UInt32?
        var longHair: Bool
        var bald: Bool
        var beard: Bool
        var dress: Bool
        var helmet: Bool
        /// Lord Draconian's red sigil on the chest.
        var sigil = false
    }

    static func look(_ race: Race, _ variant: Int) -> Look {
        var l = baseLook(race, variant)
        if variant >= 6 {
            // Lord Draconian's livery: black tabard with his red sigil, red cloak, steel helm.
            l.tunic = 0x1E1C22
            l.legs = 0x2A2226
            l.cape = 0x8E1410
            l.helmet = true
            l.dress = false
            l.sigil = true
        }
        return l
    }

    private static func baseLook(_ race: Race, _ variant: Int) -> Look {
        var rng = SplitMix64(seed: Hash.of(0x7E0B1E, race.index, variant))
        let female = variant == 7 || (3...5).contains(variant)
        switch race {
        case .human:
            return Look(race: race, female: female, skin: rng.pick([0xE8B48A, 0xD49A6E, 0xA86E44, 0xF0C8A0]),
                        hair: rng.pick([0x3A2414, 0x6A4422, 0xC89A44, 0x1A1410, 0x8A3A1E, 0xC8C0B0]),
                        tunic: rng.pick([0x3A5A9A, 0x8A2A22, 0x3E6A2E, 0x8A6A3A, 0x6A3A7A, 0xB08A40]),
                        legs: rng.pick([0x4A3A2A, 0x2A2A3A, 0x5A4A3A]), cape: rng.chance(0.25) ? 0x2A3A6A : nil,
                        longHair: female, bald: !female && rng.chance(0.15), beard: !female && rng.chance(0.45),
                        dress: female && rng.chance(0.7), helmet: false)
        case .elf:
            return Look(race: race, female: female, skin: rng.pick([0xF4D8C0, 0xE8C8A8, 0xF0DCC8]),
                        hair: rng.pick([0xF0E0A0, 0xE0DCD4, 0xC8A858, 0x2A2A3A, 0xB8682A]),
                        tunic: rng.pick([0x3E7A3A, 0x2E5A4A, 0x5A7A9A, 0xC8C8B8, 0x6A8A3A]),
                        legs: rng.pick([0x3A4A2A, 0x5A5A4A]), cape: rng.chance(0.5) ? 0x2E4A2A : nil,
                        longHair: true, bald: false, beard: false, dress: female && rng.chance(0.5), helmet: false)
        case .dwarf:
            return Look(race: race, female: female, skin: rng.pick([0xE0A882, 0xC88A64, 0xE8B890]),
                        hair: rng.pick([0x8A3A1E, 0x5A3418, 0xC86A2A, 0x9A9A9A, 0x2A1A10]),
                        tunic: rng.pick([0x7A3A22, 0x3A4A7A, 0x5A4A2A, 0x6A2A2A]),
                        legs: rng.pick([0x3A2A1A, 0x4A3A2A]), cape: nil,
                        longHair: female, bald: false, beard: !female, dress: false, helmet: rng.chance(0.4))
        case .orc:
            return Look(race: race, female: female, skin: rng.pick([0x6A8A3A, 0x5A7A44, 0x7A8A4A, 0x4E6A36]),
                        hair: 0x1A1A14, tunic: rng.pick([0x5A3A22, 0x4A3A2A, 0x6A4A2A, 0x3A2E26]),
                        legs: rng.pick([0x3A2A1E, 0x2A2420]), cape: nil,
                        longHair: female, bald: !female && rng.chance(0.6), beard: false, dress: false, helmet: rng.chance(0.25))
        }
    }

    /// Body proportions: across, front-to-back, height.
    static func build(_ race: Race) -> V3 {
        switch race {
        case .human: return V3(1.06, 1.06, 1.06)
        case .elf: return V3(0.96, 0.96, 1.14)
        case .dwarf: return V3(1.28, 1.2, 0.8)
        case .orc: return V3(1.28, 1.2, 1.14)
        }
    }

    /// A person facing south (towards the viewer) about (0, 0); `step` swings the legs.
    static func figure(_ l: Look, step: Int) -> Model {
        var m = Model()
        m.seed = Hash.of(11, l.race.index, Int(l.tunic), Int(l.hair))
        let skin = Paint(l.skin, jitter: 0.03)
        let hair = Paint(l.hair, .hair, jitter: 0.05, shine: 0.15)
        let tunic = Paint(l.tunic, .cloth, jitter: 0.05)
        let sleeve = Paint(col: hex(l.tunic) * 0.86, .cloth)
        let legs = Paint(l.legs, .cloth)
        let boots = Paint(0x3A2414, jitter: 0.05)
        let steel = Paint(0x9AA0AA, .metal, shine: 0.5)
        let swing = Float(step) * 2.4
        if l.dress {
            m.cone(0, 0, 5.8, 4.2, 0, 14, tunic)
            for (side, s) in [(-1 as Float, swing), (1, -swing)] { m.box(side * 2.4 - 1.6, s - 1.6, 0, side * 2.4 + 1.6, s + 2.4, 1.6, boots) }
        } else {
            for (side, s) in [(-1 as Float, swing), (1, -swing)] {
                let x = side * 2.4
                m.rod(V3(x, s * 0.5, 12), V3(x, s, 3.2), 1.9, legs)
                m.box(x - 1.9, s - 2.2, 0, x + 1.9, s + 2.6, 3.6, boots)
            }
        }
        if let c = l.cape {
            m.box(-5.2, -4.4, 9, 5.2, -3, 23, Paint(c, .cloth))
            m.box(-6, -4.8, 5, 6, -3.2, 10, Paint(c, .cloth))
        }
        m.blob(0, 0, 18, 5, 3.4, 5.6, tunic)
        m.blob(0, 0.1, 13.4, 4.6, 3.2, 1.3, Paint(0x4A2E18))
        if l.sigil {
            m.blob(0, 3.2, 19, 1.9, 0.8, 2.2, Paint(0xC81810, shine: 0.2))
            m.blob(0, 3.5, 19.6, 0.8, 0.5, 0.8, Paint(0xF0C030))
        }
        m.ball(-4.5, 0, 22, 2.2, sleeve)
        m.ball(4.5, 0, 22, 2.2, sleeve)
        let armSwing = -swing * 0.7
        m.rod(V3(-5.5, 0, 21.5), V3(-6.2, 1.5 + armSwing, 14.2), 1.5, sleeve)
        m.rod(V3(5.5, 0, 21.5), V3(6.1, 1 - armSwing, 14.2), 1.5, sleeve)
        m.ball(-6.2, 1.8 + armSwing, 13.4, 1.4, skin)
        m.ball(6.1, 1.2 - armSwing, 13.4, 1.4, skin)
        // Head.
        m.ball(0, 0.3, 26.4, 3.3, skin)
        let eye = Paint(l.race == .orc ? 0xC02010 : 0x1A1410)
        m.ball(-1.2, 3.25, 26.6, 0.45, eye)
        m.ball(1.2, 3.25, 26.6, 0.45, eye)
        if !l.bald { m.blob(0, -0.8, 27.4, 3.6, 3.4, 3.2, hair) }
        if l.longHair { m.blob(0, -2.2, 23.6, 3.4, 1.6, 3.8, hair) }
        if l.beard {
            let big: Float = l.race == .dwarf ? 1.4 : 1
            m.blob(0, 2.5, 24.4 - big, 2.6 * big, 1.6, 2.4 * big, hair)
        }
        if l.helmet { m.blob(0, -0.2, 28.4, 3.8, 3.8, 2.4, steel) }
        if l.race == .elf {
            for side: Float in [-1, 1] { m.rod(V3(side * 3, 0.2, 26.8), V3(side * 4.8, -0.4, 28.8), 0.55, skin) }
        }
        if l.race == .orc {
            m.blob(0, 2.6, 27.6, 2.8, 0.8, 0.7, Paint(col: hex(l.skin) * 0.7))
            for side: Float in [-1, 1] { m.ball(side * 1.1, 3.3, 24.9, 0.6, Paint(0xF0E8D0)) }
            if l.bald { m.blob(0, -1.4, 29.2, 1.2, 1.2, 1.4, hair) }
        }
        return m
    }

    static func model(_ race: Race, variant: Int, facing: Direction, step: Int) -> Model {
        if let (rank, female) = Populace.guardRank(look: variant) { return GuardArt.model(rank, female: female, facing: facing, step: step) }
        return Posing.stand(figure(look(race, variant), step: step), facing: facing, scale: build(race))
    }

    /// Head and shoulders, facing the viewer, for the conversation window.
    static func portrait(_ race: Race, variant: Int) -> Model {
        let l = look(race, variant)
        var m = Model()
        m.leanX = 0
        m.shadow = false
        let skin = Paint(l.skin, jitter: 0.03)
        let hair = Paint(l.hair, .hair, jitter: 0.05, shine: 0.15)
        let tunic = Paint(l.tunic, .cloth)
        let wide: Float = race == .dwarf || race == .orc ? 1.18 : (race == .elf ? 0.92 : 1)
        if let c = l.cape { m.blob(0, 36, -8, 31 * wide, 16, 8, Paint(c, .cloth)) }
        m.blob(0, 40, 0, 25 * wide, 14, 11, tunic)
        m.ball(-19 * wide, 33, 3, 9, Paint(col: hex(l.tunic) * 0.86, .cloth))
        m.ball(19 * wide, 33, 3, 9, Paint(col: hex(l.tunic) * 0.86, .cloth))
        m.blob(0, 21, 2, 6 * wide, 6, 6, skin)
        if l.sigil {
            m.blob(0, 42, 10.5, 6, 6, 1.4, Paint(0xC81810, shine: 0.2))
            m.blob(0, 41, 11.6, 2.4, 2.4, 0.8, Paint(0xF0C030, shine: 0.4))
        }
        if l.longHair {
            m.blob(-11, 13, -1, 5.5, 13, 6, hair)
            m.blob(11, 13, -1, 5.5, 13, 6, hair)
        }
        if !l.bald { m.blob(0, -1, 1, 14.5 * wide, 15, 10, hair) }
        m.blob(0, 5, 6, 11.5 * wide, 13.5, 10.5, skin)
        if !l.bald { m.blob(0, -7, 11, 11 * wide, 5.5, 5.5, hair) }
        if race == .elf {
            for side: Float in [-1, 1] { m.rod(V3(side * 10.5, 5, 4), V3(side * 14.5, 0, 3), 1.5, skin) }
        }
        let iris: UInt32 = race == .orc ? 0xC02010 : (race == .elf ? 0x3A8A5A : 0x3A4A6A)
        for x: Float in [-4.6, 4.6] {
            m.blob(x * wide, 4.5, 15.8, 2.3, 1.4, 0.6, Paint(race == .orc ? 0xE8D890 : 0xF8F4EC))
            m.ball(x * wide, 4.6, 16.2, 1.2, Paint(iris))
            m.box(x * wide - 2.6, race == .orc ? 2 : 1.2, 15.5, x * wide + 2.6, race == .orc ? 3.4 : 2.1, 16.4,
                  Paint(col: race == .orc ? hex(l.skin) * 0.6 : hex(l.hair)))
        }
        m.blob(0, 8.5, 16.4, race == .orc ? 2.8 : 1.8, 3.2, 1.6, Paint(col: hex(l.skin) * 0.9))
        if l.beard {
            let big: Float = race == .dwarf ? 1.5 : 1
            m.blob(0, 18, 11, 9 * big, 7 * big, 6, hair)
            m.blob(0, 10.5, 15.5, 5, 1.6, 1.4, hair)
        } else {
            m.box(-3.2, 13.2, 15, 3.2, 14.2, 15.6, Paint(0x8A3A30))
        }
        if race == .orc {
            for side: Float in [-1, 1] { m.blob(side * 3.6, 12, 16.4, 1.1, 2.4, 1.1, Paint(0xF0E8D0)) }
        }
        if l.helmet { m.blob(0, -6, 6, 15 * wide, 9, 9, Paint(0x9AA0AA, .metal, shine: 0.5)) }
        return m
    }
}
