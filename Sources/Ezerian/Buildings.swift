import Foundation

enum BuildingKind: CaseIterable {
    case tavern, inn, provisions, smithy, armory, healer, temple, home
    /// Shops of salves and ointments (and, one day, potions).
    case apothecary, alchemist

    var minSize: (w: Int, h: Int) {
        switch self {
        case .tavern: return (9, 7)
        case .inn: return (9, 8)
        case .temple: return (9, 8)
        default: return (6, 6)
        }
    }

    var signIcon: String? {
        switch self {
        case .tavern: return "tavern"
        case .inn: return "inn"
        case .provisions: return "provisions"
        case .smithy: return "smithy"
        case .armory: return "armory"
        case .healer: return "healer"
        case .apothecary: return "apothecary"
        case .alchemist: return "alchemist"
        case .temple, .home: return nil
        }
    }
}

/// The floor of a building enclosed by its walls. Every building faces south: its
/// door is in the south wall, so the north wall is the back of the room, where
/// tall furniture stands against it.
final class Interior {
    let b: RegionBuilder
    let x0: Int, y0: Int, x1: Int, y1: Int
    let door: Point
    let entry: Point

    init(_ b: RegionBuilder, x0: Int, y0: Int, x1: Int, y1: Int, door: Point) {
        self.b = b
        self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        self.door = door
        entry = Point(x: door.x, y: y1)
    }

    var width: Int { x1 - x0 + 1 }
    var height: Int { y1 - y0 + 1 }

    /// Row `d` steps in from the back (north) wall.
    func row(_ d: Int) -> Int { y0 + d }

    func contains(_ x: Int, _ y: Int) -> Bool { x >= x0 && x <= x1 && y >= y0 && y <= y1 }

    func isFree(_ x: Int, _ y: Int) -> Bool {
        contains(x, y) && !b.t(x, y).isWall && b.f(x, y) == .none && !(x == entry.x && y == entry.y)
    }

    private func passable(_ x: Int, _ y: Int) -> Bool {
        let f = b.f(x, y)
        if f == .door { return true }
        return !b.t(x, y).blocksMovement && !f.blocksMovement
    }

    /// True when every walkable floor tile can still be reached from the door.
    func isConnected() -> Bool {
        var total = 0
        for y in y0...y1 { for x in x0...x1 where passable(x, y) { total += 1 } }
        var seen = Set<Point>([entry])
        var queue = [entry]
        while let p = queue.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let q = Point(x: p.x + dx, y: p.y + dy)
                guard contains(q.x, q.y), !seen.contains(q), passable(q.x, q.y) else { continue }
                seen.insert(q)
                queue.append(q)
            }
        }
        return seen.count >= total
    }

    /// Places a feature if the tile is free and the room stays fully walkable.
    @discardableResult
    func place(_ f: Feature, _ x: Int, _ y: Int) -> Bool {
        guard isFree(x, y) else { return false }
        b.setF(x, y, f)
        if f.blocksMovement && !isConnected() {
            b.setF(x, y, .none)
            return false
        }
        return true
    }

    /// Tall furniture must stand against the north wall so it can lean on it.
    @discardableResult
    func placeTall(_ f: Feature, _ x: Int) -> Bool { place(f, x, y0) }

    /// A bed is two tiles long, head against the north side.
    @discardableResult
    func placeBed(_ x: Int, _ y: Int) -> Bool {
        guard isFree(x, y), isFree(x, y + 1) else { return false }
        b.setF(x, y, .bed)
        b.setF(x, y + 1, .bedFoot)
        if !isConnected() { b.setF(x, y, .none); b.setF(x, y + 1, .none); return false }
        return true
    }

    func placeTable(_ x: Int, _ y: Int) -> Bool {
        let table: Feature = [.table, .tableMug, .tableFood, .tableCandle][b.rng.int(4)]
        guard place(table, x, y) else { return false }
        if isFree(x - 1, y) { b.setF(x - 1, y, .chair) }
        if isFree(x + 1, y) { b.setF(x + 1, y, .chair) }
        return true
    }

    /// Scatters tables with chairs over the open middle of the room.
    func placeTables(from firstRow: Int, count: Int) {
        var placed: [Point] = []
        var candidates: [Point] = []
        for d in firstRow..<height {
            let y = row(d)
            for x in (x0 + 1)...max(x0 + 1, x1 - 1) where abs(x - entry.x) >= 2 && isFree(x, y) {
                candidates.append(Point(x: x, y: y))
            }
        }
        b.rng.shuffle(&candidates)
        for c in candidates where placed.count < count {
            if placed.contains(where: { abs($0.x - c.x) < 4 && abs($0.y - c.y) < 2 }) { continue }
            if placeTable(c.x, c.y) { placed.append(c) }
        }
    }

    /// Fills free spots along the walls with clutter.
    func clutter(_ items: [Feature], count: Int) {
        var spots: [Point] = []
        for y in y0...y1 {
            for x in x0...x1 where (x == x0 || x == x1 || y == y0 || y == y1) && isFree(x, y) {
                if abs(x - entry.x) <= 1 && abs(y - entry.y) <= 1 { continue }
                spots.append(Point(x: x, y: y))
            }
        }
        b.rng.shuffle(&spots)
        var n = 0
        for s in spots where n < count {
            if place(b.rng.pick(items), s.x, s.y) { n += 1 }
        }
    }
}

