import Foundation

/// The four peoples of Ezerian. Each has a typical disposition towards strangers.
enum Race: String, Codable, CaseIterable {
    case human, elf, dwarf, orc

    /// Average friendliness of the race towards the Avatar (-100...100).
    var meanFriendliness: Int {
        switch self {
        case .human: return 25
        case .elf: return 0
        case .dwarf: return -25
        case .orc: return -50
        }
    }

    var name: String { rawValue }
    var index: Int { Race.allCases.firstIndex(of: self)! }
    var article: String { self == .elf || self == .orc ? "an" : "a" }
}

/// How an NPC feels about the Avatar, from the friendliness score.
enum Disposition: Int, Comparable {
    case hostile, unfriendly, neutral, friendly, adoring

    init(_ f: Int) {
        switch f {
        case ...(-61): self = .hostile
        case ...(-21): self = .unfriendly
        case ...19: self = .neutral
        case ...59: self = .friendly
        default: self = .adoring
        }
    }

    var word: String {
        switch self {
        case .hostile: return "Hostile"
        case .unfriendly: return "Unfriendly"
        case .neutral: return "Neutral"
        case .friendly: return "Friendly"
        case .adoring: return "Adoring"
        }
    }

    /// How the NPC regards the Avatar, for "look".
    var regard: String {
        switch self {
        case .hostile: return "glares at you with open hatred"
        case .unfriendly: return "eyes you with suspicion"
        case .neutral: return "pays you little mind"
        case .friendly: return "gives you a friendly nod"
        case .adoring: return "beams at the sight of you"
        }
    }

    static func < (a: Disposition, b: Disposition) -> Bool { a.rawValue < b.rawValue }
}

/// A person of Ezerian. Each belongs to the region it was born in and wanders
/// within its bounds (a building's floor, a town, or a stretch of wilderness).
final class NPC: Codable {
    let id: Int
    let name: String
    let race: Race
    let female: Bool
    /// Which of the race's looks (clothes, hair) the NPC wears.
    let look: Int
    /// -100 (extremely hostile) ... 100 (adoring).
    var friendliness: Int
    var x: Int
    var y: Int
    var z: Int
    let homeX: Int
    let homeY: Int
    /// Where the NPC may walk: x0, y0, x1, y1 (inclusive).
    var bounds: [Int]
    let role: String
    /// The building or town the NPC belongs to, if any (for small talk).
    let home: String?
    var facing: Int = Direction.south.rawValue
    var talks = 0
    var compliments = 0
    /// Whether the NPC has told the Avatar their name.
    var known = false
    /// The last few things said between the NPC and the Avatar, remembered across meetings.
    var memory: [String]?
    /// Travelling in the Avatar's party.
    var following: Bool {
        get { inParty ?? false }
        set { inParty = newValue }
    }
    private var inParty: Bool?
    /// Friendliness when they last refused to join or left the party (see `Party.lockedOut`).
    var refusedAt: Int?
    /// Health; at 0 the NPC dies. (Optional storage: saves from before combat lack it.)
    private var hpStore: Int?
    private var maxHPStore: Int?
    var maxHP: Int {
        get { maxHPStore ?? Populace.health(Hash.unit(0x4EA17, id, 0)) }
        set { maxHPStore = newValue }
    }
    var hp: Int {
        get { hpStore ?? maxHP }
        set { hpStore = newValue }
    }

    // Not saved: where the NPC stood before this turn (for gliding) and chatter timing.
    var prevX = 0
    var prevY = 0
    var lastShout = -100

    private enum CodingKeys: String, CodingKey {
        case id, name, race, female, look, friendliness, x, y, z, homeX, homeY, bounds, role, home, facing, talks,
             compliments, known, memory, inParty, refusedAt, hpStore = "hp", maxHPStore = "maxHP"
    }

    init(id: Int, name: String, race: Race, female: Bool, look: Int, friendliness: Int, x: Int, y: Int, z: Int,
         bounds: [Int], role: String, home: String?) {
        self.id = id
        self.name = name
        self.race = race
        self.female = female
        self.look = look
        self.friendliness = friendliness
        self.x = x
        self.y = y
        self.z = z
        homeX = x
        homeY = y
        self.bounds = bounds
        self.role = role
        self.home = home
        prevX = x
        prevY = y
    }

    var disposition: Disposition { Disposition(friendliness) }
    var he: String { female ? "she" : "he" }
    var his: String { female ? "her" : "his" }
    var him: String { female ? "her" : "him" }

