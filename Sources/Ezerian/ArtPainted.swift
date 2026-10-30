import Foundation
import simd

/// Folk with painted portraits, by trade: the bards and the peasants. Each one's figure
/// on the map wears the painting's colours and hat, and holds what they hold in it
/// (an instrument, a hoe, a loaf). The bard sheet's horned, red-skinned fiddler belongs
/// to no race of Ezerian, so bard painting 4 is not used.
enum PaintedFolk {
    enum Prop {
        case lute, lyre, drum, flute, harp, tambourine, hurdyGurdy
        case hoe, flourSack, woodAxe, crook, net, vegetables, loaf, spindle, bucket, herbs
    }
    enum Hat { case none, feather, straw, cap, scarf(UInt32), hood }

    struct Painted {
        /// The trade they follow ("bard", "peasant").
        var role: String
        /// The painting, Resources/Portraits/<painting>.jpg.
        var painting: String
        var look: PeopleArt.Look
        var prop: Prop
        var hat: Hat = .none
        var apron = false
        var race: Race { look.race }
    }

    private static func look(_ race: Race, female: Bool, skin: UInt32, hair: UInt32, tunic: UInt32, legs: UInt32,
                             cape: UInt32? = nil, longHair: Bool, beard: Bool = false, dress: Bool = false) -> PeopleArt.Look {
        PeopleArt.Look(race: race, female: female, skin: skin, hair: hair, tunic: tunic, legs: legs, cape: cape,
                       longHair: longHair, bald: false, beard: beard, dress: dress, helmet: false)
    }

    static let all: [Painted] = bards + peasants

    static let bards: [Painted] = [
        Painted(role: "bard", painting: "bard-0", look: look(.human, female: false, skin: 0xE8B48A, hair: 0x6A4422, tunic: 0x7A1E2A,
                                                            legs: 0x3A2A22, cape: 0x6A1A24, longHair: false), prop: .lute, hat: .feather),
        Painted(role: "bard", painting: "bard-1", look: look(.elf, female: false, skin: 0x4A2E1E, hair: 0xC8C8C4, tunic: 0x1E4A32,
                                                            legs: 0x3A2E22, cape: 0x1E4A32, longHair: true), prop: .lyre),
        Painted(role: "bard", painting: "bard-2", look: look(.dwarf, female: false, skin: 0xE0A882, hair: 0xB8481E, tunic: 0xB88A2A,
                                                            legs: 0x7A2A22, longHair: false, beard: true), prop: .drum),
        Painted(role: "bard", painting: "bard-3", look: look(.human, female: false, skin: 0xD8A27A, hair: 0x8A8680, tunic: 0x26305E,
                                                            legs: 0x2A2A3A, cape: 0x1E2448, longHair: false, beard: true), prop: .flute),
        Painted(role: "bard", painting: "bard-5", look: look(.human, female: true, skin: 0xF0C8A0, hair: 0x9A3A1E, tunic: 0x1E5A5A,
                                                            legs: 0x1E5A5A, longHair: true, dress: true), prop: .lute),
        Painted(role: "bard", painting: "bard-6", look: look(.human, female: true, skin: 0x4A2E1E, hair: 0x1A1410, tunic: 0x6A1A24,
                                                            legs: 0x6A1A24, longHair: true, dress: true), prop: .harp),
        Painted(role: "bard", painting: "bard-7", look: look(.dwarf, female: true, skin: 0xD49A6E, hair: 0x2A1A10, tunic: 0x3A5A2A,
                                                            legs: 0x5A3A2A, longHair: true), prop: .tambourine),
        Painted(role: "bard", painting: "bard-8", look: look(.human, female: true, skin: 0xC89070, hair: 0x8A8680, tunic: 0x26305E,
                                                            legs: 0x26305E, cape: 0x1E2448, longHair: false, dress: true), prop: .flute),
        Painted(role: "bard", painting: "bard-9", look: look(.elf, female: true, skin: 0xF4D8C0, hair: 0xE8D080, tunic: 0x26408A,
                                                            legs: 0x26408A, longHair: true, dress: true), prop: .hurdyGurdy),
    ]

