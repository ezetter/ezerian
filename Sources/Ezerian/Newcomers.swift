import Foundation

/// The land fills up again. Every region keeps the roll of people it was first given
/// (`Populace.roster`, the same each time for the same world). When someone on it is
/// gone (slain, mostly), each new day brings a chance that a newcomer of the same kind
/// takes their place: a new mercenary for a dead mercenary, a new watchman for a fallen
/// one, an orc for an orc, a wolf for a wolf, a new blacksmith for the smithy. Each
/// newcomer is a stranger (new name, face, health and purse) who lives where the one
/// they replace lived. A place is filled at most once, so no region ever holds more
/// people than it began with; and no one appears where the Avatar would see it happen.
extension Game {
    /// The chance, each day, that someone's empty place is filled.
    static let newcomerChance = 0.2
    /// Newcomers arrive no nearer the Avatar than this (out of sight).
    static let newcomerClearance = 14
    /// At most this many days of arrivals are made up at once (after a long rest).
    static let newcomerCatchUp = 7

    /// Called as time passes: on each new day, the empty places may be filled.
    func welcomeNewcomers() {
        let today = day
        guard let last = newcomersDay else { newcomersDay = today; return }
        guard today > last else { return }
        for d in max(last + 1, today - Game.newcomerCatchUp + 1)...today { fillEmptyPlaces(day: d) }
        newcomersDay = today
    }

    /// Gives each empty place in the land its daily chance of a newcomer. Returns who came.
    @discardableResult
    func fillEmptyPlaces(day d: Int) -> [NPC] {
        var filled = Set<Int>()
        for r in world.regions.values { for n in r.npcs { filled.insert(n.place) } }
        for n in party { filled.insert(n.place) }
        var came: [NPC] = []
        let regions = world.regions.values.sorted { ($0.key.z, $0.key.y, $0.key.x) < ($1.key.z, $1.key.y, $1.key.x) }
        for region in regions {
            for t in Populace.roster(region, seed: world.seed, avatarHealth: maxHP) where !filled.contains(t.id) {
                guard Hash.unit(world.seed, t.id, d, 0x5EED) < Game.newcomerChance,
                      let (px, py) = newcomerSpot(for: t, day: d) else { continue }
                var rng = SplitMix64(seed: Hash.of(world.seed, t.id, d, 0xC0FFEE))
                let n = Populace.person(id: Int(truncatingIfNeeded: Hash.of(world.seed, t.id, d, 0xBEEF)),
                                        race: t.race, x: px, y: py, z: t.z, role: t.role, bounds: t.bounds, home: t.home,
                                        draconian: t.servesDraconian, warband: t.warband, guardRank: t.guardRank,
                                        avatarHealth: maxHP, &rng)
                n.slot = t.id
                region.npcs.append(n)
                filled.insert(t.id)
                came.append(n)
            }
        }
        return came
    }

    /// Where a newcomer arrives: where the one they replace first stood, or near it, on
    /// open ground no one holds, out of the Avatar's sight.
    private func newcomerSpot(for t: NPC, day d: Int) -> (Int, Int)? {
        func ok(_ x: Int, _ y: Int) -> Bool {
            guard x >= t.bounds[0], y >= t.bounds[1], x <= t.bounds[2], y <= t.bounds[3] else { return false }
            if t.z == z && max(abs(x - self.x), abs(y - self.y)) < Game.newcomerClearance { return false }
            let f = world.feature(x, y, t.z)
            if f == .door || f == .caveEntrance || f == .ladderUp || !world.isPassable(x, y, t.z) { return false }
            return world.npc(at: x, y, t.z) == nil && !party.contains { $0.x == x && $0.y == y && $0.z == t.z }
        }
        if ok(t.homeX, t.homeY) { return (t.homeX, t.homeY) }
        for k in 0..<24 {
            let dx = Int(Hash.of(world.seed, t.id, d, 100 + k) % 7) - 3, dy = Int(Hash.of(world.seed, t.id, d, 200 + k) % 7) - 3
            if ok(t.homeX + dx, t.homeY + dy) { return (t.homeX + dx, t.homeY + dy) }
        }
        return nil
    }
}