    /// "Thora" once she has told you her name, otherwise "the dwarf".
    var shortName: String { known ? name : "the \(race.name)" }
    var description: String { "\(race.article) \(race.name) \(role)" }

    func mayStand(_ px: Int, _ py: Int) -> Bool {
        px >= bounds[0] && py >= bounds[1] && px <= bounds[2] && py <= bounds[3]
    }

    func changeFriendliness(by d: Int) { friendliness = max(-100, min(100, friendliness + d)) }
}

/// Where to draw an NPC this frame (position in tiles, perhaps between two).
struct NPCPose {
    var x: Double
    var y: Double
    var race: Race
    var look: Int
    var facing: Direction
    var step: Int
}

/// Settles NPCs into a freshly generated region: keepers in shops and taverns,
/// townsfolk in the streets, elves in the woods, dwarves in the hills, orc bands
/// at campfires and in caves, travellers on the roads.
enum Populace {
    static let looks = 6

    private static let firstNames: [Race: (male: [String], female: [String])] = [
        .human: (["Aldric", "Cedric", "Gareth", "Ivor", "Lucan", "Nolan", "Piers", "Tobin", "Vance", "Bram", "Corwin", "Osric",
                  "Haldor", "Edmund", "Rolf", "Simeon"],
                 ["Brenna", "Dara", "Fiona", "Hilda", "Kara", "Mira", "Orla", "Seren", "Una", "Wren", "Edda", "Greta",
                  "Isolde", "Maren", "Tamsin", "Rosalind"]),
        .elf: (["Aerendil", "Caelum", "Elrion", "Faelar", "Ilythor", "Lorien", "Saelis", "Thalion", "Vaeril", "Nimral"],
               ["Aelyth", "Caladwen", "Elowen", "Ithiriel", "Lirael", "Miriel", "Naeris", "Sylvaine", "Thessaly", "Yllana"]),
        .dwarf: (["Borin", "Dolgrim", "Durgan", "Gimrek", "Harbek", "Korgan", "Morgrin", "Thrain", "Ulfgar", "Brokk"],
                 ["Bruna", "Dagna", "Edda", "Gerda", "Helka", "Kathra", "Mardred", "Thora", "Ulla", "Vistra"]),
        .orc: (["Grishnak", "Ugluk", "Gorbag", "Muzgash", "Krull", "Thrak", "Ruzdug", "Bolg", "Nazgrub", "Skarr"],
               ["Grisha", "Ushka", "Bagra", "Murzah", "Krasha", "Volga", "Rugga", "Sharra", "Yazga", "Ghorza"]),
    ]

    /// Health from 1 to 200, mostly towards the low end: 200·u^(5/3) averages 75.
    static func health(_ u: Double) -> Int {
        max(1, min(200, Int((200 * pow(u, 5.0 / 3.0)).rounded())))
    }

    /// A friendliness drawn from a bell curve round the race's mean.
    static func friendliness(_ race: Race, _ rng: inout SplitMix64) -> Int {
        let u1 = max(1e-9, rng.double()), u2 = rng.double()
        let g = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        return max(-100, min(100, race.meanFriendliness + Int((g * 30).rounded())))
    }

    private static func pickRace(_ weights: [(Race, Double)], _ rng: inout SplitMix64) -> Race {
        var r = rng.double() * weights.reduce(0) { $0 + $1.1 }
        for (race, w) in weights {
            if r < w { return race }
            r -= w
        }
        return weights[0].0
    }

    private static let townFolk: [(Race, Double)] = [(.human, 64), (.elf, 13), (.dwarf, 15), (.orc, 8)]

