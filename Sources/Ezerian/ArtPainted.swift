import Foundation
import simd

/// Folk with painted portraits. Every human but the watch is now painted from one of
/// two everyday sets, the townsfolk and the country folk, and every elf from the elf
/// set, and every orc from the orc set, whatever their trade; the earlier sets by trade
/// below are kept so the look numbers in saves stay put, and still dress the dwarf bards.
/// By trade: the bards, the peasants, the human farmhands,
/// the human townsmen and townswomen, and the humans and elves drinking in taverns. Each one's figure on the map wears the painting's colours
/// and hat, and holds what they hold in it (an instrument, a hoe, a loaf, a broom). The bard sheet's horned, red-skinned fiddler belongs
/// to no race of Ezerian, so bard painting 4 is not used.
enum PaintedFolk {
    enum Prop {
        case lute, lyre, drum, flute, harp, tambourine, hurdyGurdy
        case hoe, flourSack, woodAxe, crook, net, vegetables, loaf, spindle, bucket, herbs
        case sack, rope, broom, tray, brush, laundry, jug, pot, crate
        case pitchfork, sheaf, apples, rake, sickle, spade
        case mug, bread, dice, bowl
        case none
    }
    enum Hat { case none, feather, straw, cap(UInt32), scarf(UInt32), hood }

    struct Painted {
        /// The trade they follow ("bard", "peasant").
        var role: String
        /// The painting, Resources/Portraits/<painting>.jpg.
        var painting: String
        var look: PeopleArt.Look
        var prop: Prop
        var hat: Hat = .none
        /// The apron's colour, if they wear one.
        var apron: UInt32?
        var race: Race { look.race }
    }

    private static func look(_ race: Race, female: Bool, skin: UInt32, hair: UInt32, tunic: UInt32, legs: UInt32,
                             cape: UInt32? = nil, longHair: Bool, bald: Bool = false, beard: Bool = false, dress: Bool = false) -> PeopleArt.Look {
        PeopleArt.Look(race: race, female: female, skin: skin, hair: hair, tunic: tunic, legs: legs, cape: cape,
                       longHair: longHair, bald: bald, beard: beard, dress: dress, helmet: false)
    }

