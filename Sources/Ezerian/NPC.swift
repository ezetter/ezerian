import Foundation

/// The four peoples of Ezerian. Each has a typical disposition towards strangers.
enum Race: String, Codable, CaseIterable {
    case human, elf, dwarf, orc
    /// Not a people but beasts of the wilds, in packs: they never talk, carry nothing,
    /// and bite for 1-10.
    case wolf

    /// Average friendliness of the race towards the Avatar (-100...100).
    var meanFriendliness: Int {
        switch self {
        case .human: return 25
        case .elf: return 0
        case .dwarf: return -25
        case .orc: return -50
        case .wolf: return -75
        }
    }

    var name: String { rawValue }
    var isBeast: Bool { self == .wolf }
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
    // (Name and sex change only for a dwarf woman from an older save: dwarves are all men.)
    private(set) var name: String
    let race: Race
    private(set) var female: Bool
    /// Which of the race's looks (clothes, hair) the NPC wears.
    var look: Int
    /// -100 (extremely hostile) ... 100 (adoring).
    var friendliness: Int
    var x: Int
    var y: Int
    var z: Int
    let homeX: Int
    let homeY: Int
    /// Where the NPC may walk: x0, y0, x1, y1 (inclusive).
    var bounds: [Int]
    var role: String
    /// The building or town the NPC belongs to, if any (for small talk).
    let home: String?
    var facing: Int = Direction.south.rawValue
    var talks = 0
    var compliments = 0
    /// For a newcomer, the id of the person on the region's first roll whose place they
    /// took (see `Game.fillEmptyPlaces`).
    var slot: Int?
    /// The place on the region's first roll that this person fills.
    var place: Int { slot ?? id }
    /// The day flattery last warmed them, and how many compliments did that day.
    private var flatteredDay: Int?
    private var flatteredCount: Int?
    /// Only this many compliments a day raise someone's friendliness; insults always count.
    static let complimentsPerDay = 2
    /// Whether a compliment paid on `day` can still raise their friendliness.
    func flatterable(on day: Int) -> Bool { flatteredDay != day || (flatteredCount ?? 0) < NPC.complimentsPerDay }
    /// Counts a compliment that raised their friendliness on `day`.
    func flattered(on day: Int) {
        flatteredCount = flatteredDay == day ? (flatteredCount ?? 0) + 1 : 1
        flatteredDay = day
    }
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
    /// The most gold they have turned down to join the party (they want more next time).
    var hireRefused: Int?
    /// Adventurers are the only folk who will join the Avatar's party.
    var isAdventurer: Bool { role == "adventurer" }
    /// The Avatar has attacked them (or someone they were defending).
    var struckByAvatar: Bool {
        get { struckStore ?? false }
        set { struckStore = newValue }
    }
    private var struckStore: Bool?
    /// Openly serves Lord Draconian, Wizard Lord and Emperor of Sespooland, in his livery.
    var servesDraconian: Bool {
        get { draconianStore ?? false }
        set { draconianStore = newValue }
    }
    private var draconianStore: Bool?
    /// Secretly in Draconian's pay: one in ten of the ordinary humans, elves and dwarves, the watch
    /// among them (a traitor in the watch never comes to the Avatar's aid). They look
    /// and live like anyone else, until a fight unmasks them.
    var agent: Bool {
        get { agentStore ?? false }
        set { agentStore = newValue ? true : nil }
    }
    private var agentStore: Bool?
    /// A hidden agent who has shown their true allegiance (by fighting the Avatar's party).
    var unmasked: Bool {
        get { unmaskedStore ?? false }
        set { unmaskedStore = newValue ? true : nil }
    }
    private var unmaskedStore: Bool?
    /// Known to stand with Draconian: his open servants, and agents who have been unmasked.
    var openlyDraconian: Bool { servesDraconian || (agent && unmasked) }
    /// Truly his, whether or not anyone knows it.
    var forDraconian: Bool { servesDraconian || agent }
    /// Members of one of Draconian's roving warbands share a band number.
    var warband: Int?
    /// The painting shown when talking to someone whose figure isn't painted (Lord
    /// Draconian's humans keep his livery on the map).
    var portrait: String?
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
    /// Gold coins carried, about one for every 10 points of starting health.
    private var goldStore: Int?
    var gold: Int {
        get {
            if let g = goldStore { return g }
            if race.isBeast { return 0 }
            var rng = SplitMix64(seed: Hash.of(0x601D, id, 0))
            return Populace.coins(forHealth: maxHP, &rng)
        }
        set { goldStore = newValue }
    }
    /// The weapon carried, if any. (Stored as 0 for none; missing in older saves, where
    /// it is drawn the same way as for new people.)
    private var weaponStore: Int?
    var weapon: Weapon? {
        get {
            if race.isBeast { return nil }
            if let w = weaponStore { return Weapon(rawValue: w) }
            if let r = guardRank { return .forGuard(rank: r) }
            var rng = SplitMix64(seed: Hash.of(0x3EA90, id, 0))
            return Weapon.roll(health: maxHP, servant: servesDraconian, child: role == "child", &rng)
        }
        set { weaponStore = newValue?.rawValue ?? 0 }
    }
    /// Dwarves are all men, and none serves Lord Draconian. Older saves may have dwarf
    /// women (who become men of the same standing, with a man's name) and dwarf
    /// mercenaries in his pay (who become free warriors).
    func dwarvesAreMenOfNoLord() {
        if female {
            female = false
            let men = Populace.firstNames[.dwarf]!.male
            name = men[Int(Hash.of(0xD3A2F, id, 0) % UInt64(men.count))]
        }
        if servesDraconian {
            servesDraconian = false
            if role == "mercenary" { role = "warrior" }
        }
    }