    static let peasants: [Painted] = [
        Painted(role: "peasant", painting: "peasant-0", look: look(.human, female: false, skin: 0xE0A882, hair: 0x6A4422, tunic: 0x6A4A2A,
                                                                  legs: 0x5A4A3A, longHair: false, beard: true), prop: .hoe, hat: .straw),
        Painted(role: "peasant", painting: "peasant-1", look: look(.human, female: false, skin: 0x4A2E1E, hair: 0x1A1410, tunic: 0x4A505A,
                                                                  legs: 0x4A3A2A, longHair: false), prop: .flourSack, hat: .cap, apron: true),
        Painted(role: "peasant", painting: "peasant-2", look: look(.human, female: false, skin: 0xE8B48A, hair: 0xB8481E, tunic: 0x8A3A22,
                                                                  legs: 0x5A2A22, longHair: false, beard: true), prop: .woodAxe),
        Painted(role: "peasant", painting: "peasant-3", look: look(.human, female: false, skin: 0xC89070, hair: 0xC8C4C0, tunic: 0x5A5244,
                                                                  legs: 0x4A4234, cape: 0x5A4A3A, longHair: false, beard: true), prop: .crook, hat: .hood),
        Painted(role: "peasant", painting: "peasant-4", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x1A1410, tunic: 0x3A4A6A,
                                                                  legs: 0x3A3A3A, longHair: false, beard: true), prop: .net, apron: true),
        Painted(role: "peasant", painting: "peasant-5", look: look(.human, female: true, skin: 0xF0C8A0, hair: 0x9A3A1E, tunic: 0x3A4A32,
                                                                  legs: 0x3A4A32, longHair: true, dress: true), prop: .vegetables, hat: .scarf(0xD8CCB0)),
        Painted(role: "peasant", painting: "peasant-6", look: look(.human, female: true, skin: 0x4A2E1E, hair: 0x1A1410, tunic: 0x5A3A2A,
                                                                  legs: 0x5A3A2A, longHair: false, dress: true), prop: .loaf, hat: .scarf(0xD8CCB0), apron: true),
        Painted(role: "peasant", painting: "peasant-7", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xC8C4C0, tunic: 0x6A6458,
                                                                  legs: 0x6A6458, cape: 0x5A3A2A, longHair: false, dress: true), prop: .spindle, hat: .scarf(0xD8CCB0)),
        Painted(role: "peasant", painting: "peasant-8", look: look(.human, female: true, skin: 0xC89070, hair: 0x1A1410, tunic: 0xB08A3A,
                                                                  legs: 0xB08A3A, longHair: true, dress: true), prop: .bucket, hat: .scarf(0x8A2A22), apron: true),
        Painted(role: "peasant", painting: "peasant-9", look: look(.human, female: true, skin: 0xF0D0B0, hair: 0x1A1410, tunic: 0x3A4A3A,
                                                                  legs: 0x5A5A4A, cape: 0x3A4A3A, longHair: true, dress: true), prop: .herbs, hat: .scarf(0xD8CCB0)),
    ]

    /// The person facing south, built on an ordinary figure, with hat, apron and prop.
    static func figure(_ p: Painted, step: Int) -> Model {
        var m = PeopleArt.figure(p.look, step: step)
        let wood = Paint(0xB07A38, .wood(1), jitter: 0.05, shine: 0.2)
        let pale = Paint(0x8A6A42, .wood(2))
        let dark = Paint(0x5A3418, jitter: 0.05)
        let brass = Paint(0xC8A040, .metal, shine: 0.5)
        let iron = Paint(0x8A8E96, .metal, shine: 0.4)
        let hide = Paint(0xE4D8B8, jitter: 0.04)
        let linen = Paint(0xDCD0B4, .cloth, jitter: 0.05)
        if p.apron { m.box(-2.8, 3.4, 9.6, 2.8, 3.9, 20.5, linen) }
        switch p.prop {
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
        case .hoe:
            // Tall tools reach well above the head and lean out, or they vanish against the body.
            m.rod(V3(6.2, 1.8, 0.6), V3(7.6, 1.2, 35), 0.65, pale)
            m.box(6.8, 1.2, 34, 8.4, 4.6, 35.4, iron)
        case .flourSack:
            m.blob(0.8, 4.2, 16.4, 3, 2, 3, linen)
            m.ball(0.8, 4.2, 19.6, 0.9, linen)
        case .woodAxe:
            // Shouldered: the haft over the right shoulder, the head showing behind it.
            m.rod(V3(6.2, 2.6, 13.4), V3(4.2, -2.6, 30), 0.6, pale)
            m.box(3.6, -4.6, 28, 4.8, -2, 31.6, iron)
        case .crook:
            m.rod(V3(6.2, 1.8, 0.6), V3(7.6, 1.2, 35), 0.65, pale)
            m.rod(V3(7.6, 1.2, 35), V3(9.4, 1.2, 37), 0.6, pale)
            m.rod(V3(9.4, 1.2, 37), V3(10.4, 1.2, 35.2), 0.55, pale)
        case .net:
            m.blob(1.2, 4.4, 14.6, 3.6, 1.6, 3.2, Paint(0xA89A78, .cloth, jitter: 0.12))
        case .vegetables:
            m.blob(1, 4.4, 15.4, 3.4, 2, 1.8, Paint(0x8A6A3A, .wood(2)))
            m.ball(0, 4.6, 17, 1, Paint(0xE8E0D0))
            m.ball(1.8, 4.4, 17.2, 0.9, Paint(0xD8C8E0))
            m.rod(V3(2.6, 4.8, 16.8), V3(3.6, 5.2, 18.6), 0.45, Paint(0xD86A20))
            m.blob(2.2, 4.4, 18.6, 1.4, 1, 1, Paint(0x4A8A2A, .cloth))
        case .loaf:
            m.blob(0.6, 4.6, 16.4, 2.8, 1.8, 1.8, Paint(0xB8803A, jitter: 0.08))
        case .spindle:
            m.rod(V3(2.8, 4, 20), V3(1.6, 4.4, 12), 0.25, linen)
            m.blob(1.6, 4.4, 12, 0.9, 0.9, 0.6, wood)
            m.ball(3.8, 3.8, 20.4, 1.1, Paint(0xF0ECE0, .cloth))
        case .bucket:
            m.cone(0.6, 4.6, 2, 2.3, 12.4, 16.4, Paint(0x7A5228, .wood(1)))
            m.box(-1.8, 2.4, 15.6, 3, 6.8, 16, iron)
        case .herbs:
            m.rod(V3(1.6, 4.2, 13.6), V3(3.4, 4.4, 20), 0.6, Paint(0x4A6A2A, .cloth))
            m.blob(3.4, 4.4, 20.6, 1.6, 1.2, 1.6, Paint(0x5A7A34, .cloth, jitter: 0.12))
            m.ball(3.8, 4.8, 21.6, 0.6, Paint(0x8A6AB0))
        }
        switch p.hat {
        case .none: break
        case .feather:
            m.blob(0, -0.3, 28.8, 4, 4, 1.7, Paint(0x6A1A24, .cloth))
            m.blob(-2.4, -2.4, 30.4, 0.7, 2.8, 1, Paint(0xE8E0D8, .hair))
        case .straw:
            m.blob(0, -0.3, 28.6, 3.6, 3.6, 1.8, Paint(0xC8A860, .cloth, jitter: 0.1))
            m.blob(0, -0.3, 27.9, 6.4, 6.4, 0.45, Paint(0xC8A860, .cloth, jitter: 0.1))
        case .cap:
            m.blob(0, -0.6, 28.6, 3.9, 3.9, 1.9, Paint(0x6A4A3A, .cloth))
        case .scarf(let c):
            m.blob(0, -0.8, 28, 3.9, 3.8, 2.8, Paint(c, .cloth))
            m.blob(0, -3, 26.4, 2.4, 1.2, 1.8, Paint(c, .cloth))
        case .hood:
            m.blob(0, -0.8, 27.6, 4.2, 4.2, 3.4, Paint(0x5A4A3A, .cloth))
        }
        return m
    }

    static func model(_ p: Painted, facing: Direction, step: Int) -> Model {
        Posing.stand(figure(p, step: step), facing: facing, scale: PeopleArt.build(p.race))
    }
}
