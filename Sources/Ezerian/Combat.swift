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

    init(enemies: [NPC], order: [NPC?]) {
        self.enemies = enemies
        self.order = order
    }

    /// What Lord Draconian's people cry out whenever they attack.
    static let draconianBattleCry = "Thou shalt bow down before Lord Draconian, mighty emperor of Sespooland and Ezerian."

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

    /// Chance per turn that an unfriendly NPC standing beside the Avatar attacks:
    /// none at 0 or above, (friendliness / 100)² below, certain at -100.
    static func ambushChance(_ friendliness: Int) -> Double {
        friendliness >= 0 ? 0 : pow(Double(min(100, -friendliness)) / 100, 2)
    }

    /// Unfriendly people this close to the Avatar during a fight may join it against them,
    /// each round, with the same chance as an ambush.
    static let joinDistance = 3

    /// The town watch within this distance of the Avatar comes to their aid against Lord
    /// Draconian's people (checked every round).
    static let watchAidDistance = 3

    /// Wolves close in on the Avatar from this far off, and a wolf's packmates within this
    /// distance of it join any fight it is in.
    static let wolfScent = 8

    /// Chance that an NPC whose friendliness a conversation has just lowered below 0 attacks.
    static func provokedChance(_ friendliness: Int) -> Double {
        friendliness >= 0 ? 0 : Double(min(100, -friendliness)) / 100
    }
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
        if enemy.servesDraconian {
            log("\(enemy.shortName.capitalizedFirst) cries: \"\(Combat.draconianBattleCry)\"")
        }
        combat = c
        if enemy.race == .wolf { joinPack(of: enemy, to: c) }
        if startedByEnemy { callTheWatch() }
        // Draconian's people stand together: his servants close by join in.
        if enemy.servesDraconian {
            for ally in world.npcs(near: enemy.x, enemy.y, z, radius: 6)
            where ally !== enemy && ally.servesDraconian && ally.friendliness < 0 && !ally.following && ally.hp > 0 {
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
        // A servant drawn into a fight that started with someone else announces himself too,
        // unless he's only one of a band answering their leader's cry.
        if enemy.servesDraconian && !c.enemies.contains(where: \.servesDraconian) {
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
        where !n.following && n.hp > 0 && n.friendliness < 0 && !n.keepsThePeace
            && !c.enemies.contains(where: { $0 === n }) && !c.allies.contains(where: { $0 === n }) {
            if roll() < Combat.ambushChance(n.friendliness) { join(n, to: c, attackedByAvatar: false) }
        }
    }

    /// While the Avatar fights Lord Draconian's people, the town watch within
    /// `Combat.watchAidDistance` of them comes to their aid, striking only at his people.
    /// (Their kills earn the party no experience.)
    func callTheWatch() {
        guard let c = combat, !gameOver, c.enemies.contains(where: { $0.servesDraconian && $0.hp > 0 }) else { return }
        let watch = world.npcs(near: x, y, z, radius: Combat.watchAidDistance).filter { n in
            n.guardRank != nil && n.hp > 0 && !n.following && !n.servesDraconian
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
        for n in world.npcs(near: x, y, z, radius: 1) where !n.following && n.hp > 0 && n.friendliness < 0 && !n.keepsThePeace {
            if roll() < Combat.ambushChance(n.friendliness) {
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
        let isEnemy = c.enemies.contains { $0 === n }
        // Foes: nil is the Avatar.
        var foes: [NPC?] = []
        if isEnemy {
            foes.append(nil)
            foes += world.party.filter { $0.hp > 0 && $0.z == z }
            foes += c.allies.filter { $0.hp > 0 && $0.z == z }
        } else if c.allies.contains(where: { $0 === n }) {
            // The watch strikes only at Draconian's people.
            foes += c.enemies.filter { $0.hp > 0 && $0.z == z && $0.servesDraconian }
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
            if target.hp == 0 { kill(target, byAvatar: attacker == nil, byParty: attacker == nil || attacker?.following == true) }
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
        if let c = combat {
            c.enemies.removeAll { $0 === n }
            c.allies.removeAll { $0 === n }
            if let i = c.order.firstIndex(where: { $0 === n }) {
                c.order.remove(at: i)
                if i < c.current { c.current -= 1 }
                if c.current >= c.order.count { c.current = 0 }
            }
        }
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