    /// Experience from foes the party has defeated, for companions (never shown).
    private var xpStore: Int?
    var experience: Int {
        get { xpStore ?? 0 }
        set { xpStore = newValue == 0 ? nil : newValue }
    }

    /// What else they carry besides the weapon in hand (companions fill this; see `Inventory`).
    private var packStore: [Item]?
    var pack: [Item] {
        get { packStore ?? [] }
        set { packStore = newValue.isEmpty ? nil : newValue }
    }

    /// "his short sword", or "his bare hands".
    var armedWith: String { race == .wolf ? "its fangs" : "\(his) \(weapon?.name ?? "bare hands")" }

    // Not saved: where the NPC stood before this turn (for gliding) and chatter timing.
    var prevX = 0
    var prevY = 0
    var lastShout = -100
    /// Until this turn they keep clear of the Avatar, having fled from them in a fight.
    var cowedUntil = -1

    private enum CodingKeys: String, CodingKey {
        case id, name, race, female, look, friendliness, x, y, z, homeX, homeY, bounds, role, home, facing, talks,
             compliments, flatteredDay, flatteredCount, known, memory, inParty, refusedAt, hireRefused, struckStore = "struck", slot, hpStore = "hp", maxHPStore = "maxHP", draconianStore = "draconian", warband, portrait, goldStore = "gold", weaponStore = "weapon", packStore = "pack", xpStore = "xp", agentStore = "agent", unmaskedStore = "unmasked"
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

    /// The painted portrait shown when talking to them: every human, and the painted
    /// folk of the other races.
    var painting: String? {
        if let r = guardRank { return Portraits.guardName(rank: r, female: female) }
        if let p = portrait { return p }
        if let p = Populace.painted(look: look), p.race == race { return p.painting }
        return nil
    }

    /// The rank in the town watch (0 watchman ... 4 knight), for guards.
    var guardRank: Int? { race == .human ? Populace.guardRank(look: look)?.rank : nil }

    /// How tough they look, so the Avatar can judge a fight before picking it.
    var build: String {
        let look: String
        switch maxHP {
        case _ where race.isBeast: look = maxHP < 24 ? "young and lean" : maxHP < 38 ? "rangy and grey" : "big and grizzled"
        case ..<40: look = "slight and frail"
        case ..<80: look = "of ordinary build"
        case ..<120: look = "sturdy"
        case ..<160: look = "powerfully built"
        default: look = "huge and formidable"
        }
        let f = Double(hp) / Double(max(1, maxHP))
        return look + (f < 0.35 ? ", and badly hurt" : f < 0.75 ? ", and wounded" : "")
    }
    var he: String { race.isBeast ? "it" : female ? "she" : "he" }
    var his: String { race.isBeast ? "its" : female ? "her" : "his" }
    var him: String { race.isBeast ? "it" : female ? "her" : "him" }

