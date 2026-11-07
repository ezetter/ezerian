import Foundation

/// A fight in progress. Everyone takes turns in a fixed round: the Avatar, then each
/// companion, then each enemy (or the enemy first, if they started it). For now
/// everyone fights bare-handed and equally well: half the blows land, for 1-10 damage.
final class Combat {
    /// The people the party is fighting.
    var enemies: [NPC]
    /// Others fighting on the party's side: the town watch, against Draconian's people.
    var allies: [NPC] = []
    /// Turn order; nil is the Avatar.
    var order: [NPC?]
    /// Whose turn it is (an index into `order`).
    var current = 0
    /// Foes who have lost their nerve and are running from the Avatar.
    var fleeing: [NPC] = []
    /// Foes already badly hurt enough to have weighed running (each does so once).
    var shaken: [NPC] = []

    init(enemies: [NPC], order: [NPC?]) {
        self.enemies = enemies
        self.order = order
    }

    /// What Lord Draconian's people cry out whenever they attack.
    static let draconianBattleCry = "Thou shalt bow down before Lord Draconian, mighty emperor of Sespooland and Ezerian."

    /// A foe left with less than this much health, the first time, may lose their nerve...
    static let fearHealth = 10
    /// ...with this chance, and run from the Avatar instead of fighting.
    static let fleeChance = 0.5
    /// One who got away keeps clear of the Avatar this many turns (two hours) before menacing them again.
    static let cowedTurns = 60

    static let hitChance = 0.5
    static let maxDamage = 10
    /// How much attacking someone sours them towards the Avatar.
    static let attackedPenalty = 60
    /// Out of a fight, health comes back one point every this many turns
    /// (a turn is two minutes, so 3 points an hour; a healer is far quicker).
    static let recoveryTurns = 20

    /// Enemies further away than this have been escaped.
    static let escapeDistance = 8
    /// Chance a foe who can't reach anyone falls behind this turn, so a retreat can succeed.
    static let pursuitStumble = 0.25

    /// Chance that someone who dislikes the Avatar attacks: each turn they stand beside them,
    /// each round of a fight close by, and when words sour them. None at -50 or above, then 2%
    /// for every point below -50: 2% at -51, 50% at -75, certain at -100.
    static func attackChance(_ friendliness: Int) -> Double {
        friendliness > -51 ? 0 : min(1, 0.02 * Double(-50 - friendliness))
    }

    /// Unfriendly people this close to the Avatar during a fight may join it against them,
    /// each round, with the same chance (`attackChance`).
    static let joinDistance = 3

    /// The town watch within this distance of the Avatar comes to their aid against Lord
    /// Draconian's people (checked every round).
    static let watchAidDistance = 3

    /// Wolves close in on the Avatar from this far off, and a wolf's packmates within this
    /// distance of it join any fight it is in.
    static let wolfScent = 8

}

extension Game {
    var inCombat: Bool { combat != nil }

    /// Wounds heal with time while there is no fighting: the Avatar, the companions,
    /// and the people round about.
    func recover() {
        guard combat == nil, !gameOver, turn % Combat.recoveryTurns == 0 else { return }
        hp = min(maxHP, hp + 1)
        for n in world.npcs(near: x, y, z, radius: 18) where n.hp > 0 && n.hp < n.maxHP { n.hp += 1 }
    }

    // MARK: Starting

    /// The Avatar turns to attack whoever stands in a direction (after pressing F).
    func attack(dx: Int, dy: Int) {
        attackPending = false
        guard !gameOver, conversation == nil, dx != 0 || dy != 0 else { return }
        facing = dx != 0 && dy != 0 ? (dy < 0 ? .north : .south) : Direction.from(dx: dx, dy: dy)
        guard let target = world.npc(at: x + dx, y + dy, z) else {
            log("There is no one there to attack.")
            return
        }
        if target.following {
            log("You won't raise a hand against \(target.name).")
            return
        }
        if let c = combat {
            if !c.enemies.contains(where: { $0 === target }) { join(target, to: c, attackedByAvatar: true) }
            strike(nil, target)
            endAvatarTurn()
        } else {
            startCombat(against: target, startedByEnemy: false)
        }
    }

