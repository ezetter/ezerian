import Foundation

/// Generates regions. The natural landscape comes from continuous noise fields, so
/// coastlines, forests and rivers flow seamlessly across region borders; towns,
/// buildings and other sites are then laid on top using a per-region random stream.
final class WorldGenerator {
    let seed: UInt64
    private let elevation: Perlin
    private let moisture: Perlin
    private let rivers: Perlin
    private let ridges: Perlin
    private let groves: Perlin

    init(seed: UInt64) {
        self.seed = seed
        elevation = Perlin(seed: seed &+ 11)
        moisture = Perlin(seed: seed &+ 23)
        rivers = Perlin(seed: seed &+ 37)
        ridges = Perlin(seed: seed &+ 41)
        groves = Perlin(seed: seed &+ 53)
    }

    // MARK: Natural terrain

    func elevationAt(_ x: Int, _ y: Int) -> Double {
        let fx = Double(x), fy = Double(y)
        var e = elevation.fbm(fx / 150, fy / 150, octaves: 5) + 0.03
        // Lift the lowlands around the starting region into a friendly home continent,
        // without piling the highlands up into mountains.
        let d = ((fx - 32) * (fx - 32) + (fy - 32) * (fy - 32)).squareRoot()
        let home = max(0, 1 - d / 130)
        if e < 0.1 { e += (0.1 - e) * min(1, home * 1.6) }
        if e > 0.2 { e -= (e - 0.2) * home * 0.6 }
        return e
    }

    func baseTerrain(_ x: Int, _ y: Int) -> Terrain {
        let fx = Double(x), fy = Double(y)
        let e = elevationAt(x, y)
        if e < -0.20 { return .deepWater }
        if e < -0.11 { return .shallowWater }
        let river = abs(rivers.fbm(fx / 140, fy / 140, octaves: 2))
        if e < 0.34 && river < 0.010 + max(0, 0.2 - e) * 0.03 { return .shallowWater }
        if e < -0.07 { return .sand }
        let ridge = 1 - abs(ridges.fbm(fx / 55, fy / 55, octaves: 3)) * 2.2
        if e > 0.46 || (e > 0.12 && ridge > 0.93 - (e - 0.12) * 0.9) { return .mountain }
        if e > 0.32 || (e > 0.1 && ridge > 0.82) { return .hills }
        let m = moisture.fbm(fx / 110 + 100, fy / 110 - 50, octaves: 4)
        if m > 0.26 && e < 0.12 { return .swamp }
        if m > 0.07 { return .forest }
        if m < -0.40 { return .sand }
        if m < -0.17 { return .brush }
        return .grass
    }

    /// Wild plants and stones, decided per tile so they never depend on generation order.
    func scatter(_ t: Terrain, _ x: Int, _ y: Int, nearWater: () -> Bool) -> Feature {
        var r = Hash.unit(seed, x, y, 7)
        let pick = Hash.unit(seed, x, y, 8)
        let g = groves.noise(Double(x) / 14, Double(y) / 14) * 0.5 + 0.5
        func take(_ p: Double) -> Bool {
            if r < p { return true }
            r -= p
            return false
        }
        switch t {
        case .grass:
            if take(0.010 + 0.16 * g * g * g) {
                return pick < 0.55 ? .oakTree : pick < 0.72 ? .pineTree : pick < 0.84 ? .birchTree
                    : pick < 0.9 ? .blossomTree : .bush
            }
            if take(0.022) { return .bush }
            if take(0.028) {
                return [.flowersRed, .flowersYellow, .flowersBlue, .flowersWhite][Int(pick * 4) % 4]
            }
            if take(0.008) { return .rock }
            if take(0.010) { return .fern }
            if take(0.004) { return .deadBranch }
            if take(0.003) { return .stump }
            if take(0.003) { return .mushrooms }
        case .forest:
            if take(0.05) { return .fern }
            if take(0.02) { return .mushrooms }
            if take(0.012) { return .rock }
        case .brush:
            if take(0.08) { return .bush }
            if take(0.025) { return .rock }
            if take(0.02) { return .deadBranch }
            if take(0.012) { return pick < 0.6 ? .oakTree : .pineTree }
            if take(0.012) { return .flowersYellow }
            if take(0.004) { return .boulder }
        case .hills:
            if take(0.04) { return .rock }
            if take(0.012) { return .boulder }
            if take(0.06 * g) { return .pineTree }
            if take(0.03) { return .bush }
            if take(0.012) { return .deadBranch }
        case .swamp:
            if take(0.035) { return .deadTree }
            if take(0.09) { return .reeds }
            if take(0.02) { return .mushrooms }
        case .sand:
            if nearWater() {
                if take(0.035) { return .palmTree }
                if take(0.01) { return .rock }
            } else {
                if take(0.03) { return .cactus }
                if take(0.016) { return .rock }
                if take(0.006) { return .deadBranch }
                if take(0.004) { return .boulder }
            }
        case .shallowWater:
            if nearWater() {
                if take(0.06) { return .reeds }
                if take(0.02) { return .lilyPad }
            }
        default:
            break
        }
        return .none
    }