    /// "Thora" once she has told you her name, otherwise "the dwarf".
    /// What they do, as others would name them: a townsman or townswoman for the plain
    /// folk of the streets (stored as "townsperson", or "townsfolk" in older saves).
    var title: String { role == "townsperson" || role == "townsfolk" ? (female ? "townswoman" : "townsman") : role }
    /// Humans (and so the watch) are known by their trade until introduced: "the bard",
    /// "the watchwoman"; the other races by their race: "the dwarf".
    private var knownBy: String { race == .human ? title : elvenDrinker ? kind : race.name }
    /// Elves drinking in a tavern are "elven drinkers", not "elf drinkers".
    private var elvenDrinker: Bool { race == .elf && role == "drinker" }
    /// Race and trade together: "human farmhand", "elven drinker".
    var kind: String { race.isBeast ? race.name : elvenDrinker ? "elven \(title)" : "\(race.name) \(title)" }
    var shortName: String { known ? name : "the \(knownBy)" }
    /// "A dwarf", or "An innkeeper", for someone not yet introduced.
    var stranger: String {
        let vowel = knownBy.first.map { "aeiou".contains($0) } ?? false
        return (vowel ? "An " : "A ") + knownBy
    }
    var description: String {
        if race.isBeast { return "\(race.article) \(kind)" }
        // What the eye sees, never whom they serve: his people's black and red is only their dress.
        return "\(race.article) \(kind)" + (servesDraconian ? " in a black tabard with a red sigil and a red cloak" : "")
            + (weapon.map { ", armed with a \($0.name)" } ?? ", unarmed")
    }

    func mayStand(_ px: Int, _ py: Int) -> Bool {
        px >= bounds[0] && py >= bounds[1] && px <= bounds[2] && py <= bounds[3]
    }

    /// Draconian's people never warm to the Avatar above 0, whatever is said; wolves never
    /// above -50.
    func changeFriendliness(by d: Int) {
        friendliness = max(-100, min(race == .wolf ? Populace.wolfFriendliness.upperBound : forDraconian ? 0 : 100, friendliness + d))
    }
}

/// Where to draw an NPC this frame (position in tiles, perhaps between two).
struct NPCPose {
    var x: Double
    var y: Double
    var race: Race
    var look: Int
    var facing: Direction
    var step: Int
    var weapon: Weapon?
}

/// Settles NPCs into a freshly generated region: keepers in shops and taverns,
/// townsfolk in the streets, elves in the woods, dwarves in the hills, orc bands
/// at campfires and in caves, travellers on the roads.
enum Populace {
    /// 0-2 men, 3-5 women, 6-7 Lord Draconian's livery (man, woman), then the town
    /// watch: two looks (man, woman) for each of its five ranks, then the painted folk
    /// (bards and peasants), one look each.
    static let paintedLooks = 8 + 2 * GuardArt.ranks
    static let looks = paintedLooks + PaintedFolk.all.count

    static func painted(look: Int) -> PaintedFolk.Painted? {
        look >= paintedLooks && look < looks ? PaintedFolk.all[look - paintedLooks] : nil
    }
    /// The race a look belongs to, for the looks only one race wears (the watch, the painted folk).
    static func lookRace(_ look: Int) -> Race? {
        guardRank(look: look) != nil ? .human : painted(look: look)?.race
    }

    /// The everyday set someone is painted from, if any: every elf from the elf set,
    /// every orc from the orc set;
    /// human children from the children; human barkeeps from the barkeepers; adventurers of every race from the adventurers;
    /// every other human but the watch from the townsfolk if they live in a town, or the
    /// country folk if they live at a farmhouse or in the wilds.
    static func everydaySet(_ n: NPC) -> [PaintedFolk.Painted]? {
        if n.role == "adventurer" { return PaintedFolk.adventurers }
        if n.race == .dwarf { return n.role == "warrior" ? PaintedFolk.dwarfWarriors : PaintedFolk.dwarfFolk }
        if n.race == .elf { return PaintedFolk.elfFolk }
        if n.race == .orc { return PaintedFolk.orcFolk }
        guard n.race == .human, n.guardRank == nil else { return nil }
        if n.role == "child" { return PaintedFolk.humanChildren }
        if n.role == "barkeep" { return PaintedFolk.barkeepers }
        return n.home.map { $0.hasSuffix("Farmhouse") } ?? true ? PaintedFolk.countryFolk : PaintedFolk.townFolk
    }