    func startCombat(against enemy: NPC, startedByEnemy: Bool) {
        guard !gameOver, enemy.hp > 0 else { return }
        conversation = nil
        attackPending = false
        if let c = combat {
            join(enemy, to: c, attackedByAvatar: !startedByEnemy)
            return
        }
        unmask(enemy)
        let companions = world.party.filter { $0.z == z && $0.hp > 0 }
        let c: Combat
        if startedByEnemy {
            c = Combat(enemies: [enemy], order: [enemy, nil] + companions)
            log("\(enemy.shortName.capitalizedFirst) attacks you!")
        } else {
            enemy.changeFriendliness(by: -Combat.attackedPenalty)
            enemy.struckByAvatar = true
            c = Combat(enemies: [enemy], order: [nil] + companions + [enemy])
            log("You attack \(enemy.shortName)!")
        }
        // Lord Draconian's people cry out his name in every fight, whoever strikes first.
        if enemy.openlyDraconian {
            log("\(enemy.shortName.capitalizedFirst) cries: \"\(Combat.draconianBattleCry)\"")
        }
        combat = c
        if enemy.race == .wolf { joinPack(of: enemy, to: c) }
        if startedByEnemy { callTheWatch() }
        // Draconian's people stand together: his servants close by join in.
        if enemy.openlyDraconian {
            for ally in world.npcs(near: enemy.x, enemy.y, z, radius: 6)
            where ally !== enemy && ally.openlyDraconian && ally.friendliness < 0 && !ally.following && ally.hp > 0
                && turn >= ally.cowedUntil {
                join(ally, to: c, attackedByAvatar: false)
            }
        }
        if !companions.isEmpty {
            log("\(companions.map(\.name).joined(separator: companions.count == 2 ? " and " : ", ")) \(companions.count == 1 ? "joins" : "join") the fight.")
        }
        if startedByEnemy {
            // (When the Avatar strikes first, the onlookers are weighed as their turn ends.)
            checkBystanders()
            runUntilAvatarsTurn()
        } else {
            strike(nil, enemy)
            endAvatarTurn()
        }
    }

    private func join(_ enemy: NPC, to c: Combat, attackedByAvatar: Bool) {
        guard !c.enemies.contains(where: { $0 === enemy }) else { return }
        unmask(enemy)
        // A servant drawn into a fight that started with someone else announces himself too,
        // unless he's only one of a band answering their leader's cry.
        if enemy.openlyDraconian && !c.enemies.contains(where: \.openlyDraconian) {
            log("\(enemy.shortName.capitalizedFirst) cries: \"\(Combat.draconianBattleCry)\"")
        }
        if attackedByAvatar {
            enemy.changeFriendliness(by: -Combat.attackedPenalty)
            enemy.struckByAvatar = true
        }
        // An ally the Avatar turns on is an ally no longer (and already has a turn).
        let wasAlly = c.allies.contains { $0 === enemy }
        c.allies.removeAll { $0 === enemy }
        c.enemies.append(enemy)
        if !wasAlly { c.order.append(enemy) }
        log("\(enemy.shortName.capitalizedFirst) joins the fight!")
        if enemy.race == .wolf { joinPack(of: enemy, to: c) }
    }

    /// A hidden agent of Draconian who fights the party, whoever struck first, shows their true colours.
    private func unmask(_ n: NPC) {
        guard n.agent, !n.unmasked else { return }
        n.unmasked = true
        log("\(n.shortName.capitalizedFirst) reveals \(n.his) true allegiance: \(n.he) secretly serves Lord Draconian!")
    }

    /// Wolves hunt as a pack: when one fights, the rest of its pack nearby joins in.
    private func joinPack(of wolf: NPC, to c: Combat) {
        let mates = world.npcs(near: wolf.x, wolf.y, z, radius: Combat.wolfScent)
            .filter { w in w.race == .wolf && w.hp > 0 && !c.enemies.contains { $0 === w } }
        guard !mates.isEmpty else { return }
        for m in mates {
            c.enemies.append(m)
            c.order.append(m)
        }
        log(mates.count == 1 ? "Another wolf joins the fight!" : "\(mates.count) more wolves join the fight!")
    }

    /// During a fight, each unfriendly onlooker within `Combat.joinDistance` of the Avatar
    /// may take the chance to join in against them (checked every round). Those who do
    /// come at the party on their turns like any other foe.
    func checkBystanders() {
        callTheWatch()
        guard let c = combat, !gameOver else { return }
        for n in world.npcs(near: x, y, z, radius: Combat.joinDistance)
        where !n.following && n.hp > 0 && n.friendliness < 0 && turn >= n.cowedUntil
            && !c.enemies.contains(where: { $0 === n }) && !c.allies.contains(where: { $0 === n }) {
            if roll() < Combat.attackChance(n.friendliness) { join(n, to: c, attackedByAvatar: false) }
        }
    }

