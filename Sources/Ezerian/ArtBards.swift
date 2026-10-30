import Foundation
import simd

/// Ezerian's bards, as in their painted portraits: each one's figure on the map wears
/// the painting's colours and plays its instrument. (The sheet's horned, red-skinned
/// fiddler belongs to no race of Ezerian, so painting 4 is not used.)
enum BardArt {
    enum Instrument { case lute, lyre, drum, flute, harp, tambourine, hurdyGurdy }

    struct Bard {
        /// Which painting (Resources/Portraits/bard-N.jpg).
        var painting: Int
        var look: PeopleArt.Look
        var instrument: Instrument
        var featherHat = false
        var race: Race { look.race }
    }

    private static func look(_ race: Race, female: Bool, skin: UInt32, hair: UInt32, tunic: UInt32, legs: UInt32,
                             cape: UInt32? = nil, longHair: Bool, beard: Bool = false, dress: Bool = false) -> PeopleArt.Look {
        PeopleArt.Look(race: race, female: female, skin: skin, hair: hair, tunic: tunic, legs: legs, cape: cape,
                       longHair: longHair, bald: false, beard: beard, dress: dress, helmet: false)
    }

    static let bards: [Bard] = [
        Bard(painting: 0, look: look(.human, female: false, skin: 0xE8B48A, hair: 0x6A4422, tunic: 0x7A1E2A, legs: 0x3A2A22,
                                     cape: 0x6A1A24, longHair: false), instrument: .lute, featherHat: true),
        Bard(painting: 1, look: look(.elf, female: false, skin: 0x4A2E1E, hair: 0xC8C8C4, tunic: 0x1E4A32, legs: 0x3A2E22,
                                     cape: 0x1E4A32, longHair: true), instrument: .lyre),
        Bard(painting: 2, look: look(.dwarf, female: false, skin: 0xE0A882, hair: 0xB8481E, tunic: 0xB88A2A, legs: 0x7A2A22,
                                     longHair: false, beard: true), instrument: .drum),
        Bard(painting: 3, look: look(.human, female: false, skin: 0xD8A27A, hair: 0x8A8680, tunic: 0x26305E, legs: 0x2A2A3A,
                                     cape: 0x1E2448, longHair: false, beard: true), instrument: .flute),
        Bard(painting: 5, look: look(.human, female: true, skin: 0xF0C8A0, hair: 0x9A3A1E, tunic: 0x1E5A5A, legs: 0x1E5A5A,
                                     longHair: true, dress: true), instrument: .lute),
        Bard(painting: 6, look: look(.human, female: true, skin: 0x4A2E1E, hair: 0x1A1410, tunic: 0x6A1A24, legs: 0x6A1A24,
                                     longHair: true, dress: true), instrument: .harp),
        Bard(painting: 7, look: look(.dwarf, female: true, skin: 0xD49A6E, hair: 0x2A1A10, tunic: 0x3A5A2A, legs: 0x5A3A2A,
                                     longHair: true), instrument: .tambourine),
        Bard(painting: 8, look: look(.human, female: true, skin: 0xC89070, hair: 0x8A8680, tunic: 0x26305E, legs: 0x26305E,
                                     cape: 0x1E2448, longHair: false, dress: true), instrument: .flute),
        Bard(painting: 9, look: look(.elf, female: true, skin: 0xF4D8C0, hair: 0xE8D080, tunic: 0x26408A, legs: 0x26408A,
                                     longHair: true, dress: true), instrument: .hurdyGurdy),
    ]

    /// A bard facing south, built on an ordinary person's figure, instrument in hand.
    static func figure(_ b: Bard, step: Int) -> Model {
        var m = PeopleArt.figure(b.look, step: step)
        let wood = Paint(0xB07A38, .wood(1), jitter: 0.05, shine: 0.2)
        let dark = Paint(0x5A3418, jitter: 0.05)
        let brass = Paint(0xC8A040, .metal, shine: 0.5)
        let hide = Paint(0xE4D8B8, jitter: 0.04)
        switch b.instrument {
        case .lute:
            m.blob(1.2, 3.9, 16.2, 2.7, 1.1, 2.1, wood)
            m.ball(1.2, 4.9, 16.4, 0.6, dark)
            m.rod(V3(2.8, 3.9, 17.2), V3(6.6, 3.6, 21.2), 0.5, dark)
        case .lyre:
            m.blob(0, 3.9, 14.6, 2.2, 0.9, 1, brass)
            m.rod(V3(-1.6, 3.9, 14.6), V3(-2.2, 3.9, 20), 0.45, brass)
            m.rod(V3(1.6, 3.9, 14.6), V3(2.2, 3.9, 20), 0.45, brass)
            m.rod(V3(-2.2, 3.9, 20), V3(2.2, 3.9, 20), 0.4, brass)
        case .drum:
            m.blob(0.6, 4.4, 16, 3.4, 1, 3.4, Paint(0x7A4A24, jitter: 0.05))
            m.blob(0.6, 5.2, 16, 3, 0.4, 3, hide)
        case .flute:
            m.rod(V3(-0.6, 3.8, 25), V3(4.6, 3.9, 20.2), 0.38, wood)
        case .harp:
            m.rod(V3(2.6, 3.8, 9.5), V3(2.6, 3.8, 22.5), 0.55, wood)
            m.rod(V3(2.6, 3.8, 22.5), V3(-1.2, 3.8, 19.5), 0.5, wood)
            m.rod(V3(-1.2, 3.8, 19.5), V3(2.4, 3.8, 10), 0.9, wood)
        case .tambourine:
            m.blob(3.4, 3.8, 19, 2.3, 0.5, 2.3, hide)
            for a in stride(from: Float(0), to: 6.28, by: 1.05) { m.ball(3.4 + cos(a) * 2.3, 3.8, 19 + sin(a) * 2.3, 0.45, brass) }
        case .hurdyGurdy:
            m.blob(0, 4.4, 14.6, 3.8, 1.7, 1.7, wood)
            m.rod(V3(3.8, 4.4, 14.6), V3(5, 4.6, 16), 0.35, dark)
            m.box(-2.4, 5.8, 14.2, 2.4, 6.2, 15.6, dark)
        }
        if b.featherHat {
            m.blob(0, -0.3, 28.8, 4, 4, 1.7, Paint(0x6A1A24, .cloth))
            m.blob(-2.4, -2.4, 30.4, 0.7, 2.8, 1, Paint(0xE8E0D8, .hair))
        }
        return m
    }

    static func model(_ b: Bard, facing: Direction, step: Int) -> Model {
        Posing.stand(figure(b, step: step), facing: facing, scale: PeopleArt.build(b.race))
    }
}