    /// Paints someone from their everyday set. Draconian's servants keep his livery on
    /// the map and are only given the portrait. The pick is fixed by who they are, so it
    /// is the same each time (it also repaints people from older saves). His humans, elves
    /// and orcs have paintings of their own, and carry the weapon theirs shows, as do dwarf
    /// warriors.
    static func paint(_ n: NPC) {
        if n.race == .dwarf { n.dwarvesAreMenOfNoLord() }
        if n.servesDraconian, let set = PaintedFolk.draconian(n.race) {
            let mine = set.filter { $0.female == n.female }
            let pick = mine[Int(Hash.of(0xD7A60, n.id, 0) % UInt64(mine.count))]
            n.portrait = pick.painting
            if let w = pick.weapon, n.hp > 0 { n.weapon = w }
            return
        }
        guard let set = everydaySet(n) else { return }
        let mine = set.indices.filter { set[$0].look.female == n.female && set[$0].race == n.race }
        let pick = mine[Int(Hash.of(0x9A1D7, n.id, 0) % UInt64(mine.count))]
        if n.servesDraconian {
            n.portrait = set[pick].painting
        } else if !set.contains(where: { $0.painting == painted(look: n.look)?.painting }) {
            n.look = paintedLooks + PaintedFolk.all.firstIndex { $0.painting == set[pick].painting }!
            n.portrait = nil
        }
        if let w = painted(look: n.look)?.weapon, n.hp > 0, !n.servesDraconian { n.weapon = w }
    }

    static func guardLook(rank: Int, female: Bool) -> Int { 8 + rank * 2 + (female ? 1 : 0) }
    static func guardRank(look: Int) -> (rank: Int, female: Bool)? {
        look >= 8 && look < paintedLooks ? ((look - 8) / 2, look % 2 == 1) : nil
    }

    /// How common each rank of the watch is: watchmen, serjeants, men-at-arms (the
    /// captain is chosen apart), knights.
    private static let watchRanks: [(Int, Double)] = [(0, 45), (1, 30), (2, 20), (4, 5)]
    /// Health by rank in the watch, so a higher rank is always tougher: watchmen
    /// 40-69, serjeants 70-99, men-at-arms 100-129, captains 130-159, knights 160-200.
    static let guardHealth: [ClosedRange<Int>] = [40...69, 70...99, 100...129, 130...159, 160...200]

    static func guardHealth(rank: Int, _ u: Double) -> Int {
        let r = guardHealth[rank]
        return min(r.upperBound, r.lowerBound + Int(u * Double(r.count)))
    }

    /// Wolves: 10-50 health, and friendliness from -100 to -50.
    static let wolfHealth = 10...50, wolfFriendliness = -100 ... -50

    /// Adventurers: the only folk who will take up with the Avatar. They are between half as
    /// hardy as the Avatar and a quarter again as hardy (when they are met).
    static func adventurerHealth(avatar: Int, _ u: Double) -> Int {
        max(1, Int((Double(avatar) * (0.5 + 0.75 * u)).rounded()))
    }
    /// Their races, about as many of each as there are paintings.
    private static let adventurerRaces: [(Race, Double)] = [(.human, 40), (.elf, 20), (.dwarf, 20), (.orc, 20)]