enum Buildings {
    static func styles(for kind: BuildingKind, rng: inout SplitMix64) -> (wall: Terrain, floor: Terrain, roof: RoofStyle) {
        switch kind {
        case .smithy: return (.stoneWall, .stoneFloor, .slate)
        case .armory: return (.stoneWall, .cobble, .slate)
        case .temple: return (.stoneWall, .marble, .slate)
        case .healer: return (.timberWall, .stoneFloor, .tile)
        case .apothecary: return (.timberWall, .woodFloor, .tile)
        case .alchemist: return (.stoneWall, .stoneFloor, .slate)
        case .inn: return (rng.chance(0.5) ? .timberWall : .brickWall, .woodFloor, rng.chance(0.5) ? .shingle : .tile)
        case .tavern:
            let wall: Terrain = [.brickWall, .stoneWall, .timberWall][rng.int(3)]
            let floor: Terrain = wall == .stoneWall ? .cobble : (rng.chance(0.5) ? .brickFloor : .woodFloor)
            return (wall, floor, .shingle)
        case .provisions: return (rng.chance(0.6) ? .timberWall : .logWall, .woodFloor, .shingle)
        case .home:
            let wall: Terrain = [.timberWall, .logWall, .stoneWall, .brickWall][rng.int(4)]
            let roof: RoofStyle = wall == .logWall ? .thatch : [.shingle, .thatch, .tile, .slate][rng.int(4)]
            return (wall, .woodFloor, roof)
        }
    }

    static func name(for kind: BuildingKind, rng: inout SplitMix64) -> String {
        switch kind {
        case .tavern: return Names.tavern(&rng)
        case .inn: return Names.inn(&rng)
        case .provisions: return "\(Names.person(&rng))'s Provisions"
        case .smithy: return rng.chance(0.5) ? "The \(rng.pick(["Iron", "Red", "Black", "Ringing"])) Anvil" : "\(Names.person(&rng))'s Smithy"
        case .armory: return "\(Names.person(&rng))'s Arms"
        case .healer: return rng.chance(0.5) ? "House of Healing" : "The Gentle Hand"
        case .apothecary: return rng.chance(0.5) ? "\(Names.person(&rng))'s Apothecary" : "The Mortar and Pestle"
        case .alchemist: return rng.chance(0.5) ? "The \(rng.pick(["Green", "Silver", "Bubbling", "Gilded"])) Alembic" : "\(Names.person(&rng))'s Alchemy"
        case .temple: return "Temple of \(Names.virtue(&rng))"
        case .home: return "\(Names.person(&rng))'s House"
        }
    }