    static func populate(_ region: Region, seed: UInt64) {
        let key = region.key
        var rng = SplitMix64(seed: Hash.of(seed, key.x, key.y, 7000 + key.z))
        let n = Region.size, ox = region.originX, oy = region.originY
        var taken = Set<Int>()
        var people: [NPC] = []

        func free(_ lx: Int, _ ly: Int) -> Bool {
            guard lx >= 1, ly >= 1, lx < n - 1, ly < n - 1 else { return false }
            let i = ly * n + lx
            let f = region.features[i]
            if taken.contains(i) || region.terrain[i].blocksMovement { return false }
            if f == .door || f == .caveEntrance || f == .ladderUp || f.blocksMovement { return false }
            return true
        }

        func add(_ race: Race, _ lx: Int, _ ly: Int, role: String, bounds: (Int, Int, Int, Int), home: String?) {
            let female = rng.chance(0.5)
            let names = firstNames[race]!
            let look = (female ? 3 : 0) + rng.int(3)
            let npc = NPC(id: Int(truncatingIfNeeded: Hash.of(seed, ox + lx, oy + ly, 9000 + key.z + people.count)),
                          name: rng.pick(female ? names.female : names.male), race: race, female: female, look: look,
                          friendliness: friendliness(race, &rng), x: ox + lx, y: oy + ly, z: key.z,
                          bounds: [ox + max(1, bounds.0), oy + max(1, bounds.1), ox + min(n - 2, bounds.2), oy + min(n - 2, bounds.3)],
                          role: role, home: home)
            npc.facing = rng.int(4)
            npc.maxHP = health(rng.double())
            npc.hp = npc.maxHP
            taken.insert(ly * n + lx)
            people.append(npc)
        }

        /// A free tile in a rectangle (local coordinates), or nil.
        func spot(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, where ok: (Int, Int) -> Bool = { _, _ in true }) -> (Int, Int)? {
            guard x0 <= x1, y0 <= y1 else { return nil }
            for _ in 0..<40 {
                let x = x0 + rng.int(x1 - x0 + 1), y = y0 + rng.int(y1 - y0 + 1)
                if free(x, y) && ok(x, y) { return (x, y) }
            }
            return nil
        }

        func near(_ cx: Int, _ cy: Int, _ r: Int, where ok: (Int, Int) -> Bool = { _, _ in true }) -> (Int, Int)? {
            spot(cx - r, cy - r, cx + r, cy + r, where: ok)
        }

        func terrainIs(_ ts: [Terrain]) -> (Int, Int) -> Bool { { x, y in ts.contains(region.terrain[y * n + x]) } }

        if key.z > 0 {
            // Orc bands and dwarf miners in the caverns.
            let floor = terrainIs([.caveFloor])
            if rng.chance(0.6), let c = spot(4, 4, n - 5, n - 5, where: floor) {
                for _ in 0..<(2 + rng.int(3)) {
                    if let p = near(c.0, c.1, 3, where: floor) {
                        add(.orc, p.0, p.1, role: rng.pick(["raider", "warrior", "brute"]), bounds: (c.0 - 7, c.1 - 7, c.0 + 7, c.1 + 7), home: nil)
                    }
                }
            }
            if rng.chance(0.35), let c = spot(4, 4, n - 5, n - 5, where: floor) {
                for _ in 0..<(1 + rng.int(2)) {
                    if let p = near(c.0, c.1, 2, where: floor) {
                        add(.dwarf, p.0, p.1, role: "miner", bounds: (c.0 - 6, c.1 - 6, c.0 + 6, c.1 + 6), home: nil)
                    }
                }
            }
            region.npcs = people
            return
        }

        let town = region.places.first { $0.kind == .town }
        // Keepers and residents inside buildings.
        for b in region.places where b.kind == .building {
            let x0 = b.x - ox + 1, y0 = b.y - oy + 1, x1 = b.x - ox + b.w - 2, y1 = b.y - oy + b.h - 2
            let (role, weights, chance, extra) = trade(b.name)
            guard rng.chance(chance) else { continue }
            let inside: (Int, Int) -> Bool = { x, y in region.features[(y + 1) * n + x] != .door }
            if let p = spot(x0, y0, x1, y1, where: inside) {
                add(pickRace(weights, &rng), p.0, p.1, role: role, bounds: (x0, y0, x1, y1), home: b.name)
            }
            for _ in 0..<extra {
                if let p = spot(x0, y0, x1, y1, where: inside) {
                    add(pickRace(townFolk, &rng), p.0, p.1, role: rng.pick(["patron", "traveller", "drinker"]),
                        bounds: (x0, y0, x1, y1), home: b.name)
                }
            }
        }
        // Townsfolk in the streets.
        if let t = town {
            let x0 = t.x - ox, y0 = t.y - oy, x1 = x0 + t.w - 1, y1 = y0 + t.h - 1
            let outdoors: (Int, Int) -> Bool = { x, y in
                !region.roofed.contains { $0.contains(ox + x, oy + y) }
            }
            for _ in 0..<(t.w > 40 ? 9 : 6) {
                if let p = spot(x0, y0, x1, y1, where: outdoors) {
                    let race = pickRace(townFolk, &rng)
                    let role = race == .orc ? rng.pick(["mercenary", "labourer"])
                        : rng.pick(["townsfolk", "merchant", "guard", "beggar", "bard", "farmhand", "child"])
                    add(race, p.0, p.1, role: role, bounds: (x0, y0, x1, y1), home: t.name)
                }
            }
        }
        // Folk of the wilds.
        var counts: [Terrain: Int] = [:]
        for t in region.terrain { counts[t, default: 0] += 1 }
        let total = n * n
        let wild: (Int, Int) -> Bool = { x, y in !region.roofed.contains { $0.contains(ox + x, oy + y) } && town?.contains(ox + x, oy + y) != true }
        func band(_ race: Race, _ size: Int, roles: [String], where ok: @escaping (Int, Int) -> Bool, at centre: (Int, Int)? = nil) {
            guard let c = centre ?? spot(6, 6, n - 7, n - 7, where: { ok($0, $1) && wild($0, $1) }) else { return }
            for _ in 0..<size {
                if let p = near(c.0, c.1, 3, where: { ok($0, $1) && wild($0, $1) }) {
                    add(race, p.0, p.1, role: rng.pick(roles), bounds: (c.0 - 8, c.1 - 8, c.0 + 8, c.1 + 8), home: nil)
                }
            }
        }
        if counts[.forest, default: 0] > total / 8 && rng.chance(0.55) {
            band(.elf, 1 + rng.int(3), roles: ["ranger", "wanderer", "druid", "hunter"], where: terrainIs([.forest, .grass]))
        }
        if counts[.mountain, default: 0] + counts[.hills, default: 0] > total / 10 && rng.chance(0.45) {
            band(.dwarf, 1 + rng.int(2), roles: ["prospector", "miner", "stonecutter"], where: terrainIs([.hills, .grass, .brush, .dirt]))
        }
        if let camp = region.places.first(where: { $0.name.contains("campsite") }), rng.chance(0.6) {
            band(.orc, 2 + rng.int(3), roles: ["raider", "warrior", "scout"], where: { _, _ in true },
                 at: (camp.x - ox + camp.w / 2, camp.y - oy + camp.h / 2))
        } else if counts[.brush, default: 0] + counts[.sand, default: 0] + counts[.swamp, default: 0] > total / 6 && rng.chance(0.3) {
            band(.orc, 2 + rng.int(2), roles: ["raider", "scout", "warrior"], where: terrainIs([.brush, .sand, .swamp, .grass]))
        }
        if counts[.dirt, default: 0] > 30 && rng.chance(0.4) {
            band(.human, 1 + rng.int(2), roles: ["traveller", "pilgrim", "pedlar", "woodcutter"], where: terrainIs([.dirt]))
        }
        region.npcs = people
    }

