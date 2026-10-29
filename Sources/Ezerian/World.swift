import Foundation

/// Floor division and modulo that behave for negative world coordinates.
@inline(__always) func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
@inline(__always) func floorMod(_ a: Int, _ b: Int) -> Int { let m = a % b; return m < 0 ? m + b : m }

struct RegionKey: Hashable, Codable {
    var x: Int
    var y: Int
    /// 0 is the surface; 1 is the cave level beneath it.
    var z: Int
}

/// A named area inside a region: a town, a building, or a landmark.
struct Place: Codable {
    enum Kind: String, Codable { case town, building, landmark }
    var kind: Kind
    var name: String
    var x: Int
    var y: Int
    var w: Int
    var h: Int
    /// Buildings wear a roof that lifts off while the Avatar is indoors.
    var roof: RoofStyle?

    func contains(_ px: Int, _ py: Int) -> Bool { px >= x && py >= y && px < x + w && py < y + h }
}

/// Text on a signpost or shop sign; `icon` picks the picture on a hanging sign.
struct Sign: Codable {
    var text: String
    var icon: String?
}

/// One 64x64 map grid. Generated the first time it is needed and kept from then on.
final class Region {
    static let size = 64

    let key: RegionKey
    var terrain: [Terrain]
    var features: [Feature]
    var explored: [Bool]
    var visited = false
    var name: String
    var places: [Place] = [] {
        didSet { roofed = places.filter { $0.kind == .building && $0.roof != nil } }
    }
    /// The buildings that have roofs (a cached subset of `places`).
    private(set) var roofed: [Place] = []
    var signs: [Int: Sign] = [:]
    /// The people who live here.
    var npcs: [NPC] = []

    init(key: RegionKey, name: String = "") {
        self.key = key
        self.name = name
        let n = Region.size * Region.size
        terrain = Array(repeating: .grass, count: n)
        features = Array(repeating: .none, count: n)
        explored = Array(repeating: false, count: n)
    }

    var originX: Int { key.x * Region.size }
    var originY: Int { key.y * Region.size }

    @inline(__always) func index(_ wx: Int, _ wy: Int) -> Int {
        (wy - originY) * Region.size + (wx - originX)
    }

    func contains(_ wx: Int, _ wy: Int) -> Bool {
        wx >= originX && wy >= originY && wx < originX + Region.size && wy < originY + Region.size
    }
}

/// The whole (endless) world: a sparse grid of regions, generated lazily.
final class World {
    let seed: UInt64
    let generator: WorldGenerator
    private(set) var regions: [RegionKey: Region] = [:]
    private var lastRegion: Region?

    /// Called whenever a brand-new region is generated (used for logging/testing).
    var onGenerate: ((Region) -> Void)?

    init(seed: UInt64) {
        self.seed = seed
        generator = WorldGenerator(seed: seed)
    }

    /// Restores previously generated regions (from a save file).
    func adopt(_ region: Region) {
        regions[region.key] = region
    }

    func existingRegion(_ key: RegionKey) -> Region? { regions[key] }

    func region(_ key: RegionKey) -> Region {
        if let r = regions[key] { return r }
        let r = generator.generate(key, world: self)
        regions[key] = r
        onGenerate?(r)
        return r
    }

    @inline(__always)
    func region(containing wx: Int, _ wy: Int, _ z: Int) -> Region {
        if let r = lastRegion, r.key.z == z, r.contains(wx, wy) { return r }
        let r = region(RegionKey(x: floorDiv(wx, Region.size), y: floorDiv(wy, Region.size), z: z))
        lastRegion = r
        return r
    }

    @inline(__always)
    func terrain(_ wx: Int, _ wy: Int, _ z: Int) -> Terrain {
        let r = region(containing: wx, wy, z)
        return r.terrain[r.index(wx, wy)]
    }

    @inline(__always)
    func feature(_ wx: Int, _ wy: Int, _ z: Int) -> Feature {
        let r = region(containing: wx, wy, z)
        return r.features[r.index(wx, wy)]
    }

    func sign(_ wx: Int, _ wy: Int, _ z: Int) -> Sign? {
        let r = region(containing: wx, wy, z)
        return r.signs[r.index(wx, wy)]
    }

    func markExplored(_ wx: Int, _ wy: Int, _ z: Int) {
        let r = region(containing: wx, wy, z)
        r.explored[r.index(wx, wy)] = true
    }

    /// Explored state without forcing generation (for the overview map).
    func isExplored(_ wx: Int, _ wy: Int, _ z: Int) -> Bool {
        guard let r = regions[RegionKey(x: floorDiv(wx, Region.size), y: floorDiv(wy, Region.size), z: z)] else {
            return false
        }
        return r.explored[r.index(wx, wy)]
    }

    /// Whether the Avatar may step onto a tile.
    func isPassable(_ wx: Int, _ wy: Int, _ z: Int) -> Bool {
        let f = feature(wx, wy, z)
        if f == .door || f == .caveEntrance || f == .ladderUp { return true }
        if terrain(wx, wy, z).blocksMovement { return false }
        return !f.blocksMovement
    }

    /// Existing NPCs within `radius` tiles of a point (regions are not generated for this).
    func npcs(near x: Int, _ y: Int, _ z: Int, radius: Int) -> [NPC] {
        var out: [NPC] = []
        for ry in floorDiv(y - radius, Region.size)...floorDiv(y + radius, Region.size) {
            for rx in floorDiv(x - radius, Region.size)...floorDiv(x + radius, Region.size) {
                guard let r = regions[RegionKey(x: rx, y: ry, z: z)] else { continue }
                for n in r.npcs where abs(n.x - x) <= radius && abs(n.y - y) <= radius { out.append(n) }
            }
        }
        return out
    }

    /// The NPC standing on a tile, if any (NPCs never leave their own region).
    func npc(at x: Int, _ y: Int, _ z: Int) -> NPC? {
        guard let r = regions[RegionKey(x: floorDiv(x, Region.size), y: floorDiv(y, Region.size), z: z)] else { return nil }
        return r.npcs.first { $0.x == x && $0.y == y }
    }

    /// The roofed building containing a tile, if any. Buildings never straddle a
    /// region border, so only the tile's own region needs searching.
    func building(at wx: Int, _ wy: Int, _ z: Int) -> Place? {
        guard z == 0 else { return nil }
        let r = region(containing: wx, wy, z)
        return r.roofed.first { $0.contains(wx, wy) }
    }

    /// The most specific place (building before town) containing a tile.
    func place(at wx: Int, _ wy: Int, _ z: Int) -> (town: Place?, building: Place?, landmark: Place?) {
        let r = region(containing: wx, wy, z)
        var town: Place?, building: Place?, landmark: Place?
        for p in r.places where p.contains(wx, wy) {
            switch p.kind {
            case .town: town = p
            case .building: building = p
            case .landmark: landmark = p
            }
        }
        return (town, building, landmark)
    }
}