    /// While the Avatar fights Lord Draconian's people, the town watch within
    /// `Combat.watchAidDistance` of them comes to their aid, striking only at his people.
    /// (Their kills earn the party no experience.)
    func callTheWatch() {
        guard let c = combat, !gameOver, c.enemies.contains(where: { $0.openlyDraconian && $0.hp > 0 }) else { return }
        let watch = world.npcs(near: x, y, z, radius: Combat.watchAidDistance).filter { n in
            n.guardRank != nil && n.hp > 0 && !n.following && !n.forDraconian
                && !c.enemies.contains { $0 === n } && !c.allies.contains { $0 === n }
        }
        for g in watch {
            c.allies.append(g)
            c.order.append(g)
            log("\(g.shortName.capitalizedFirst) comes to your aid!")
        }
    }

    /// An unfriendly NPC beside the Avatar may attack (checked every turn).
    func checkAmbush() {
        guard combat == nil, conversation == nil, !gameOver else { return }
        for n in world.npcs(near: x, y, z, radius: 1) where !n.following && n.hp > 0 && n.friendliness < 0 && turn >= n.cowedUntil {
            if roll() < Combat.attackChance(n.friendliness) {
                startCombat(against: n, startedByEnemy: true)
                return
            }
        }
    }

    // MARK: Turns

    /// The Avatar has acted (struck, stepped or waited): everyone else takes their
    /// turn, in order, until it comes round to the Avatar again.
    func endAvatarTurn() {
        guard let c = combat else { return }
        turn += 1
        // Onlookers who join go to the end of the round, so they act before it comes round again.
        checkBystanders()
        c.current = (c.current + 1) % c.order.count
        runUntilAvatarsTurn()
    }

    private func runUntilAvatarsTurn() {
        var guardCount = 0
        while let c = combat, !gameOver, guardCount < 64 {
            guardCount += 1
            if checkCombatOver() { return }
            guard let fighter = c.order[c.current] else { return }   // the Avatar's turn
            if fighter.hp > 0 && fighter.z == z { fighterTurn(fighter, c) }
            guard let c2 = combat else { return }
            c2.current = (c2.current + 1) % c2.order.count
        }
    }