    static let firstNames: [Race: (male: [String], female: [String])] = [
        .wolf: (["Wolf"], ["Wolf"]),
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

    /// A purse of coins for someone of this much starting health: random (Poisson),
    /// averaging a tenth of the health.
    static func coins(forHealth health: Int, _ rng: inout SplitMix64) -> Int {
        let limit = exp(-Double(max(0, health)) / 10)
        var k = 0
        var p = rng.double()
        while p > limit && k < 200 {
            k += 1
            p *= rng.double()
        }
        return k
    }

    /// A friendliness drawn from a bell curve round the race's mean.
    static func friendliness(_ race: Race, _ rng: inout SplitMix64) -> Int {
        max(-100, min(100, race.meanFriendliness + Int((gaussian(&rng) * 30).rounded())))
    }

    /// Lord Draconian's people: always between -100 and 0. His orcs are half again as
    /// unfriendly as other orcs (averaging -75); his mercenaries average -50.
    static func servantFriendliness(_ race: Race, _ rng: inout SplitMix64) -> Int {
        let (mean, spread) = race == .orc ? (-76.0, 20.0) : (-50.0, 30.0)
        return max(-100, min(0, Int((mean + gaussian(&rng) * spread).rounded())))
    }

    private static func gaussian(_ rng: inout SplitMix64) -> Double {
        let u1 = max(1e-9, rng.double()), u2 = rng.double()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// Chance that an orc outside a warband serves Lord Draconian. The warbands are all
    /// his and the orc adventurers all free, so this is set so that, counting both, three orcs in four serve him.
    static let orcAllegiance = 0.7

    /// Mercenaries Draconian has hired: humans and elves (most orcs serve him anyway).
    /// (Never dwarves: they serve no lord, though plenty of them are hostile all the same.)
    private static let hirelings: [(Race, Double)] = [(.human, 60), (.elf, 15)]

    private static func pickRace(_ weights: [(Race, Double)], _ rng: inout SplitMix64) -> Race {
        var r = rng.double() * weights.reduce(0) { $0 + $1.1 }
        for (race, w) in weights {
            if r < w { return race }
            r -= w
        }
        return weights[0].0
    }

    private static let townFolk: [(Race, Double)] = [(.human, 64), (.elf, 13), (.dwarf, 15), (.orc, 8)]

    static func populate(_ region: Region, seed: UInt64, avatarHealth: Int = 100) {
        region.npcs = roster(region, seed: seed, avatarHealth: avatarHealth)
    }

    /// Makes one person: their sex, name, looks, mood, health, purse and weapon, drawn
    /// from `rng`. `draconian` nil: orcs serve Lord Draconian on the toss of a coin, others
    /// don't. (Positions and bounds are in world coordinates.)
    static func person(id: Int, race: Race, x: Int, y: Int, z: Int, role: String, bounds: [Int], home: String?,
                       draconian: Bool? = nil, warband: Int? = nil, guardRank: Int? = nil, avatarHealth: Int,
                       _ rng: inout SplitMix64) -> NPC {
        let female = rng.chance(0.5) && race != .dwarf
        let names = firstNames[race]!
        let servant = guardRank == nil && race != .dwarf && (draconian ?? (race == .orc && rng.chance(orcAllegiance)))
        var look = servant ? (female ? 7 : 6) : (female ? 3 : 0) + rng.int(3)
        var job = servant && draconian == nil && home != nil ? "mercenary" : role
        if let r = guardRank {
            look = guardLook(rank: r, female: female)
            job = GuardArt.title(r, female: female)
        }
        // (Everyone but the watch is then painted from their race's everyday set: see `paint`.)
        let npc = NPC(id: id, name: rng.pick(female ? names.female : names.male), race: race, female: female, look: look,
                      friendliness: servant ? servantFriendliness(race, &rng) : friendliness(race, &rng),
                      x: x, y: y, z: z, bounds: bounds, role: job, home: home)
        npc.servesDraconian = servant
        npc.warband = warband
        npc.facing = rng.int(4)
        let u = rng.double()
        npc.maxHP = guardRank.map { guardHealth(rank: $0, u) } ?? health(u)
        npc.hp = npc.maxHP
        npc.gold = coins(forHealth: npc.maxHP, &rng)
        npc.weapon = guardRank.map { Weapon.forGuard(rank: $0) }
            ?? Weapon.roll(health: npc.maxHP, servant: servant, child: job == "child", &rng)
        if job == "adventurer" {
            // Adventurers go unarmed, for now.
            npc.maxHP = adventurerHealth(avatar: avatarHealth, u)
            npc.hp = npc.maxHP
            _ = rng.int(51)   // (once their mood; kept so the rest of the world is drawn as before)
            npc.gold = coins(forHealth: npc.maxHP, &rng)
            npc.weapon = nil
        }
        if race.isBeast {
            // Wolves carry nothing, and are never anything but dangerous.
            npc.look = 0
            npc.maxHP = wolfHealth.lowerBound + rng.int(wolfHealth.count)
            npc.hp = npc.maxHP
            npc.friendliness = wolfFriendliness.lowerBound + rng.int(wolfFriendliness.count)
            npc.gold = 0
            npc.weapon = nil
        } else {
            paint(npc)
        }
        temper(npc)
        // Merchants and pedlars carry a few things to sell.
        if Trade.isMerchant(npc) { npc.pack = Trade.merchantGoods(id: npc.id) }
        return npc
    }

    /// How ordinary folk feel about the Avatar when first met, and whether they secretly serve
    /// Draconian. Humans, elves and dwarves range evenly from -50 to 50, the watch, shopkeepers and
    /// adventurers among them; free orcs from -100 to -1 (though they can be won round). One in ten
    /// of the humans, elves and dwarves (the watch too, but not children or adventurers) is his hidden agent,
    /// from -100 to -51. Fixed by who they are, so it is the same every time.
    static let agentShare = 0.1
    static let folkFriendliness = -50...50, orcFriendliness = -100 ... -1, agentFriendliness = -100 ... -51

    static func temper(_ n: NPC) {
        guard !n.race.isBeast, !n.servesDraconian else { return }
        func pick(_ r: ClosedRange<Int>) -> Int {
            r.lowerBound + min(r.count - 1, Int(Hash.unit(0x7E3B, n.id, 0) * Double(r.count)))
        }
        n.agent = n.race != .orc && n.role != "child" && !n.isAdventurer
            && Hash.unit(0xA6E7, n.id, 0) < agentShare
        n.friendliness = pick(n.agent ? agentFriendliness : n.race == .orc ? orcFriendliness : folkFriendliness)
    }

    /// The people a region is first given, the same every time for the same world: who
    /// lives and roams there at the start (and whose places newcomers later fill).
    static func roster(_ region: Region, seed: UInt64, avatarHealth: Int = 100) -> [NPC] {
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

        func add(_ race: Race, _ lx: Int, _ ly: Int, role: String, bounds: (Int, Int, Int, Int), home: String?,
                 draconian: Bool? = nil, warband: Int? = nil, guardRank: Int? = nil) {
            let npc = person(id: Int(truncatingIfNeeded: Hash.of(seed, ox + lx, oy + ly, 9000 + key.z + people.count)),
                             race: race, x: ox + lx, y: oy + ly, z: key.z, role: role,
                             bounds: [ox + max(1, bounds.0), oy + max(1, bounds.1), ox + min(n - 2, bounds.2), oy + min(n - 2, bounds.3)],
                             home: home, draconian: draconian, warband: warband, guardRank: guardRank,
                             avatarHealth: avatarHealth, &rng)
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
                let theirs = rng.chance(orcAllegiance)
                for _ in 0..<(2 + rng.int(3)) {
                    if let p = near(c.0, c.1, 3, where: floor) {
                        add(.orc, p.0, p.1, role: rng.pick(["raider", "warrior", "brute"]), bounds: (c.0 - 7, c.1 - 7, c.0 + 7, c.1 + 7),
                            home: nil, draconian: theirs)
                    }
                }
            }
            if rng.chance(0.35), let c = spot(4, 4, n - 5, n - 5, where: floor) {
                for _ in 0..<(1 + rng.int(2)) {
                    if let p = near(c.0, c.1, 2, where: floor) {
                        add(.dwarf, p.0, p.1, role: rng.pick(["miner", "miner", "warrior"]), bounds: (c.0 - 6, c.1 - 6, c.0 + 6, c.1 + 6), home: nil)
                    }
                }
            }
            return people
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
                    if rng.chance(0.2) {
                        add(pickRace(hirelings, &rng), p.0, p.1, role: "mercenary", bounds: (x0, y0, x1, y1), home: b.name, draconian: true)
                    } else {
                        add(pickRace(townFolk, &rng), p.0, p.1, role: rng.pick(["patron", "traveller", "drinker"]),
                            bounds: (x0, y0, x1, y1), home: b.name)
                    }
                }
            }
        }
        // Peasants working the land round farmhouses out in the country.
        for b in region.places where b.kind == .building && b.name.hasSuffix("Farmhouse") && town?.contains(b.x, b.y) != true {
            let x0 = b.x - ox - 6, y0 = b.y - oy - 6, x1 = b.x - ox + b.w + 5, y1 = b.y - oy + b.h + 5
            let outside: (Int, Int) -> Bool = { x, y in !region.roofed.contains { $0.contains(ox + x, oy + y) } }
            for _ in 0..<(1 + rng.int(2)) {
                if let p = spot(max(1, x0), max(1, y0), min(n - 2, x1), min(n - 2, y1), where: outside) {
                    add(.human, p.0, p.1, role: "peasant", bounds: (x0, y0, x1, y1), home: b.name)
                }
            }
        }
        // The town watch, then townsfolk, in the streets.
        if let t = town {
            let x0 = t.x - ox, y0 = t.y - oy, x1 = x0 + t.w - 1, y1 = y0 + t.h - 1
            let outdoors: (Int, Int) -> Bool = { x, y in
                !region.roofed.contains { $0.contains(ox + x, oy + y) }
            }
            let big = t.w > 40
            for k in 0..<(big ? 4 : 2 + rng.int(2)) {
                // A big town's watch has a captain; the rest are drawn by how common their rank is.
                var rank = watchRanks[0].0
                if big && k == 0 {
                    rank = 3
                } else {
                    var r = rng.double() * watchRanks.reduce(0) { $0 + $1.1 }
                    for (rk, w) in watchRanks { if r < w { rank = rk; break }; r -= w }
                }
                if let p = spot(x0, y0, x1, y1, where: outdoors) {
                    add(.human, p.0, p.1, role: "", bounds: (x0, y0, x1, y1), home: t.name, guardRank: rank)
                }
            }
            for _ in 0..<(t.w > 40 ? 9 : 6) {
                if let p = spot(x0, y0, x1, y1, where: outdoors) {
                    if rng.chance(0.15) {
                        // One of Draconian's hired swords, loitering in the streets.
                        add(pickRace(hirelings, &rng), p.0, p.1, role: "mercenary", bounds: (x0, y0, x1, y1), home: t.name, draconian: true)
                        continue
                    }
                    let race = pickRace(townFolk, &rng)
                    // (Peasants, like their portraits, are all human.)
                    let role = race == .orc ? rng.pick(["labourer", "porter", "drover"])
                        : race == .human ? rng.pick(["townsperson", "townsperson", "merchant", "beggar", "bard", "peasant", "farmhand", "child"])
                        : race == .dwarf ? rng.pick(["townsperson", "townsperson", "merchant", "beggar", "bard", "warrior", "child"])
                        : rng.pick(["townsperson", "townsperson", "merchant", "beggar", "bard", "farmhand", "child"])
                    add(race, p.0, p.1, role: role, bounds: (x0, y0, x1, y1), home: t.name)
                }
            }
        }
        // Folk of the wilds.
        var counts: [Terrain: Int] = [:]
        for t in region.terrain { counts[t, default: 0] += 1 }
        let total = n * n
        let wild: (Int, Int) -> Bool = { x, y in !region.roofed.contains { $0.contains(ox + x, oy + y) } && town?.contains(ox + x, oy + y) != true }
        func band(_ race: Race, _ size: Int, roles: [String], where ok: @escaping (Int, Int) -> Bool, at centre: (Int, Int)? = nil,
                  draconian: Bool? = nil) {
            guard let c = centre ?? spot(6, 6, n - 7, n - 7, where: { ok($0, $1) && wild($0, $1) }) else { return }
            let theirs = race == .orc ? (draconian ?? rng.chance(orcAllegiance)) : draconian
            for _ in 0..<size {
                if let p = near(c.0, c.1, 3, where: { ok($0, $1) && wild($0, $1) }) {
                    add(race, p.0, p.1, role: rng.pick(roles), bounds: (c.0 - 8, c.1 - 8, c.0 + 8, c.1 + 8), home: nil, draconian: theirs)
                }
            }
        }
        if counts[.forest, default: 0] > total / 8 && rng.chance(0.55) {
            band(.elf, 1 + rng.int(3), roles: ["ranger", "wanderer", "druid", "hunter"], where: terrainIs([.forest, .grass]))
        }
        if counts[.mountain, default: 0] + counts[.hills, default: 0] > total / 10 && rng.chance(0.45) {
            band(.dwarf, 1 + rng.int(2), roles: ["prospector", "miner", "stonecutter", "warrior", "warrior"], where: terrainIs([.hills, .grass, .brush, .dirt]))
        }
        if let camp = region.places.first(where: { $0.name.contains("campsite") }), rng.chance(0.75) {
            band(.orc, 2 + rng.int(3), roles: ["raider", "warrior", "scout"], where: { _, _ in true },
                 at: (camp.x - ox + camp.w / 2, camp.y - oy + camp.h / 2))
        } else if counts[.brush, default: 0] + counts[.sand, default: 0] + counts[.swamp, default: 0] > total / 8 && rng.chance(0.45) {
            band(.orc, 2 + rng.int(2), roles: ["raider", "scout", "warrior"], where: terrainIs([.brush, .sand, .swamp, .grass]))
        }
        // A pack of wolves, out in the wilds only.
        if town == nil, rng.chance(0.3) {
            band(.wolf, 3 + rng.int(4), roles: ["wolf"], where: terrainIs([.forest, .grass, .hills, .brush]))
        }
        if counts[.dirt, default: 0] > 30 && rng.chance(0.4) {
            band(.human, 1 + rng.int(2), roles: ["traveller", "pilgrim", "pedlar", "woodcutter", "peasant"], where: terrainIs([.dirt]))
        }
        // Draconian's mercenaries out on the roads and in the countryside.
        if rng.chance(0.25), let c = spot(6, 6, n - 7, n - 7, where: { terrainIs([.dirt, .grass, .brush])($0, $1) && wild($0, $1) }) {
            for _ in 0..<(1 + rng.int(3)) {
                if let p = near(c.0, c.1, 2, where: { wild($0, $1) }) {
                    add(pickRace(hirelings, &rng), p.0, p.1, role: "mercenary", bounds: (c.0 - 10, c.1 - 10, c.0 + 10, c.1 + 10),
                        home: nil, draconian: true)
                }
            }
        }
        // A roving warband of Draconian's orcs, ranging over the whole of the wilds here.
        if town == nil, rng.chance(0.28),
           let c = spot(8, 8, n - 9, n - 9, where: { terrainIs([.grass, .brush, .sand, .hills, .dirt])($0, $1) && wild($0, $1) }) {
            let id = Int(truncatingIfNeeded: Hash.of(seed, key.x, key.y, 4242) & 0xFFFFFF)
            for k in 0..<(3 + rng.int(3)) {
                if let p = near(c.0, c.1, 2, where: { wild($0, $1) }) {
                    add(.orc, p.0, p.1, role: k == 0 ? "warband captain" : rng.pick(["warband raider", "warband brute"]),
                        bounds: (1, 1, n - 2, n - 2), home: nil, draconian: true, warband: id)
                }
            }
        }
        // Adventurers: a few in the streets of every town and now and then at an inn,
        // and the odd one or two out on the roads and in the wilds.
        func adventurer(_ lx: Int, _ ly: Int, bounds: (Int, Int, Int, Int), home: String?) {
            add(pickRace(adventurerRaces, &rng), lx, ly, role: "adventurer", bounds: bounds, home: home, draconian: false)
        }
        if let t = town {
            let x0 = t.x - ox, y0 = t.y - oy, x1 = x0 + t.w - 1, y1 = y0 + t.h - 1
            let outdoors: (Int, Int) -> Bool = { x, y in !region.roofed.contains { $0.contains(ox + x, oy + y) } }
            for _ in 0..<(t.w > 40 ? 2 + rng.int(3) : 1 + rng.int(2)) {
                if let p = spot(x0, y0, x1, y1, where: outdoors) { adventurer(p.0, p.1, bounds: (x0, y0, x1, y1), home: t.name) }
            }
        }
        for b in region.places where b.kind == .building && Names.isInn(b.name) && rng.chance(0.5) {
            let x0 = b.x - ox + 1, y0 = b.y - oy + 1, x1 = b.x - ox + b.w - 2, y1 = b.y - oy + b.h - 2
            if let p = spot(x0, y0, x1, y1, where: { x, y in region.features[(y + 1) * n + x] != .door }) {
                adventurer(p.0, p.1, bounds: (x0, y0, x1, y1), home: b.name)
            }
        }
        if rng.chance(town == nil ? 0.25 : 0.1),
           let c = spot(6, 6, n - 7, n - 7, where: { terrainIs([.dirt, .grass, .forest, .brush, .hills])($0, $1) && wild($0, $1) }) {
            for _ in 0..<(rng.chance(0.3) ? 2 : 1) {
                if let p = near(c.0, c.1, 2, where: { wild($0, $1) }) {
                    adventurer(p.0, p.1, bounds: (c.0 - 10, c.1 - 10, c.0 + 10, c.1 + 10), home: nil)
                }
            }
        }
        return people
    }