    /// Builds a walled, roofed building filling (x, y, w, h) with its door in the
    /// south wall. Returns the tile just outside the door.
    @discardableResult
    static func build(_ b: RegionBuilder, kind: BuildingKind, x: Int, y: Int, w: Int, h: Int,
                      name givenName: String? = nil, roof givenRoof: RoofStyle? = nil) -> Point {
        var (wall, floor, roof) = styles(for: kind, rng: &b.rng)
        if let givenRoof { roof = givenRoof }
        let name = givenName ?? self.name(for: kind, rng: &b.rng)
        for yy in y..<(y + h) {
            for xx in x..<(x + w) {
                let edge = xx == x || yy == y || xx == x + w - 1 || yy == y + h - 1
                b.setT(xx, yy, edge ? wall : floor)
                b.setF(xx, yy, .none)
            }
        }
        b.reserve(x - 1, y - 1, w + 2, h + 2)
        let doorX = x + w / 2 + (w > 7 ? b.rng.int(3) - 1 : 0)
        let door = Point(x: doorX, y: y + h - 1)
        b.setF(door.x, door.y, .door)
        let room = Interior(b, x0: x + 1, y0: y + 1, x1: x + w - 2, y1: y + h - 2, door: door)
        furnish(room, kind: kind, wall: wall)
        addWindows(b, x: x, y: y, w: w, h: h, door: door, stained: kind == .temple)
        decorateWalls(b, room: room, kind: kind)

        let outside = Point(x: door.x, y: door.y + 1)
        if let icon = kind.signIcon {
            for sx in [door.x + 1, door.x - 1] where b.inside(sx, outside.y) && b.f(sx, outside.y) == .none
                && !b.t(sx, outside.y).blocksMovement {
                b.setF(sx, outside.y, .hangingSign)
                b.setSign(sx, outside.y, name, icon: icon)
                break
            }
        }
        b.addPlace(.building, name, x, y, w, h, roof: roof)
        return outside
    }

    private static func furnish(_ r: Interior, kind: BuildingKind, wall: Terrain) {
        switch kind {
        case .tavern: furnishTavern(r)
        case .inn: furnishInn(r, wall: wall)
        case .provisions: furnishShop(r, wares: [.barrel, .crate, .sack, .sack], counterItems: [.crate, .barrel, .sack])
        case .armory: furnishShop(r, wares: [.crate, .chest, .barrel], counterItems: [.weaponRack, .weaponRack, .chest])
        case .smithy: furnishSmithy(r)
        case .healer: furnishHealer(r)
        case .apothecary: furnishShop(r, wares: [.barrel, .sack, .crate], counterItems: [.chest, .crate])
        case .alchemist:
            furnishShop(r, wares: [.barrel, .chest], counterItems: [.chest, .barrel])
            r.place(.cauldron, (r.x0 + r.x1) / 2, r.row(r.height - 2))
        case .temple: furnishTemple(r)
        case .home: furnishHome(r)
        }
    }

    private static func furnishTavern(_ r: Interior) {
        let b = r.b
        let barLen = min(r.width - 3, 6)
        let barOnLeft = r.entry.x > (r.x0 + r.x1) / 2
        let barStart = barOnLeft ? r.x0 : r.x1 - barLen + 1
        var fireX = barOnLeft ? r.x1 - 1 : r.x0 + 1
        if r.height >= 6 {
            for (i, x) in (barStart..<(barStart + barLen)).enumerated() {
                b.setF(x, r.row(2), .counter)
                if i == barLen / 2 { r.placeTall(.shelf, x) } else { r.place(i % 3 == 1 ? .barrel : .keg, x, r.row(0)) }
            }
            if !r.isConnected() {
                for x in barStart..<(barStart + barLen) where b.f(x, r.row(2)) == .counter { b.setF(x, r.row(2), .none) }
            }
        } else {
            fireX = r.x1 - 1
        }
        if !r.placeTall(.fireplace, fireX) { r.placeTall(.fireplace, (r.x0 + r.x1) / 2) }
        if r.width >= 8 { r.placeTall(.harpsichord, barOnLeft ? fireX - 2 : fireX + 2) }
        r.placeTables(from: r.height >= 6 ? 4 : 1, count: max(2, r.width * r.height / 14))
        r.clutter([.barrel, .plant, .barrel], count: 2)
    }

