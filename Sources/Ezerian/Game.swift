import Foundation

/// Game state and the rules for walking around. No combat, NPCs or object handling
/// yet: the Avatar explores, reads signs and looks at things.
final class Game {
    let world: World
    private(set) var x: Int
    private(set) var y: Int
    private(set) var z: Int = 0
    var facing: Direction = .south
    private(set) var step = 0
    var turn = 0
    private(set) var messages: [String] = []
    /// Bumped whenever the Avatar changes place without walking (stairs, teleports),
    /// so the view knows to jump rather than glide.
    private(set) var jumps = 0

    /// The Avatar's name, chosen when a new game begins.
    private(set) var playerName = "Avatar"
    /// The name being typed while a new game asks for one; nil once it is chosen.
    var nameEntry: String?
    static let maxNameLength = 12

    /// The talk in progress, if any.
    var conversation: Conversation?
    /// The fight in progress, if any.
    var combat: Combat?
    /// The Avatar's health; at 0 the adventure is over.
    var hp = 100
    var maxHP = 100
    var gameOver = false
    /// F was pressed: the next direction key attacks.
    var attackPending = false
    /// Called when something changes outside a key press (Claude's answer arriving).
    var onChange: (() -> Void)?
    /// Who voices the NPCs (replaced in tests).
    var claude = ClaudeClient.shared
    /// The dice for joining and leaving (replaced in tests).
    var roll: () -> Double = { Double.random(in: 0..<1) }
    /// Where the Avatar has just been, for companions to follow in single file.
    var trail: [Point] = []

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
        guard dx != 0 || dy != 0, conversation == nil, !gameOver else { return false }
        facing = dx != 0 && dy != 0 ? (dy < 0 ? .north : .south) : Direction.from(dx: dx, dy: dy)
        let nx = x + dx, ny = y + dy
        // In a fight, walking into an enemy strikes them; bystanders are in the way.
        if let c = combat, let npc = world.npc(at: nx, ny, z), !npc.following {
            if c.enemies.contains(where: { $0 === npc }) {
                strike(nil, npc)
                endAvatarTurn()
            } else {
                log("\(npc.shortName.capitalizedFirst) is in the way.")
            }
            return false
        }
        var swapped: NPC?
        if let npc = world.npc(at: nx, ny, z) {
            // Companions step aside (swap places); anyone else stops you for a word.
            guard npc.following, world.isPassable(nx, ny, z) else {
                startConversation(with: npc)
                return false
            }
            swapped = npc
        }
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
            regroupParty()
            updateNPCs()
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
            regroupParty()
            updateNPCs()
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
        let old = Point(x: x, y: y)
        if let s = swapped {
            s.prevX = s.x; s.prevY = s.y
            s.x = old.x; s.y = old.y
        }
        x = nx
        y = ny
        step += 1
        turn += 1
        if combat != nil {
            // In a fight companions take their own turns rather than following.
            arrive()
            endAvatarTurn()
            return true
        }
        arrive()
        if swapped == nil { updateFollowers(from: old) } else { trail.insert(old, at: 0) }
        updateNPCs()
        recover()
        checkAmbush()
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

    /// Lets a turn pass without moving.
    func waitTurn() {
        guard conversation == nil, !gameOver else { return }
        if combat != nil { endAvatarTurn(); return }
        turn += 1
        updateNPCs()
        recover()
        checkAmbush()
    }

    // MARK: People

    /// Each turn the people nearby go about their business: most wander a little,
    /// the hostile close in on the Avatar, the adoring come over to say hello.
    private func updateNPCs() {
        let near = world.npcs(near: x, y, z, radius: 18).filter { !$0.following }
        var occupied = Set(near.map { Point(x: $0.x, y: $0.y) })
        occupied.insert(Point(x: x, y: y))
        for n in near {
            n.prevX = n.x
            n.prevY = n.y
            let dx = x - n.x, dy = y - n.y, dist = max(abs(dx), abs(dy))
            let roll = Hash.unit(world.seed, n.id, turn, 31)
            var want: (Int, Int)?
            switch n.disposition {
            case .hostile where dist <= 7 && dist > 1 && roll < 0.55: want = toward(dx, dy)
            case .adoring where dist <= 4 && dist > 1 && roll < 0.35: want = toward(dx, dy)
            default:
                if roll < 0.3 {
                    let d = Direction(rawValue: Int(Hash.of(world.seed, n.id, turn, 32) % 4))!
                    want = (d.dx, d.dy)
                }
            }
            if let (sx, sy) = want {
                let tx = n.x + sx, ty = n.y + sy
                let f = world.feature(tx, ty, z)
                if n.mayStand(tx, ty), world.isPassable(tx, ty, z), !occupied.contains(Point(x: tx, y: ty)),
                   f != .door, f != .caveEntrance, f != .ladderUp {
                    occupied.remove(Point(x: n.x, y: n.y))
                    n.x = tx
                    n.y = ty
                    occupied.insert(Point(x: tx, y: ty))
                }
                n.facing = Direction.from(dx: sx, dy: sy).rawValue
            }
            let after = max(abs(x - n.x), abs(y - n.y))
            guard after <= 2, conversation == nil, turn - n.lastShout > 12 else { continue }
            switch n.disposition {
            case .hostile:
                n.lastShout = turn
                let taunt: String
                switch n.race {
                case .orc: taunt = "snarls: \"Pinkskin smell like dinner!\""
                case .dwarf: taunt = "growls: \"Off with ye, before I lose my temper!\""
                case .elf: taunt = "hisses: \"Leave this place, mortal.\""
                case .human: taunt = "shouts: \"Get away from me!\""
                }
                log("\(n.shortName.capitalizedFirst) \(taunt)")
            case .adoring:
                n.lastShout = turn
                log("\(n.shortName.capitalizedFirst) waves at you happily.")
            default:
                break
            }
        }
    }