    /// Who works in a building, judged by its name: role, likely races, the chance
    /// someone is in, and how many guests besides.
    private static func trade(_ name: String) -> (String, [(Race, Double)], Double, Int) {
        if Names.isInn(name) { return ("innkeeper", [(.human, 70), (.elf, 10), (.dwarf, 15), (.orc, 5)], 1, 1) }
        if name.contains("Provisions") { return ("provisioner", [(.human, 70), (.dwarf, 15), (.elf, 10), (.orc, 5)], 1, 0) }
        if name.contains("Anvil") || name.contains("Smithy") { return ("blacksmith", [(.dwarf, 55), (.human, 40), (.orc, 5)], 1, 0) }
        if name.contains("Arms") { return ("armourer", [(.human, 45), (.dwarf, 40), (.orc, 15)], 1, 0) }
        if name.contains("Apothecary") || name.contains("Mortar") { return ("apothecary", [(.human, 60), (.elf, 30), (.dwarf, 10)], 1, 0) }
        if name.contains("Alembic") || name.contains("Alchemy") { return ("alchemist", [(.human, 55), (.elf, 25), (.dwarf, 15), (.orc, 5)], 1, 0) }
        if name.contains("Healing") || name.contains("Gentle") { return ("healer", [(.human, 60), (.elf, 40)], 1, 0) }
        if name.hasPrefix("Temple") { return ("cleric", [(.human, 70), (.elf, 30)], 1, 0) }
        if name.contains("Farmhouse") { return ("farmer", [(.human, 85), (.dwarf, 10), (.elf, 5)], 0.9, 0) }
        if name.contains("Cottage") { return ("cottager", [(.human, 70), (.elf, 20), (.dwarf, 10)], 0.8, 0) }
        if name.hasSuffix("House") { return ("householder", townFolk, 0.7, 0) }
        return ("barkeep", [(.human, 60), (.dwarf, 20), (.elf, 10), (.orc, 10)], 1, 2)
    }
}
