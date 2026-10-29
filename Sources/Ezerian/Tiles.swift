import Foundation

/// The ground layer. Every map cell has exactly one terrain.
enum Terrain: UInt8, CaseIterable {
    case deepWater, shallowWater, grass, brush, forest, swamp, sand, dirt, hills, mountain
    case cobble, woodFloor, stoneFloor, brickFloor, carpet, redCarpet, marble, field, bridge
    case stoneWall, brickWall, timberWall, logWall
    case caveFloor, caveWall

    var isWater: Bool { self == .deepWater || self == .shallowWater }

    var isWall: Bool { self == .stoneWall || self == .brickWall || self == .timberWall || self == .logWall }

    var isFloor: Bool {
        switch self {
        case .woodFloor, .stoneFloor, .brickFloor, .carpet, .redCarpet, .marble: return true
        default: return false
        }
    }

    var blocksMovement: Bool {
        switch self {
        case .deepWater, .shallowWater, .mountain, .caveWall: return true
        default: return isWall
        }
    }

    /// Natural ground meets its neighbours along organic, wobbly edges; man-made
    /// floors and walls keep straight ones.
    var isNatural: Bool {
        switch self {
        case .deepWater, .shallowWater, .grass, .brush, .forest, .swamp, .sand, .dirt, .hills,
             .mountain, .cobble, .caveFloor, .caveWall:
            return true
        default:
            return false
        }
    }

    var name: String {
        switch self {
        case .deepWater: return "deep water"
        case .shallowWater: return "shallow water"
        case .grass: return "grass"
        case .brush: return "scrubland"
        case .forest: return "the forest floor"
        case .swamp: return "swamp"
        case .sand: return "sand"
        case .dirt: return "a dirt road"
        case .hills: return "hills"
        case .mountain: return "mountains"
        case .cobble: return "cobblestones"
        case .woodFloor: return "a wooden floor"
        case .stoneFloor: return "a flagstone floor"
        case .brickFloor: return "a brick floor"
        case .carpet, .redCarpet: return "a carpet"
        case .marble: return "a marble floor"
        case .field: return "a tilled field"
        case .bridge: return "a bridge"
        case .stoneWall: return "a stone wall"
        case .brickWall: return "a brick wall"
        case .timberWall: return "a timbered wall"
        case .logWall: return "a log wall"
        case .caveFloor: return "a cave floor"
        case .caveWall: return "solid rock"
        }
    }

    /// Colour used on the overview map.
    var mapColor: UInt32 {
        switch self {
        case .deepWater: return rgb(0x1A3478)
        case .shallowWater: return rgb(0x2E5CB8)
        case .grass: return rgb(0x5A7A30)
        case .brush: return rgb(0x8A8A42)
        case .forest: return rgb(0x2C4A1C)
        case .swamp: return rgb(0x4A5230)
        case .sand: return rgb(0xC8A46A)
        case .dirt: return rgb(0x8A5A30)
        case .hills: return rgb(0x7A7A40)
        case .mountain: return rgb(0x8E8A82)
        case .cobble: return rgb(0x9A968C)
        case .woodFloor: return rgb(0x7A4A24)
        case .stoneFloor, .marble: return rgb(0xB0ACA2)
        case .brickFloor: return rgb(0xA0482A)
        case .carpet: return rgb(0x1C2A90)
        case .redCarpet: return rgb(0x9A1C1C)
        case .field: return rgb(0x6A4424)
        case .bridge: return rgb(0xA0743E)
        case .stoneWall, .brickWall, .timberWall, .logWall: return rgb(0x3A3028)
        case .caveFloor: return rgb(0x7A5232)
        case .caveWall: return rgb(0x161210)
        }
    }
}

/// Roof coverings; a building wears its roof until the Avatar steps inside.
enum RoofStyle: String, Codable, CaseIterable {
    case shingle, slate, thatch, tile
}

/// Objects standing on top of the terrain: trees, furniture, doors, signs...
enum Feature: UInt8, CaseIterable {
    case none
    // Nature
    case oakTree, pineTree, birchTree, palmTree, deadTree, appleTree, blossomTree
    case bush, berryBush, flowersRed, flowersYellow, flowersBlue, flowersWhite
    case rock, boulder, mushrooms, cactus, reeds, lilyPad, stump, fern, deadBranch
    // Outdoor structures
    case signpost, well, fountain, lampPost, fence, gravestone, graveCross
    case shrine, standingStone, campfire, haystack, wheat, cabbage, scarecrow
    case caveEntrance, ladderUp, tent, logSeat, rubble, brokenColumn, hangingSign, woodpile
    case beehive, stocks
    // Mounted in walls
    case door, window, stainedGlass, wallTorch, banner, painting
    // Interior furnishings
    case table, tableMug, tableFood, tableCandle, chair, stool, bed, bedFoot
    case barrel, keg, counter, fireplace, bookshelf, chest, candelabra
    case anvil, forge, shelf, crate, sack, pew, altar, throne, plant
    case wardrobe, weaponRack, nightstand, harpsichord, cauldron