    private static func furnishInn(_ r: Interior, wall: Terrain) {
        let b = r.b
        var front = 0
        if r.height >= 7 && r.width >= 7 {
            // Guest rooms along the back, each with a door into the common room.
            let partition = r.row(3)
            for x in r.x0...r.x1 { b.setT(x, partition, wall); b.setF(x, partition, .none) }
            var starts: [Int] = []
            var s = r.x0
            while s + 2 <= r.x1 { starts.append(s); s += 4 }
            for (i, start) in starts.enumerated() {
                if i > 0 { for d in 0..<3 { b.setT(start - 1, r.row(d), wall) } }
                let roomEnd = i + 1 < starts.count ? starts[i + 1] - 2 : r.x1
                b.setF(start + 1, partition, .door)
                b.setF(start, r.y0, .bed)
                b.setF(start, r.y0 + 1, .bedFoot)
                if roomEnd >= start + 2 { b.setF(start + 2, r.row(0), b.rng.chance(0.5) ? .nightstand : .chest) }
            }
            front = 4
        } else {
            for x in stride(from: r.x0, to: r.x1, by: 3) where x != r.entry.x { r.placeBed(x, r.y0) }
            front = 3
        }
        let counterY = r.row(front)
        let counterStart = r.entry.x > (r.x0 + r.x1) / 2 ? r.x0 : r.x1 - 2
        if counterY != r.entry.y {
            for x in counterStart..<(counterStart + 3) { r.place(.counter, x, counterY) }
        }
        r.placeTables(from: front + 1, count: 1)
        r.clutter([.plant, .barrel, .chest], count: 2)
    }

    private static func furnishShop(_ r: Interior, wares: [Feature], counterItems: [Feature]) {
        let len = min(r.width - 2, 5)
        let start = r.entry.x > (r.x0 + r.x1) / 2 ? r.x0 : r.x1 - len + 1
        if r.height >= 5 {
            for (i, x) in (start..<(start + len)).enumerated() {
                r.place(.counter, x, r.row(2))
                if i % 2 == 0 { r.placeTall(.shelf, x) } else { r.place(counterItems[i % counterItems.count], x, r.row(0)) }
            }
        }
        r.clutter(wares, count: max(3, r.width / 2))
        r.clutter([.plant], count: 1)
    }

    private static func furnishSmithy(_ r: Interior) {
        let cx = (r.x0 + r.x1) / 2
        r.place(.forge, cx, r.row(0))
        r.place(.anvil, cx, r.row(2))
        r.place(.barrel, cx + 2, r.row(1))
        r.placeTall(.weaponRack, r.x0)
        r.clutter([.woodpile, .crate, .weaponRack, .barrel], count: 3)
    }

    private static func furnishHealer(_ r: Interior) {
        let bedX = r.entry.x > (r.x0 + r.x1) / 2 ? r.x0 : r.x1
        var y = r.y0
        while y + 1 <= r.y1 {
            r.placeBed(bedX, y)
            y += 3
        }
        for x in stride(from: r.x0 + 1, through: r.x1 - 1, by: 2) where x != bedX { r.placeTall(.shelf, x) }
        r.place(.cauldron, (r.x0 + r.x1) / 2, r.row(2))
        r.clutter([.plant, .chest, .nightstand], count: 3)
    }

