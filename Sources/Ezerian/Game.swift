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
    /// Whether the Avatar is a woman, and which of the five looks of a man or a woman
    /// they have, chosen after the name.
    private(set) var female = false
    private(set) var avatarLook = 0
    /// The ten looks to choose from: the five men, then the five women.
    static let lookChoices = 2 * AvatarArt.perSex
    /// While a new game asks how the Avatar looks: which of the ten is highlighted
    /// (0-4 the men, 5-9 the women). Nil once chosen.
    var lookEntry: Int?
    /// Still choosing a name or a look.
    var creatingCharacter: Bool { nameEntry != nil || lookEntry != nil }
    var avatar: AvatarArt.Look { AvatarArt.look(female: female, avatarLook) }

    /// The talk in progress, if any.
    var conversation: Conversation?
    /// The fight in progress, if any.
    var combat: Combat?
    /// The Avatar's health; at 0 the adventure is over.
    var hp = 100
    var maxHP = 100 { didSet { world.avatarHealth = maxHP } }
    /// Experience from foes defeated (never shown; see `Experience`).
    var experience = 0
    /// The beers drunk on day `beerDay`: past `Trade.healingBeers` they hurt instead of healing.
    var beerDay = 0, beersToday = 0
    /// Gold coins; the adventure begins with none.
    var gold = 0
    /// The weapon in the Avatar's hand, and everything else they carry (see `Inventory`);
    /// the adventure begins with neither.
    var weapon: Weapon?
    var pack: [Item] = []
    /// The character sheet on show, if any: 0 the Avatar's, then each companion's.
    var sheet: Int?
    /// On the sheet, the line of belongings waiting for someone to give it to.
    var sheetGiving: Int?
    /// The wares of the trader being talked to are open (see `Shop`), with what last happened.
    var shopping = false
    var shopNotice: String?
    var gameOver = false
    /// The day of the last 8 AM autosave (0: none yet), the morning a slain Avatar can rise again from.
    var autosavedDay = 0
    /// It is past 8 in the morning of a day not yet autosaved. A fight in progress puts it off until it ends,
    /// so the Avatar never wakes into the middle of one.
    var autosaveDue: Bool {
        !creatingCharacter && !gameOver && !inCombat && hp > 0 && day > autosavedDay && hourOfDay >= 8
    }
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
    /// The last day newcomers were welcomed (not saved: counting starts afresh each session).
    var newcomersDay: Int?

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

    /// Accepts the name typed at the start of a new game, then asks how the Avatar looks.
    func confirmName() {
        let typed = (nameEntry ?? "").trimmingCharacters(in: .whitespaces)
        playerName = typed.isEmpty ? "Avatar" : typed
        nameEntry = nil
        lookEntry = (female ? AvatarArt.perSex : 0) + avatarLook
    }

    /// Accepts one of the ten looks (0-4 the men, 5-9 the women; by default the one
    /// highlighted) and sets the scene.
    func confirmLook(_ choice: Int? = nil) {
        let c = max(0, min(Game.lookChoices - 1, choice ?? lookEntry ?? 0))
        female = c >= AvatarArt.perSex
        avatarLook = c % AvatarArt.perSex
        lookEntry = nil
        log("Welcome to the Land of Ezerian, \(playerName)!")
        log("Dark news travels the roads: Lord Draconian, Wizard Lord and Emperor of Sespooland, means to conquer Ezerian. Beware his black-and-red mercenaries and the orc warbands that roam the wilds.")
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
    init(world: World, name: String, female: Bool, look: Int, x: Int, y: Int, z: Int, facing: Direction, turn: Int) {
        self.world = world
        playerName = name
        self.female = female
        avatarLook = max(0, min(AvatarArt.perSex - 1, look))
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
        guard dx != 0 || dy != 0, conversation == nil, sheet == nil, !gameOver else { return false }
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
        if let npc = world.npc(at: nx, ny, z), !npc.following, inDoorway(nx, ny) {
            // Someone standing in a doorway steps out of the way (or, with nowhere else to go,
            // trades places), so no one can shut the Avatar in or out.
            var taken = Set(world.npcs(near: nx, ny, z, radius: 2).map { Point(x: $0.x, y: $0.y) })
            taken.insert(Point(x: x, y: y))
            if !stepAside(npc, taken: taken) { swapped = npc }
            log("\(npc.shortName.capitalizedFirst) steps out of your way.")
        } else if let npc = world.npc(at: nx, ny, z) {
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
        guard conversation == nil, sheet == nil, !gameOver else { return }
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
        welcomeNewcomers()
        let near = world.npcs(near: x, y, z, radius: 18).filter { !$0.following }
        var occupied = Set(near.map { Point(x: $0.x, y: $0.y) })
        occupied.insert(Point(x: x, y: y))
        for n in near {
            n.prevX = n.x
            n.prevY = n.y
            let dx = x - n.x, dy = y - n.y, dist = max(abs(dx), abs(dy))
            let roll = Hash.unit(world.seed, n.id, turn, 31)
            // No one lingers in a doorway: they step clear at once.
            if inDoorway(n.x, n.y) {
                occupied.remove(Point(x: n.x, y: n.y))
                _ = stepAside(n, taken: occupied)
                occupied.insert(Point(x: n.x, y: n.y))
                continue
            }
            var want: (Int, Int)?
            switch n.disposition {
            case _ where turn < n.cowedUntil && dist <= Combat.escapeDistance + 2:
                // Having fled a fight with the Avatar, they keep their distance for a while.
                want = (-dx.signum(), -dy.signum())
            case _ where n.openlyDraconian && n.friendliness < 0 && dist <= (n.warband == nil ? 6 : 10) && dist > 1 && roll < 0.6:
                // Draconian's people hunt the Avatar; a warband from further off.
                want = toward(dx, dy)
            case _ where n.race == .wolf && dist <= Combat.wolfScent && dist > 1 && roll < 0.6:
                // Wolves pick up the Avatar's scent and close in.
                want = toward(dx, dy)
            case .hostile where dist <= 7 && dist > 1 && roll < 0.55: want = toward(dx, dy)
            case .adoring where dist <= 4 && dist > 1 && roll < 0.35: want = toward(dx, dy)
            default:
                if let band = n.warband, roll < 0.6 {
                    // A warband roams together, changing course every dozen turns.
                    let d = Direction(rawValue: Int(Hash.of(world.seed, band, turn / 12, 33) % 4))!
                    want = (d.dx, d.dy)
                } else if roll < 0.3 {
                    let d = Direction(rawValue: Int(Hash.of(world.seed, n.id, turn, 32) % 4))!
                    want = (d.dx, d.dy)
                }
            }
            if let (sx, sy) = want {
                let tx = n.x + sx, ty = n.y + sy
                let f = world.feature(tx, ty, z)
                if n.mayStand(tx, ty), world.isPassable(tx, ty, z), !occupied.contains(Point(x: tx, y: ty)),
                   f != .door, f != .caveEntrance, f != .ladderUp, !inDoorway(tx, ty) {
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
                case .wolf: taunt = "bares its fangs and growls."
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

    /// Whether a tile stands right before a door (inside or out), where someone standing
    /// would block the way.
    func inDoorway(_ px: Int, _ py: Int) -> Bool {
        [(0, 1), (1, 0), (-1, 0), (0, -1)].contains { world.feature(px + $0.0, py + $0.1, z) == .door }
    }

    /// Moves someone off a doorway to a free tile nearby that blocks no door: one within
    /// the bounds they keep to if possible, else any. Returns false if there's nowhere to go.
    @discardableResult
    func stepAside(_ n: NPC, taken: Set<Point>) -> Bool {
        func inside(_ q: Point) -> String { world.building(at: q.x, q.y, z).map { "\($0.x),\($0.y)" } ?? "" }
        var options: [Point] = []
        for r in 1...3 {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let p = Point(x: n.x + dx, y: n.y + dy)
                    let f = world.feature(p.x, p.y, z)
                    guard world.isPassable(p.x, p.y, z), !taken.contains(p), world.npc(at: p.x, p.y, z) == nil,
                          p != Point(x: x, y: y), f != .door, f != .caveEntrance, f != .ladderUp, !inDoorway(p.x, p.y),
                          // On the same side of the door: no slipping through walls into or out of a building.
                          inside(p) == inside(Point(x: n.x, y: n.y))
                    else { continue }
                    options.append(p)
                }
            }
            if !options.isEmpty { break }
        }
        guard let p = options.first(where: { n.mayStand($0.x, $0.y) }) ?? options.first else { return false }
        n.prevX = n.x
        n.prevY = n.y
        n.facing = Direction.from(dx: (p.x - n.x).signum(), dy: (p.y - n.y).signum()).rawValue
        n.x = p.x
        n.y = p.y
        return true
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
                           step: moving ? 1 + (n.id + turn) % 2 : 0, weapon: n.weapon)
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

    /// Talks with a companion wherever they walk in the party's train: a click on them on the
    /// map, or Talk on their character sheet. A fight leaves no time for it.
    func talkToCompanion(_ npc: NPC) {
        guard npc.following, conversation == nil, !creatingCharacter, !gameOver else { return }
        guard !inCombat else { log("There is no time to talk in the middle of a fight."); return }
        sheet = nil
        sheetGiving = nil
        showHelp = false
        showMap = false
        startConversation(with: npc)
    }

    func startConversation(with npc: NPC) {
        // Beasts can't be talked to.
        if npc.race.isBeast {
            npc.facing = Direction.from(dx: x - npc.x, dy: y - npc.y).rawValue
            log("\(npc.shortName.capitalizedFirst) only growls at you.")
            return
        }
        npc.facing = Direction.from(dx: x - npc.x, dy: y - npc.y).rawValue
        npc.prevX = npc.x
        npc.prevY = npc.y
        let g = Dialogue.greeting(npc, player: playerName)
        var c = Conversation(npc: npc)
        c.lines.append(Conversation.Line(text: g.text, fromAvatar: false))
        c.over = g.refuses
        c.byClaude = claude.isAvailable
        // A healer asks straight away whether the Avatar needs healing, and an innkeeper whether
        // they want a room (unless they won't serve them).
        if !c.over, sellsRest(npc), Trade.willTrade(npc) {
            c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, .ask, player: playerName), fromAvatar: false))
            c.healingAsked = true
            // A barkeep's offer names the price, and the gold for it is ready to hand over.
            if npc.role == "barkeep" { c.price = Trade.beerPrice(npc); c.goldInput = "\(c.price!)" }
        }
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
        if healerAnswer(&c, said) {
            conversation = c
            return
        }
        if Trade.trades(c.npc), Dialogue.asksToTrade(said) {
            conversation = c
            openShop()
            return
        }
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
                // Only two kind words a day win anyone over, whatever Claude calls them (a
                // compliment, a friendly word, pleasant small talk); insults always tell.
                let flattery = r.friendliness_change > 0
                if flattery && !npc.flatterable(on: self.day) {
                    // Unmoved: flattered enough today.
                } else {
                    npc.changeFriendliness(by: r.friendliness_change)
                    if flattery { npc.flattered(on: self.day) }
                }
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
        // A hidden agent of Draconian asked about him, or about spies, mostly denies it, but sometimes lets it slip.
        case _ where npc.agent && !npc.unmasked && topic != .join && topic != .dismiss && Dialogue.probes(said):
            reply = (Dialogue.agentAnswer(npc, player: playerName), false)
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
            case .lockedOut, .full, .already, .notAdventurer: break
            }
        } else if intent == "dismiss", npc.following {
            removeFromParty(npc, lockOut: false)
            c.over = true
        } else if npc.following, npc.friendliness < before, roll() < Party.leaveChance(npc.friendliness) {
            say(Dialogue.leaving(npc))
            removeFromParty(npc, lockOut: true)
            c.over = true
        } else if !c.over, !c.offerRolled, !npc.following, npc.isAdventurer, world.party.count < Party.maxSize, !Party.lockedOut(npc) {
            c.offerRolled = true
            if roll() < Party.chance(npc.friendliness) {
                say(Dialogue.offer(npc, player: playerName))
                c.offer = true
            }
        }
        conversation = c
        // Words that sour someone below -50 may come to blows.
        if intent != "ask_to_join", !npc.following, npc.friendliness < before,
           roll() < Combat.attackChance(npc.friendliness) {
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

    // MARK: Healing

    /// Healers sell a night's rest that heals completely; innkeepers a room for the night;
    /// barkeeps a beer.
    func sellsRest(_ npc: NPC) -> Bool { npc.role == "healer" || npc.role == "innkeeper" || npc.role == "barkeep" }

    /// Answers talk of healing in a house of healing, or of a room at an inn: yes or no to
    /// the question asked, or asking for the service or its price. Returns false when the
    /// words are about something else.
    private func healerAnswer(_ c: inout Conversation, _ said: String) -> Bool {
        let npc = c.npc
        guard sellsRest(npc) else { return false }
        // Asking someone to join (or leave) the party is about that, "please" or not.
        if let t = Dialogue.topic(for: said), t == .join || t == .dismiss { return false }
        let asks = npc.role == "innkeeper" ? Dialogue.asksForLodging(said)
            : npc.role == "barkeep" ? Dialogue.asksForBeer(said) : Dialogue.asksForHealing(said)
        let no = c.healingAsked && Dialogue.isNo(said)
        guard no || (c.healingAsked && Dialogue.isYes(said)) || asks else { return false }
        c.healingAsked = false
        if no {
            c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, .declined, player: playerName), fromAvatar: false))
            // Turned down, a barkeep's gold field takes tips.
            if npc.role == "barkeep" { c.price = nil; c.goldInput = ""; c.goldFocus = false }
        } else {
            quoteHealing(&c)
        }
        return true
    }

    /// The healer or innkeeper names the price, and the Avatar may offer gold; or refuses them outright.
    private func quoteHealing(_ c: inout Conversation, after offered: Int? = nil) {
        let npc = c.npc
        guard Trade.willTrade(npc) else {
            c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, .refuse, player: playerName), fromAvatar: false))
            c.price = nil
            c.goldFocus = false
            return
        }
        let inn = npc.role == "innkeeper", bar = npc.role == "barkeep"
        let k = inn ? party.count : bar ? 0 : woundedCompanions.count
        let p = bar ? Trade.beerPrice(npc) : inn ? Trade.lodgingPrice(npc, companions: k) : Trade.healingPrice(npc, companions: k)
        let line: Dialogue.Healing = offered.map { .tooLittle(offered: $0, price: p) } ?? .quote(p, companions: k)
        c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, line, player: playerName), fromAvatar: false))
        c.price = p
        c.goldInput = "\(p)"
        c.goldFocus = true
    }

    func typeGold(_ ch: Character) {
        guard var c = conversation, takesGold(c), ch.isASCII, ch.isNumber,
              c.goldInput.count < Conversation.maxGoldDigits else { return }
        if c.goldInput == "0" { c.goldInput = "" }
        c.goldInput.append(ch)
        conversation = c
    }

    func backspaceGold() {
        guard var c = conversation, !c.goldInput.isEmpty else { return }
        c.goldInput.removeLast()
        conversation = c
    }

    /// Whether typing goes to the gold offered (true) or the words said.
    func focusGold(_ on: Bool) {
        guard var c = conversation else { return }
        c.goldFocus = on && takesGold(c)
        conversation = c
    }

    /// The Avatar hands over the gold in the field. The healer or innkeeper may take it (see
    /// `Trade`); if they do, the Avatar rests the night, and wakes whole at a healer's or 50
    /// points better at an inn.
    func offerGold() {
        guard var c = conversation, !c.over, !c.pending, let amount = Int(c.goldInput), amount > 0 else { return }
        let npc = c.npc
        if npc.role == "barkeep" { return pourBeer(amount) }
        guard let price = c.price else { return hire(amount) }
        guard amount <= gold else {
            c.notice = gold == 0 ? "You have no gold." : "You have only \(gold) gold."
            conversation = c
            return
        }
        c.notice = nil
        c.lines.append(Conversation.Line(text: Dialogue.giving(amount), fromAvatar: true))
        let deal = Trade.settle(offered: amount, price: price)
        npc.changeFriendliness(by: deal.friendliness)
        guard roll() < deal.acceptChance else {
            quoteHealing(&c, after: amount)
            conversation = c
            return
        }
        gold -= amount
        c.price = nil
        c.goldInput = ""
        c.goldFocus = false
        c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, .accepted, player: playerName), fromAvatar: false))
        if npc.role == "innkeeper" {
            let before = hp
            restTheNight(healing: Trade.lodgingHeal)
            c.lines.append(Conversation.Line(text: Dialogue.innkeeper(npc, .morning(companions: party.count), player: playerName), fromAvatar: false))
            conversation = c
            let feel = hp == maxHP ? "You wake whole again." : hp > before ? "You wake much refreshed (+\(hp - before) health)." : "You wake refreshed."
            log("You pay \(amount) gold and sleep the night at \(npc.home ?? "the inn"). \(feel) You have \(gold) gold left.")
            return
        }
        let healed = woundedCompanions
        restTheNight()
        c.lines.append(Conversation.Line(text: Dialogue.healer(npc, .morning(companions: healed.count), player: playerName), fromAvatar: false))
        conversation = c
        let who = healed.isEmpty ? "You wake" : healed.count == 1 ? "You and \(healed[0].shortName) wake" : "You and your companions wake"
        log("You pay \(amount) gold and rest the night at \(npc.home ?? "the healer's"). \(who) whole again. You have \(gold) gold left.")
    }

    /// The Avatar hands a barkeep gold: for a beer, if one is on offer (drunk at once, for
    /// 5 health), with anything over the price a tip; otherwise all of it a tip. Any tip
    /// pleases them by 5. Short of the price, they haggle like any merchant (`Trade.settle`).
    private func pourBeer(_ amount: Int) {
        guard var c = conversation, Trade.willTrade(c.npc) else { return }
        let npc = c.npc
        guard amount <= gold else {
            c.notice = gold == 0 ? "You have no gold." : "You have only \(gold) gold."
            conversation = c
            return
        }
        c.notice = nil
        c.lines.append(Conversation.Line(text: Dialogue.giving(amount), fromAvatar: true))
        guard let price = c.price else {
            gold -= amount
            npc.gold += amount
            npc.changeFriendliness(by: Trade.tipFriendliness)
            c.goldInput = ""
            c.lines.append(Conversation.Line(text: Dialogue.barkeepThanks(npc, player: playerName), fromAvatar: false))
            conversation = c
            log("You tip \(npc.shortName) \(amount) gold. You have \(gold) gold left.")
            return
        }
        let tip = amount - price
        if tip > 0 {
            npc.changeFriendliness(by: Trade.tipFriendliness)
        } else {
            let deal = Trade.settle(offered: amount, price: price)
            npc.changeFriendliness(by: deal.friendliness)
            guard roll() < deal.acceptChance else {
                quoteHealing(&c, after: amount)
                conversation = c
                return
            }
        }
        gold -= amount
        npc.gold += amount
        let before = hp
        if beerDay != day { beerDay = day; beersToday = 0 }
        beersToday += 1
        let drunk = beersToday > Trade.healingBeers
        // Drink can't quite kill: a drunk Avatar is left with at least 1 health.
        hp = drunk ? max(min(hp, 1), hp - Trade.drunkHurt) : min(maxHP, hp + Trade.beerHeal)
        c.lines.append(Conversation.Line(text: Dialogue.restSeller(npc, .accepted, player: playerName), fromAvatar: false))
        if tip > 0 { c.lines.append(Conversation.Line(text: Dialogue.barkeepThanks(npc, player: playerName), fromAvatar: false)) }
        // Another round is on offer, at what they'd ask now.
        c.price = Trade.beerPrice(npc)
        c.goldInput = "\(c.price!)"
        conversation = c
        let feel = hp > before ? " (+\(hp - before) health)" : hp < before ? " (\(hp - before) health)" : ""
        log("You pay \(amount) gold\(tip > 0 ? ", tip included," : "") and drink a beer at \(npc.home ?? "the tavern")\(feel). You have \(gold) gold left.")
        log(drunk ? "You've had too much, you're drunk!" : "Ahhh, that went down well!")
    }

    /// How many nights the Avatar has slept (the view fades out and in for each).
    private(set) var nights = 0

    /// Companions who would be healed with the Avatar (each costs the healer's fee more).
    var woundedCompanions: [NPC] { party.filter { $0.hp < $0.maxHP } }

    /// Sleeps until 8 in the morning; the Avatar and the companions wake fully healed, or
    /// healed by `healing` points at most.
    private func restTheNight(healing: Int? = nil) {
        func mended(_ hp: Int, _ maxHP: Int) -> Int { healing.map { min(maxHP, hp + $0) } ?? maxHP }
        for n in party { n.hp = mended(n.hp, n.maxHP) }
        let m = minutes
        var wake = m / (24 * 60) * (24 * 60) + 8 * 60
        if wake <= m { wake += 24 * 60 }
        turn = (wake - 8 * 60) / 2
        hp = mended(hp, maxHP)
        nights += 1
    }

    private func remember(_ npc: NPC, avatar: String, npcSaid: String) {
        var m = npc.memory ?? []
        m.append("\(playerName) said: \"\(avatar)\" and you answered: \"\(npcSaid)\"")
        npc.memory = Array(m.suffix(6))
    }

    func endConversation() {
        guard let c = conversation else { return }
        conversation = nil
        shopping = false
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