    /// Who works in a building, judged by its name: role, likely races, the chance
    /// someone is in, and how many guests besides.
    private static func trade(_ name: String) -> (String, [(Race, Double)], Double, Int) {
        if Names.isInn(name) { return ("innkeeper", [(.human, 70), (.elf, 10), (.dwarf, 15), (.orc, 5)], 1, 1) }
        if name.contains("Provisions") { return ("provisioner", [(.human, 70), (.dwarf, 15), (.elf, 10), (.orc, 5)], 1, 0) }
        if name.contains("Anvil") || name.contains("Smithy") { return ("blacksmith", [(.dwarf, 55), (.human, 40), (.orc, 5)], 1, 0) }
        if name.contains("Arms") { return ("armourer", [(.human, 45), (.dwarf, 40), (.orc, 15)], 1, 0) }
        if name.contains("Healing") || name.contains("Gentle") { return ("healer", [(.human, 60), (.elf, 40)], 1, 0) }
        if name.hasPrefix("Temple") { return ("cleric", [(.human, 70), (.elf, 30)], 1, 0) }
        if name.contains("Farmhouse") { return ("farmer", [(.human, 85), (.dwarf, 10), (.elf, 5)], 0.9, 0) }
        if name.contains("Cottage") { return ("cottager", [(.human, 70), (.elf, 20), (.dwarf, 10)], 0.8, 0) }
        if name.hasSuffix("House") { return ("householder", townFolk, 0.7, 0) }
        return ("barkeep", [(.human, 60), (.dwarf, 20), (.elf, 10), (.orc, 10)], 1, 2)
    }
}
