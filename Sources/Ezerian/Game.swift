import Foundation

/// Game state and the rules for walking around. No combat, NPCs or object handling
/// yet: the Avatar explores, reads signs and looks at things.
final class Game {
    let world: World
    private(set) var x: Int
    private(set) var y: Int
    private(set) var z: Int = 0
    private(set) var facing: Direction = .south
    private(set) var step = 0
    private(set) var turn = 0
    private(set) var messages: [String] = []
    /// Bumped whenever the Avatar changes place without walking (stairs, teleports),
    /// so the view knows to jump rather than glide.
    private(set) var jumps = 0

    /// The Avatar's name, chosen when a new game begins.
    private(set) var playerName = "Avatar"
    /// The name being typed while a new game asks for one; nil once it is chosen.
    var nameEntry: String?
    static let maxNameLength = 12

    var showMap = false
    var showGrid = false
    var showHelp = false
    var mapScale = 3

    private var lastTown: String?
    private var lastBuilding: String?
    private var lastLandmark: String?
    private var lastRegion: RegionKey?
    private var lastTerrainMood: String?

    /// Tiles around the Avatar that count as seen (and go on the map).
    static let viewW = 21
    static let viewH = 15

    init(seed: UInt64) {
        world = World(seed: seed)
        let start = Game.startPosition(in: world)
        x = start.x
        y = start.y
        nameEntry = ""
        arrive(quiet: true)
    }

    /// Accepts the name typed at the start of a new game and sets the scene.
    func confirmName() {
        let typed = (nameEntry ?? "").trimmingCharacters(in: .whitespaces)
        playerName = typed.isEmpty ? "Avatar" : typed
        nameEntry = nil
        log("Welcome to the Land of Ezerian, \(playerName)!")
        log("Use the arrow keys to walk. Press H for help.")
        if let town = currentPlaces.town {
            log("You stand in the town of \(town.name), in \(region.name).")
        } else {
            log("You stand in \(region.name).")
        }
    }

    /// Adds a typed character to the name being entered, if it is allowed.
    func typeName(_ ch: Character) {
        guard var entry = nameEntry, entry.count < Game.maxNameLength,
              ch.isLetter || ch == " " || ch == "-" || ch == "'" else { return }
        if entry.isEmpty && ch == " " { return }
        entry.append(entry.isEmpty ? Character(ch.uppercased()) : ch)
        nameEntry = entry
    }

    /// Restores a saved game.
    init(world: World, name: String, x: Int, y: Int, z: Int, facing: Direction, turn: Int) {
        self.world = world
        playerName = name
        self.x = x
        self.y = y
        self.z = z
        self.facing = facing
        self.turn = turn
        log("Welcome back to the Land of Ezerian, \(name).")
        arrive(quiet: true)
    }

    var regionKey: RegionKey { RegionKey(x: floorDiv(x, Region.size), y: floorDiv(y, Region.size), z: z) }
    var region: Region { world.region(regionKey) }
    var currentPlaces: (town: Place?, building: Place?, landmark: Place?) { world.place(at: x, y, z) }
    var isUnderground: Bool { z > 0 }

    /// While the Avatar is inside a building every roof lifts off, as in Britannia.
    var isIndoors: Bool { world.building(at: x, y, z) != nil }