    // MARK: Region assembly

    func generate(_ key: RegionKey, world: World) -> Region {
        if key.z != 0 {
            let surface = world.region(RegionKey(x: key.x, y: key.y, z: 0))
            let cave = CaveBuilder.build(key, surface: surface, seed: seed)
            Populace.populate(cave, seed: seed)
            return cave
        }
        let b = RegionBuilder(key: key, generator: self)
        b.layNaturalTerrain()

        var hubs: [Point] = []
        var siteEntrances: [Point] = []
        let isHome = key.x == 0 && key.y == 0
        if isHome || b.rng.chance(0.32) {
            if let gates = Settlements.buildTown(b, large: isHome || b.rng.chance(0.5), nearCenter: isHome) {
                hubs.append(contentsOf: gates)
            } else if isHome {
                // The adventure always starts in a town, whatever the land looks like.
                let gates = Settlements.buildTown(b, large: false, nearCenter: true)
                    ?? Settlements.buildTown(b, large: false, nearCenter: true, force: true)
                hubs.append(contentsOf: gates ?? [])
            }
        }
        if hubs.isEmpty && b.rng.chance(0.3), let door = Sites.roadsideInn(b) { hubs.append(door) }
        if b.rng.chance(hubs.isEmpty ? 0.4 : 0.25), let p = Sites.farm(b) { siteEntrances.append(p) }
        if b.rng.chance(0.15), let p = Sites.shrine(b) { siteEntrances.append(p) }
        if b.rng.chance(0.2), let p = Sites.ruins(b) { siteEntrances.append(p) }
        if b.rng.chance(0.12), let p = Sites.graveyard(b) { siteEntrances.append(p) }
        if b.rng.chance(0.3) { _ = Sites.campsite(b) }
        if b.rng.chance(0.12) { _ = Sites.standingStones(b) }
        if b.rng.chance(0.3), let p = Sites.cottage(b) { siteEntrances.append(p) }
        if b.rng.chance(0.12) { _ = Sites.orchard(b) }
        if b.rng.chance(0.7) { Sites.caveEntrances(b, count: 1 + b.rng.int(2)) }

        Roads.build(b, hubs: hubs, sites: siteEntrances)
        b.region.name = Names.regionName(for: b.region, rng: &b.rng)
        Populace.populate(b.region, seed: seed)
        return b.region
    }

    // MARK: Road crossings shared by neighbouring regions

    private func roadable(_ t: Terrain) -> Bool { !t.isWater && t != .mountain }

    /// Row (0..<64) where a road crosses the border between region (ex, ey) and (ex+1, ey).
    func verticalCrossing(_ ex: Int, _ ey: Int) -> Int? {
        let h = Hash.of(seed, ex, ey, 101)
        guard h % 100 < 55 else { return nil }
        let base = 10 + Int((h >> 8) % 44)
        let wx = (ex + 1) * Region.size
        for i in 0..<17 {
            let ly = base + (i % 2 == 0 ? i / 2 : -(i + 1) / 2)
            guard ly >= 4, ly < 60 else { continue }
            let wy = ey * Region.size + ly
            if roadable(baseTerrain(wx - 1, wy)) && roadable(baseTerrain(wx, wy)) { return ly }
        }
        return nil
    }

    /// Column where a road crosses the border between region (ex, ey) and (ex, ey+1).
    func horizontalCrossing(_ ex: Int, _ ey: Int) -> Int? {
        let h = Hash.of(seed, ex, ey, 202)
        guard h % 100 < 55 else { return nil }
        let base = 10 + Int((h >> 8) % 44)
        let wy = (ey + 1) * Region.size
        for i in 0..<17 {
            let lx = base + (i % 2 == 0 ? i / 2 : -(i + 1) / 2)
            guard lx >= 4, lx < 60 else { continue }
            let wx = ex * Region.size + lx
            if roadable(baseTerrain(wx, wy - 1)) && roadable(baseTerrain(wx, wy)) { return lx }
        }
        return nil
    }
}