    // New lists go on the end: a person's look is their index here, kept in saves.
    static let all: [Painted] = bards + peasants + townsfolk + farmhands + elvenDrinkers + drinkers + townFolk + countryFolk + elfFolk + orcFolk
    private static let linen: UInt32 = 0xDCD0B4, leather: UInt32 = 0x5A3A22

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
                                                                  legs: 0x4A3A2A, longHair: false), prop: .flourSack, hat: .cap(0x6A4A3A), apron: linen),
        Painted(role: "peasant", painting: "peasant-2", look: look(.human, female: false, skin: 0xE8B48A, hair: 0xB8481E, tunic: 0x8A3A22,
                                                                  legs: 0x5A2A22, longHair: false, beard: true), prop: .woodAxe),
        Painted(role: "peasant", painting: "peasant-3", look: look(.human, female: false, skin: 0xC89070, hair: 0xC8C4C0, tunic: 0x5A5244,
                                                                  legs: 0x4A4234, cape: 0x5A4A3A, longHair: false, beard: true), prop: .crook, hat: .hood),
        Painted(role: "peasant", painting: "peasant-4", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x1A1410, tunic: 0x3A4A6A,
                                                                  legs: 0x3A3A3A, longHair: false, beard: true), prop: .net, apron: linen),
        Painted(role: "peasant", painting: "peasant-5", look: look(.human, female: true, skin: 0xF0C8A0, hair: 0x9A3A1E, tunic: 0x3A4A32,
                                                                  legs: 0x3A4A32, longHair: true, dress: true), prop: .vegetables, hat: .scarf(0xD8CCB0)),
        Painted(role: "peasant", painting: "peasant-6", look: look(.human, female: true, skin: 0x4A2E1E, hair: 0x1A1410, tunic: 0x5A3A2A,
                                                                  legs: 0x5A3A2A, longHair: false, dress: true), prop: .loaf, hat: .scarf(0xD8CCB0), apron: linen),
        Painted(role: "peasant", painting: "peasant-7", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xC8C4C0, tunic: 0x6A6458,
                                                                  legs: 0x6A6458, cape: 0x5A3A2A, longHair: false, dress: true), prop: .spindle, hat: .scarf(0xD8CCB0)),
        Painted(role: "peasant", painting: "peasant-8", look: look(.human, female: true, skin: 0xC89070, hair: 0x1A1410, tunic: 0xB08A3A,
                                                                  legs: 0xB08A3A, longHair: true, dress: true), prop: .bucket, hat: .scarf(0x8A2A22), apron: linen),
        Painted(role: "peasant", painting: "peasant-9", look: look(.human, female: true, skin: 0xF0D0B0, hair: 0x1A1410, tunic: 0x3A4A3A,
                                                                  legs: 0x5A5A4A, cape: 0x3A4A3A, longHair: true, dress: true), prop: .herbs, hat: .scarf(0xD8CCB0)),
    ]

    /// Human townsmen and townswomen, each with the tools or wares of a town trade.
    static let townsfolk: [Painted] = [
        Painted(role: "townsperson", painting: "townsfolk-0", look: look(.human, female: false, skin: 0xE8A88A, hair: 0x4A4440, tunic: 0x5A3A22,
                                                                        legs: 0x4A3A2A, longHair: false, beard: true), prop: .sack),
        Painted(role: "townsperson", painting: "townsfolk-1", look: look(.human, female: false, skin: 0x3A2418, hair: 0x14100C, tunic: 0xB8AA90,
                                                                        legs: 0x5A4A3A, longHair: false), prop: .rope),
        Painted(role: "townsperson", painting: "townsfolk-2", look: look(.human, female: false, skin: 0xE0B090, hair: 0xC8C4C0, tunic: 0x5A6044,
                                                                        legs: 0x4A4A3A, longHair: false, beard: true),
                prop: .broom, hat: .cap(0x5A5650)),
        Painted(role: "townsperson", painting: "townsfolk-3", look: look(.human, female: false, skin: 0xD8A27A, hair: 0x2A1A10, tunic: 0xD8CCB0,
                                                                        legs: 0x5A4A3A, longHair: false, beard: true), prop: .tray, apron: 0xC8B898),
        Painted(role: "townsperson", painting: "townsfolk-4", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x14100C, tunic: 0x4A4038,
                                                                        legs: 0x3A342E, longHair: false, beard: true), prop: .brush, apron: 0x5A4E42),
        Painted(role: "townsperson", painting: "townsfolk-5", look: look(.human, female: true, skin: 0x3A2418, hair: 0x14100C, tunic: 0x3A4A6A,
                                                                        legs: 0x3A4A6A, longHair: false, dress: true),
                prop: .laundry, hat: .scarf(0xD8CCB0)),
        Painted(role: "townsperson", painting: "townsfolk-6", look: look(.human, female: true, skin: 0xF0C8A8, hair: 0xB8481E, tunic: 0x6A4A2E,
                                                                        legs: 0x6A4A2E, longHair: false, dress: true),
                prop: .jug, hat: .scarf(0xD8CCB0), apron: linen),
        Painted(role: "townsperson", painting: "townsfolk-7", look: look(.human, female: true, skin: 0xB8805A, hair: 0x8A8680, tunic: 0x4A4A50,
                                                                        legs: 0x4A4A50, longHair: true, dress: true),
                prop: .pot, hat: .scarf(0xD8CCB0), apron: 0xC8B898),
        Painted(role: "townsperson", painting: "townsfolk-8", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xD8D4D0, tunic: 0x6A5440,
                                                                        legs: 0x6A5440, cape: 0x4A3028, longHair: false, dress: true),
                prop: .bucket, hat: .scarf(0xD8CCB0), apron: linen),
        Painted(role: "townsperson", painting: "townsfolk-9", look: look(.human, female: true, skin: 0xF0D0B0, hair: 0x14100C, tunic: 0x4A5438,
                                                                        legs: 0x4A5438, longHair: false, dress: true), prop: .crate),
    ]

    static let farmhands: [Painted] = [
        Painted(role: "farmhand", painting: "farmhand-0", look: look(.human, female: false, skin: 0xD8A07A, hair: 0x1A1410, tunic: 0xD8CCB0,
                                                                    legs: 0x4A3A2A, longHair: false, beard: true), prop: .hoe, hat: .straw),
        Painted(role: "farmhand", painting: "farmhand-1", look: look(.human, female: false, skin: 0x3A2418, hair: 0x14100C, tunic: 0x5A3A22,
                                                                    legs: 0x4A3A2A, longHair: false), prop: .pitchfork),
        Painted(role: "farmhand", painting: "farmhand-2", look: look(.human, female: false, skin: 0xE0B090, hair: 0xC8C4C0, tunic: 0x3A4A62,
                                                                    legs: 0x3A4A62, longHair: false, beard: true),
                prop: .sheaf, hat: .scarf(0x8A7A62)),
        Painted(role: "farmhand", painting: "farmhand-3", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x14100C, tunic: 0x7A7470,
                                                                    legs: 0x5A4A3A, longHair: false, beard: true), prop: .flourSack, apron: 0x8A7A62),
        Painted(role: "farmhand", painting: "farmhand-4", look: look(.human, female: false, skin: 0xF0C0A0, hair: 0xC8501E, tunic: 0x4A5432,
                                                                    legs: 0x4A5432, longHair: false, beard: true), prop: .apples),
        Painted(role: "farmhand", painting: "farmhand-5", look: look(.human, female: true, skin: 0x3A2418, hair: 0x14100C, tunic: 0x6A4A2E,
                                                                    legs: 0x6A4A2E, longHair: false, dress: true),
                prop: .rake, hat: .scarf(0xD8CCB0), apron: linen),
        Painted(role: "farmhand", painting: "farmhand-6", look: look(.human, female: true, skin: 0xD8A07A, hair: 0x14100C, tunic: 0xD8CCB0,
                                                                    legs: 0xC8B898, longHair: true, dress: true), prop: .bucket, apron: 0x4A4440),
        Painted(role: "farmhand", painting: "farmhand-7", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xC8C4C0, tunic: 0x3A4A62,
                                                                    legs: 0x3A4A62, longHair: false, dress: true),
                prop: .vegetables, hat: .scarf(0xD8CCB0), apron: 0xC8B898),
        Painted(role: "farmhand", painting: "farmhand-8", look: look(.human, female: true, skin: 0xF0D0B0, hair: 0x14100C, tunic: 0x6A4A2E,
                                                                    legs: 0x6A4A2E, longHair: false, dress: true), prop: .sickle),
        Painted(role: "farmhand", painting: "farmhand-9", look: look(.human, female: true, skin: 0xD8A07A, hair: 0x2A1A10, tunic: 0x4A5432,
                                                                    legs: 0x4A5432, longHair: false, dress: true),
                prop: .spade, hat: .scarf(0x8A5A34)),
    ]

    static let elvenDrinkers: [Painted] = [
        Painted(role: "drinker", painting: "elven-drinker-0", look: look(.elf, female: false, skin: 0xC89070, hair: 0x14100C, tunic: 0x5A3A22,
                                                                        legs: 0x2A2420, longHair: true), prop: .mug, apron: linen),
        Painted(role: "drinker", painting: "elven-drinker-1", look: look(.elf, female: false, skin: 0x5A3624, hair: 0xE0E0DC, tunic: 0x4A5A32,
                                                                        legs: 0x3A3428, longHair: false), prop: .mug),
        Painted(role: "drinker", painting: "elven-drinker-2", look: look(.elf, female: false, skin: 0xF0C8A8, hair: 0xB8481E, tunic: 0x5A3A22,
                                                                        legs: 0x3A2A22, cape: 0x26305E, longHair: false), prop: .bread),
        Painted(role: "drinker", painting: "elven-drinker-3", look: look(.elf, female: false, skin: 0xD8A27A, hair: 0xA8A4A0, tunic: 0x4A4440,
                                                                        legs: 0x3A3632, cape: 0x3A3632, longHair: true), prop: .mug),
        Painted(role: "drinker", painting: "elven-drinker-4", look: look(.elf, female: false, skin: 0xF0D0B0, hair: 0xE0C070, tunic: 0x6A1A24,
                                                                        legs: 0x3A2A22, longHair: true), prop: .dice),
        Painted(role: "drinker", painting: "elven-drinker-5", look: look(.elf, female: true, skin: 0xF4D0B8, hair: 0xB8481E, tunic: 0x4A5A32,
                                                                        legs: 0x4A5A32, longHair: true, dress: true), prop: .mug),
        Painted(role: "drinker", painting: "elven-drinker-6", look: look(.elf, female: true, skin: 0x9A6A48, hair: 0x14100C, tunic: 0x5A3A22,
                                                                        legs: 0x5A3A22, longHair: true, dress: true), prop: .mug),
        Painted(role: "drinker", painting: "elven-drinker-7", look: look(.elf, female: true, skin: 0x8A5A3A, hair: 0xD8D8D4, tunic: 0x3A4A62,
                                                                        legs: 0x3A4A62, cape: 0x26305E, longHair: true, dress: true), prop: .bowl),
        Painted(role: "drinker", painting: "elven-drinker-8", look: look(.elf, female: true, skin: 0xF0D0B8, hair: 0x14100C, tunic: 0x6A1A24,
                                                                        legs: 0x6A1A24, longHair: false, dress: true), prop: .mug),
        Painted(role: "drinker", painting: "elven-drinker-9", look: look(.elf, female: true, skin: 0x9A6A48, hair: 0xA8A4A0, tunic: 0xA07A2A,
                                                                        legs: 0xA07A2A, cape: 0x4A4440, longHair: true, dress: true), prop: .bread),
    ]

    static let drinkers: [Painted] = [
        Painted(role: "drinker", painting: "drinker-0", look: look(.human, female: false, skin: 0xE8A88A, hair: 0x5A4A3A, tunic: 0x7A2A22,
                                                                  legs: 0x3A2A22, longHair: false, beard: true), prop: .mug, apron: 0x4A3022),
        Painted(role: "drinker", painting: "drinker-1", look: look(.human, female: false, skin: 0x4A2E1E, hair: 0x14100C, tunic: 0xD8CCB0,
                                                                  legs: 0x3A3A44, longHair: false), prop: .mug, apron: 0x3A4A62),
        Painted(role: "drinker", painting: "drinker-2", look: look(.human, female: false, skin: 0xD8A27A, hair: 0xA8A4A0, tunic: 0x4A5432,
                                                                  legs: 0x3A3428, longHair: false, beard: true), prop: .bowl, hat: .cap(0x5A3A22)),
        Painted(role: "drinker", painting: "drinker-3", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x14100C, tunic: 0x5A544C,
                                                                  legs: 0x3A3632, longHair: false, beard: true), prop: .mug),
        Painted(role: "drinker", painting: "drinker-4", look: look(.human, female: false, skin: 0xF0C0A0, hair: 0xB8501E, tunic: 0x9A7A2A,
                                                                  legs: 0x4A3A2A, longHair: false, beard: true), prop: .dice),
        Painted(role: "drinker", painting: "drinker-5", look: look(.human, female: true, skin: 0x3A2418, hair: 0x14100C, tunic: 0x3A4A62,
                                                                  legs: 0x3A4A62, longHair: false, dress: true), prop: .mug, hat: .scarf(0xC8B898)),
        Painted(role: "drinker", painting: "drinker-6", look: look(.human, female: true, skin: 0xF0C8A8, hair: 0x6A3A1E, tunic: 0xD8CCB0,
                                                                  legs: 0x4A5432, longHair: false, dress: true), prop: .bread, apron: 0x4A5432),
        Painted(role: "drinker", painting: "drinker-7", look: look(.human, female: true, skin: 0xC8946A, hair: 0x14100C, tunic: 0x7A2A22,
                                                                  legs: 0x7A2A22, longHair: true, dress: true), prop: .mug),
        Painted(role: "drinker", painting: "drinker-8", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xC8C4C0, tunic: 0x7A7468,
                                                                  legs: 0x7A7468, cape: 0x4A3022, longHair: false, dress: true), prop: .bowl),
        Painted(role: "drinker", painting: "drinker-9", look: look(.human, female: true, skin: 0xF0D0B0, hair: 0x14100C, tunic: 0x9A7A2A,
                                                                  legs: 0x9A7A2A, longHair: false, dress: true), prop: .mug, apron: 0x4A3022),
    ]

    /// The everyday folk of the towns, five men then five women.
    static let townFolk: [Painted] = [
        Painted(role: "town", painting: "town-0", look: look(.human, female: false, skin: 0xE8A88A, hair: 0x6A5A4A, tunic: 0x7A4A2E,
                                                            legs: 0x4A3A2A, longHair: false, beard: true), prop: .none, apron: linen),
        Painted(role: "town", painting: "town-1", look: look(.human, female: false, skin: 0x5A3A26, hair: 0x14100C, tunic: 0x7A7468,
                                                            legs: 0x4A4038, longHair: false), prop: .none),
        Painted(role: "town", painting: "town-2", look: look(.human, female: false, skin: 0xC8946A, hair: 0x2A1E16, tunic: 0x4A5A7A,
                                                            legs: 0x4A3A2A, longHair: false, beard: true), prop: .none),
        Painted(role: "town", painting: "town-3", look: look(.human, female: false, skin: 0xD8A87A, hair: 0x14100C, tunic: 0x6A6A3A,
                                                            legs: 0x4A3A2A, longHair: false), prop: .none),
        Painted(role: "town", painting: "town-4", look: look(.human, female: false, skin: 0xD8A27A, hair: 0xD8D4D0, tunic: 0xC8B898,
                                                            legs: 0x5A5048, cape: 0x5A5654, longHair: false, beard: true), prop: .flourSack),
        Painted(role: "town", painting: "town-5", look: look(.human, female: true, skin: 0x5A3A26, hair: 0x14100C, tunic: 0x7A4A2E,
                                                            legs: 0x7A4A2E, longHair: false, dress: true), prop: .none, hat: .scarf(0xD8CCB0), apron: linen),
        Painted(role: "town", painting: "town-6", look: look(.human, female: true, skin: 0xF0C8A8, hair: 0xC8501E, tunic: 0x5A4A3A,
                                                            legs: 0x5A4A3A, longHair: false, dress: true), prop: .none, apron: linen),
        Painted(role: "town", painting: "town-7", look: look(.human, female: true, skin: 0xC8946A, hair: 0x2A1A10, tunic: 0x4A5A7A,
                                                            legs: 0x4A5A7A, cape: 0x6A4A3A, longHair: true, dress: true), prop: .none),
        Painted(role: "town", painting: "town-8", look: look(.human, female: true, skin: 0xE8C0A0, hair: 0xD8D4D0, tunic: 0xC8B898,
                                                            legs: 0xC8B898, cape: 0x5A5A32, longHair: false, dress: true), prop: .none, hat: .scarf(0xD8CCB0)),
        Painted(role: "town", painting: "town-9", look: look(.human, female: true, skin: 0xE0B090, hair: 0x14100C, tunic: 0x6A3E26,
                                                            legs: 0x6A3E26, longHair: false, dress: true), prop: .none),
    ]

    /// The everyday folk of farms and the wilds, five men then five women.
    static let countryFolk: [Painted] = [
        Painted(role: "country", painting: "country-0", look: look(.human, female: false, skin: 0xD8A27A, hair: 0x4A3020, tunic: 0x6A4028,
                                                                  legs: 0x5A4A3A, longHair: false, beard: true), prop: .hoe, apron: linen),
        Painted(role: "country", painting: "country-1", look: look(.human, female: false, skin: 0x4A2E1E, hair: 0x14100C, tunic: 0x5A3A26,
                                                                  legs: 0x4A3A2A, longHair: false, beard: true), prop: .none, apron: linen),
        Painted(role: "country", painting: "country-2", look: look(.human, female: false, skin: 0xE0B090, hair: 0xE0DCD4, tunic: 0x6A4A30,
                                                                  legs: 0x5A4A3A, longHair: false, beard: true), prop: .sack, hat: .cap(0x9A8A6A)),
        Painted(role: "country", painting: "country-3", look: look(.human, female: false, skin: 0xD0A07A, hair: 0x14100C, tunic: 0x5A5A32,
                                                                  legs: 0x4A3A2A, longHair: true, beard: true), prop: .none),
        Painted(role: "country", painting: "country-4", look: look(.human, female: false, skin: 0xF0C8A8, hair: 0xC8501E, tunic: 0x4A5A7A,
                                                                  legs: 0x4A3A2A, longHair: false), prop: .flourSack),
        Painted(role: "country", painting: "country-5", look: look(.human, female: true, skin: 0xC8946A, hair: 0x2A1A10, tunic: 0x6A3E26,
                                                                  legs: 0x6A3E26, longHair: false, dress: true), prop: .none, hat: .scarf(0x6A3E26), apron: linen),
        Painted(role: "country", painting: "country-6", look: look(.human, female: true, skin: 0x5A3A26, hair: 0x14100C, tunic: 0xA08A3A,
                                                                  legs: 0x6A4A2E, longHair: false, dress: true), prop: .sheaf),
        Painted(role: "country", painting: "country-7", look: look(.human, female: true, skin: 0xC8946A, hair: 0xA8A4A0, tunic: 0x7A6A5A,
                                                                  legs: 0x7A6A5A, cape: 0x5A4030, longHair: true, dress: true), prop: .none, hat: .scarf(0xD8CCB0)),
        Painted(role: "country", painting: "country-8", look: look(.human, female: true, skin: 0xE8B898, hair: 0x8A5A34, tunic: 0x5A5A32,
                                                                  legs: 0x5A5A32, longHair: false, dress: true), prop: .none),
        Painted(role: "country", painting: "country-9", look: look(.human, female: true, skin: 0xE0B090, hair: 0x14100C, tunic: 0xD8CCB0,
                                                                  legs: 0x6A3E2A, longHair: true, dress: true), prop: .none, apron: 0x6A3E2A),
    ]

    /// Every elf, five men then five women.
    static let elfFolk: [Painted] = [
        Painted(role: "elf", painting: "elf-0", look: look(.elf, female: false, skin: 0xC8946A, hair: 0x2A1A12, tunic: 0xDCCCB0,
                                                          legs: 0xC8B494, cape: 0xC8B494, longHair: true), prop: .none),
        Painted(role: "elf", painting: "elf-1", look: look(.elf, female: false, skin: 0x4A2E1E, hair: 0xC0BCB8, tunic: 0x3A4270,
                                                          legs: 0x3A4270, cape: 0x7A86AA, longHair: false), prop: .none),
        Painted(role: "elf", painting: "elf-2", look: look(.elf, female: false, skin: 0xF0C8A8, hair: 0xB8461E, tunic: 0xDCD4B0,
                                                          legs: 0x8A9A6A, cape: 0x9AA878, longHair: false), prop: .none),
        Painted(role: "elf", painting: "elf-3", look: look(.elf, female: false, skin: 0xD8A27A, hair: 0x2A1A12, tunic: 0x4A3A50,
                                                          legs: 0x4A3A50, cape: 0x8A7E90, longHair: true), prop: .none),
        Painted(role: "elf", painting: "elf-4", look: look(.elf, female: false, skin: 0xF0D8C8, hair: 0xE8DCC0, tunic: 0xE0D4D8,
                                                          legs: 0x9A7AAA, cape: 0x9A7AAA, longHair: true), prop: .none),
        Painted(role: "elf", painting: "elf-5", look: look(.elf, female: true, skin: 0x8A5A3A, hair: 0x1A1410, tunic: 0x9AA27A,
                                                          legs: 0x9AA27A, cape: 0xE0D4BC, longHair: true, dress: true), prop: .none),
        Painted(role: "elf", painting: "elf-6", look: look(.elf, female: true, skin: 0xF0C8A8, hair: 0xC8501E, tunic: 0x7A86B0,
                                                          legs: 0x7A86B0, cape: 0x9AA0C4, longHair: false, dress: true), prop: .none),
        Painted(role: "elf", painting: "elf-7", look: look(.elf, female: true, skin: 0xD8A882, hair: 0x1A1410, tunic: 0xE0D4BC,
                                                          legs: 0xE0D4BC, cape: 0xD8B888, longHair: true, dress: true), prop: .none),
        Painted(role: "elf", painting: "elf-8", look: look(.elf, female: true, skin: 0xE0BCA0, hair: 0xB8B4B0, tunic: 0x9A8AB4,
                                                          legs: 0x9A8AB4, cape: 0xC8BCD4, longHair: false, dress: true), prop: .none),
        Painted(role: "elf", painting: "elf-9", look: look(.elf, female: true, skin: 0xF0D0B0, hair: 0xC89A60, tunic: 0x8A9A6A,
                                                          legs: 0x8A9A6A, cape: 0xD8C8A8, longHair: true, dress: true), prop: .none),
    ]

    /// Every orc, five men then five women.
    static let orcFolk: [Painted] = [
        Painted(role: "orc", painting: "orc-0", look: look(.orc, female: false, skin: 0x7A8040, hair: 0x9A9490, tunic: 0x6A3A22,
                                                          legs: 0x4A2E22, longHair: true), prop: .none, apron: 0xD8B8A0),
        Painted(role: "orc", painting: "orc-1", look: look(.orc, female: false, skin: 0x7A8040, hair: 0x2A1A14, tunic: 0x4A5068,
                                                          legs: 0x5A3A2A, longHair: false), prop: .none),
        Painted(role: "orc", painting: "orc-2", look: look(.orc, female: false, skin: 0x7A8040, hair: 0x5A6030, tunic: 0xC8A890,
                                                          legs: 0x5A3A2A, longHair: false, bald: true), prop: .none),
        Painted(role: "orc", painting: "orc-3", look: look(.orc, female: false, skin: 0x7A8040, hair: 0x3A2016, tunic: 0xB89A80,
                                                          legs: 0x5A3A2A, cape: 0x4A4A32, longHair: true), prop: .none),
        Painted(role: "orc", painting: "orc-4", look: look(.orc, female: false, skin: 0x7A8040, hair: 0x8A8680, tunic: 0x7A2A2A,
                                                          legs: 0x4A2E22, longHair: false, beard: true), prop: .none),
        Painted(role: "orc", painting: "orc-5", look: look(.orc, female: true, skin: 0x7A8040, hair: 0x2A1414, tunic: 0x6A3A22,
                                                          legs: 0x6A3A22, longHair: true, dress: true), prop: .none, apron: 0xD8B8A0),
        Painted(role: "orc", painting: "orc-6", look: look(.orc, female: true, skin: 0x7A8040, hair: 0xD0CCC8, tunic: 0x4A5068,
                                                          legs: 0x4A5068, longHair: false, dress: true), prop: .none),
        Painted(role: "orc", painting: "orc-7", look: look(.orc, female: true, skin: 0x7A8040, hair: 0x8A2A1A, tunic: 0xA0602A,
                                                          legs: 0x6A3A22, longHair: false, dress: true), prop: .none),
        Painted(role: "orc", painting: "orc-8", look: look(.orc, female: true, skin: 0x7A8040, hair: 0x3A2420, tunic: 0xC8A890,
                                                          legs: 0x6A2A22, cape: 0x6A2A22, longHair: true, dress: true), prop: .none),
        Painted(role: "orc", painting: "orc-9", look: look(.orc, female: true, skin: 0x7A8040, hair: 0x2A1414, tunic: 0x7A746A,
                                                          legs: 0x5A3A2A, longHair: true, dress: true), prop: .none),
    ]

    /// One of Lord Draconian's people, in his black and red, with the weapon they hold (nil:
    /// none in sight, so they keep what they carry). Only the portraits are painted: on the
    /// map they wear his livery like all his servants.
    typealias Servant = (painting: String, female: Bool, weapon: Weapon?)

    /// His painted servants by race: so far his orcs and his elves (humans in his pay are
    /// painted from their everyday set).
    static func draconian(_ race: Race) -> [Servant]? {
        switch race {
        case .orc: return draconianOrcs
        case .elf: return draconianElves
        default: return nil
        }
    }

    /// His orcs. Painting 3, an orc with a crossbow, waits until there are bows.
    static let draconianOrcs: [Servant] = [
        ("draconian-orc-0", false, .shortSword), ("draconian-orc-1", false, .spear),
        ("draconian-orc-2", false, .hammer), ("draconian-orc-4", false, .axe),
        ("draconian-orc-5", true, .spear), ("draconian-orc-6", true, nil),
        ("draconian-orc-7", true, .shortSword), ("draconian-orc-8", true, .longSword),
        ("draconian-orc-9", true, .axe),
    ]

    /// His elves. Painting 3, an elf with a crossbow, likewise waits for bows.
    static let draconianElves: [Servant] = [
        ("draconian-elf-0", false, .longSword), ("draconian-elf-1", false, .spear),
        ("draconian-elf-2", false, nil), ("draconian-elf-4", false, .longSword),
        ("draconian-elf-5", true, .spear), ("draconian-elf-6", true, .shortSword),
        ("draconian-elf-7", true, nil), ("draconian-elf-8", true, .shortSword),
        ("draconian-elf-9", true, .axe),
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
        if let a = p.apron { m.box(-2.8, 3.4, 9.6, 2.8, 3.9, 20.5, Paint(a, .cloth, jitter: 0.06)) }
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
        case .sack:
            // Slung over the right shoulder.
            m.blob(4.2, 1.6, 22.4, 2.4, 2.2, 3.4, Paint(0xB8A478, .cloth, jitter: 0.1))
            m.ball(3.4, 3.2, 25.6, 1.1, Paint(0xB8A478, .cloth, jitter: 0.1))
        case .rope:
            for i in 0..<3 { m.blob(1, 4.2 + Float(i) * 0.3, 14.4 + Float(i) * 0.5, 3.2 - Float(i) * 0.3, 0.7, 3.2 - Float(i) * 0.3,
                                    Paint(0xB89A68, .cloth, jitter: 0.1)) }
        case .broom:
            m.rod(V3(6.2, 1.8, 3.4), V3(7.6, 1.2, 35), 0.6, pale)
            m.cone(6.1, 1.9, 0.6, 1.8, 0.4, 4.6, Paint(0x8A6A3A, .cloth, jitter: 0.12))
        case .tray:
            m.blob(0.6, 5, 15.6, 4.6, 2.6, 0.45, dark)
            for dx: Float in [-1.4, 2.4] {
                m.cone(0.6 + dx, 5, 0.9, 0.9, 15.9, 18.2, Paint(0x8A4A2A, jitter: 0.06, shine: 0.3))
            }
        case .brush:
            m.blob(1.6, 4.4, 15, 2, 1, 0.8, wood)
            m.blob(1.6, 4.4, 14, 1.9, 0.9, 0.6, Paint(0xC8A870, .hair))
        case .laundry:
            for (i, c) in [0xDCD4C0, 0x5A6A8A, 0xD0C8B0, 0x7A8AA0].enumerated() {
                m.blob(0.8, 4.4, 13.8 + Float(i) * 1.3, 3.8 - Float(i) * 0.3, 2, 1, Paint(UInt32(c), .cloth, jitter: 0.08))
            }
        case .jug:
            m.blob(0.6, 4.8, 15.6, 2.4, 2, 2.8, Paint(0xA8562A, jitter: 0.06, shine: 0.25))
            m.cone(0.6, 4.8, 1.4, 1.1, 17.8, 19.6, Paint(0xA8562A, jitter: 0.06, shine: 0.25))
            m.blob(0.6, 4.8, 16, 2.45, 2.05, 0.4, Paint(0x3A7A6A))
        case .pot:
            m.cone(0.6, 4.8, 2.8, 2.4, 13, 17, Paint(0x3A3632, .metal, jitter: 0.08, shine: 0.25))
            m.rod(V3(-2.2, 4.8, 17), V3(3.4, 4.8, 17), 0.3, Paint(0x3A3632, .metal))
            m.blob(-1.6, 3.8, 14.4, 1.2, 0.6, 2.2, linen)
        case .crate:
            m.box(-3.2, 3.6, 12.6, 4.2, 7.2, 17.4, Paint(0x6A4A2A, .wood(1), jitter: 0.08))
            m.box(-3.3, 3.5, 14.8, 4.3, 7.3, 15.3, dark)
        case .pitchfork:
            m.rod(V3(6.2, 1.8, 0.6), V3(7.4, 1.2, 33), 0.6, pale)
            m.rod(V3(6.4, 1.2, 33), V3(8.4, 1.2, 33), 0.3, iron)
            for dx: Float in [-1, 0, 1] { m.rod(V3(7.4 + dx, 1.2, 33), V3(7.4 + dx, 1.2, 37), 0.25, iron) }
        case .sheaf, .sickle:
            let straw = Paint(0xD8B060, .cloth, jitter: 0.12)
            m.rod(V3(-0.6, 4.6, 9.6), V3(3.4, 4.4, 24), 1.3, straw)
            m.blob(3.8, 4.4, 24.6, 1.8, 1.2, 2, straw)
            m.blob(0.8, 4.8, 16.4, 1.4, 1, 0.5, Paint(0xB08A40, .cloth))
            if p.prop == .sickle {
                m.rod(V3(-1.6, 4.8, 14.6), V3(-1.8, 5, 17.4), 0.4, dark)
                m.rod(V3(-1.8, 5, 17.4), V3(0.6, 5.4, 21), 0.35, iron)
                m.rod(V3(0.6, 5.4, 21), V3(2.4, 5.4, 19.6), 0.3, iron)
            }
        case .apples:
            m.blob(0.8, 4.8, 15, 3.8, 2.4, 1.6, Paint(0x7A5228, .wood(2)))
            for (dx, dy) in [(-2.2, 0.2), (-0.6, -0.4), (1, 0.4), (2.6, -0.2), (0, 1), (1.8, -0.8)] as [(Float, Float)] {
                m.ball(0.8 + dx, 4.8 + dy, 16.6, 0.8, Paint(0xB0242A, jitter: 0.08, shine: 0.3))
            }
        case .rake:
            m.rod(V3(6.2, 1.8, 0.6), V3(7.4, 1.2, 35), 0.6, pale)
            m.rod(V3(5.2, 1.2, 35), V3(9.6, 1.2, 35), 0.4, pale)
            for i in 0..<5 { let x = 5.4 + Float(i) * 1; m.rod(V3(x, 1.2, 35), V3(x, 2.6, 34), 0.2, pale) }
        case .spade:
            m.rod(V3(6.2, 1.8, 6), V3(7.4, 1.2, 28), 0.6, pale)
            m.box(5.8, 0.9, 28, 9, 1.6, 35, iron)
            m.rod(V3(6.2, 1.8, 6), V3(6, 1.8, 4), 0.9, pale)
        case .none:
            break
        case .mug:
            let copper = Paint(0x8A4A2A, .metal, jitter: 0.06, shine: 0.35)
            m.cone(-1.6, 4.4, 1.2, 1.1, 17, 20.4, copper)
            m.rod(V3(-3, 4.4, 18), V3(-3, 4.4, 19.8), 0.35, copper)
        case .bread:
            m.blob(0.8, 4.6, 16.6, 2.4, 1.6, 1.4, Paint(0xC8904A, jitter: 0.1))
            m.blob(1.6, 4.8, 17.4, 1, 0.8, 0.6, Paint(0xF0E0C0, jitter: 0.08))
        case .dice:
            for (dx, dz) in [(0, 0), (1.4, 0.6)] as [(Float, Float)] {
                m.box(0.4 + dx, 4.2, 16 + dz, 1.4 + dx, 5.2, 17 + dz, Paint(0xF0E8D4))
            }
        case .bowl:
            m.cone(0.6, 4.8, 1.6, 2.8, 14.6, 16.6, Paint(0x6A3A1E, .wood(1)))
            m.blob(0.6, 4.8, 16.5, 2.5, 2.5, 0.4, Paint(0xA05A2A, jitter: 0.15))
            m.rod(V3(1.8, 4.8, 16.6), V3(3.6, 4.4, 19), 0.25, Paint(0x8A6A42))
        }
        switch p.hat {
        case .none: break
        case .feather:
            m.blob(0, -0.3, 28.8, 4, 4, 1.7, Paint(0x6A1A24, .cloth))
            m.blob(-2.4, -2.4, 30.4, 0.7, 2.8, 1, Paint(0xE8E0D8, .hair))
        case .straw:
            m.blob(0, -0.3, 28.6, 3.6, 3.6, 1.8, Paint(0xC8A860, .cloth, jitter: 0.1))
            m.blob(0, -0.3, 27.9, 6.4, 6.4, 0.45, Paint(0xC8A860, .cloth, jitter: 0.1))
        case .cap(let c):
            m.blob(0, -0.6, 28.6, 3.9, 3.9, 1.9, Paint(c, .cloth))
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