    var blocksMovement: Bool {
        switch self {
        case .none, .flowersRed, .flowersYellow, .flowersBlue, .flowersWhite, .mushrooms, .fern,
             .lilyPad, .wheat, .cabbage, .caveEntrance, .ladderUp, .logSeat, .rubble, .door,
             .chair, .stool, .pew, .throne, .reeds, .deadBranch:
            return false
        default:
            return true
        }
    }

    var isTree: Bool {
        switch self {
        case .oakTree, .pineTree, .birchTree, .palmTree, .deadTree, .appleTree, .blossomTree: return true
        default: return false
        }
    }

    /// Plants and rocks get mirrored at random so the wilderness looks less repetitive.
    var mirrorsRandomly: Bool {
        switch self {
        case .oakTree, .pineTree, .birchTree, .palmTree, .deadTree, .appleTree, .blossomTree, .bush, .berryBush,
             .rock, .boulder, .mushrooms, .cactus, .reeds, .lilyPad, .stump, .fern, .deadBranch,
             .flowersRed, .flowersYellow, .flowersBlue, .flowersWhite, .haystack, .woodpile, .rubble:
            return true
        default:
            return false
        }
    }

    var isWallMounted: Bool {
        switch self {
        case .door, .window, .stainedGlass, .wallTorch, .banner, .painting: return true
        default: return false
        }
    }

    var name: String {
        switch self {
        case .none: return ""
        case .oakTree: return "an oak tree"
        case .pineTree: return "a pine tree"
        case .birchTree: return "a birch tree"
        case .palmTree: return "a palm tree"
        case .deadTree: return "a dead tree"
        case .appleTree: return "an apple tree"
        case .blossomTree: return "a blossoming tree"
        case .bush: return "a bush"
        case .berryBush: return "a berry bush"
        case .flowersRed, .flowersYellow, .flowersBlue, .flowersWhite: return "wildflowers"
        case .rock: return "a rock"
        case .boulder: return "a boulder"
        case .mushrooms: return "some mushrooms"
        case .cactus: return "a cactus"
        case .reeds: return "reeds"
        case .lilyPad: return "lily pads"
        case .stump: return "a tree stump"
        case .fern: return "ferns"
        case .deadBranch: return "a bleached branch"
        case .signpost: return "a signpost"
        case .well: return "a well"
        case .fountain: return "a fountain"
        case .lampPost: return "a lamp post"
        case .fence: return "a fence"
        case .gravestone: return "a gravestone"
        case .graveCross: return "a grave marker"
        case .shrine: return "a shrine"
        case .standingStone: return "a standing stone"
        case .campfire: return "a campfire"
        case .haystack: return "a haystack"
        case .wheat: return "wheat"
        case .cabbage: return "cabbages"
        case .scarecrow: return "a scarecrow"
        case .caveEntrance: return "a cave entrance"
        case .ladderUp: return "a ladder leading up"
        case .tent: return "a tent"
        case .logSeat: return "a log"
        case .rubble: return "rubble"
        case .brokenColumn: return "a broken column"
        case .hangingSign: return "a sign"
        case .woodpile: return "a woodpile"
        case .beehive: return "a beehive"
        case .stocks: return "the stocks"
        case .door: return "a door"
        case .window: return "a window"
        case .stainedGlass: return "a stained glass window"
        case .wallTorch: return "a torch"
        case .banner: return "a tapestry"
        case .painting: return "a painting"
        case .table, .tableMug, .tableFood, .tableCandle: return "a table"
        case .chair: return "a chair"
        case .stool: return "a stool"
        case .bed, .bedFoot: return "a bed"
        case .barrel: return "a barrel"
        case .keg: return "a keg of ale"
        case .counter: return "a counter"
        case .fireplace: return "a fireplace"
        case .bookshelf: return "a bookshelf"
        case .chest: return "a chest"
        case .candelabra: return "a candelabra"
        case .anvil: return "an anvil"
        case .forge: return "a forge"
        case .shelf: return "shelves of goods"
        case .crate: return "a crate"
        case .sack: return "a sack of grain"
        case .pew: return "a pew"
        case .altar: return "an altar"
        case .throne: return "a throne"
        case .plant: return "a potted plant"
        case .wardrobe: return "a wardrobe"
        case .weaponRack: return "a weapon rack"
        case .nightstand: return "a nightstand"
        case .harpsichord: return "a harpsichord"
        case .cauldron: return "a cauldron"
        }
    }
}

enum Direction: Int, CaseIterable {
    case north, east, south, west

    var dx: Int { [0, 1, 0, -1][rawValue] }
    var dy: Int { [-1, 0, 1, 0][rawValue] }

    static func from(dx: Int, dy: Int) -> Direction {
        if abs(dx) > abs(dy) { return dx > 0 ? .east : .west }
        return dy > 0 ? .south : .north
    }
}

/// Packs an opaque 0xRRGGBB colour into the framebuffer's pixel format (R in the lowest byte).
@inline(__always)
func rgb(_ hex: UInt32) -> UInt32 {
    let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
    return 0xFF00_0000 | (b << 16) | (g << 8) | r
}