    private func toward(_ dx: Int, _ dy: Int) -> (Int, Int) {
        abs(dx) >= abs(dy) ? (dx.signum(), 0) : (0, dy.signum())
    }

    /// Where to draw the people in view, `t` of the way through this turn's steps.
    func npcPoses(t: Double) -> [NPCPose] {
        let e = t * t * (3 - 2 * t)
        return world.npcs(near: x, y, z, radius: 16).map { n in
            let moving = (n.prevX != n.x || n.prevY != n.y) && t < 0.75
            return NPCPose(x: Double(n.prevX) + Double(n.x - n.prevX) * e, y: Double(n.prevY) + Double(n.y - n.prevY) * e,
                           race: n.race, look: n.look, facing: Direction(rawValue: n.facing) ?? .south,
                           step: moving ? 1 + (n.id + turn) % 2 : 0)
        }
    }

    /// Talks to someone beside the Avatar (the one ahead first).
    func talk() {
        guard conversation == nil else { return }
        if let n = world.npc(at: x + facing.dx, y + facing.dy, z) { startConversation(with: n); return }
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                if let n = world.npc(at: x + dx, y + dy, z) { startConversation(with: n); return }
            }
        }
        log("There is no one beside you to talk to.")
    }

    func startConversation(with npc: NPC) {
        npc.facing = Direction.from(dx: x - npc.x, dy: y - npc.y).rawValue
        npc.prevX = npc.x
        npc.prevY = npc.y
        let g = Dialogue.greeting(npc, player: playerName)
        var c = Conversation(npc: npc)
        c.lines.append(Conversation.Line(text: g.text, fromAvatar: false))
        c.over = g.refuses
        c.byClaude = claude.isAvailable
        conversation = c
        log(g.refuses ? g.text : "You speak with \(npc.shortName).")
    }

    /// The Avatar raises a topic; the NPC answers as their mood dictates.
    func say(_ t: Topic) {
        guard var c = conversation, !c.over else { return }
        c.lines.append(Conversation.Line(text: Dialogue.ask(t), fromAvatar: true))
        let r = Dialogue.reply(c.npc, t, game: self)
        c.lines.append(Conversation.Line(text: r.text, fromAvatar: false))
        if r.ends { c.over = true }
        conversation = c
    }

    // MARK: Free-text conversation

    func typeInConversation(_ ch: Character) {
        guard var c = conversation, !c.over, c.input.count < Conversation.maxInput else { return }
        guard ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " || ch.isSymbol else { return }
        if c.input.isEmpty && ch == " " { return }
        c.input.append(ch)
        conversation = c
    }

    func backspaceInConversation() {
        guard var c = conversation, !c.input.isEmpty else { return }
        c.input.removeLast()
        conversation = c
    }

    /// Says what the Avatar typed. Claude answers (in a moment) if it can; otherwise
    /// the line is matched to a scripted topic.
    func submitConversation() {
        guard var c = conversation, !c.over, !c.pending else { return }
        let said = c.input.trimmingCharacters(in: .whitespaces)
        guard !said.isEmpty else { return }
        let history = c.lines
        c.input = ""
        c.lines.append(Conversation.Line(text: said, fromAvatar: true))
        let npc = c.npc
        guard claude.isAvailable else {
            c.byClaude = false
            conversation = c
            scriptedAnswer(said)
            return
        }
        c.pending = true
        c.byClaude = true
        conversation = c
        let decision = joinDecision(npc)
        let before = npc.friendliness
        AIDialogue.ask(npc, game: self, history: history, said: said, joinRule: joinRule(decision), client: claude) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(r):
                npc.changeFriendliness(by: r.friendliness_change)
                if r.reveals_name { npc.known = true }
                self.remember(npc, avatar: said, npcSaid: r.reply)
                if var cc = self.conversation, cc.npc === npc {
                    cc.pending = false
                    cc.notice = nil
                    cc.lines.append(Conversation.Line(text: r.reply, fromAvatar: false))
                    if r.ends_conversation { cc.over = true }
                    self.conversation = cc
                    self.afterReply(npc, intent: r.intent, decision: decision, before: before, scripted: false)
                }
            case let .failure(e):
                if var cc = self.conversation, cc.npc === npc {
                    cc.pending = false
                    cc.byClaude = false
                    cc.notice = "Claude could not answer (\(e)); the reply is scripted."
                    self.conversation = cc
                    self.scriptedAnswer(said)
                }
            }
            self.onChange?()
        }
    }

    private func scriptedAnswer(_ said: String) {
        guard var c = conversation else { return }
        let npc = c.npc
        let before = npc.friendliness
        let topic = Dialogue.topic(for: said)
        let decision = joinDecision(npc)
        let reply: (text: String, ends: Bool)
        switch topic {
        case .join?: reply = (Dialogue.joinAnswer(npc, decision, player: playerName), false)
        case .dismiss?: reply = (npc.following ? Dialogue.dismissed(npc) : "Dismiss me? I'm not travelling with you.", false)
        case let t?: reply = Dialogue.reply(npc, t, game: self)
        case nil: reply = (Dialogue.smallTalk(npc), false)
        }
        c.lines.append(Conversation.Line(text: reply.text, fromAvatar: false))
        if reply.ends { c.over = true }
        conversation = c
        remember(npc, avatar: said, npcSaid: reply.text)
        let intent = topic == .join ? "ask_to_join" : topic == .dismiss ? "dismiss" : "other"
        afterReply(npc, intent: intent, decision: decision, before: before, scripted: true)
    }

    /// Joining and leaving, once the NPC has answered: a request to join is settled by
    /// the dice rolled beforehand; a companion who now likes the Avatar less may leave;
    /// and anyone who likes the Avatar may, once per talk, ask to come along.
    private func afterReply(_ npc: NPC, intent: String, decision: Party.Decision, before: Int, scripted: Bool) {
        guard var c = conversation, c.npc === npc else { return }
        func say(_ text: String) { c.lines.append(Conversation.Line(text: text, fromAvatar: false)) }
        if intent == "ask_to_join" {
            c.offerRolled = true
            switch decision {
            case .accept: addToParty(npc)
            case .refuse: npc.refusedAt = npc.friendliness
            case .lockedOut, .full, .already: break
            }
        } else if intent == "dismiss", npc.following {
            removeFromParty(npc, lockOut: false)
            c.over = true
        } else if npc.following, npc.friendliness < before, roll() < Party.leaveChance(npc.friendliness) {
            say(Dialogue.leaving(npc))
            removeFromParty(npc, lockOut: true)
            c.over = true
        } else if !c.over, !c.offerRolled, !npc.following, world.party.count < Party.maxSize, !Party.lockedOut(npc) {
            c.offerRolled = true
            if roll() < Party.chance(npc.friendliness) {
                say(Dialogue.offer(npc, player: playerName))
                c.offer = true
            }
        }
        conversation = c
        // Words that sour someone below 0 may come to blows.
        if intent != "ask_to_join", !npc.following, npc.friendliness < before, npc.friendliness < 0,
           roll() < Combat.provokedChance(npc.friendliness) {
            conversation = nil
            startCombat(against: npc, startedByEnemy: true)
        }
    }

    /// The Avatar answers an NPC's offer to join.
    func answerOffer(_ yes: Bool) {
        guard var c = conversation, c.offer else { return }
        c.offer = false
        let npc = c.npc
        c.lines.append(Conversation.Line(text: yes ? "Gladly. Come with me." : "Not now, I'm afraid.", fromAvatar: true))
        conversation = c
        if yes, world.party.count < Party.maxSize {
            addToParty(npc)
            c.lines.append(Conversation.Line(text: Dialogue.welcomed(npc), fromAvatar: false))
        } else {
            npc.changeFriendliness(by: -3)
            c.lines.append(Conversation.Line(text: npc.disposition >= .friendly ? "As you wish. Perhaps another time." : "Hmph. Your loss.",
                                             fromAvatar: false))
        }
        conversation = c
    }

    private func remember(_ npc: NPC, avatar: String, npcSaid: String) {
        var m = npc.memory ?? []
        m.append("\(playerName) said: \"\(avatar)\" and you answered: \"\(npcSaid)\"")
        npc.memory = Array(m.suffix(6))
    }

    func endConversation() {
        guard let c = conversation else { return }
        conversation = nil
        if !c.over || c.lines.count > 1 { log("You take your leave of \(c.npc.shortName).") }
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
        regroupParty()
    }

    /// Turns the Avatar without moving (developer screenshots).
    func face(_ d: Direction) { facing = d }

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
        if let n = world.npc(at: lx, ly, z) {
            let who = n.known ? "\(n.name), \(n.description)" : n.description
            log("You see \(who), \(n.build). \(n.he.capitalizedFirst) \(n.disposition.regard).")
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
