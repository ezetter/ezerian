import Foundation

/// Persists the world (every region generated so far) and the Avatar's position,
/// so the land you have explored is still there next time.
enum SaveGame {
    private struct File: Codable {
        /// 4: ordinary folk's new moods, and Draconian's hidden agents.
        var version = 5
        var seed: String
        var x: Int
        var y: Int
        var z: Int
        var facing: Int
        var name: String?
        /// Missing in saves from before the Avatar could be a woman.
        var female: Bool?
        /// Which of the five looks of a man or a woman; missing in older saves.
        var look: Int?
        var turn: Int
        var regions: [RegionRecord]
        var party: [NPC]?
        var hp: Int?
        var maxHP: Int?
        var gold: Int?
        /// The weapons of saves from before belongings: the best was in hand.
        var weapons: [Weapon]?
        var weapon: Weapon?
        var pack: [Item]?
        var experience: Int?
        /// The day of the last morning autosave; missing in older saves.
        var autosaved: Int?
        /// The day's beers so far (past two, they hurt); missing in older saves.
        var beerDay: Int?
        var beersToday: Int?
    }

    private struct RegionRecord: Codable {
        var x: Int
        var y: Int
        var z: Int
        var name: String
        var visited: Bool
        var terrain: Data
        var features: Data
        var explored: Data
        var places: [Place]
        var signs: [Int: Sign]
        /// Missing in saves from before there were people.
        var npcs: [NPC]?
    }

    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Land of Ezerian 2", isDirectory: true).appendingPathComponent("world.plist")
    }

    /// Where the morning autosave is kept, beside the world.
    static var autosaveURL: URL { url.deletingLastPathComponent().appendingPathComponent("autosave.plist") }

    /// The 8 AM save: records the morning in the game, then writes the world to the autosave file.
    static func autosave(_ game: Game, to url: URL = SaveGame.autosaveURL) throws {
        game.autosavedDay = game.day
        try save(game, to: url)
    }

    /// A new world begins: the old world's mornings can't be returned to.
    static func discardAutosave(at url: URL = SaveGame.autosaveURL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func save(_ game: Game, to url: URL = SaveGame.url) throws {
        let regions = game.world.regions.values.map { r in
            RegionRecord(x: r.key.x, y: r.key.y, z: r.key.z, name: r.name, visited: r.visited,
                         terrain: Data(r.terrain.map(\.rawValue)), features: Data(r.features.map(\.rawValue)),
                         explored: Data(r.explored.map { $0 ? 1 : 0 }), places: r.places, signs: r.signs, npcs: r.npcs)
        }
        let file = File(seed: String(game.world.seed), x: game.x, y: game.y, z: game.z,
                        facing: game.facing.rawValue, name: game.creatingCharacter ? nil : game.playerName,
                        female: game.female, look: game.avatarLook, turn: game.turn, regions: regions,
                        party: game.world.party, hp: game.hp, maxHP: game.maxHP,
                        gold: game.gold, weapons: nil, weapon: game.weapon, pack: game.pack,
                        experience: game.experience, autosaved: game.autosavedDay,
                        beerDay: game.beerDay, beersToday: game.beersToday)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = SaveGame.url) -> Game? {
        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListDecoder().decode(File.self, from: data),
              file.version >= 2, let seed = UInt64(file.seed)
        else { return nil }
        let world = World(seed: seed)
        let n = Region.size * Region.size
        for rec in file.regions {
            guard rec.terrain.count == n, rec.features.count == n, rec.explored.count == n else { continue }
            let region = Region(key: RegionKey(x: rec.x, y: rec.y, z: rec.z), name: rec.name)
            region.terrain = rec.terrain.map { Terrain(rawValue: $0) ?? .grass }
            region.features = rec.features.map { Feature(rawValue: $0) ?? .none }
            region.explored = rec.explored.map { $0 != 0 }
            region.visited = rec.visited
            region.places = rec.places
            region.signs = rec.signs
            if let npcs = rec.npcs { region.npcs = npcs } else { Populace.populate(region, seed: seed, avatarHealth: file.maxHP ?? 100) }
            for n in region.npcs { n.prevX = n.x; n.prevY = n.y; Populace.paint(n) }
            world.adopt(region)
        }
        // Saves from before version 5: the folk not yet met take the current moods and the current
        // share of hidden agents (one in ten); people the Avatar has spoken to or fought keep their feelings.
        if file.version < 5 {
            for r in world.regions.values {
                for n in r.npcs where n.talks == 0 && !n.known && !n.struckByAvatar && !n.unmasked && (n.memory ?? []).isEmpty {
                    Populace.temper(n)
                }
            }
        }
        world.party = file.party ?? []
        for n in world.party { n.prevX = n.x; n.prevY = n.y; Populace.paint(n) }
        let game = Game(world: world, name: file.name ?? "Avatar", female: file.female ?? false, look: file.look ?? 0, x: file.x, y: file.y, z: file.z,
                        facing: Direction(rawValue: file.facing) ?? .south, turn: file.turn)
        game.hp = file.hp ?? 100
        game.maxHP = file.maxHP ?? 100
        game.gold = file.gold ?? 0
        game.experience = file.experience ?? 0
        game.autosavedDay = file.autosaved ?? 0
        game.beerDay = file.beerDay ?? 0
        game.beersToday = file.beersToday ?? 0
        // A fallen Avatar wakes to the death notice, to rise again from the autosave or begin anew.
        game.gameOver = game.hp <= 0
        if let old = file.weapons, file.pack == nil {
            game.weapon = old.max()
            game.pack = Array(old.sorted(by: >).dropFirst().prefix(Game.carryLimit - 1)).map { .weapon($0) }
        } else {
            game.weapon = file.weapon
            game.pack = file.pack ?? []
        }
        // Quit before choosing a name? Ask again.
        if file.name == nil { game.nameEntry = "" }
        return game
    }
}