    /// Game clock: each step takes two minutes; the adventure begins at 8 in the morning.
    var minutes: Int { 8 * 60 + turn * 2 }
    var day: Int { minutes / (24 * 60) + 1 }
    /// Hours since midnight as a fraction (for the sky and the light).
    var hourOfDay: Double { Double(minutes % (24 * 60)) / 60 }
    var timeString: String {
        let m = minutes % (24 * 60)
        let h = m / 60, mm = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, mm, h < 12 ? "AM" : "PM")
    }

    func log(_ text: String) {
        if messages.last == text { return }
        messages.append(text)
        if messages.count > 60 { messages.removeFirst(messages.count - 60) }
    }

    // MARK: Movement

    @discardableResult
    func move(dx: Int, dy: Int) -> Bool {
        guard dx != 0 || dy != 0 else { return false }
        facing = dx != 0 && dy != 0 ? (dy < 0 ? .north : .south) : Direction.from(dx: dx, dy: dy)
        let nx = x + dx, ny = y + dy
        let target = world.feature(nx, ny, z)

        if target == .caveEntrance && z == 0 {
            z = 1
            x = nx
            y = ny + 1
            facing = .south
            turn += 1
            jumps += 1
            log("You descend into the dark caverns.")
            arrive()
            return true
        }
        if target == .ladderUp && z > 0 {
            z = 0
            x = nx
            y = ny + 1
            facing = .south
            turn += 1
            jumps += 1
            log("You climb back up into the daylight.")
            arrive()
            return true
        }
        if dx != 0 && dy != 0 && !world.isPassable(x + dx, y, z) && !world.isPassable(x, y + dy, z) {
            log("Blocked!")
            return false
        }
        guard world.isPassable(nx, ny, z) else {
            bump(nx, ny)
            return false
        }
        x = nx
        y = ny
        step += 1
        turn += 1
        arrive()
        return true
    }

    private func bump(_ bx: Int, _ by: Int) {
        let f = world.feature(bx, by, z), t = world.terrain(bx, by, z)
        if let sign = world.sign(bx, by, z), f == .signpost || f == .hangingSign {
            log("The sign reads: \"\(sign.text)\"")
        } else if f != .none && f.blocksMovement && !f.isWallMounted {
            log("Blocked by \(f.name).")
        } else if t.isWater {
            log("The water is too deep to wade.")
        } else if t == .mountain {
            log("The mountains are too steep to climb.")
        } else {
            log("Blocked!")
        }
    }

    /// Updates exploration bookkeeping and narrates what changed after moving.
    private func arrive(quiet: Bool = false) {
        let key = regionKey
        let region = world.region(key)
        if key != lastRegion {
            if !quiet {
                if z > 0 {
                    // The cave name was already announced by the descent message.
                } else if region.visited {
                    log("You return to \(region.name).")
                } else {
                    log("You enter \(region.name), lands unknown to you.")
                }
            }
            region.visited = true
            lastRegion = key
        }

        let places = currentPlaces
        if places.town?.name != lastTown {
            if let town = places.town { if !quiet { log("You enter the town of \(town.name).") } }
            else if let old = lastTown { log("You leave \(old).") }
            lastTown = places.town?.name
        }
        if places.building?.name != lastBuilding {
            if let b = places.building, !quiet { log("You enter \(b.name).") }
            lastBuilding = places.building?.name
        }
        if places.landmark?.name != lastLandmark {
            if let l = places.landmark, !quiet, z == 0 { log("You come upon \(l.name).") }
            lastLandmark = places.landmark?.name
        }

        let mood: String?
        switch world.terrain(x, y, z) {
        case .swamp: mood = "You wade into a fetid swamp."
        case .forest: mood = "You walk beneath the dark eaves of the forest."
        case .hills: mood = "You climb into rolling hills."
        case .bridge: mood = "You cross a wooden bridge."
        case .sand: mood = world.feature(x, y, z) == .none ? "Sand crunches underfoot." : nil
        default: mood = nil
        }
        if mood != lastTerrainMood, let mood, !quiet { log(mood) }
        lastTerrainMood = mood
        markSeen()
    }

    /// Everything on screen goes on the map; underground only what the torch reaches.
    private func markSeen() {
        let rx = Game.viewW / 2, ry = Game.viewH / 2
        for dy in -ry...ry {
            for dx in -rx...rx {
                if z > 0 && dx * dx + dy * dy > 49 { continue }
                world.markExplored(x + dx, y + dy, z)
            }
        }
    }

    /// Moves the Avatar directly (developer screenshots only).
    func teleport(_ tx: Int, _ ty: Int, _ tz: Int) {
        x = tx
        y = ty
        z = tz
        jumps += 1
        arrive()
    }

    /// Spends time without moving (developer screenshots of night scenes).
    func wait(turns: Int) { turn += turns }

    // MARK: Looking

    func lookAhead() {
        look(at: x + facing.dx, y + facing.dy)
    }

    func look(at lx: Int, _ ly: Int) {
        if lx == x && ly == y {
            log("You see yourself, standing on \(world.terrain(x, y, z).name).")
            return
        }
        let f = world.feature(lx, ly, z), t = world.terrain(lx, ly, z)
        if let sign = world.sign(lx, ly, z) {
            log("The sign reads: \"\(sign.text)\"")
        } else if f != .none {
            log("You see \(f.name).")
        } else {
            log("You see \(t.name).")
        }
    }

    // MARK: Start position

    /// In front of the tavern in the home town (or the middle of the home region).
    static func startPosition(in world: World) -> (x: Int, y: Int) {
        let home = world.region(RegionKey(x: 0, y: 0, z: 0))
        let n = Region.size
        for (i, sign) in home.signs where sign.icon == "tavern" {
            let sx = home.originX + i % n, sy = home.originY + i / n
            for dx in [-1, 1] where world.feature(sx + dx, sy - 1, 0) == .door {
                if world.isPassable(sx + dx, sy, 0) { return (sx + dx, sy) }
            }
        }
        if let town = home.places.first(where: { $0.kind == .town }) {
            let cx = town.x + town.w / 2, cy = town.y + town.h / 2 + 1
            if world.isPassable(cx, cy, 0) { return (cx, cy) }
        }
        for r in 0..<32 {
            for dy in -r...r {
                for dx in -r...r where world.isPassable(32 + dx, 32 + dy, 0) && !world.terrain(32 + dx, 32 + dy, 0).isWater {
                    return (32 + dx, 32 + dy)
                }
            }
        }
        return (32, 32)
    }
}