struct Point: Hashable {
    var x: Int
    var y: Int
}

/// Mutable view of a region under construction, in local (0..<64) coordinates.
final class RegionBuilder {
    let region: Region
    let generator: WorldGenerator
    var rng: SplitMix64
    /// Tiles claimed by a structure; nothing else may be built there.
    var reserved: [Bool]
    let n = Region.size

    init(key: RegionKey, generator: WorldGenerator) {
        region = Region(key: key)
        self.generator = generator
        rng = SplitMix64(seed: Hash.of(generator.seed, key.x, key.y, 1000 + key.z))
        reserved = Array(repeating: false, count: Region.size * Region.size)
    }

    var ox: Int { region.originX }
    var oy: Int { region.originY }

    @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n }
    @inline(__always) func t(_ x: Int, _ y: Int) -> Terrain { region.terrain[y * n + x] }
    @inline(__always) func f(_ x: Int, _ y: Int) -> Feature { region.features[y * n + x] }
    @inline(__always) func setT(_ x: Int, _ y: Int, _ v: Terrain) { region.terrain[y * n + x] = v }
    @inline(__always) func setF(_ x: Int, _ y: Int, _ v: Feature) { region.features[y * n + x] = v }
    func isReserved(_ x: Int, _ y: Int) -> Bool { reserved[y * n + x] }

    func reserve(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        for yy in max(0, y)..<min(n, y + h) {
            for xx in max(0, x)..<min(n, x + w) { reserved[yy * n + xx] = true }
        }
    }

    func setSign(_ x: Int, _ y: Int, _ text: String, icon: String? = nil) {
        region.signs[y * n + x] = Sign(text: text, icon: icon)
    }

    func addPlace(_ kind: Place.Kind, _ name: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int, roof: RoofStyle? = nil) {
        region.places.append(Place(kind: kind, name: name, x: ox + x, y: oy + y, w: w, h: h, roof: roof))
    }

    func layNaturalTerrain() {
        let g = generator
        for y in 0..<n {
            for x in 0..<n {
                setT(x, y, g.baseTerrain(ox + x, oy + y))
            }
        }
        for y in 0..<n {
            for x in 0..<n {
                let terrain = t(x, y)
                let wx = ox + x, wy = oy + y
                let feature = g.scatter(terrain, wx, wy) {
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nb = self.inside(x + dx, y + dy) ? self.t(x + dx, y + dy) : g.baseTerrain(wx + dx, wy + dy)
                        if terrain == .shallowWater ? !nb.isWater : nb.isWater { return true }
                    }
                    return false
                }
                setF(x, y, feature)
            }
        }
    }

    /// Ground a structure can be built on (it will be cleared first).
    static func buildable(_ t: Terrain) -> Bool {
        switch t {
        case .grass, .brush, .sand, .hills, .forest, .dirt: return true
        default: return false
        }
    }

    /// Finds a free rectangle whose ground is (almost) all acceptable.
    func findSpot(w: Int, h: Int, margin: Int = 3, tries: Int = 60, preferCenter: Bool = false,
                  allowedBad: Int = 0, accept: (Terrain) -> Bool = RegionBuilder.buildable) -> Point? {
        guard w + 2 * margin < n, h + 2 * margin < n else { return nil }
        var best: (Point, Int)?
        for i in 0..<tries {
            var x = margin + rng.int(n - w - 2 * margin)
            var y = margin + rng.int(n - h - 2 * margin)
            if preferCenter {
                let spread = 4 + i / 3
                x = max(margin, min(n - w - margin, (n - w) / 2 + rng.int(2 * spread + 1) - spread))
                y = max(margin, min(n - h - margin, (n - h) / 2 + rng.int(2 * spread + 1) - spread))
            }
            var bad = 0
            var blocked = false
            for yy in y..<(y + h) where !blocked {
                for xx in x..<(x + w) {
                    if isReserved(xx, yy) { blocked = true; break }
                    if !accept(t(xx, yy)) { bad += 1 }
                }
            }
            if blocked || bad > allowedBad { continue }
            if bad == 0 { return Point(x: x, y: y) }
            if best == nil || bad < best!.1 { best = (Point(x: x, y: y), bad) }
        }
        return best?.0
    }

    /// Turns a rectangle into plain clearing (grass) with no features.
    func clear(_ x: Int, _ y: Int, _ w: Int, _ h: Int, to ground: Terrain = .grass) {
        for yy in y..<(y + h) {
            for xx in x..<(x + w) where inside(xx, yy) {
                setT(xx, yy, ground)
                setF(xx, yy, .none)
            }
        }
    }
}
