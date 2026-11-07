import Foundation

/// The Avatar's companions: up to three NPCs who travel with the Avatar. Only adventurers
/// will join: asked, or of their own accord, as their friendliness allows, or hired for gold.
enum Party {
    static let maxSize = 3
    /// After a refusal or a parting, friendliness must rise this much before they'll join again.
    static let rejoinMargin = 35

    /// The chance an NPC joins (or offers to join): none at friendliness 0 or below,
    /// rising ever faster to a certainty at 100.
    static func chance(_ friendliness: Int) -> Double {
        friendliness <= 0 ? 0 : pow(Double(min(100, friendliness)) / 100, 2)
    }

    /// The chance a companion leaves after a conversation makes them like the Avatar
    /// less: certain at 0 or below, half the "won't join" chance above it.
    static func leaveChance(_ friendliness: Int) -> Double {
        friendliness <= 0 ? 1 : (1 - chance(friendliness)) / 2
    }

    /// Whether an earlier refusal or parting still holds (friendliness hasn't risen enough).
    static func lockedOut(_ n: NPC) -> Bool {
        guard let r = n.refusedAt else { return false }
        return n.friendliness < min(100, r + rejoinMargin)
    }

    /// The chance an adventurer takes the gold offered to join: 1% a coin, certain at 100.
    static func hireChance(_ gold: Int) -> Double { min(1, Double(max(0, gold)) / 100) }

    /// What happens if the Avatar asks this NPC to join now.
    enum Decision { case accept, refuse, lockedOut, full, already, notAdventurer }
}

extension Game {
    var party: [NPC] { world.party }

    /// Decides, with a roll of the dice, whether the NPC would join if asked now.
    func joinDecision(_ npc: NPC) -> Party.Decision {
        if npc.following { return .already }
        if !npc.isAdventurer { return .notAdventurer }
        if world.party.count >= Party.maxSize { return .full }
        if Party.lockedOut(npc) { return .lockedOut }
        return roll() < Party.chance(npc.friendliness) ? .accept : .refuse
    }

    /// What the NPC is to do if asked to join, for Claude's character sheet.
    func joinRule(_ d: Party.Decision) -> String {
        switch d {
        case .accept: return "If the Avatar asks you to join their party or travel with them, you agree gladly."
        case .refuse: return "If the Avatar asks you to join their party or travel with them, you refuse, in keeping with your mood."
        case .lockedOut: return "You recently refused to travel with the Avatar (or parted ways). If they ask you to join their party, you refuse; you would need to think much better of them first."
        case .full: return "If the Avatar asks you to join their party, you point out that they already travel with three companions and there's no room for you."
        case .already: return "You are travelling with the Avatar as one of their companions. If they dismiss you from the party, accept it and say farewell."
        case .notAdventurer: return "You are no adventurer: your life and work are here. If the Avatar asks you to join their party or travel with them, you decline, in keeping with your mood."
        }
    }

    /// Whether the Avatar can offer this NPC gold to join: an adventurer not yet in the party,
    /// with room for them.
    func canHire(_ npc: NPC) -> Bool { npc.isAdventurer && !npc.following && world.party.count < Party.maxSize }

    /// Whether the conversation shows the gold field: a price has been named, or the
    /// Avatar is talking to an adventurer who might be hired.
    func takesGold(_ c: Conversation) -> Bool {
        !c.over && !c.offer && (c.price != nil || canHire(c.npc) || (c.npc.role == "barkeep" && Trade.willTrade(c.npc)))
    }

    /// The Avatar offers an adventurer gold to join. Each coin is a 1% chance they take it
    /// (and join); once a talk, and only for more than they have turned down before.
    func hire(_ amount: Int) {
        guard var c = conversation, !c.over, !c.pending, canHire(c.npc), amount > 0 else { return }
        let npc = c.npc
        guard amount <= gold else {
            c.notice = gold == 0 ? "You have no gold." : "You have only \(gold) gold."
            conversation = c
            return
        }
        c.notice = nil
        c.goldInput = ""
        c.goldFocus = false
        c.lines.append(Conversation.Line(text: Dialogue.hiring(amount), fromAvatar: true))
        func say(_ h: Dialogue.Hire) { c.lines.append(Conversation.Line(text: Dialogue.hire(npc, h, player: playerName), fromAvatar: false)) }
        if let r = npc.hireRefused, amount <= r {
            say(.tooLittle(r))
        } else if c.hireRolled {
            say(.again)
        } else {
            c.hireRolled = true
            if roll() < Party.hireChance(amount) {
                gold -= amount
                npc.gold += amount
                say(.accept)
                conversation = c
                addToParty(npc)
                log("You pay \(npc.name) \(amount) gold to join you. You have \(gold) gold left.")
                return
            }
            npc.hireRefused = max(npc.hireRefused ?? 0, amount)
            say(.refuse)
        }
        conversation = c
    }