    /// An NPC's turn: strike the nearest foe within reach, or step towards them.
    private func fighterTurn(_ n: NPC, _ c: Combat) {
        if c.fleeing.contains(where: { $0 === n }) { fleeTurn(n, c); return }
        let isEnemy = c.enemies.contains { $0 === n }
        // Foes: nil is the Avatar.
        var foes: [NPC?] = []
        if isEnemy {
            foes.append(nil)
            foes += world.party.filter { $0.hp > 0 && $0.z == z }
            foes += c.allies.filter { $0.hp > 0 && $0.z == z }
        } else if c.allies.contains(where: { $0 === n }) {
            // The watch strikes only at Draconian's people.
            foes += c.enemies.filter { $0.hp > 0 && $0.z == z && $0.openlyDraconian }
        } else {
            foes += c.enemies.filter { $0.hp > 0 && $0.z == z }
        }
        func pos(_ f: NPC?) -> Point { f.map { Point(x: $0.x, y: $0.y) } ?? Point(x: x, y: y) }
        func dist(_ p: Point) -> Int { max(abs(p.x - n.x), abs(p.y - n.y)) }
        // Strike the weakest foe within reach; otherwise head for the nearest.
        func health(_ f: NPC?) -> Int { f?.hp ?? hp }
        let inReach = foes.filter { dist(pos($0)) <= 1 }
        guard let target = inReach.min(by: { health($0) < health($1) })
                ?? foes.min(by: { dist(pos($0)) < dist(pos($1)) }) else { return }
        let tp = pos(target)
        n.facing = Direction.from(dx: tp.x - n.x, dy: tp.y - n.y).rawValue
        if dist(tp) <= 1 {
            strike(n, target)
            return
        }
        // Step to the free neighbouring tile that brings them closest
        // (a pursuing enemy sometimes falls behind).
        if isEnemy && roll() < Combat.pursuitStumble { return }
        let home = world.region(containing: n.x, n.y, n.z)
        var best: Point?
        var bestD = dist(tp)
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let p = Point(x: n.x + dx, y: n.y + dy)
                let d = max(abs(tp.x - p.x), abs(tp.y - p.y))
                guard d < bestD, world.isPassable(p.x, p.y, z), world.npc(at: p.x, p.y, z) == nil,
                      p != Point(x: x, y: y) else { continue }
                let f = world.feature(p.x, p.y, z)
                if f == .caveEntrance || f == .ladderUp || f == .door && isEnemy { continue }
                // People belong to their region's roll; they don't chase across its border.
                if !n.following && !home.contains(p.x, p.y) { continue }
                if dx != 0 && dy != 0 && !world.isPassable(n.x + dx, n.y, z) && !world.isPassable(n.x, n.y + dy, z) { continue }
                best = p
                bestD = d
            }
        }
        if let p = best {
            n.prevX = n.x
            n.prevY = n.y
            n.facing = Direction.from(dx: p.x - n.x, dy: p.y - n.y).rawValue
            n.x = p.x
            n.y = p.y
        }
    }

    /// A foe who has lost their nerve steps away from the Avatar, as far as they can; more
    /// than `Combat.escapeDistance` off, they are out of the fight, and keep clear for a while.
    private func fleeTurn(_ n: NPC, _ c: Combat) {
        func far(_ px: Int, _ py: Int) -> Int { max(abs(px - x), abs(py - y)) }
        if let p = fleeStep(for: n) {
            n.prevX = n.x
            n.prevY = n.y
            n.facing = Direction.from(dx: p.x - n.x, dy: p.y - n.y).rawValue
            n.x = p.x
            n.y = p.y
        }
        if far(n.x, n.y) > Combat.escapeDistance {
            leave(n, c)
            n.cowedUntil = turn + Combat.cowedTurns
            log("\(n.shortName.capitalizedFirst) has fled.")
        }
    }

    /// Where someone running from the Avatar steps next: by a "flee map", so they run round
    /// walls towards open ground rather than into a corner. The distance (in steps) from the
    /// Avatar over the ground near them is turned about (times -1.2) and smoothed again, so
    /// downhill leads away from the Avatar by the best way out. Nil when they are cornered.
    private func fleeStep(for n: NPC) -> Point? {
        let r = 16, w = 2 * r + 1
        let home = world.region(containing: n.x, n.y, n.z)
        func index(_ px: Int, _ py: Int) -> Int? {
            let ix = px - n.x + r, iy = py - n.y + r
            return ix >= 0 && iy >= 0 && ix < w && iy < w ? iy * w + ix : nil
        }
        func open(_ px: Int, _ py: Int) -> Bool {
            guard home.contains(px, py), world.isPassable(px, py, z) else { return false }
            let f = world.feature(px, py, z)
            return f != .caveEntrance && f != .ladderUp
        }
        func step(_ px: Int, _ py: Int, _ dx: Int, _ dy: Int) -> Bool {
            open(px + dx, py + dy) && (dx == 0 || dy == 0 || open(px + dx, py) || open(px, py + dy))
        }
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
        guard let start = index(x, y) else { return nil }
        // Steps from the Avatar.
        var cost = [Double](repeating: .infinity, count: w * w)
        cost[start] = 0
        var queue = [(x, y)], head = 0
        while head < queue.count {
            let (px, py) = queue[head]; head += 1
            let here = cost[index(px, py)!]
            for (dx, dy) in dirs where step(px, py, dx, dy) {
                guard let k = index(px + dx, py + dy), cost[k] == .infinity else { continue }
                cost[k] = here + 1
                queue.append((px + dx, py + dy))
            }
        }
        // Turned about, then smoothed: each place is at most one step worse than its best neighbour.
        var flee = cost.map { $0 == .infinity ? .infinity : -1.2 * $0 }
        for _ in 0..<40 {
            var changed = false
            for (px, py) in queue {
                let k = index(px, py)!
                for (dx, dy) in dirs where step(px, py, dx, dy) {
                    if let m = index(px + dx, py + dy), flee[m] + 1 < flee[k] { flee[k] = flee[m] + 1; changed = true }
                }
            }
            if !changed { break }
        }
        var best: Point?
        var bestF = index(n.x, n.y).map { flee[$0] } ?? .infinity
        for (dx, dy) in dirs where step(n.x, n.y, dx, dy) {
            let p = Point(x: n.x + dx, y: n.y + dy)
            guard p != Point(x: x, y: y), world.npc(at: p.x, p.y, z) == nil, let k = index(p.x, p.y), flee[k] < bestF else { continue }
            best = p
            bestF = flee[k]
        }
        return best
    }

    /// Takes someone out of the fight: killed, or fled.
    private func leave(_ n: NPC, _ c: Combat) {
        c.enemies.removeAll { $0 === n }
        c.allies.removeAll { $0 === n }
        c.fleeing.removeAll { $0 === n }
        if let i = c.order.firstIndex(where: { $0 === n }) {
            c.order.remove(at: i)
            if i < c.current { c.current -= 1 }
            if c.current >= c.order.count { c.current = 0 }
        }
    }

    /// One blow: half land, for 1-10 damage plus the weapon's bonus. nil is the Avatar.
    func strike(_ attacker: NPC?, _ target: NPC?) {
        let a = attacker.map { $0.shortName.capitalizedFirst } ?? "You"
        let t = (target.map { $0.shortName } ?? "you") + " with " + (attacker?.armedWith ?? "your \(weapon?.name ?? "bare hands")")
        let arm = attacker == nil ? weapon : attacker?.weapon
        guard roll() < Combat.hitChance else {
            log("\(a) \(attacker == nil ? "miss" : "misses") \(t).")
            return
        }
        let damage = min(Combat.maxDamage, 1 + Int(roll() * Double(Combat.maxDamage))) + (arm?.bonus ?? 0)
        // With hit scores on (Options menu), each landed blow reports the damage and what the one struck has left.
        let scores = Options.showHitScores
        if let target {
            target.hp = max(0, target.hp - damage)
            log("\(a) \(attacker == nil ? "hit" : "hits") \(t)" + (scores ? " for \(damage): \(target.hp) of \(target.maxHP) left." : "."))
            if target.hp == 0 {
                kill(target, byAvatar: attacker == nil, byParty: attacker == nil || attacker?.following == true)
            } else if target.hp < Combat.fearHealth, let c = combat, c.enemies.contains(where: { $0 === target }),
                      !c.shaken.contains(where: { $0 === target }) {
                // Badly hurt, a foe may lose their nerve and run.
                c.shaken.append(target)
                if roll() < Combat.fleeChance {
                    c.fleeing.append(target)
                    log(Dialogue.fear(target))
                }
            }
        } else {
            log("\(a) hits \(t)" + (scores ? " for \(damage): you have \(max(0, hp - damage)) of \(maxHP) left." : "."))
            hp = max(0, hp - damage)
            if hp == 0 {
                gameOver = true
                combat = nil
                attackPending = false
                log("You have been slain!")
            }
        }
    }

    private func kill(_ n: NPC, byAvatar: Bool, byParty: Bool) {
        if n.following {
            world.party.removeAll { $0 === n }
            n.following = false
            log("\(n.name) has fallen! \(n.he.capitalizedFirst) is gone from your party.")
        } else {
            world.region(containing: n.x, n.y, n.z).npcs.removeAll { $0 === n }
            log("\(n.shortName.capitalizedFirst) dies.")
            let foe = combat?.enemies.contains { $0 === n } ?? true
            // The party takes the purse of a foe they fell (beasts have none); a foe the watch
            // fells, or a fallen ally, keeps theirs.
            if !foe || !byParty || n.race.isBeast {
            } else if n.gold > 0 {
                gold += n.gold
                log("You take \(n.gold) gold \(n.gold == 1 ? "coin" : "coins") from \(n.his) body. You now have \(gold).")
                n.gold = 0
            } else {
                log("\(n.he.capitalizedFirst) carried no gold.")
            }
            // Whoever the Avatar slays, and any foe a companion fells, the party takes all
            // they carried (room permitting); a foe the watch fells keeps it.
            if byAvatar || (byParty && foe && !n.race.isBeast) { loot(n) }
            // A foe the party defeats is experience for all of them.
            if byParty && foe { shareExperience(forDefeating: n) }
        }
        if let c = combat { leave(n, c) }
    }

    /// Ends the fight when every enemy is dead, or left far behind.
    @discardableResult
    private func checkCombatOver() -> Bool {
        guard let c = combat else { return true }
        let near = c.enemies.filter { $0.hp > 0 && $0.z == z && max(abs($0.x - x), abs($0.y - y)) <= Combat.escapeDistance }
        guard near.isEmpty else { return false }
        combat = nil
        log(c.enemies.isEmpty ? "The fight is over." : "You have escaped.")
        trail.removeAll()
        return true
    }

    /// Where the Avatar fell, for the game-over screen.
    var deathMessage: String { "Thou hast fallen in \(region.name)." }
}