    private static func furnishTemple(_ r: Interior) {
        let b = r.b
        let aisle = r.entry.x
        for d in 0..<r.height { b.setT(aisle, r.row(d), .redCarpet) }
        r.place(.altar, aisle, r.row(0))
        r.place(.candelabra, aisle - 2, r.row(0))
        r.place(.candelabra, aisle + 2, r.row(0))
        var d = 2
        while d < r.height - 1 {
            let y = r.row(d)
            for x in r.x0...r.x1 where abs(x - aisle) >= 2 && x != r.x0 && x != r.x1 { r.place(.pew, x, y) }
            d += 2
        }
        r.clutter([.plant, .candelabra], count: 2)
    }

    private static func furnishHome(_ r: Interior) {
        let b = r.b
        let bedX = r.entry.x > (r.x0 + r.x1) / 2 ? r.x0 : r.x1
        r.placeBed(bedX, r.y0)
        let otherSide = bedX == r.x0 ? r.x1 : r.x0
        r.placeTall(.fireplace, otherSide == r.x0 ? r.x0 + 1 : r.x1 - 1)
        r.placeTall(b.rng.chance(0.5) ? .bookshelf : .wardrobe, (r.x0 + r.x1) / 2)
        // A rug in the middle of the room.
        let cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2
        if r.width >= 5 && r.height >= 4 {
            let rug: Terrain = b.rng.chance(0.5) ? .carpet : .redCarpet
            for y in cy...(cy + 1) {
                for x in (cx - 1)...(cx + 1) where r.contains(x, y) && b.f(x, y) == .none { b.setT(x, y, rug) }
            }
        }
        r.placeTables(from: 1, count: 1)
        r.clutter([.chest, .barrel, .plant, .nightstand], count: 2)
    }

    /// Furniture that stands tall against the north wall; windows stay clear of it.
    private static func isTall(_ f: Feature) -> Bool {
        switch f {
        case .fireplace, .bookshelf, .wardrobe, .shelf, .weaponRack, .harpsichord, .forge: return true
        default: return false
        }
    }

    private static func addWindows(_ b: RegionBuilder, x: Int, y: Int, w: Int, h: Int, door: Point, stained: Bool) {
        let glass: Feature = stained ? .stainedGlass : .window
        func tryWindow(_ wx: Int, _ wy: Int, inward: (Int, Int)) {
            guard b.f(wx, wy) == .none, abs(wx - door.x) + abs(wy - door.y) > 1 else { return }
            let ix = wx + inward.0, iy = wy + inward.1
            guard !b.t(ix, iy).isWall, !isTall(b.f(ix, iy)) else { return }
            b.setF(wx, wy, glass)
        }
        for wx in stride(from: x + 2, to: x + w - 2, by: 3) {
            tryWindow(wx, y, inward: (0, 1))
            tryWindow(wx, y + h - 1, inward: (0, -1))
        }
        for wy in stride(from: y + 2, to: y + h - 2, by: 3) {
            tryWindow(x, wy, inward: (1, 0))
            tryWindow(x + w - 1, wy, inward: (-1, 0))
        }
    }

    /// Torches, paintings and tapestries hang on the north and west walls, whose
    /// faces look into the room.
    private static func decorateWalls(_ b: RegionBuilder, room r: Interior, kind: BuildingKind) {
        let y = r.y0 - 1
        var options: [Feature] = [.wallTorch, .wallTorch]
        switch kind {
        case .temple: options = [.banner, .wallTorch, .banner]
        case .home, .inn: options = [.painting, .wallTorch]
        case .tavern: options = [.wallTorch, .painting, .wallTorch]
        default: break
        }
        var placed = 0
        for x in stride(from: r.x0 + 1, through: r.x1 - 1, by: 3) where placed < 3 {
            guard b.t(x, y).isWall, b.f(x, y) == .none, !isTall(b.f(x, r.y0)) else { continue }
            b.setF(x, y, options[placed % options.count])
            placed += 1
        }
        // A torch on the west wall of bigger rooms.
        let wy = (r.y0 + r.y1) / 2 + 1
        if r.height >= 5, b.t(r.x0 - 1, wy).isWall, b.f(r.x0 - 1, wy) == .none, b.f(r.x0, wy) == .none {
            b.setF(r.x0 - 1, wy, .wallTorch)
        }
    }
}