    func addToParty(_ npc: NPC) {
        guard !npc.following, world.party.count < Party.maxSize else { return }
        if let r = world.existingRegion(RegionKey(x: floorDiv(npc.x, Region.size), y: floorDiv(npc.y, Region.size), z: npc.z)) {
            r.npcs.removeAll { $0 === npc }
        }
        npc.following = true
        npc.known = true
        npc.refusedAt = nil
        world.party.append(npc)
        log("\(npc.name) joins your party.")
    }

    /// The companion goes their own way, settling where they stand.
    func removeFromParty(_ npc: NPC, lockOut: Bool) {
        guard npc.following else { return }
        world.party.removeAll { $0 === npc }
        npc.following = false
        if lockOut { npc.refusedAt = npc.friendliness }
        let r = world.region(containing: npc.x, npc.y, npc.z)
        let ox = r.originX, oy = r.originY, n = Region.size
        npc.bounds = [max(ox + 1, npc.x - 8), max(oy + 1, npc.y - 8), min(ox + n - 2, npc.x + 8), min(oy + n - 2, npc.y + 8)]
        r.npcs.append(npc)
        log("\(npc.name) leaves your party.")
    }

    /// After the Avatar steps away from `old`, each companion steps into the place
    /// the one ahead of them has just left, so the party walks in single file.
    func updateFollowers(from old: Point) {
        trail.insert(old, at: 0)
        if trail.count > Party.maxSize + 2 { trail.removeLast(trail.count - Party.maxSize - 2) }
        var taken = Set(world.npcs(near: x, y, z, radius: 6).filter { !$0.following }.map { Point(x: $0.x, y: $0.y) })
        taken.insert(Point(x: x, y: y))
        for (i, n) in world.party.enumerated() {
            n.prevX = n.x
            n.prevY = n.y
            if n.z != z || max(abs(n.x - x), abs(n.y - y)) > 8 {
                regroup(n, taken: &taken)
                continue
            }
            let others = Set(world.party.filter { $0 !== n }.map { Point(x: $0.x, y: $0.y) })
            if i < trail.count {
                let t = trail[i]
                if t != Point(x: n.x, y: n.y), canFollowerStand(t), !taken.contains(t), !others.contains(t) {
                    n.facing = Direction.from(dx: t.x - n.x, dy: t.y - n.y).rawValue
                    n.x = t.x
                    n.y = t.y
                }
            }
            taken.insert(Point(x: n.x, y: n.y))
        }
    }

    /// Puts every companion beside the Avatar at once (after stairs or a teleport).
    func regroupParty() {
        trail.removeAll()
        var taken = Set(world.npcs(near: x, y, z, radius: 6).filter { !$0.following }.map { Point(x: $0.x, y: $0.y) })
        taken.insert(Point(x: x, y: y))
        for n in world.party { regroup(n, taken: &taken) }
    }

    private func regroup(_ n: NPC, taken: inout Set<Point>) {
        for r in 1...4 {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let p = Point(x: x + dx, y: y + dy)
                    guard !taken.contains(p), canFollowerStand(p), world.npc(at: p.x, p.y, z) == nil || world.npc(at: p.x, p.y, z) === n else { continue }
                    n.z = z
                    n.x = p.x
                    n.y = p.y
                    n.prevX = p.x
                    n.prevY = p.y
                    n.facing = Direction.south.rawValue
                    taken.insert(p)
                    return
                }
            }
        }
    }

    private func canFollowerStand(_ p: Point) -> Bool {
        let f = world.feature(p.x, p.y, z)
        return world.isPassable(p.x, p.y, z) && f != .caveEntrance && f != .ladderUp
    }
}
