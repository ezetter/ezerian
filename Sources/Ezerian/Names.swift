import Foundation

/// Random names for towns, taverns, people and wild regions.
enum Names {
    private static let townStarts = ["Ash", "Bri", "Cal", "Dun", "Ely", "Fen", "Gal", "Hol", "Ith", "Kel", "Lor",
                                     "Mar", "Nor", "Oak", "Pel", "Quen", "Ros", "Sel", "Tor", "Ul", "Ver", "Wyn",
                                     "Yor", "Zan", "Ember", "Thorn", "Raven", "Stone", "Silver", "Wolf", "Moon"]
    private static let townEnds = ["ford", "haven", "dale", "mere", "wick", "ton", "moor", "brook", "fall", "gate",
                                   "hollow", "stead", "vale", "crest", "wood", "by", "holm", "bury", "watch", "reach"]
    private static let people = ["Aldric", "Brenna", "Cedric", "Dara", "Elwin", "Fiona", "Gareth", "Hilda", "Ivor",
                                 "Jorah", "Kara", "Lucan", "Mira", "Nolan", "Orla", "Piers", "Quinn", "Rowan",
                                 "Seren", "Tobin", "Una", "Vance", "Wren", "Yara", "Bram", "Corwin", "Edda",
                                 "Fenwick", "Greta", "Haldor", "Isolde", "Maren", "Osric", "Tamsin"]
    private static let tavernAdjectives = ["Golden", "Silver", "Prancing", "Sleeping", "Rusty", "Laughing", "Drunken",
                                           "Wandering", "Crimson", "Blue", "Green", "Black", "Jolly", "Weary",
                                           "Hidden", "Salty", "Merry", "Lucky", "Gilded", "Thirsty", "Howling"]
    private static let tavernNouns = ["Goblet", "Dragon", "Pony", "Boar", "Stag", "Griffin", "Anchor", "Lantern",
                                      "Tankard", "Unicorn", "Wyvern", "Kettle", "Fox", "Raven", "Hart", "Mermaid",
                                      "Owl", "Badger", "Barrel", "Harp", "Troll", "Gryphon"]
    private static let innNames = ["The Wayfarer's Rest", "The Quiet Hearth", "The Feathered Pillow", "The Traveller's Repose",
                                   "The Lantern Lodge", "The Warm Welcome", "The Pilgrim's Bed", "The Sleepy Shepherd",
                                   "The Moonrise Inn", "The Hearthstone Inn", "The Old Mill Inn", "The Crossroads Inn"]
    private static let virtues = ["Honesty", "Compassion", "Valor", "Justice", "Sacrifice", "Honor",
                                  "Spirituality", "Humility", "the Dawn", "the Twin Moons"]
    private static let regionAdjectives = ["Whispering", "Amber", "Silent", "Misty", "Golden", "Shadow", "Emerald",
                                           "Sunken", "Windswept", "Grey", "Ashen", "Thorny", "Hollow", "Bright",
                                           "Dusky", "Ancient", "Murmuring", "Weeping", "Lonely", "Stormy", "Verdant",
                                           "Crimson", "Elder", "Moonlit", "Serpent's", "Giant's", "Raven", "Wolfsong"]

    static func town(_ rng: inout SplitMix64) -> String { rng.pick(townStarts) + rng.pick(townEnds) }
    static func person(_ rng: inout SplitMix64) -> String { rng.pick(people) }
    static func tavern(_ rng: inout SplitMix64) -> String { "The \(rng.pick(tavernAdjectives)) \(rng.pick(tavernNouns))" }
    static func inn(_ rng: inout SplitMix64) -> String { rng.pick(innNames) }
    static func isInn(_ name: String) -> Bool { innNames.contains(name) }
    static func virtue(_ rng: inout SplitMix64) -> String { rng.pick(virtues) }

    static func regionName(for region: Region, rng: inout SplitMix64) -> String {
        var water = 0, forest = 0, high = 0, swamp = 0, sand = 0, plain = 0
        for t in region.terrain {
            switch t {
            case .deepWater, .shallowWater: water += 1
            case .forest: forest += 1
            case .mountain, .hills: high += 1
            case .swamp: swamp += 1
            case .sand: sand += 1
            default: plain += 1
            }
        }
        let total = region.terrain.count
        let nouns: [String]
        if water > total * 6 / 10 {
            nouns = ["Sea", "Bay", "Waters", "Sound", "Deep", "Shallows"]
        } else {
            let best = [(forest, 0), (high, 1), (swamp * 2, 2), (sand, 3), (plain, 4)].max { $0.0 < $1.0 }!.1
            switch best {
            case 0: nouns = ["Wood", "Forest", "Weald", "Woods", "Thicket", "Greenwood"]
            case 1: nouns = ["Hills", "Highlands", "Fells", "Crags", "Peaks", "Heights"]
            case 2: nouns = ["Marsh", "Fen", "Bog", "Mire", "Wetlands"]
            case 3: nouns = ["Dunes", "Sands", "Barrens", "Coast", "Strand"]
            default: nouns = ["Plains", "Fields", "Meadows", "Downs", "Lea", "Vale"]
            }
        }
        return "the \(rng.pick(regionAdjectives)) \(rng.pick(nouns))"
    }
}
