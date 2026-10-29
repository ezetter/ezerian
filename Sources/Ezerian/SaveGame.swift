import Foundation

/// Persists the world (every region generated so far) and the Avatar's position,
/// so the land you have explored is still there next time.
enum SaveGame {
    private struct File: Codable {
        var version = 2
        var seed: String
        var x: Int
        var y: Int
        var z: Int
        var facing: Int
        var name: String?
        var turn: Int
        var regions: [RegionRecord]
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
    }

    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Land of Ezerian 2", isDirectory: true).appendingPathComponent("world.plist")
    }

    static func save(_ game: Game, to url: URL = SaveGame.url) throws {
        let regions = game.world.regions.values.map { r in
            RegionRecord(x: r.key.x, y: r.key.y, z: r.key.z, name: r.name, visited: r.visited,
                         terrain: Data(r.terrain.map(\.rawValue)), features: Data(r.features.map(\.rawValue)),
                         explored: Data(r.explored.map { $0 ? 1 : 0 }), places: r.places, signs: r.signs)
        }
        let file = File(seed: String(game.world.seed), x: game.x, y: game.y, z: game.z,
                        facing: game.facing.rawValue, name: game.nameEntry == nil ? game.playerName : nil, turn: game.turn, regions: regions)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = SaveGame.url) -> Game? {
        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListDecoder().decode(File.self, from: data),
              file.version == 2, let seed = UInt64(file.seed)
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
            world.adopt(region)
        }
        let game = Game(world: world, name: file.name ?? "Avatar", x: file.x, y: file.y, z: file.z,
                        facing: Direction(rawValue: file.facing) ?? .south, turn: file.turn)
        // Quit before choosing a name? Ask again.
        if file.name == nil { game.nameEntry = "" }
        return game
    }
}
