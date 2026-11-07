import AppKit

/// Developer utilities driven from the command line (screenshots, sprite sheets, tests).
enum DevTools {
    /// Follows a walk script: "E5 N3" steps, "@x,y[,z]" teleports, "find:feature"
    /// jumps next to the nearest such feature, "wait:N" lets N turns pass.
    static func walk(_ game: Game, _ script: String) {
        for token in script.split(separator: " ") {
            if token.hasPrefix("@") {
                let n = token.dropFirst().split(separator: ",").compactMap { Int($0) }
                if n.count >= 2 { game.teleport(n[0], n[1], n.count > 2 ? n[2] : 0) }
                continue
            }
            if token == "talk" { game.talk(); continue }
            if token.hasPrefix("wield:") {
                // Hands the Avatar a weapon: wield:shortSword
                if let w = Weapon.allCases.first(where: { "\($0)" == token.dropFirst(6) }) { if let old = game.weapon { game.pack.append(.weapon(old)) }; game.weapon = w }
                continue
            }
            if token.hasPrefix("type:") {
                for ch in token.dropFirst(5).replacingOccurrences(of: "_", with: " ") { game.typeInConversation(ch) }
                continue
            }
            if token == "send" { game.submitConversation(); continue }
            if token == "trade" { game.openShop(); continue }
            if token == "bye" { game.endConversation(); continue }
            if token == "slain" { game.hp = 0; game.gameOver = true; game.autosavedDay = game.day; continue }
            if token.hasPrefix("hp:") { game.hp = Int(token.dropFirst(3)) ?? game.hp; continue }
            if token.hasPrefix("gold:") { game.gold = Int(token.dropFirst(5)) ?? game.gold; continue }
            if token.hasPrefix("buy:") { game.perform(Game.ShopAction.buy(Int(token.dropFirst(4)) ?? 0)); continue }
            if token == "warband" || token == "mercenary" || token == "guard" {
                // Stand a few paces from the nearest warband orc (or mercenary).
                var best: NPC?
                for ry in -4...4 {
                    for rx in -4...4 {
                        for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs
                        where token == "warband" ? n.warband != nil : token == "guard" ? n.guardRank != nil : n.role == "mercenary" {
                            if best == nil || abs(n.x - game.x) + abs(n.y - game.y) < abs(best!.x - game.x) + abs(best!.y - game.y) { best = n }
                        }
                    }
                }
                if let n = best {
                    for (dx, dy) in [(0, 3), (3, 0), (-3, 0), (0, -3), (0, 2), (2, 0)] where game.world.isPassable(n.x + dx, n.y + dy, 0)
                        && game.world.npc(at: n.x + dx, n.y + dy, 0) == nil {
                        game.teleport(n.x + dx, n.y + dy, 0)
                        break
                    }
                }
                continue
            }
            if token == "fight" { game.attack(dx: game.facing.dx, dy: game.facing.dy); continue }
            if token == "slay" { game.hp = 0; game.gameOver = true; game.combat = nil; game.log("You have been slain!"); continue }
            if token == "recruit" {
                // Brings the nearest NPCs into the party (developer screenshots).
                let folk = game.world.npcs(near: game.x, game.y, game.z, radius: 30).filter { !$0.following }
                    .sorted { abs($0.x - game.x) + abs($0.y - game.y) < abs($1.x - game.x) + abs($1.y - game.y) }
                for n in folk.prefix(Party.maxSize) { game.addToParty(n) }
                game.regroupParty()
                continue
            }
            if token.hasPrefix("say:"), let n = Int(token.dropFirst(4)), let t = Topic(rawValue: n) { game.say(t); continue }
            if token.hasPrefix("npc:") {
                // Stand beside the nearest NPC of a race (or the nearest guard, "guard" or
                // "guard3" for a rank), facing them.
                let what = String(token.dropFirst(4))
                let race = Race(rawValue: what)
                let rank = what.hasPrefix("guard") ? Int(what.dropFirst(5)) : nil
                func wanted(_ n: NPC) -> Bool {
                    if let race { return n.race == race }
                    if ["bard", "peasant", "farmhand", "healer", "innkeeper", "blacksmith", "armourer", "merchant", "pedlar", "apothecary", "alchemist", "adventurer", "barkeep"].contains(what) { return n.role == what }
                    if what == "drinker" { return n.role == what && n.race == .human }
                    if what == "elvenDrinker" { return n.role == "drinker" && n.race == .elf }
                    if what == "townsfolk" { return n.role == "townsperson" && n.race == .human }
                    if what == "draconianOrc" { return n.race == .orc && n.servesDraconian }
                    if what == "draconianHuman" { return n.race == .human && n.servesDraconian }
                    if what == "draconianElf" { return n.race == .elf && n.servesDraconian }
                    if what == "dwarfWarrior" { return n.race == .dwarf && n.role == "warrior" }
                    if what == "child" { return n.race == .human && n.role == "child" }
                    guard what.hasPrefix("guard"), let r = n.guardRank else { return false }
                    return rank == nil || rank == r
                }
                var best: NPC?
                for ry in -2...2 {
                    for rx in -2...2 {
                        for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs where wanted(n) {
                            if best == nil || abs(n.x - game.x) + abs(n.y - game.y) < abs(best!.x - game.x) + abs(best!.y - game.y) { best = n }
                        }
                    }
                }
                if let n = best {
                    for (dx, dy) in [(0, 1), (1, 0), (-1, 0), (0, -1)] where game.world.isPassable(n.x + dx, n.y + dy, 0)
                        && game.world.npc(at: n.x + dx, n.y + dy, 0) == nil {
                        game.teleport(n.x + dx, n.y + dy, 0)
                        game.face(Direction.from(dx: -dx, dy: -dy))
                        break
                    }
                }
                continue
            }
            if token.hasPrefix("wait:") {
                game.wait(turns: Int(token.dropFirst(5)) ?? 0)
                continue
            }
            if token.hasPrefix("find:") {
                let name = token.dropFirst(5)
                let terrainName = name.hasPrefix("t.") ? String(name.dropFirst(2)) : nil
                var best: (Int, Int, Int)?
                for ry in -2...2 {
                    for rx in -2...2 {
                        let r = game.world.region(RegionKey(x: rx, y: ry, z: 0))
                        for i in 0..<(Region.size * Region.size) {
                            let hit: Bool
                            if let tn = terrainName { hit = "\(r.terrain[i])" == tn }
                            else { hit = "\(r.features[i])" == name }
                            guard hit else { continue }
                            let wx = r.originX + i % Region.size, wy = r.originY + i / Region.size
                            let d = abs(wx - game.x) + abs(wy - game.y)
                            if best == nil || d < best!.2 { best = (wx, wy, d) }
                        }
                    }
                }
                if let b = best { game.teleport(b.0, b.1 + 1, 0) }
                continue
            }
            guard let d = token.first else { continue }
            let count = Int(token.dropFirst()) ?? 1
            let (dx, dy): (Int, Int)
            switch d {
            case "N": (dx, dy) = (0, -1)
            case "S": (dx, dy) = (0, 1)
            case "E": (dx, dy) = (1, 0)
            case "W": (dx, dy) = (-1, 0)
            default: continue
            }
            for _ in 0..<count { game.move(dx: dx, dy: dy) }
        }
    }
}

extension DevTools {
    /// Each kind of figure holding each weapon (rows), facing south and east, standing
    /// and mid-stride, laid over the figure the plain way (no depth test).
    static func writeArmsSheet(to path: String) {
        let bank = SpriteBank.shared
        var figures: [(Art, WeaponArt.Carrier, Direction, Int)] = []
        for d in [Direction.south, .east] {
            for s in [0, 1] {
                for race in Race.allCases { figures.append((bank.people[race.index][0][d.rawValue][s], .of(race), d, s)) }
                figures.append((bank.people[Race.human.index][Populace.guardLook(rank: 1, female: false)][d.rawValue][s], .guardsman, d, s))
                figures.append((bank.avatar(female: false, look: 0)[d.rawValue][s], .avatarMan, d, s))
                figures.append((bank.avatar(female: true, look: 0)[d.rawValue][s], .avatarWoman, d, s))
            }
        }
        let cw = 46, ch = 70
        let fb = Framebuffer(width: figures.count * cw, height: Weapon.allCases.count * ch)
        let grass = TextureBank.shared
        for y in 0..<fb.height { for x in 0..<fb.width { fb.set(x, y, grass.texel(.grass, x, y) | 0xFF00_0000) } }
        for (r, w) in Weapon.allCases.enumerated() {
            for (i, (body, carrier, d, s)) in figures.enumerated() {
                let ax = i * cw + 8, ay = r * ch + 40
                let held = bank.weapon(w, carrier: carrier, facing: d, step: s)
                if let sh = body.shadow { fb.blit(sh, ax, ay) }
                if d == .south { fb.blit(body.sprite, ax, ay); fb.blit(held.sprite, ax, ay) }
                else { fb.blit(held.sprite, ax, ay); fb.blit(body.sprite, ax, ay) }
            }
        }
        fb.writePNG(to: path, scale: 3)
        print("Wrote \(path)")
    }

    /// Every object (first variant and frame) and the Avatar's poses, on grass.
    static func writeSpriteSheet(to path: String) {
        let t0 = Date()
        let bank = SpriteBank.shared
        print("sprites built in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        var arts: [(String, Art)] = []
        for f in Feature.allCases {
            for v in 0..<min(2, bank.variantCount(f)) {
                if let a = bank.art(f, variant: v, frame: 0) { arts.append(("\(f)", a)) }
            }
        }
        for g in [false, true] {
            for look in 0..<AvatarArt.perSex {
                for d in Direction.allCases { for s in 0..<3 { arts.append(("avatar", bank.avatar(female: g, look: look)[d.rawValue][s])) } }
            }
        }
        for look in 8..<Populace.looks {
            let race = Populace.lookRace(look) ?? .human
            for d in Direction.allCases { arts.append(("painted", bank.people[race.index][look][d.rawValue][0])) }
        }
        let cols = 14, cw = 76, ch = 104
        let rows = (arts.count + cols - 1) / cols
        let fb = Framebuffer(width: cols * cw, height: rows * ch)
        let grass = TextureBank.shared
        for y in 0..<fb.height { for x in 0..<fb.width { fb.set(x, y, grass.texel(.grass, x, y) | 0xFF00_0000) } }
        for (i, (_, art)) in arts.enumerated() {
            let ax = (i % cols) * cw + 30, ay = (i / cols) * ch + 64
            if let sh = art.shadow { fb.blit(sh, ax, ay) }
            fb.blit(art.sprite, ax, ay)
        }
        fb.writePNG(to: path, scale: 2)
        print("Wrote \(arts.count) sprites to \(path)")
    }
}

extension DevTools {
    /// The full screen, pixel art and words, at `scale` device pixels per art pixel.
    static func compose(_ fb: Framebuffer, texts: [TextItem], scale: Int) -> CGImage? {
        guard let base = fb.makeImage() else { return nil }
        let w = fb.width * scale, h = fb.height * scale
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        TextRenderer.draw(texts, in: ctx, scale: CGFloat(scale), height: CGFloat(h))
        return ctx.makeImage()
    }

    /// Renders the game screen after an optional walk (see `walk`).
    static func writeScreenshot(seed: UInt64, walk script: String, to path: String, options: Set<String>,
                                hour: Double?, scale: Int) {
        let game = Game(seed: seed)
        if options.contains("name") {
            game.nameEntry = "Iola"
        } else if options.contains("look") || options.contains("gender") {
            game.nameEntry = "Iola"
            game.confirmName()
        } else {
            // "woman" for the first woman, or "avatar0" ... "avatar9" for any of the ten.
            let pick = options.compactMap { $0.hasPrefix("avatar") ? Int($0.dropFirst(6)) : nil }.first
            game.confirmName()
            game.confirmLook(pick ?? (options.contains("woman") ? AvatarArt.perSex : 0))
        }
        walk(game, script)
        if let hour {
            let target = Int(hour * 60)
            game.wait(turns: floorMod(target - game.minutes, 24 * 60) / 2)
        }
        game.showMap = options.contains("map")
        game.showGrid = options.contains("grid")
        game.showHelp = options.contains("help")
        if options.contains("party") {
            // Two companions from among the nearest free folk, with something to carry.
            let near = game.world.npcs(near: game.x, game.y, game.z, radius: 30)
                .filter { !$0.servesDraconian && $0.guardRank == nil && $0.role != "child" }
                .sorted { abs($0.x - game.x) + abs($0.y - game.y) < abs($1.x - game.x) + abs($1.y - game.y) }
            for n in near.prefix(2) { game.addToParty(n) }
            if let a = game.party.first { a.weapon = .spear; a.pack = [.weapon(.dagger)]; a.hp = a.maxHP * 2 / 3 }
        }
        if options.contains("loaded") {
            game.weapon = .shortSword
            game.pack = [.weapon(.dagger), .weapon(.axe), .weapon(.staff), .weapon(.hammer)]
            game.gold = 37
            game.hp = 64
        }
        // "sheet" shows the Avatar's character sheet, "sheet1" the first companion's; "giving" picks a line to give.
        if let k = options.compactMap({ $0 == "sheet" ? 0 : $0.hasPrefix("sheet") ? Int($0.dropFirst(5)) : nil }).first {
            game.openSheet(k)
            if options.contains("giving") { game.perform(.give(1)) }
        }
        let screen = Screen(world: game.world)
        _ = SpriteBank.shared
        let t0 = Date()
        let pose = AvatarPose(x: Double(game.x), y: Double(game.y), facing: game.facing, step: 0)
        let fb = screen.render(game, pose: pose, frame: 0, clock: 0)
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if let img = compose(fb, texts: screen.texts, scale: scale) { Framebuffer.writePNG(img, to: path) }
        print("Rendered \(path) in \(ms) ms at", game.x, game.y, game.z, game.timeString)
        for m in game.messages.suffix(4) { print("  >", m) }
    }

    static func writeTextures(to path: String) {
        let bank = TextureBank.shared
        let mats = Mat.allCases
        let cols = 8, cell = 132
        let fb = Framebuffer(width: cols * cell, height: ((mats.count + cols - 1) / cols) * cell)
        fb.clear(rgb(0x202020))
        for (k, m) in mats.enumerated() {
            let ox = (k % cols) * cell, oy = (k / cols) * cell
            for y in 0..<128 { for x in 0..<128 { fb.set(ox + x, oy + y, bank.texel(m, x, y) | 0xFF00_0000) } }
        }
        fb.writePNG(to: path, scale: 1)
        print(mats.map { "\($0)" }.joined(separator: " "))
    }

    /// One pixel per tile overview of the generated world around the origin.
    static func writeOverview(seed: UInt64, radius: Int, to path: String) {
        let world = World(seed: seed)
        let n = Region.size, size = (2 * radius + 1) * n
        let fb = Framebuffer(width: size, height: size)
        let start = Date()
        for ry in -radius...radius {
            for rx in -radius...radius {
                let r = world.region(RegionKey(x: rx, y: ry, z: 0))
                for i in 0..<(n * n) {
                    var c = r.terrain[i].mapColor
                    let f = r.features[i]
                    if f != .none && f.blocksMovement && !r.terrain[i].isWall { c = shade(c, 0.7) }
                    fb.set((rx + radius) * n + i % n, (ry + radius) * n + i / n, c)
                }
            }
        }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        fb.writePNG(to: path, scale: 1)
        print("Generated \(world.regions.count) regions in \(ms) ms")
        for (k, r) in world.regions.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let names = r.places.filter { $0.kind != .building }.map(\.name)
            print("  (\(k.x),\(k.y)) \(r.name): \(names.joined(separator: ", "))")
        }
    }

    /// Times start-up art, world generation and steady-state frame rendering.
    static func benchmark(seed: UInt64) {
        var t0 = Date()
        _ = TextureBank.shared
        print("textures: \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        t0 = Date()
        _ = SpriteBank.shared
        print("sprites: \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        t0 = Date()
        let world = World(seed: seed)
        for ry in -1...1 { for rx in -1...1 { _ = world.region(RegionKey(x: rx, y: ry, z: 0)) } }
        print("9 regions generated in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        let game = Game(seed: seed)
        game.confirmName(); game.confirmLook()
        let screen = Screen(world: game.world)
        var pose = AvatarPose(x: Double(game.x), y: Double(game.y), facing: .south, step: 0)
        t0 = Date()
        _ = screen.render(game, pose: pose, frame: 0, clock: 0)
        print("first frame (cold ground cache): \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        t0 = Date()
        for f in 0..<60 { _ = screen.render(game, pose: pose, frame: f, clock: Double(f) / 60) }
        print("steady frame: \(String(format: "%.2f", Date().timeIntervalSince(t0) * 1000 / 60)) ms average")
        // Walking east, a pixel at a time, as the view glides.
        t0 = Date()
        for k in 0..<160 {
            pose.x = Double(game.x) + Double(k) / 32
            _ = screen.render(game, pose: pose, frame: k, clock: Double(k) / 60)
        }
        print("gliding frame: \(String(format: "%.2f", Date().timeIntervalSince(t0) * 1000 / 160)) ms average")
        game.wait(turns: 400)
        t0 = Date()
        for f in 0..<30 { _ = screen.render(game, pose: pose, frame: f, clock: Double(f) / 60) }
        print("night frame: \(String(format: "%.2f", Date().timeIntervalSince(t0) * 1000 / 30)) ms average (\(game.timeString))")
    }

    /// The application icon: the Avatar beside a cottage under an oak, framed in gold.
    static func writeIcon(to path: String) {
        let size = 128
        let fb = Framebuffer(width: size, height: size)
        let tex = TextureBank.shared, bank = SpriteBank.shared
        for y in 0..<size { for x in 0..<size { fb.set(x, y, tex.texel(.grass, x, y) | 0xFF00_0000) } }
        for y in 84..<size { for x in 0..<size { fb.set(x, y, tex.texel(.dirt, x, y) | 0xFF00_0000) } }
        if let oak = bank.art(.oakTree, variant: 1, frame: 0) {
            if let s = oak.shadow { fb.blit(s, 74, 40) }
            fb.blit(oak.sprite, 74, 40)
        }
        if let well = bank.art(.well, variant: 0, frame: 0) { fb.blit(well.sprite, 6, 66) }
        let avatar = bank.avatar(female: false, look: 0)[Direction.south.rawValue][0]
        fb.blitScaled(avatar.sprite, 44, 38, scale: 2)
        let gold = rgb(0xD8B050), dark = rgb(0x5A3A10), light = rgb(0xF8E8A0)
        for i in 0..<size {
            for (a, c) in [(0, dark), (1, gold), (2, light), (3, gold), (4, dark)] {
                fb.set(i, a, c); fb.set(a, i, c); fb.set(i, size - 1 - a, c); fb.set(size - 1 - a, i, c)
            }
        }
        fb.writePNG(to: path, scale: 8)
        print("Wrote icon to \(path)")
    }
}

extension DevTools {
    /// Checks the promises the world makes: regions are generated once and kept when
    /// you walk away and back, every building can be walked into through a door in
    /// its south wall, roofs lift indoors, keys reach the game, and saves round-trip.
    static func selfTest(seed: UInt64) -> Bool {
        var ok = true
        func check(_ cond: Bool, _ what: String) {
            print(cond ? "PASS" : "FAIL", what)
            if !cond { ok = false }
        }
        // Never touch the real keychain (or network) or the player's preferences from tests.
        ClaudeClient.shared.availableOverride = false
        let fresh = UserDefaults(suiteName: "ezerian2-selftest-\(seed)")!
        check(!Options.showHitScores(in: fresh), "hit scores are off by default")
        fresh.removePersistentDomain(forName: "ezerian2-selftest-\(seed)")
        Options.override = true
        // The credentials file: its line is found however it's written, and the default
        // location is the nearest folder above the game that holds one.
        check(ClaudeCredentials.parse("CLAUDE_API_KEY=sk-ant-test1") == "sk-ant-test1"
              && ClaudeCredentials.parse("# key\nexport CLAUDE_API_KEY = \"sk-ant-test2\"\n") == "sk-ant-test2"
              && ClaudeCredentials.parse("OTHER=1\n") == nil, "the credentials file's CLAUDE_API_KEY line is read")
        do {
            let fm = FileManager.default
            let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-creds-\(ProcessInfo.processInfo.processIdentifier)")
            let deep = root.appendingPathComponent("build/Land.app/Contents/MacOS")
            try? fm.createDirectory(at: deep, withIntermediateDirectories: true)
            let file = root.appendingPathComponent(ClaudeCredentials.fileName)
            try? "CLAUDE_API_KEY=sk-ant-test3\n".write(to: file, atomically: true, encoding: .utf8)
            check(ClaudeCredentials.findDefault(from: deep)?.standardizedFileURL == file.standardizedFileURL
                  && ClaudeCredentials.readKey(from: ClaudeCredentials.findDefault(from: deep)) == "sk-ant-test3",
                  "the credentials file is found in the project folder above the app")
            try? fm.removeItem(at: root)
        }
        let game = Game(seed: seed)
        game.nameEntry = "Iolanthe"
        game.confirmName()
        check(game.lookEntry == 0 && game.creatingCharacter, "after the name, a new game asks how the Avatar looks")
        let hits = (0..<Game.lookChoices).map { i -> Int? in
            let r = Screen.lookPortrait(i)
            return Screen.lookChoice(atX: r.x + r.w / 2, y: r.y + r.h / 2)
        }
        let (p0, p1) = (Screen.lookPortrait(0), Screen.lookPortrait(1))
        check(hits == (0..<Game.lookChoices).map { $0 } && Screen.lookChoice(atX: (p0.x + p0.w + p1.x) / 2, y: p0.y + p0.h / 2) == nil
              && Screen.lookChoice(atX: p0.x + p0.w / 2, y: p0.y - 30) == nil,
              "clicking any of the ten portraits picks it, and clicks between them don't")
        let bb = Screen.lookBegin
        check(Screen.onLookBegin(atX: bb.x + bb.w / 2, y: bb.y + bb.h / 2) && Screen.lookChoice(atX: bb.x + bb.w / 2, y: bb.y + bb.h / 2) == nil
              && !Screen.onLookBegin(atX: p0.x + p0.w / 2, y: p0.y + p0.h / 2),
              "the Begin button is apart from the portraits, so a click on a portrait only chooses it")
        game.lookEntry = 8
        check(game.creatingCharacter, "choosing a portrait doesn't begin the game")
        game.confirmLook()
        check(game.female && game.avatarLook == 3 && !game.creatingCharacter, "the Avatar can be any of the ten, here the fourth woman")
        check(game.messages.contains { $0.hasPrefix("Welcome to the Land of Ezerian") }, "the welcome comes once the Avatar is made")
        let bank = SpriteBank.shared
        let figures = [false, true].flatMap { f in (0..<AvatarArt.perSex).map { bank.avatar(female: f, look: $0)[0][0].sprite.px } }
        check(Set(figures.map { $0.hashValue }).count == Game.lookChoices, "each of the ten looks differently on the map")
        let paintings = Portraits.Outfit.allCases.flatMap { o in [false, true].flatMap { f in (0..<AvatarArt.perSex).map { (f, $0, o) } } }
        check(paintings.allSatisfy { f, look, o in Portraits.image(Portraits.avatarName(female: f, look: look, outfit: o))?.width == 236 },
              "the painted portraits load, for each of the ten in every outfit (\(paintings.count))")
        game.roll = { 1.0 }   // no chance events (ambushes, offers) while checking the world itself
        var generated: [RegionKey] = []
        game.world.onGenerate = { generated.append($0.key) }
        let home = game.world.region(RegionKey(x: 0, y: 0, z: 0))
        let snapshot = (home.terrain, home.features)
        check(home.places.contains { $0.kind == .town }, "the home region has a town")
        check(home.places.contains { $0.kind == .building && $0.name.hasPrefix("The ") }, "the home town has a named tavern")
        check(home.places.filter { $0.kind == .building }.allSatisfy { $0.roof != nil }, "every building has a roof")
        check(!game.isIndoors && game.world.feature(game.x, game.y - 1, 0) == .door, "the adventure starts at the tavern door")

        // Every door of every building lies in its south wall.
        var doorsOK = true
        for p in home.places where p.kind == .building {
            for y in p.y..<(p.y + p.h) {
                for x in p.x..<(p.x + p.w) where game.world.feature(x, y, 0) == .door {
                    let outer = x == p.x || x == p.x + p.w - 1 || y == p.y || y == p.y + p.h - 1
                    if outer && y != p.y + p.h - 1 { doorsOK = false }
                }
            }
        }
        check(doorsOK, "outer doors are all in south walls, where they can be seen")

        // Walk (by pathfinding) into a neighbouring region, then back to where we started,
        // re-planning around anyone who wanders into the way.
        func walk(until goal: @escaping (Int, Int) -> Bool) -> Bool {
            for _ in 0..<400 {
                if goal(game.x, game.y) { return true }
                game.endConversation()
                // Someone standing in the way (or on the goal): wait beside them for them to move along.
                guard let step = route(game.world, from: (game.x, game.y), goal: goal, throughGoal: true)?.first else { game.waitTurn(); continue }
                if game.world.npc(at: game.x + step.0, game.y + step.1, 0) != nil { game.waitTurn(); continue }
                game.move(dx: step.0, dy: step.1)
            }
            return goal(game.x, game.y)
        }
        let startX = game.x, startY = game.y
        var target = RegionKey(x: 1, y: 0, z: 0)
        for (nx, ny) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let there: (Int, Int) -> Bool = { x, y in floorDiv(x, Region.size) == nx && floorDiv(y, Region.size) == ny }
            guard route(game.world, from: (game.x, game.y), goal: there) != nil else { continue }
            target = RegionKey(x: nx, y: ny, z: 0)
            _ = walk(until: there)
            break
        }
        check(game.regionKey == target, "walked across a border into region (\(target.x),\(target.y))")
        let east = game.world.region(target)
        let generatedBefore = generated.count
        _ = walk { x, y in x == startX && y == startY }
        check(game.regionKey.x == 0 && game.regionKey.y == 0 && game.x == startX && game.y == startY,
              "walked back to the start in region (0,0)")
        check(game.world.region(RegionKey(x: 0, y: 0, z: 0)) === home, "region (0,0) is the same map, not regenerated")
        check(home.terrain == snapshot.0 && home.features == snapshot.1, "region (0,0) is unchanged")
        check(game.world.region(target) === east, "region (\(target.x),\(target.y)) is kept after leaving it")
        check(!generated[generatedBefore...].contains(RegionKey(x: 0, y: 0, z: 0)), "returning did not generate region (0,0) again")
        print("     (start \(startX),\(startY); \(game.world.regions.count) regions generated)")

        // Every building door must be reachable from the town on foot.
        for p in home.places where p.kind == .building {
            check(reachable(game.world, from: (startX, startY), toBuilding: p), "can walk into \(p.name)")
        }

        // Stepping through the tavern door lifts the roofs (with the townsfolk out of the way).
        let folk = home.npcs
        home.npcs = []
        game.move(dx: 0, dy: -1)
        game.move(dx: 0, dy: -1)
        check(game.isIndoors, "stepping through the door brings the Avatar indoors (roofs lift)")
        game.move(dx: 0, dy: 1)
        game.move(dx: 0, dy: 1)
        check(!game.isIndoors, "and stepping out again puts the roofs back")

        // Every feature that occurs has a picture.
        var missing: Set<Feature> = []
        for r in game.world.regions.values {
            for f in Set(r.features) where f != .none && ![.door, .window, .stainedGlass, .bedFoot].contains(f) {
                if SpriteBank.shared.art(f, variant: 0, frame: 0) == nil { missing.insert(f) }
            }
        }
        check(missing.isEmpty, "every object in the world has a sprite \(missing.isEmpty ? "" : "(missing: \(missing))")")

        home.npcs = folk
        // A frame renders above ground, indoors and underground.
        let screen = Screen(world: game.world)
        let pose = { AvatarPose(x: Double(game.x), y: Double(game.y), facing: game.facing, step: 0) }
        _ = screen.render(game, pose: pose(), frame: 0, clock: 0)
        check(screen.texts.contains { $0.text == "Iolanthe" }, "the panel shows the character's name")
        if let cave = home.features.firstIndex(of: .caveEntrance) ?? game.world.region(target).features.firstIndex(of: .caveEntrance) {
            let r = home.features.contains(.caveEntrance) ? home : game.world.region(target)
            game.teleport(r.originX + cave % Region.size, r.originY + cave / Region.size + 1, 0)
            game.endConversation()
            game.move(dx: 0, dy: -1)
            check(game.isUnderground, "a cave mouth leads underground")
            _ = screen.render(game, pose: pose(), frame: 1, clock: 0.1)
            check(game.world.feature(game.x, game.y - 1, 1) == .ladderUp, "a ladder leads back up from the cave")
            game.endConversation()
            game.move(dx: 0, dy: -1)
            check(!game.isUnderground, "climbing the ladder returns to the surface")
        }

        // People: four races, friendliness centred on each race's mean.
        check(home.npcs.count >= 8, "the home town is peopled (\(home.npcs.count) NPCs)")
        check(home.npcs.allSatisfy { (-100...100).contains($0.friendliness) }, "every friendliness is within -100...100")
        var rng = SplitMix64(seed: 77)
        for race in Race.allCases where !race.isBeast {
            let samples = (0..<4000).map { _ in Populace.friendliness(race, &rng) }
            let mean = Double(samples.reduce(0, +)) / Double(samples.count)
            check(abs(mean - Double(race.meanFriendliness)) < 3,
                  "\(race.name)s average a friendliness of \(race.meanFriendliness) (sampled \(String(format: "%.1f", mean)))")
        }
        var seen = Set<Race>()
        for ry in -2...2 { for rx in -2...2 { for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs { seen.insert(n.race) } } }
        check(seen.isSuperset(of: [.human, .elf, .dwarf, .orc]), "all four races live in the lands around home (\(seen.map(\.name).sorted().joined(separator: ", ")))")

        // Talking: walking into someone starts a conversation guided by their mood.
        if let n = home.npcs.first(where: { npc in [(0, 1), (1, 0), (-1, 0), (0, -1)].contains { game.world.isPassable(npc.x + $0.0, npc.y + $0.1, 0) && game.world.npc(at: npc.x + $0.0, npc.y + $0.1, 0) == nil } }) {
            let (dx, dy) = [(0, 1), (1, 0), (-1, 0), (0, -1)].first { game.world.isPassable(n.x + $0.0, n.y + $0.1, 0) && game.world.npc(at: n.x + $0.0, n.y + $0.1, 0) == nil }!
            game.endConversation()
            game.teleport(n.x + dx, n.y + dy, 0)
            n.friendliness = 80
            n.x = game.x - dx; n.y = game.y - dy
            game.move(dx: -dx, dy: -dy)
            check(game.conversation?.npc === n, "walking into someone starts a conversation")
            let (px, py) = (game.x, game.y)
            game.move(dx: dx, dy: dy)
            check(game.x == px && game.y == py, "the Avatar stays put while talking")
            n.known = false
            game.say(.name)
            check(n.known && game.conversation!.lines.last!.text.contains(n.name), "a friendly NPC tells their name")
            game.endConversation()
            n.friendliness = -75
            n.known = false
            game.talk()
            game.say(.name)
            check(!n.known && !game.conversation!.lines.last!.text.contains(n.name), "a hostile NPC keeps their name to themselves")
            let before = n.friendliness
            game.say(.compliment)
            check(n.friendliness != before, "a compliment changes how they feel")
            let mid = n.friendliness
            game.say(.insult)
            check(n.friendliness < mid, "an insult lowers their friendliness")
            if game.conversation?.over == false { game.say(.farewell) }
            check(game.conversation?.over == true, "farewell (or enough insults) ends the talk")
            game.endConversation()
            n.friendliness = -95
            game.talk()
            check(game.conversation?.over == true, "someone who loathes the Avatar won't talk at all")
            game.endConversation()
        } else {
            check(false, "found someone to talk to")
        }

        // Free-text conversation through Claude, with a stand-in for the API.
        let mock = ClaudeClient()
        mock.availableOverride = true
        var sent: [String: Any] = [:]
        var answer: (Data) -> Result<Data, Error> = { _ in .failure(ClaudeClient.Failure.http(500, "")) }
        mock.transport = { body, done in
            sent = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
            done(answer(body))
        }
        func apiResponse(_ reply: [String: Any], stop: String = "end_turn") -> Data {
            let text = String(data: try! JSONSerialization.data(withJSONObject: reply), encoding: .utf8)!
            return try! JSONSerialization.data(withJSONObject: [
                "id": "msg_test", "type": "message", "role": "assistant", "model": ClaudeClient.model,
                "content": [["type": "text", "text": text]], "stop_reason": stop,
                "usage": ["input_tokens": 500, "output_tokens": 60]])
        }
        game.claude = mock
        game.roll = { 0.999 }   // no chance events (offers, quarrels) in these checks
        if let n = home.npcs.first(where: { npc in [(0, 1), (1, 0), (-1, 0), (0, -1)].contains { game.world.isPassable(npc.x + $0.0, npc.y + $0.1, 0) && game.world.npc(at: npc.x + $0.0, npc.y + $0.1, 0) == nil } }) {
            let (dx, dy) = [(0, 1), (1, 0), (-1, 0), (0, -1)].first { game.world.isPassable(n.x + $0.0, n.y + $0.1, 0) && game.world.npc(at: n.x + $0.0, n.y + $0.1, 0) == nil }!
            game.teleport(n.x + dx, n.y + dy, 0)
            n.friendliness = 10
            n.known = false
            game.talk()
            for ch in "You look like a fine, honest soul. Who are you?" { game.typeInConversation(ch) }
            answer = { _ in .success(apiResponse(["reply": "Why, thank you! I'm \(n.name).", "intent": "compliment",
                                                   "friendliness_change": 8, "ends_conversation": false, "reveals_name": true])) }
            game.submitConversation()
            let msgs = sent["messages"] as? [[String: Any]] ?? []
            let prompt = msgs.first?["content"] as? String ?? ""
            let config = sent["output_config"] as? [String: Any] ?? [:]
            check(sent["model"] as? String == "claude-haiku-5-5" && config["effort"] as? String == "low"
                  && (config["format"] as? [String: Any])?["type"] as? String == "json_schema",
                  "typed words go to Claude Haiku 5.5 at low effort, asking for a structured reply")
            check(prompt.contains(n.name) && prompt.contains("Friendliness towards the Avatar: 10") && prompt.contains("fine, honest soul"),
                  "the request carries the NPC's sheet, friendliness and the Avatar's words")
            check(n.friendliness == 18 && n.known, "Claude's judgement raises friendliness (+8) and the NPC gives their name")
            check(game.conversation?.lines.last?.text == "Why, thank you! I'm \(n.name)." && game.conversation?.byClaude == true,
                  "Claude's reply appears in the conversation")
            for ch in "Die, worm!" { game.typeInConversation(ch) }
            answer = { _ in .success(apiResponse(["reply": "Guards!", "intent": "threat", "friendliness_change": -90,
                                                   "ends_conversation": true, "reveals_name": false])) }
            game.submitConversation()
            check(n.friendliness == -7 && game.conversation?.over == true, "a threat lowers friendliness (capped at -25) and can end the talk")
            game.endConversation()
            check(n.memory?.count == 2, "the NPC remembers what was said for next time")
            game.talk()
            answer = { _ in .success(apiResponse(["reply": "", "intent": "nonsense", "friendliness_change": 0,
                                                   "ends_conversation": false, "reveals_name": false], stop: "refusal")) }
            for ch in "What is your name?" { game.typeInConversation(ch) }
            game.submitConversation()
            check(game.conversation?.notice != nil && game.conversation?.byClaude == false && game.conversation?.lines.last?.fromAvatar == false,
                  "if Claude can't answer, a scripted reply is given and the window says so")
            game.endConversation()
            mock.availableOverride = false
            n.friendliness = 50
            n.known = false
            game.talk()
            for ch in "Tell me, what is your name?" { game.typeInConversation(ch) }
            game.submitConversation()
            check(n.known && game.conversation?.byClaude == false, "without Claude, typed words are matched to scripted topics")
            game.endConversation()
            // Flattery: only two compliments a day warm anyone; insults always tell.
            mock.availableOverride = true
            let fresh = NPC(id: 777001, name: "Wynn", race: .human, female: false, look: 0, friendliness: 0, x: n.x, y: n.y, z: 0,
                            bounds: n.bounds, role: "adventurer", home: nil)
            game.turn = 0
            func flatter(_ intent: String = "compliment", by gain: Int = 8) -> Int {
                let was = fresh.friendliness
                game.startConversation(with: fresh)
                for ch in "You are wonderful and brave!" { game.typeInConversation(ch) }
                answer = { _ in .success(apiResponse(["reply": "Thank you!", "intent": intent, "friendliness_change": gain,
                                                       "ends_conversation": false, "reveals_name": false])) }
                game.submitConversation()
                game.endConversation()
                return fresh.friendliness - was
            }
            let gains = [flatter(), flatter(), flatter()]
            check(gains == [8, 8, 0], "Claude's judgement: two compliments a day raise friendliness, the third doesn't (\(gains))")
            let otherGains = ["friendly", "small_talk", "greeting", "question"].map { flatter($0, by: 3) }
            check(otherGains == [0, 0, 0, 0], "nor does any other kind word that day, friendly, small talk or otherwise (\(otherGains))")
            check(AIDialogue.prompt(fresh, game: game, history: [], said: "hi").contains("won you over twice today"),
                  "Claude is told the NPC has been flattered enough today")
            game.startConversation(with: fresh)
            for ch in "You smell like a pig." { game.typeInConversation(ch) }
            answer = { _ in .success(apiResponse(["reply": "How dare you!", "intent": "insult", "friendliness_change": -10,
                                                   "ends_conversation": false, "reveals_name": false])) }
            let before = fresh.friendliness
            game.submitConversation()
            game.endConversation()
            check(fresh.friendliness == before - 10, "insults still lower friendliness after the day's compliments are spent")
            game.turn += 12 * 60
            check(flatter() == 8 && game.day == 2, "the next day, compliments work again")
            check([flatter("friendly", by: 3), flatter("small_talk", by: 2)] == [3, 0],
                  "and a friendly word counts towards the two, the same as a compliment")
            mock.availableOverride = false
            let plain = NPC(id: 777002, name: "Bran", race: .human, female: false, look: 0, friendliness: 0, x: n.x, y: n.y, z: 0,
                            bounds: n.bounds, role: "townsperson", home: nil)
            game.startConversation(with: plain)
            var steps: [Int] = []
            for _ in 0..<3 { let was = plain.friendliness; game.say(.compliment); steps.append(plain.friendliness - was) }
            let was = plain.friendliness
            game.say(.insult)
            check(steps[0] > 0 && steps[1] > 0 && steps[2] == 0 && plain.friendliness < was,
                  "scripted: two compliments a day raise friendliness, the third doesn't, and insults still tell (\(steps))")
            game.endConversation()
        }
        game.claude = ClaudeClient.shared

        // The party.
        check(Party.chance(0) == 0 && Party.chance(-40) == 0 && Party.chance(100) == 1
              && Party.chance(30) < Party.chance(60) && Party.chance(1) > 0,
              "joining: no chance at friendliness 0 or below, rising with friendliness, certain at 100")
        game.endConversation()
        let partyTest = Game(seed: seed)
        partyTest.confirmName(); partyTest.confirmLook()
        partyTest.claude = mock
        mock.availableOverride = false
        let townsfolk = partyTest.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
        // A peaceful town for these checks: no one about to pick a fight.
        for n in townsfolk { n.servesDraconian = false; n.friendliness = max(n.friendliness, 10) }
        var dice = 0.5
        partyTest.roll = { dice }
        func chat(_ n: NPC, _ text: String) {
            partyTest.endConversation()
            partyTest.teleport(n.x, n.y + 1, n.z)
            if partyTest.world.npc(at: n.x, n.y + 1, n.z) != nil || !partyTest.world.isPassable(n.x, n.y + 1, n.z) {
                partyTest.teleport(n.x + 1, n.y, n.z)
            }
            partyTest.startConversation(with: n)
            for ch in text { partyTest.typeInConversation(ch) }
            partyTest.submitConversation()
        }
        if townsfolk.count >= 6 {
            let a = townsfolk[0], b = townsfolk[1], c = townsfolk[2], d = townsfolk[3], e = townsfolk[4]
            // Only adventurers join.
            let local = townsfolk.first { !$0.isAdventurer && $0.guardRank == nil }!
            local.friendliness = 100; dice = 0
            chat(local, "Will you join my party?")
            check(!local.following && partyTest.party.isEmpty && partyTest.joinDecision(local) == .notAdventurer
                  && partyTest.conversation?.lines.last?.fromAvatar == false,
                  "only adventurers join: anyone else declines, even at friendliness 100")
            for n in [a, b, c, d, e] { n.role = "adventurer" }
            a.friendliness = 100; dice = 0.999
            chat(a, "Will you join my party?")
            check(a.following && partyTest.party.count == 1, "at friendliness 100 an NPC always agrees to join")
            check(partyTest.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.allSatisfy { $0 !== a } && partyTest.world.npc(at: a.x, a.y, 0) === a,
                  "a companion leaves their home region's roll and travels with the Avatar")
            b.friendliness = 0; dice = 0
            chat(b, "Come with me, travel with me!")
            check(!b.following && b.refusedAt == 0, "at friendliness 0 an NPC never joins, and remembers refusing")
            b.friendliness = 30; dice = 0
            chat(b, "Please join my party")
            check(!b.following, "after a refusal, asking again fails while friendliness is up by less than 35")
            b.friendliness = 36; dice = 0
            chat(b, "Please join my party")
            check(b.following, "once friendliness has risen by 35 or more, they may be asked again")
            c.friendliness = 100; dice = 0
            chat(c, "Will you join my party?")
            d.friendliness = 100; dice = 0
            chat(d, "Will you join my party?")
            check(partyTest.party.count == 3 && !d.following, "the party holds at most three")
            partyTest.endConversation()
            // Following: from the open street before the tavern.
            let street = Game.startPosition(in: partyTest.world)
            partyTest.teleport(street.x, street.y, 0)
            var walked = 0
            var last = (0, 0)
            for _ in 0..<9 {
                // Keep walking wherever there's open ground (not straight back).
                let open = [(1, 0), (0, 1), (-1, 0), (0, -1)].sorted { a, _ in a != (-last.0, -last.1) }.filter { d in
                    partyTest.world.isPassable(partyTest.x + d.0, partyTest.y + d.1, 0)
                        && partyTest.world.npc(at: partyTest.x + d.0, partyTest.y + d.1, 0).map(\.following) != false
                        && partyTest.world.feature(partyTest.x + d.0, partyTest.y + d.1, 0) != .caveEntrance
                }
                guard let d = open.first else { break }
                if partyTest.move(dx: d.0, dy: d.1) { walked += 1; last = d }
            }
            let near = partyTest.party.allSatisfy { max(abs($0.x - partyTest.x), abs($0.y - partyTest.y)) <= Party.maxSize + 2 && $0.z == partyTest.z }
            check(walked >= 4 && near, "companions follow the Avatar (\(walked) steps walked)")
            if !near { for n in partyTest.party { print("     ", n.name, n.x, n.y, n.z, "avatar", partyTest.x, partyTest.y, partyTest.z) } }
            // Talking to a companion; rudeness can drive them off, and they won't rejoin soon.
            a.friendliness = 40
            dice = 0
            chat(a, "You are a stupid fool!")
            check(!a.following && a.refusedAt == a.friendliness && partyTest.party.count == 2,
                  "a companion insulted into liking the Avatar less may leave the party")
            a.friendliness += 20; dice = 0
            chat(a, "Join me again?")
            check(!a.following, "a companion who left won't rejoin unless friendliness rises by 35")
            // Offers.
            partyTest.endConversation()
            e.friendliness = 100; dice = 0
            chat(e, "Lovely weather today.")
            check(partyTest.conversation?.offer == true || partyTest.party.count >= 3,
                  "a fond NPC asks to join during a conversation")
            if partyTest.conversation?.offer == true {
                partyTest.answerOffer(true)
                check(e.following && partyTest.party.count == 3, "saying yes to an offer brings them into the party")
            }
            partyTest.endConversation()
            // Dismissal.
            chat(b, "It's time we parted ways, leave the party.")
            check(!b.following && partyTest.party.count == 2, "a companion can be dismissed in conversation")
            // Saving.
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-party-\(ProcessInfo.processInfo.processIdentifier).plist")
            partyTest.endConversation()
            try? SaveGame.save(partyTest, to: url)
            let back = SaveGame.load(from: url)
            check(back?.party.map(\.name) == partyTest.party.map(\.name) && back?.party.allSatisfy(\.following) == true,
                  "the party survives a save")
        } else {
            check(false, "enough townsfolk to test the party")
        }

        // Hiring adventurers for gold.
        do {
            check(Populace.adventurerHealth(avatar: 200, 0) == 100 && Populace.adventurerHealth(avatar: 200, 1) == 250
                  && Populace.adventurerHealth(avatar: 100, 0.5) == 88,
                  "an adventurer's health runs from half the Avatar's to a quarter more")
            let grown = Game(seed: seed)
            grown.maxHP = 140
            check(grown.world.avatarHealth == 140, "adventurers in lands not yet seen are measured against the Avatar's health now")
            check(Party.hireChance(1) == 0.01 && Party.hireChance(50) == 0.5 && Party.hireChance(100) == 1 && Party.hireChance(300) == 1,
                  "each gold coin offered is a 1% chance an adventurer joins, certain at 100")
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            g.claude = mock
            mock.availableOverride = false
            let folk = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
            for n in folk { n.servesDraconian = false; n.friendliness = max(n.friendliness, 10) }
            var dice = 0.3
            g.roll = { dice }
            g.gold = 100
            func meet(_ n: NPC) {
                g.endConversation()
                g.teleport(n.x, n.y + 1, n.z)
                if g.world.npc(at: n.x, n.y + 1, n.z) != nil || !g.world.isPassable(n.x, n.y + 1, n.z) { g.teleport(n.x + 1, n.y, n.z) }
                g.startConversation(with: n)
            }
            func offer(_ amount: Int) {
                while !(g.conversation?.goldInput.isEmpty ?? true) { g.backspaceGold() }
                g.focusGold(true)
                for ch in "\(amount)" { g.typeGold(ch) }
                g.offerGold()
            }
            if let local = folk.first(where: { !$0.isAdventurer && !Trade.trades($0) && !g.sellsRest($0) && $0.guardRank == nil }),
               let hero = folk.first(where: \.isAdventurer) {
                meet(local)
                check(g.conversation.map(g.takesGold) == false, "there is no hiring anyone but an adventurer")
                hero.friendliness = 0
                meet(hero)
                check(g.conversation.map(g.takesGold) == true, "talking to an adventurer, the Avatar can offer gold to hire them")
                offer(20)
                check(!hero.following && g.gold == 100 && hero.hireRefused == 20 && g.conversation?.lines.last?.fromAvatar == false,
                      "turned down (20 gold against a roll of 0.3), the Avatar keeps the gold and the adventurer remembers the sum")
                dice = 0
                offer(25)
                check(!hero.following && g.gold == 100, "one offer a talk: a second the same talk is turned away")
                meet(hero)
                offer(20)
                check(!hero.following && g.conversation?.lines.last?.text.contains("20 gold") == true,
                      "next time, the same sum or less is refused out of hand")
                let purse = hero.gold
                dice = 0.39
                offer(40)
                check(hero.following && g.party.count == 1 && g.gold == 60 && hero.gold == purse + 40,
                      "40 gold against a roll of 0.39: the adventurer takes it and joins")
                check(g.conversation.map(g.takesGold) == false, "a companion can't be hired again")
                g.endConversation()
                for n in folk.filter({ !$0.following && $0.guardRank == nil }).prefix(2) {
                    n.role = "adventurer"
                    g.addToParty(n)
                }
                if let spare = folk.first(where: { !$0.following && $0.guardRank == nil }) {
                    spare.role = "adventurer"
                    check(g.party.count == 3 && !g.canHire(spare), "with three companions there's no hiring a fourth")
                }
                // Fond townsfolk no longer offer to come along; adventurers still do.
                g.endConversation()
                g.party.forEach { g.removeFromParty($0, lockOut: false) }
                if let fond = folk.first(where: { !$0.isAdventurer && !$0.following && !Trade.trades($0) && !g.sellsRest($0) && $0.guardRank == nil }) {
                    fond.friendliness = 100
                    dice = 0
                    meet(fond)
                    for ch in "Lovely weather today." { g.typeInConversation(ch) }
                    g.submitConversation()
                    check(g.conversation?.offer == false, "someone who isn't an adventurer never offers to join, however fond")
                }
            } else {
                check(false, "an adventurer and someone else in the home town")
            }
        }

        // Combat.
        var hpRng = SplitMix64(seed: 99)
        let healths = (0..<20000).map { _ in Populace.health(hpRng.double()) }
        let hpMean = Double(healths.reduce(0, +)) / Double(healths.count)
        let hpMedian = healths.sorted()[healths.count / 2]
        check(healths.min()! >= 1 && healths.max()! <= 200 && abs(hpMean - 75) < 3 && Double(hpMedian) < hpMean,
              "NPC health runs 1-200, weighted low, averaging about 75 (mean \(String(format: "%.1f", hpMean)), median \(hpMedian))")
        check(Game(seed: seed).hp == 100, "the Avatar starts with 100 health")
        check(Combat.ambushChance(-100) == 1 && Combat.ambushChance(0) == 0 && Combat.ambushChance(-60) > Combat.ambushChance(-30),
              "an unfriendly neighbour's chance of attacking grows with unfriendliness, certain at -100")
        func arena() -> (Game, [NPC]) {
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            let folk = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
            for n in folk { n.friendliness = 50; n.weapon = nil }   // bare hands, unless a test arms them
            // (Storekeepers never start fights, so the fighting tests leave them be.)
            return (g, folk.filter { !NPC.storekeepers.contains($0.role) })
        }
        func standBeside(_ g: Game, _ n: NPC) -> (Int, Int)? {
            for (dx, dy) in [(0, 1), (1, 0), (-1, 0), (0, -1)] where g.world.isPassable(n.x + dx, n.y + dy, 0)
                && g.world.npc(at: n.x + dx, n.y + dy, 0) == nil {
                g.teleport(n.x + dx, n.y + dy, 0)
                return (-dx, -dy)
            }
            return nil
        }
        do {
            // The Avatar attacks; the victim's friendliness plunges; blows deal 1-10.
            let (g, folk) = arena()
            let foe = folk[0]
            foe.maxHP = 200; foe.hp = 200; foe.friendliness = 30
            var dice = 0.0
            g.roll = { dice }
            if let (dx, dy) = standBeside(g, foe) {
                g.attack(dx: dx, dy: dy)
                check(g.inCombat && foe.friendliness == -30, "attacking someone starts a fight and drops their friendliness by 60")
                check(foe.hp < 200 && 200 - foe.hp <= 20, "a blow that lands does 1-10 damage (\(200 - foe.hp) after the foe's reply)")
                dice = 0.75   // every blow misses
                let hpBefore = (g.hp, foe.hp)
                for _ in 0..<5 { g.waitTurn() }
                check(g.hp == hpBefore.0 && foe.hp == hpBefore.1 && g.turn > 0, "half the blows miss: a roll over 0.5 does nothing")
                // Every blow lands for 10 (rolls alternate: hit, then top damage).
                var k = 0
                g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }
                foe.hp = 15
                g.move(dx: dx, dy: dy)
                check(foe.hp == 5, "walking into a foe strikes them (max blow 10: hp 15 -> 5)")
                check(g.messages.contains { $0.hasPrefix("You hit") && $0.hasSuffix(": 5 of 200 left.") },
                      "with hit scores on, each landed blow reports the foe's remaining health")
                Options.showHitScores = false
                foe.hp = 15
                g.move(dx: dx, dy: dy)
                check(g.messages.last { $0.hasPrefix("You hit") } == "You hit \(foe.shortName) with your bare hands.",
                      "with hit scores off, a blow just says who was hit")
                Options.showHitScores = true
                foe.hp = 15
                g.move(dx: dx, dy: dy)
                check(g.hp <= hpBefore.0 - 1, "the foe strikes back on their turn")
                g.move(dx: dx, dy: dy)
                check(foe.hp == 0 && !g.inCombat && !folk.contains { $0 === foe && g.world.npc(at: $0.x, $0.y, 0) === foe },
                      "a foe at 0 health dies, and the fight ends")
            } else { check(false, "found room to fight") }
        }
        do {
            // Merchants' prices, and buying a night's healing from a healer.
            check(Trade.price(base: 10, friendliness: 0) == 10 && Trade.price(base: 10, friendliness: -4) == 10
                  && Trade.price(base: 10, friendliness: -5) == 11 && Trade.price(base: 10, friendliness: -23) == 14
                  && Trade.price(base: 10, friendliness: 40) == 10,
                  "a merchant asks a coin more for every 5 points of friendliness below 0")
            check(Trade.settle(offered: 10, price: 10) == (1, 1) && Trade.settle(offered: 13, price: 10) == (7, 1)
                  && Trade.settle(offered: 9, price: 10) == (-2, 0.9) && Trade.settle(offered: 7, price: 10).friendliness == -6
                  && abs(Trade.settle(offered: 7, price: 10).acceptChance - 0.7) < 1e-9 && Trade.settle(offered: 0, price: 10).acceptChance == 0
                  && Trade.settle(offered: 11, price: 12) == (-2, 0.9),
                  "paying the price pleases (+1), more pleases more (+2 a coin), less costs 2 a coin and is taken 90%, 80%… of the time")
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            g.claude = mock
            mock.availableOverride = false
            var healers: [NPC] = []
            for ry in -2...2 { for rx in -2...2 { healers += g.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs.filter { $0.role == "healer" } } }
            if let healer = healers.first {
                var dice = 0.5
                g.roll = { dice }
                func visit(_ f: Int) {
                    g.endConversation()
                    healer.friendliness = f
                    g.startConversation(with: healer)
                }
                func say(_ text: String) {
                    for ch in text { g.typeInConversation(ch) }
                    g.submitConversation()
                }
                func offer(_ n: Int) {
                    g.focusGold(true)
                    while !(g.conversation?.goldInput.isEmpty ?? true) { g.backspaceGold() }
                    for ch in String(n) { g.typeGold(ch) }
                    g.offerGold()
                }
                visit(10)
                check(g.conversation?.healingAsked == true && g.conversation?.lines.last?.text.contains("require healing") == true,
                      "a healer asks whether the Avatar requires healing")
                say("Yes, please.")
                check(g.conversation?.price == 10 && g.conversation?.goldInput == "10" && g.conversation?.lines.last?.text.contains("10 gold") == true,
                      "say yes, and the healer names the price: 10 gold")
                g.hp = 23; g.gold = 30
                let day = g.day
                offer(10)
                check(g.hp == g.maxHP && g.gold == 20 && g.day == day + 1 && g.timeString == "8:00 AM" && healer.friendliness == 11
                      && g.nights == 1 && g.conversation?.price == nil,
                      "10 gold buys a night's rest: the Avatar wakes at 8 the next morning, wholly healed, and the healer likes them 1 better")
                visit(10)
                say("No thank you.")
                check(g.conversation?.price == nil && g.conversation?.healingAsked == false, "say no, and the healer lets it be")
                g.hp = 50
                visit(10); say("yes"); dice = 0.79
                offer(8)
                check(g.hp == g.maxHP && g.gold == 12 && healer.friendliness == 6, "8 gold is taken 80% of the time, for 4 points of friendliness")
                g.hp = 50
                visit(10); say("yes"); dice = 0.81
                offer(8)
                check(g.hp == 50 && g.gold == 12 && healer.friendliness == 6 && g.conversation?.price == 10
                      && g.conversation?.lines.last?.text.contains("My price is 10") == true,
                      "turned down, the healer keeps the gold, still loses 4 points, and names the price again")
                g.gold = 40
                visit(-12); say("How much to heal me?")
                check(g.conversation?.price == 12, "at -12 friendliness the healer asks 12")
                dice = 0.5
                offer(13)
                check(g.gold == 27 && healer.friendliness == -9, "paying a coin over the 12 asked pleases them by 3")
                visit(-55)
                check(g.conversation?.healingAsked == false, "a healer at -55 doesn't offer healing")
                say("Please heal me")
                check(g.conversation?.price == nil && g.conversation?.lines.last?.text.contains("elsewhere") == true,
                      "and below -50 refuses to do business")
                visit(10); say("yes")
                g.gold = 4; g.hp = 50
                offer(10)
                check(g.hp == 50 && g.gold == 4 && g.conversation?.notice == "You have only 4 gold.", "the Avatar can't give gold they don't have")
                check(AIDialogue.prompt(healer, game: g, history: [], said: "hello").contains("for 10 gold"),
                      "Claude is told the healer's price")
                // Wounded companions are healed too, for 5 gold more each.
                let mates = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.filter { $0 !== healer && !$0.servesDraconian && $0.guardRank == nil }.prefix(3)
                if mates.count == 3 {
                    for m in mates { g.addToParty(m) }
                    let (m0, m1, m2) = (mates[mates.startIndex], mates[mates.startIndex + 1], mates[mates.startIndex + 2])
                    m0.hp = 1; m1.hp = max(1, m1.maxHP / 2); m2.hp = m2.maxHP
                    g.hp = 50; g.gold = 40; dice = 0.5
                    visit(10); say("yes")
                    check(g.conversation?.price == 20 && g.conversation?.lines.last?.text.contains("two companions") == true,
                          "with two wounded companions (and one hale) the healer asks 10 + 5 + 5 = 20")
                    offer(20)
                    check(g.hp == g.maxHP && m0.hp == m0.maxHP && m1.hp == m1.maxHP && g.gold == 20
                          && g.conversation?.lines.last?.text.contains("companions' too") == true,
                          "and the Avatar and the companions all wake healed")
                    visit(-10); say("heal us")
                    check(g.conversation?.price == 12, "with no one wounded but the Avatar, 10 plus the dislike surcharge")
                    m0.hp = 1
                    visit(-10); say("heal us")
                    check(g.conversation?.price == 17, "a wounded companion adds 5 before the surcharge: 15 + 2")
                    for m in mates { g.removeFromParty(m, lockOut: false) }
                } else { check(false, "found three companions to take to the healer") }
                g.endConversation()
            } else { check(false, "found a healer to visit") }
            // A room at an inn: 5 gold, and a night's sleep mends 50 points.
            var keepers: [NPC] = []
            for ry in -2...2 { for rx in -2...2 { keepers += g.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs.filter { $0.role == "innkeeper" } } }
            if let keeper = keepers.first {
                g.roll = { 0.5 }
                func say(_ text: String) {
                    for ch in text { g.typeInConversation(ch) }
                    g.submitConversation()
                }
                func offer(_ n: Int) {
                    g.focusGold(true)
                    while !(g.conversation?.goldInput.isEmpty ?? true) { g.backspaceGold() }
                    for ch in String(n) { g.typeGold(ch) }
                    g.offerGold()
                }
                g.endConversation()
                keeper.friendliness = 10
                g.startConversation(with: keeper)
                check(g.conversation?.healingAsked == true && g.conversation?.lines.last?.text.contains("room") == true
                      || g.conversation?.lines.last?.text.contains("bed") == true,
                      "an innkeeper asks whether the Avatar wants a room (\(keeper.race.name))")
                say("yes")
                check(g.conversation?.price == 5 && g.conversation?.lines.last?.text.contains("5 gold") == true,
                      "say yes, and the innkeeper names the price: 5 gold")
                g.hp = 20; g.gold = 10
                let (day, nights) = (g.day, g.nights)
                offer(5)
                check(g.hp == 70 && g.gold == 5 && g.day == day + 1 && g.timeString == "8:00 AM" && g.nights == nights + 1
                      && keeper.friendliness == 11 && g.conversation?.price == nil,
                      "5 gold buys a night in a room: the Avatar wakes at 8 next morning 50 points better")
                g.endConversation()
                g.hp = g.maxHP - 10; g.gold = 10
                g.startConversation(with: keeper); say("How much for a bed?")
                offer(5)
                check(g.hp == g.maxHP, "the night's sleep heals no further than whole")
                g.endConversation()
                keeper.friendliness = -20
                g.startConversation(with: keeper); say("I need a room")
                check(g.conversation?.price == 9, "at -20 friendliness the innkeeper asks 9")
                g.endConversation()
                keeper.friendliness = -60
                g.startConversation(with: keeper); say("I need a room")
                check(g.conversation?.price == nil && g.conversation?.healingAsked == false, "below -50 the innkeeper won't let a room")
                g.endConversation()
                keeper.friendliness = 10
                check(AIDialogue.prompt(keeper, game: g, history: [], said: "hello").contains("for 5 gold"), "Claude is told the innkeeper's price")
                let mate = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.first { $0 !== keeper && !$0.servesDraconian && $0.guardRank == nil && $0.role != "healer" }
                if let mate {
                    g.addToParty(mate)
                    mate.hp = 1; g.hp = 20; g.gold = 10
                    g.startConversation(with: keeper); say("yes")
                    check(g.conversation?.price == 7 && g.conversation?.lines.last?.text.contains("7 gold") == true,
                          "a companion sharing the room costs 2 more: 7 gold")
                    offer(7)
                    check(mate.hp == min(mate.maxHP, 51) && g.hp == 70, "and each wakes 50 points better")
                    g.endConversation()
                    g.removeFromParty(mate, lockOut: false)
                }
                // A beer from a barkeep: 2 gold (1 if they like you well), drunk at once for 5 health; tips please them by 5.
                var barkeeps: [NPC] = []
                for ry in -2...2 { for rx in -2...2 { barkeeps += g.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs.filter { $0.role == "barkeep" } } }
                if let bar = barkeeps.first {
                    bar.friendliness = 10
                    g.hp = 50; g.gold = 20
                    g.startConversation(with: bar)
                    let barDay = g.day
                    check(g.conversation?.price == 2 && g.conversation?.goldInput == "2" && g.takesGold(g.conversation!)
                          && g.conversation?.lines.last?.text.contains("2 gold") == true,
                          "a barkeep offers a beer for 2 gold, the gold ready to hand over (\(bar.race.name))")
                    offer(2)
                    check(g.hp == 55 && g.gold == 18 && bar.friendliness == 11 && g.conversation?.price == 2 && g.day == barDay,
                          "2 gold buys a beer, drunk at once for 5 health, and another is on offer")
                    offer(3)
                    check(g.hp == 60 && g.gold == 15 && bar.friendliness == 16, "a 1-coin tip on top pleases the barkeep by 5")
                    g.hp = g.maxHP - 2
                    offer(2)
                    check(g.hp == g.maxHP, "a beer heals no further than whole")
                    say("no thanks")
                    check(g.conversation?.price == nil && g.takesGold(g.conversation!), "turned down, the beer is off, but the gold field stays")
                    let f0 = bar.friendliness, g0 = g.gold
                    offer(1)
                    check(bar.friendliness == f0 + 5 && g.gold == g0 - 1, "gold with no beer ordered is a tip: +5 friendliness")
                    offer(10)
                    check(bar.friendliness == f0 + 10, "a big tip pleases no more than a small one")
                    say("Another beer, please")
                    check(g.conversation?.price == 2, "asking for a beer puts one on offer again")
                    g.endConversation()
                    bar.friendliness = 51
                    g.startConversation(with: bar)
                    check(g.conversation?.price == 1 && g.conversation?.lines.last?.text.contains("gold coin") == true,
                          "a barkeep fond of you (above 50) asks only 1 gold")
                    g.endConversation()
                    bar.friendliness = 50
                    g.startConversation(with: bar)
                    check(g.conversation?.price == 2, "at 50 still 2")
                    g.endConversation()
                    bar.friendliness = -60
                    g.startConversation(with: bar); say("A beer")
                    check(g.conversation?.price == nil && !g.takesGold(g.conversation!), "below -50 the barkeep won't serve you, nor take tips")
                    g.endConversation()
                    bar.friendliness = 10
                    check(AIDialogue.prompt(bar, game: g, history: [], said: "hello").contains("beer at 2 gold"), "Claude is told the price of a beer")
                } else { check(false, "found a barkeep to visit") }
            } else { check(false, "found an innkeeper to visit") }
            let f = Screen.talkFields(trading: true), box = Screen.talkBox
            check(f.say.x + f.say.w < f.gold.x && f.gold.x + f.gold.w < f.give.x && f.give.x + f.give.w <= box.x + box.w
                  && Screen.inside(f.give, f.give.x + 5, f.give.y + 5) && !Screen.inside(f.gold, f.give.x + 5, f.give.y + 5),
                  "the words, the gold and the Give gold button sit side by side in the conversation window")
        }
        do {
            // Weapons: bonuses, who carries what, naming them in blows, taking them from the slain.
            check(Weapon.allCases.map(\.bonus) == [3, 3, 5, 5, 6, 4, 5, 5, 8],
                  "staff and dagger add 3 damage, war hammer 4, mace, short sword, axe and spear 5, long sword 6, sharp sword 8")
            check(Weapon.allCases.allSatisfy { $0.sharpened(0.99) == $0 } && Weapon.allCases.filter { $0.sharpened(0.1) == .sharpSword }
                    == [.shortSword, .longSword, .sharpSword], "only a sword can turn out sharp")
            check([Weapon.hammer, .longSword, .axe, .dagger].max() == .longSword && [Weapon.hammer, .mace].max() == .mace
                  && [Weapon.dagger, .hammer].max() == .hammer && Weapon.axe.article == "an",
                  "the Avatar fights with the weapon that does the most damage, and an axe is an axe")
            check(Game(seed: seed).weapon == nil && Game(seed: seed).pack.isEmpty, "the Avatar starts with no weapon")
            check(WeaponArt.Carrier.allCases.allSatisfy { c in Weapon.allCases.allSatisfy { w in
                Direction.allCases.allSatisfy { SpriteBank.shared.weapon(w, carrier: c, facing: $0, step: 1).sprite.w > 1 } } },
                  "every weapon is drawn in the hand of every kind of figure")
            let poseGame = Game(seed: seed)
            check(poseGame.npcPoses(t: 1).allSatisfy { p in poseGame.world.npcs(near: poseGame.x, poseGame.y, 0, radius: 16)
                .contains { Double($0.x) == p.x && Double($0.y) == p.y && $0.weapon == p.weapon } },
                  "on the map, people hold the weapon they really carry")
            check((0..<GuardArt.ranks).map { Weapon.forGuard(rank: $0) } == Array(Weapon.allCases.prefix(5)), "the watch are armed by rank, staff to long sword")
            var wrng = SplitMix64(seed: 77)
            var swords = 0, sharp = 0
            func sample(_ hp: Int) -> (armed: Double, tier: Double) {
                let ws = (0..<4000).map { _ in Weapon.roll(health: hp, servant: false, child: false, &wrng) }
                let armed = ws.compactMap { $0 }
                swords += armed.filter(\.isSword).count; sharp += armed.filter { $0 == .sharpSword }.count
                return (Double(armed.count) / 4000, Double(armed.map(\.rawValue).reduce(0, +)) / Double(max(1, armed.count)))
            }
            let weak = sample(20), middling = sample(75), strong = sample(180)
            check(weak.armed < middling.armed && middling.armed < strong.armed && weak.tier < middling.tier && middling.tier < strong.tier,
                  String(format: "tougher people are likelier armed, with better weapons (armed %.0f%%, %.0f%%, %.0f%%; tier %.1f, %.1f, %.1f)",
                         weak.armed * 100, middling.armed * 100, strong.armed * 100, weak.tier, middling.tier, strong.tier))
            let sharpShare = Double(sharp) / Double(max(1, swords))
            check(abs(sharpShare - 1.0 / 6) < 0.03, String(format: "about one sword in six is a sharp sword (%.1f%% of %d)", sharpShare * 100, swords))
            let (g, folk) = arena()
            let foe = folk[0]
            foe.maxHP = 200; foe.hp = 200; foe.weapon = .mace
            var k = 0
            g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }   // every blow lands for the most
            Options.showHitScores = false
            defer { Options.showHitScores = true }
            if let (dx, dy) = standBeside(g, foe) {
                g.attack(dx: dx, dy: dy)
                check(g.messages.contains("You hit \(foe.shortName) with your bare hands."), "the Avatar's blows are with bare hands at first")
                if foe.race == .human {
                    check(g.messages.contains { $0.hasPrefix("The \(foe.title) hits you with") }, "a human foe is named by their trade in a fight")
                }
                check(g.messages.contains { $0.hasSuffix("hits you with \(foe.his) mace.") } && g.hp == 100 - 15,
                      "a foe's blow names their weapon, and a mace adds 5 (took \(100 - g.hp))")
                g.roll = { 0.9 }
                g.waitTurn()
                check(g.messages.contains { $0.hasSuffix("misses you with \(foe.his) mace.") }, "a miss names the weapon too")
                g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }
                foe.hp = 5
                g.move(dx: dx, dy: dy)
                check(g.weapon == .mace && g.pack.isEmpty && foe.weapon == nil, "slaying a foe gives the Avatar their weapon")
                let other = folk.first { $0 !== foe && g.world.npc(at: $0.x, $0.y, 0) === $0 }!
                other.weapon = .dagger
                other.maxHP = 200; other.hp = 30
                if let (ex, ey) = standBeside(g, other) {
                    k = 0
                    g.attack(dx: ex, dy: ey)
                    check(other.hp == 30 - 15, "the Avatar's mace adds 5 to each blow")
                    g.combat = nil
                }
                check(g.weapon == .mace, "the Avatar fights with the weapon in hand")
            } else { check(false, "found room to test weapons") }
            // The party's kills yield the foe's weapon, the companions' as well as the Avatar's.
            let (g2, folk2) = arena()
            let foe2 = folk2[1], friend = folk2.first { $0 !== foe2 }!
            foe2.weapon = .longSword; foe2.hp = 1; foe2.maxHP = 50
            g2.addToParty(friend)
            g2.combat = Combat(enemies: [foe2], order: [nil, friend, foe2])
            g2.roll = { 0.0 }
            g2.strike(friend, foe2)
            check(foe2.hp == 0 && g2.weapon == .longSword && g2.messages.contains("You take \(foe2.his) long sword. You now fight with it (+6 damage)."),
                  "a foe slain by a companion is looted: the Avatar takes the long sword")
            g2.combat = nil
        }
        do {
            // Belongings: looting the slain, ten things each, equipping, dropping and giving, and the character sheet.
            let (g, folk) = arena()
            let foe = folk[1], mate = folk[2], mate2 = folk[3]
            foe.weapon = .axe; foe.pack = [.weapon(.dagger), .weapon(.dagger)]
            g.loot(foe)
            check(g.weapon == .axe && g.pack == [.weapon(.dagger), .weapon(.dagger)] && foe.weapon == nil && foe.pack.isEmpty,
                  "the Avatar takes everything a slain foe carried, duplicates too, and fights with the weapon if empty-handed")
            g.pack += Array(repeating: .weapon(.staff), count: 6)
            let full = folk[4]
            full.weapon = .longSword; full.pack = [.weapon(.spear)]
            g.loot(full)
            check(g.carried(0) == 10 && g.pack.last == .weapon(.longSword) && g.messages.last?.contains("carry no more") == true,
                  "no one carries more than ten things: what doesn't fit is left behind")
            g.addToParty(mate)
            mate.weapon = nil; mate.pack = Array(repeating: .salve, count: 9)
            let spill = folk[5]
            spill.weapon = .mace; spill.pack = [.weapon(.spear)]
            g.loot(spill)
            check(mate.weapon == .mace && mate.pack.count == 9 && g.messages.last?.contains("carry no more") == true
                  && g.messages.contains { $0.hasPrefix("\(mate.name) takes") },
                  "what the Avatar can't carry goes to a companion with room, and what no one can is left")
            g.pack = []; mate.weapon = nil; mate.pack = []
            let victim = folk[6]
            victim.weapon = .axe; victim.pack = [.salve]; victim.hp = 1; victim.maxHP = 50
            g.startCombat(against: victim, startedByEnemy: true)
            g.roll = { 0 }
            g.strike(mate, victim)
            check(victim.hp == 0 && g.pack.contains(.weapon(.axe)) && g.pack.contains(.salve),
                  "a foe a companion fells is looted too: the axe goes to the Avatar")
            g.combat = nil
            g.removeFromParty(mate, lockOut: false)
            g.weapon = .dagger; g.pack = [.weapon(.axe), .weapon(.staff)]
            g.openSheet()
            check(g.sheet == 0 && !g.move(dx: 1, dy: 0), "I opens the Avatar's sheet, and the Avatar stays put while it is open")
            g.perform(.equip(1))
            check(g.weapon == .axe && g.pack == [.weapon(.dagger), .weapon(.staff)], "equipping a weapon from the pack swaps it with the one in hand")
            g.perform(.unequip)
            check(g.weapon == nil && g.pack == [.weapon(.axe), .weapon(.dagger), .weapon(.staff)], "putting a weapon away leaves the hands empty")
            g.perform(.drop(2))
            check(g.pack == [.weapon(.axe), .weapon(.dagger)], "dropping an item leaves it behind")
            g.perform(.give(0))
            check(g.sheetGiving == nil, "with no companions there is no one to give things to")
            g.perform(.close)
            for m in [mate, mate2] { m.servesDraconian = false; g.addToParty(m) }
            mate.weapon = nil; mate.pack = []; mate2.weapon = .mace
            mate2.pack = Array(repeating: .weapon(.staff), count: 9)
            g.openSheet()
            g.perform(.next)
            check(g.sheet == 1, "→ shows the first companion's sheet")
            g.perform(.previous); g.perform(.previous)
            check(g.sheet == 2, "← from the Avatar wraps round to the last companion")
            g.perform(.next)
            g.perform(.give(0))
            g.perform(.giveTo(1))
            check(g.pack == [.weapon(.dagger)] && mate.weapon == .axe, "the Avatar gives a companion an axe, which goes into their empty hand")
            g.perform(.give(0)); g.perform(.giveTo(2))
            check(g.pack == [.weapon(.dagger)] && g.messages.last?.contains("can carry no more") == true, "a companion carrying ten things takes no more")
            g.perform(.next)
            g.perform(.give(0)); g.perform(.giveTo(0))
            check(g.weapon == .axe && mate.weapon == nil, "a companion gives the axe back")
            g.perform(.next)
            g.perform(.equip(1))
            check(mate2.weapon == .staff && mate2.pack.first == .weapon(.mace), "companions can be given a different weapon to fight with")
            check(Screen.sheetButtons(g).filter { if case .drop = $0.action { return true }; return false }.count == 10
                  && Screen.sheetButtons(g).allSatisfy { b in Screen.sheetAction(g, atX: b.rect.x + b.rect.w / 2, y: b.rect.y + b.rect.h / 2) == b.action },
                  "every line has its buttons, and a click on each one does what it says")
            let box = Screen.avatarBox
            check(Screen.inside(box, box.x + 10, box.y + 10) && !Screen.inside(box, box.x + 10, box.y + box.h + 2), "the Avatar's box in the panel is where the click opens the sheet")
            g.perform(.close)
            check(g.sheet == nil, "Close puts the sheet away")
            g.openSheet()
            check(!Screen.sheetButtons(g).contains { $0.action == .talk }, "the Avatar's own sheet has no Talk button")
            g.perform(.next)
            check(Screen.sheetButtons(g).contains { $0.action == .talk } && Screen.sheetButtons(g).allSatisfy { b in
                Screen.sheetAction(g, atX: b.rect.x + b.rect.w / 2, y: b.rect.y + b.rect.h / 2) == b.action },
                  "a companion's sheet has a Talk button of its own")
            g.perform(.talk)
            check(g.sheet == nil && g.conversation?.npc === mate, "Talk on a companion's sheet puts it away and talks with them")
            g.endConversation()
            do {
                // A companion greets the Avatar as someone they travel with, never as a stranger met on the road.
                let talks = mate.talks, liking = mate.friendliness
                var asCompanion = Set<String>(), asStranger = Set<String>()
                for f in [-60, -20, 10, 45, 90] {
                    mate.friendliness = f
                    for t in 0..<12 {
                        mate.talks = t
                        mate.following = true; asCompanion.insert(Dialogue.greeting(mate, player: g.playerName).text)
                        mate.following = false; asStranger.insert(Dialogue.greeting(mate, player: g.playerName).text)
                    }
                }
                mate.following = true; mate.talks = talks; mate.friendliness = liking
                check(asCompanion.isDisjoint(with: asStranger) && !asCompanion.contains { $0.contains("well met") || $0.contains("Welcome") },
                      "a companion's greeting is one for a fellow traveller, not a stranger")
            }
            g.talkToCompanion(mate2)
            check(g.conversation?.npc === mate2, "a companion can be talked to wherever they walk (a click on them)")
            g.endConversation()
            g.talkToCompanion(foe)
            check(g.conversation == nil, "only companions are talked to from afar")
            g.combat = Combat(enemies: [foe], order: [nil, foe])
            g.talkToCompanion(mate)
            check(g.conversation == nil && g.messages.last?.contains("no time to talk") == true, "a fight leaves no time to talk")
            g.openSheet(1)
            check(!Screen.sheetButtons(g).contains { $0.action == .talk }, "nor a Talk button on a companion's sheet")
            g.sheet = nil
            g.openSheet()
            check(g.sheet == 0 && Screen.sheetButtons(g).allSatisfy { b in
                if case .drop = b.action { return false }
                if case .give = b.action { return false }
                return true
            }, "in a fight the sheet opens, but with no time to drop or give things")
            g.sheet = nil
            let carried = try? PropertyListDecoder().decode(NPC.self, from: PropertyListEncoder().encode(mate2))
            check(carried?.weapon == .staff && carried?.pack == mate2.pack, "what a companion carries survives a save")
            g.combat = nil
        }
        do {
            // Companions join in; a companion who falls leaves the party.
            let (g, folk) = arena()
            var k = 0
            g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }
            // A foe with room beside them for both the Avatar and the companion.
            func freeBeside(_ n: NPC) -> [(Int, Int)] {
                [(1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)].filter {
                    g.world.isPassable(n.x + $0.0, n.y + $0.1, 0) && g.world.npc(at: n.x + $0.0, n.y + $0.1, 0) == nil
                }
            }
            let foe = folk.dropFirst(2).first { freeBeside($0).count >= 3 } ?? folk[2]
            let friend = folk.first { $0 !== foe }!
            g.addToParty(friend)
            friend.hp = 5; friend.maxHP = 50
            foe.maxHP = 200; foe.hp = 200
            if let (dx, dy) = standBeside(g, foe) {
                g.regroupParty()
                // Put the companion beside the foe so the foe's blows land on it first.
                if let spot = freeBeside(foe).first(where: { (foe.x + $0.0, foe.y + $0.1) != (g.x, g.y) }) {
                    friend.x = foe.x + spot.0; friend.y = foe.y + spot.1
                }
                let before = foe.hp
                g.attack(dx: dx, dy: dy)
                check(g.combat?.order.contains { $0 === friend } == true || !friend.following, "companions join the fight in the round robin")
                check(200 - before + foe.hp <= 0 || foe.hp <= before - 2, "the companion's blows land on the foe too")
                for _ in 0..<6 where g.inCombat && friend.following { g.waitTurn() }
                check(!friend.following && g.party.isEmpty, "a companion who reaches 0 health dies and leaves the party")
            } else { check(false, "found room for the party fight") }
        }
        do {
            // An NPC at -100 beside the Avatar always attacks; the Avatar can die.
            let (g, folk) = arena()
            let foe = folk[3]
            foe.friendliness = -100
            foe.maxHP = 200; foe.hp = 200
            g.roll = { 0.999 }
            if standBeside(g, foe) != nil {
                g.waitTurn()
                check(g.inCombat, "an NPC at -100 standing beside the Avatar always attacks")
                var k = 0
                g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }
                g.hp = 25
                for _ in 0..<5 where !g.gameOver { g.waitTurn() }
                check(g.gameOver && g.hp == 0 && !g.inCombat, "the Avatar at 0 health is slain and the game is over")
                check(!g.move(dx: 1, dy: 0), "nothing more can be done once slain")
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-dead-\(ProcessInfo.processInfo.processIdentifier).plist")
                try? SaveGame.save(g, to: url)
                let fallen = SaveGame.load(from: url)
                check(fallen?.gameOver == true && fallen?.hp == 0, "a slain Avatar's save reopens at the death notice")
                try? FileManager.default.removeItem(at: url)
            } else { check(false, "found room for the ambush") }
        }
        do {
            // Every morning at 8 the world is autosaved; a slain Avatar can rise again from it.
            let (g, _) = arena()
            g.turn = (2 * 24 * 60 + 7 * 60 - 8 * 60) / 2   // 7 AM on day 3
            g.autosavedDay = 2
            check(g.day == 3 && !g.autosaveDue, "no autosave before 8 in the morning")
            g.wait(turns: 30)
            check(g.timeString == "8:00 AM" && g.autosaveDue, "the autosave falls due at 8 AM")
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-autosave-\(ProcessInfo.processInfo.processIdentifier).plist")
            try? SaveGame.autosave(g, to: url)
            check(g.autosavedDay == 3 && !g.autosaveDue, "once saved, the morning is not saved again")
            g.wait(turns: 6 * 30)
            check(!g.autosaveDue, "nor later that day")
            g.wait(turns: 18 * 30)
            check(g.day == 4 && g.timeString == "8:00 AM" && g.autosaveDue, "the next morning is saved again")
            let morningGold = g.gold, morningTurn = g.turn - 24 * 30
            g.gold += 99
            g.hp = 0
            g.gameOver = true
            check(!g.autosaveDue, "a slain Avatar is never autosaved")
            if let back = SaveGame.load(from: url) {
                check(!back.gameOver && back.hp > 0 && back.turn == morningTurn && back.gold == morningGold,
                      "rising again restores the world as it was that morning")
                check(back.autosavedDay == 3 && !back.autosaveDue, "the restored morning is not saved over at once")
            } else { check(false, "the autosave loads") }
            SaveGame.discardAutosave(at: url)
            check(SaveGame.load(from: url) == nil, "a new world discards the old world's autosave")
        }
        do {
            // Rude words that sour someone below 0 can start a fight.
            let (g, folk) = arena()
            let foe = folk[4]
            foe.friendliness = -40
            g.claude = mock
            mock.availableOverride = false
            var dice = 0.0
            g.roll = { dice }
            if standBeside(g, foe) != nil {
                g.startConversation(with: foe)
                for ch in "You stupid fool!" { g.typeInConversation(ch) }
                dice = 0.0
                g.submitConversation()
                check(g.inCombat && g.conversation == nil, "an insult that drops friendliness below 0 can start a fight")
            } else { check(false, "found room for the quarrel") }
        }

        do {
            // Wounds heal with time out of a fight; a retreat can succeed.
            let (g, folk) = arena()
            g.hp = 40
            g.roll = { 0.999 }
            for _ in 0..<200 { g.waitTurn() }
            check(g.hp == 50, "out of a fight the Avatar heals 1 health every 20 turns (40 -> \(g.hp) in 200 turns)")
            // Someone (not one of Draconian's, whose friends would join in) with room beside them.
            var spot: (NPC, (Int, Int))?
            for n in folk.dropFirst(5) where !n.servesDraconian && n.z == 0 {
                if let d = standBeside(g, n) { spot = (n, d); break }
            }
            if let (foe, (dx, dy)) = spot {
                foe.maxHP = 200; foe.hp = 200; foe.friendliness = 50
                g.attack(dx: dx, dy: dy)
                // Step back one pace; a foe who stumbles doesn't follow.
                g.roll = { 0.1 }
                let away = [(-dx, -dy), (-dy, dx), (dy, -dx)].first {
                    g.world.isPassable(g.x + $0.0, g.y + $0.1, 0) && g.world.npc(at: g.x + $0.0, g.y + $0.1, 0) == nil
                }
                if let a = away {
                    let (fx, fy) = (foe.x, foe.y)
                    g.move(dx: a.0, dy: a.1)
                    check(foe.x == fx && foe.y == fy && g.inCombat, "a pursuing foe sometimes falls behind")
                }
                // Out of reach by more than 8 tiles: escaped.
                g.teleport(foe.x + Combat.escapeDistance + 1, foe.y, 0)
                g.waitTurn()
                check(!g.inCombat && !g.gameOver && g.messages.contains("You have escaped."),
                      "leaving a foe more than \(Combat.escapeDistance) tiles behind ends the fight")
                check(foe.build.contains("formidable"), "looking at someone tells how tough they are")
            } else { check(false, "found room to run") }
        }

        // Gold.
        check(Game(seed: seed).gold == 0, "the Avatar starts with no gold")
        var grng = SplitMix64(seed: 31)
        for h in [20, 75, 150] {
            let purses = (0..<5000).map { _ in Populace.coins(forHealth: h, &grng) }
            let m = Double(purses.reduce(0, +)) / Double(purses.count)
            check(abs(m - Double(h) / 10) < 0.25 && Set(purses).count > 3,
                  "a foe with \(h) health carries a random purse averaging \(h / 10) coins (sampled \(String(format: "%.2f", m)))")
        }
        do {
            let (g, folk) = arena()
            let foe = folk[0]
            foe.maxHP = 30; foe.hp = 1; foe.gold = 7
            g.roll = { 0.0 }
            if let (dx, dy) = standBeside(g, foe) {
                g.attack(dx: dx, dy: dy)
                check(foe.hp == 0 && g.gold == 7 && foe.gold == 0, "defeating a foe hands their gold to the Avatar")
            }
        }

        // Lord Draconian's people.
        do {
            let w = World(seed: seed)
            var all: [NPC] = []
            var bands = Set<Int>(), townMercs = 0, wildMercs = 0
            for ry in -8...8 {
                for rx in -8...8 {
                    let r = w.region(RegionKey(x: rx, y: ry, z: 0))
                    all += r.npcs
                    for n in r.npcs {
                        if let b = n.warband { bands.insert(b) }
                        if n.role == "mercenary" { if n.home != nil { townMercs += 1 } else { wildMercs += 1 } }
                    }
                    if r.features.contains(.caveEntrance) { all += w.region(RegionKey(x: rx, y: ry, z: 1)).npcs }
                }
            }
            // Every human has a trade, and goes by it until introduced.
            let humans = all.filter { $0.race == .human }
            let trades = Set(humans.map(\.title))
            check(humans.allSatisfy { !$0.title.isEmpty && $0.title != "human" && $0.shortName == "the \($0.title)" },
                  "every human goes by their trade until introduced (\(trades.count) trades)")
            let peasants = humans.filter { $0.title == "peasant" }
            check(peasants.contains { $0.home?.hasSuffix("Farmhouse") == true } && peasants.contains { $0.home == nil }
                  && humans.contains { $0.title == "townsman" && !$0.female } && humans.contains { $0.title == "townswoman" && $0.female }
                  && !humans.contains { $0.title == "townsperson" },
                  "there are peasants on farms and in the country, and townsmen and townswomen (\(peasants.count) peasants, \(humans.filter { $0.title.hasPrefix("towns") }.count) town folk)")
            let elvenDrinkers = all.filter { $0.race == .elf && $0.role == "drinker" }
            check(all.filter { $0.race != .human && !($0.race == .elf && $0.role == "drinker") }.allSatisfy { $0.shortName == "the \($0.race.name)" },
                  "the other races go by their race")
            check(!elvenDrinkers.isEmpty && elvenDrinkers.allSatisfy { $0.shortName == "the elven drinker" && $0.stranger == "An elven drinker"
                                                                       && $0.description.hasPrefix("an elven drinker") },
                  "elves drinking in taverns are elven drinkers (\(elvenDrinkers.count) of them)")
            // Dwarf bards look like their paintings.
            // Dwarves: all men, none in Draconian's pay (yet some hostile), painted from the
            // ordinary or the warrior set, the warriors armed as painted.
            let dwarves = all.filter { $0.race == .dwarf && !$0.isAdventurer }
            check(!dwarves.isEmpty && dwarves.allSatisfy { !$0.female && !$0.servesDraconian },
                  "dwarves are all men, and none serves Lord Draconian (\(dwarves.count) of them)")
            check(dwarves.contains { Disposition($0.friendliness) == .hostile }, "yet some dwarves are hostile")
            check(dwarves.allSatisfy { n in
                guard let p = Populace.painted(look: n.look) else { return false }
                let set = n.role == "warrior" ? PaintedFolk.dwarfWarriors : PaintedFolk.dwarfFolk
                return set.contains { $0.painting == p.painting } && n.painting == p.painting && (p.weapon == nil || p.weapon == n.weapon)
            }, "every dwarf has an ordinary or, for warriors, a warrior painting, dressed to match on the map")
            let warriors = dwarves.filter { $0.role == "warrior" }
            check(!warriors.isEmpty && Set(warriors.compactMap(\.weapon)).isSuperset(of: [.axe, .hammer]),
                  "dwarf warriors carry the axes and hammers painted (\(warriors.count) of them)")
            check(!PaintedFolk.dwarfWarriors.contains { $0.painting == "dwarf-warrior-3" }, "the dwarf crossbowman waits for bows")
            // Human children are painted from the children, and every painting is there.
            let kids = all.filter { $0.race == .human && $0.role == "child" }
            check(!kids.isEmpty && kids.allSatisfy { n in
                PaintedFolk.humanChildren.contains { $0.painting == n.painting && $0.look.female == n.female }
            }, "human children have children's paintings, boys and girls alike (\(kids.count) of them)")
            check(PaintedFolk.humanChildren.allSatisfy { Portraits.image($0.painting) != nil },
                  "the children's paintings load")
            // A dwarf woman in Draconian's pay, from an older save, becomes a free dwarf warrior.
            let oldDwarf = NPC(id: 4242, name: "Thora", race: .dwarf, female: true, look: 3, friendliness: -50, x: 0, y: 0, z: 0,
                               bounds: [0, 0, 1, 1], role: "mercenary", home: nil)
            oldDwarf.servesDraconian = true
            Populace.paint(oldDwarf)
            check(!oldDwarf.female && !oldDwarf.servesDraconian && oldDwarf.role == "warrior"
                  && PaintedFolk.dwarfWarriors.contains { $0.painting == oldDwarf.painting } && oldDwarf.name != "Thora",
                  "an older save's dwarf woman in Draconian's pay becomes a free dwarf warrior, with a man's name")
            // Adventurers: in towns and in the wilds, of every race, unarmed, painted as adventurers.
            let heroes = all.filter(\.isAdventurer)
            check(heroes.contains { $0.home != nil } && heroes.contains { $0.home == nil }
                  && Set(heroes.map(\.race)) == [.human, .elf, .dwarf, .orc],
                  "adventurers of every race roam the towns (\(heroes.filter { $0.home != nil }.count)) and the wilds (\(heroes.filter { $0.home == nil }.count))")
            check(heroes.allSatisfy { Populace.adventurerFriendliness.contains($0.friendliness) && (50...125).contains($0.maxHP)
                                      && $0.weapon == nil && !$0.servesDraconian },
                  "adventurers' friendliness runs -25 to 25, their health half to one and a quarter times the Avatar's, and none is armed or serves Draconian")
            check(heroes.allSatisfy { n in PaintedFolk.adventurers.contains { $0.painting == n.painting && $0.race == n.race && $0.look.female == n.female } },
                  "every adventurer wears an adventurer's painting of their own race and sex")
            check(PaintedFolk.adventurers.count == 50 && PaintedFolk.adventurers.allSatisfy { Portraits.image($0.painting) != nil },
                  "all 50 adventurer paintings load")
            // Every human but the watch is painted from the town or the country set, by where they live;
            // every elf and orc from their own set.
            let barkeeps = all.filter { $0.race == .human && $0.role == "barkeep" }
            check(!barkeeps.isEmpty && barkeeps.allSatisfy { n in PaintedFolk.barkeepers.contains { $0.painting == n.painting && $0.look.female == n.female } }
                  && PaintedFolk.barkeepers.allSatisfy { Portraits.image($0.painting) != nil },
                  "every human barkeep wears one of the six barkeep paintings, of their own sex (\(barkeeps.count) of them)")
            let everyday = all.filter { !$0.isAdventurer && (($0.race == .human && $0.guardRank == nil && $0.role != "child" && $0.role != "barkeep") || $0.race == .elf || $0.race == .orc) }
            let names: (String) -> Set<String> = { kind in
                Set((kind == "town" ? PaintedFolk.townFolk : kind == "country" ? PaintedFolk.countryFolk : kind == "orc" ? PaintedFolk.orcFolk : PaintedFolk.elfFolk).map(\.painting))
            }
            let isCountry: (NPC) -> Bool = { $0.home.map { $0.hasSuffix("Farmhouse") } ?? true }
            let setOf: (NPC) -> String = { $0.servesDraconian ? "draconian" : $0.race == .elf ? "elf" : $0.race == .orc ? "orc" : isCountry($0) ? "country" : "town" }
            let servantPainting = Dictionary(uniqueKeysWithValues: (PaintedFolk.draconianOrcs + PaintedFolk.draconianElves + PaintedFolk.draconianHumans).map { ($0.painting, $0) })
            check(everyday.filter { setOf($0) != "draconian" }.allSatisfy { n in n.painting.map { names(setOf(n)).contains($0) } ?? false },
                  "every human but the watch, the children and the barkeeps has a town or country painting by where they live, every free elf an elf painting and every free orc an orc painting (\(everyday.count) of them)")
            let hisOrcs = everyday.filter { setOf($0) == "draconian" && $0.race == .orc }
            let hisElves = everyday.filter { setOf($0) == "draconian" && $0.race == .elf }
            let hisHumans = everyday.filter { setOf($0) == "draconian" && $0.race == .human }
            for (race, plural, his) in [("orc", "orcs", hisOrcs), ("elf", "elves", hisElves), ("human", "humans", hisHumans)] {
                check(!his.isEmpty && his.allSatisfy { n in
                    guard let p = n.painting.flatMap({ servantPainting[$0] }), p.painting.hasPrefix("draconian-\(race)-") else { return false }
                    return p.female == n.female && (p.weapon == nil || p.weapon == n.weapon)
                }, "Draconian's \(plural) have their own paintings, of their sex, and carry the weapon painted (\(his.count) of them)")
                let set = PaintedFolk.draconian(Race(rawValue: race)!)!
                check((race == "human" || !set.contains { $0.painting == "draconian-\(race)-3" }) && set.allSatisfy { Portraits.image($0.painting) != nil },
                      "his \(race) paintings load" + (race == "human" ? "" : ", all but the crossbowman"))
            }
            check(Set(hisOrcs.compactMap(\.weapon)).isSuperset(of: [.hammer, .axe, .spear]), "his orcs carry war hammers, axes and spears")
            check(everyday.filter { !$0.servesDraconian }.allSatisfy { n in
                guard let p = Populace.painted(look: n.look) else { return false }
                return p.painting == n.painting && p.look.female == n.female && p.race == n.race && n.portrait == nil
            }, "and their figures on the map are dressed as painted, for their race and sex")
            check(everyday.filter(\.servesDraconian).allSatisfy { [6, 7].contains($0.look) && $0.portrait != nil }
                  && everyday.contains { $0.servesDraconian },
                  "Draconian's humans, elves and orcs keep his livery on the map, with a painting to talk to")
            check(Set(everyday.map(setOf)) == ["town", "country", "elf", "orc", "draconian"], "there are town folk, country folk, elves and orcs")
            check(all.filter { $0.race == .elf && $0.role == "drinker" }.allSatisfy { $0.shortName == "the elven drinker" },
                  "elves drinking in taverns are still elven drinkers")
            // An NPC from an older save, in a plain look, is repainted on loading.
            let old = everyday.first { !$0.servesDraconian }!
            let (kept, lookBefore) = (old.painting, old.look)
            old.look = old.female ? 3 : 0
            Populace.paint(old)
            check(old.look == lookBefore && old.painting == kept, "people from older saves are repainted the same way")
            check(all.filter { $0.role == "peasant" }.allSatisfy { $0.race == .human }, "peasants are all human")
            check(PaintedFolk.all.enumerated().allSatisfy { i, p in Portraits.image(p.painting) != nil
                && SpriteBank.shared.people[p.race.index][Populace.paintedLooks + i][0][0].sprite.w > 1 },
                  "every painted person's painting loads, and each is drawn on the map")
            // The town watch.
            let guards = all.filter { $0.guardRank != nil }
            let ranks = Set(guards.compactMap(\.guardRank))
            check(!guards.isEmpty && guards.allSatisfy { $0.race == .human && $0.home != nil && !$0.servesDraconian && $0.role == GuardArt.title($0.guardRank!, female: $0.female) },
                  "the towns keep a watch of human guards (\(guards.count) in all)")
            check(ranks.count >= 4, "the watch has several ranks (\(ranks.sorted()))")
            check(guards.allSatisfy { Populace.guardHealth[$0.guardRank!].contains($0.maxHP) }, "each guard's health lies in their rank's band")
            let byRank = (0..<GuardArt.ranks).map { r in guards.filter { $0.guardRank == r }.map(\.maxHP) }
            check(zip(byRank, byRank.dropFirst()).allSatisfy { lo, hi in lo.isEmpty || hi.isEmpty || lo.max()! < hi.min()! },
                  "a higher rank is always tougher: \(byRank.map { $0.isEmpty ? "-" : "\($0.min()!)-\($0.max()!)" }.joined(separator: ", "))")
            check((0..<GuardArt.ranks).allSatisfy { r in [false, true].allSatisfy { Portraits.image(Portraits.guardName(rank: r, female: $0)) != nil } },
                  "every rank of the watch has a painted portrait, for a man and a woman")
            check(SpriteBank.shared.people[Race.human.index][Populace.guardLook(rank: 2, female: true)][0][0].sprite.w > 1,
                  "the watch are drawn on the map")
            let servants = all.filter(\.servesDraconian)
            let mercs = servants.filter { $0.race != .orc }
            let orcs = all.filter { $0.race == .orc }
            let theirOrcs = orcs.filter(\.servesDraconian), freeOrcs = orcs.filter { !$0.servesDraconian }
            func mean(_ a: [NPC]) -> Double { Double(a.map(\.friendliness).reduce(0, +)) / Double(max(1, a.count)) }
            check(!mercs.isEmpty && servants.allSatisfy { (-100...0).contains($0.friendliness) },
                  "Draconian's people (\(servants.count) of \(all.count)) are always between -100 and 0")
            check(townMercs > 0 && wildMercs > 0, "his mercenaries are met in towns (\(townMercs)) and the countryside (\(wildMercs))")
            let share = Double(theirOrcs.count) / Double(max(1, orcs.count))
            check(abs(share - 0.75) < 0.06, "about three orcs in four serve him (\(theirOrcs.count) of \(orcs.count))")
            var srng = SplitMix64(seed: 5)
            let sample = (0..<4000).map { _ in Populace.servantFriendliness(.orc, &srng) }
            let sm = Double(sample.reduce(0, +)) / Double(sample.count)
            check(abs(sm + 75) < 3, "his orcs are 50% more unfriendly than other orcs: mean \(String(format: "%.1f", sm)) vs -50 (in the world: \(Int(mean(theirOrcs))) vs \(Int(mean(freeOrcs))))")
            check(!bands.isEmpty && all.filter { $0.warband != nil }.allSatisfy { $0.race == .orc && $0.servesDraconian && $0.home == nil },
                  "roving warbands of his orcs roam the wilds (\(bands.count) bands)")
            // Orcs are a common sight in the wilds: in at least two lands in five.
            let wildOrcLands = (-8...8).flatMap { ry in (-8...8).map { rx in (rx, ry) } }.filter { (rx, ry) in
                w.region(RegionKey(x: rx, y: ry, z: 0)).npcs.contains { $0.race == .orc && $0.home == nil }
            }.count
            check(Double(wildOrcLands) / 289 >= 0.4,
                  "orcs roam the wilds of \(wildOrcLands) of 289 lands (\(all.filter { $0.race == .orc && $0.home == nil }.count) orcs)")
            if let m = mercs.first {
                m.friendliness = -5
                m.changeFriendliness(by: 40)
                check(m.friendliness == 0, "nothing raises his servants above 0")
                check(Party.chance(m.friendliness) == 0, "so they can never be persuaded to join the party")
            }
        }
        do {
            // A servant who attacks brings his fellows within reach into the fight.
            let (g, folk) = arena()
            g.roll = { 0.999 }
            if folk.count >= 3, let (_, _) = standBeside(g, folk[0]) {
                let boss = folk[0], mate = folk[1]
                boss.servesDraconian = true; mate.servesDraconian = true
                boss.friendliness = -100; mate.friendliness = -40
                mate.x = boss.x + 2; mate.y = boss.y
                g.startCombat(against: boss, startedByEnemy: true)
                check(g.combat?.enemies.contains { $0 === mate } == true, "Draconian's servants nearby join a fight together")
                check(g.messages.contains { $0.hasSuffix("cries: \"Thou shalt bow down before Lord Draconian, mighty emperor of Sespooland and Ezerian.\"") },
                      "Draconian's people announce themselves when they attack")
            }
            // ...and when the Avatar attacks them first.
            let (g2, folk2) = arena()
            g2.roll = { 0.999 }
            if folk2.count >= 7, let (dx, dy) = standBeside(g2, folk2[6]) {
                folk2[6].servesDraconian = true
                g2.attack(dx: dx, dy: dy)
                check(g2.messages.suffix(4).contains { $0.contains("cries: \"\(Combat.draconianBattleCry)\"") },
                      "Draconian's people cry out even when the Avatar attacks first")
            }
        }

        do {
            // In a fight, unfriendly onlookers within 3 paces may join in, and close in on the party.
            let (g, folk) = arena()
            var dice = 0.999
            g.roll = { dice }
            for n in g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs { n.servesDraconian = false }   // no servants rallying to the foe
            if folk.count >= 4, standBeside(g, folk[0]) != nil {
                let foe = folk[0]
                foe.friendliness = -100; foe.maxHP = 500; foe.hp = 500
                // Free tiles exactly `d` paces from the Avatar, in the Avatar's region, with the
                // straight step towards the Avatar open (no wall or door in the way).
                let home = g.world.region(containing: g.x, g.y, 0)
                func open(_ px: Int, _ py: Int) -> Bool {
                    g.world.isPassable(px, py, 0) && g.world.npc(at: px, py, 0) == nil && home.contains(px, py)
                        && g.world.feature(px, py, 0) != .door
                }
                func spot(_ d: Int, avoiding taken: [(Int, Int)]) -> (Int, Int)? {
                    for dy in -d...d { for dx in -d...d where max(abs(dx), abs(dy)) == d {
                        let (px, py) = (g.x + dx, g.y + dy)
                        if open(px, py), open(px - dx.signum(), py - dy.signum()), open(px - dx.signum(), py), open(px, py - dy.signum()),
                           !taken.contains(where: { $0 == (px, py) }) { return (px, py) }
                    } }
                    return nil
                }
                let (grim, glad, far) = (folk[1], folk[2], folk[3])
                if let a = spot(3, avoiding: []), let b = spot(3, avoiding: [a]), let c = spot(5, avoiding: [a, b]) {
                    (grim.x, grim.y) = a; (glad.x, glad.y) = b; (far.x, far.y) = c
                    grim.friendliness = -90; glad.friendliness = 20; far.friendliness = -100
                    g.startCombat(against: foe, startedByEnemy: true)
                    check(g.combat?.enemies.count == 1, "onlookers keep out of a fight when the dice say so")
                    dice = 0.5
                    let before = max(abs(grim.x - g.x), abs(grim.y - g.y))
                    g.waitTurn()
                    let enemies = g.combat?.enemies ?? []
                    check(enemies.contains { $0 === grim } && !enemies.contains { $0 === glad } && !enemies.contains { $0 === far },
                          "an unfriendly onlooker within 3 paces joins the fight; a friendly one and one 5 paces off do not")
                    check(g.messages.contains { $0 == "\(grim.shortName.capitalizedFirst) joins the fight!" }, "and the log says so")
                    check(max(abs(grim.x - g.x), abs(grim.y - g.y)) < before, "and they move towards the party at once")
                    check(Combat.ambushChance(-30) > 0 && Combat.ambushChance(0) == 0, "the chance is the ambush chance")
                } else { check(false, "found room for onlookers") }
            }
        }

        do {
            // The town watch within 3 paces helps the Avatar against Draconian's people, and
            // only against them; the party earns no experience from the watch's kills.
            let (g, folk) = arena()
            var dice = 0.999
            g.roll = { dice }
            let guards = folk.filter { $0.guardRank != nil }
            let others = folk.filter { $0.guardRank == nil }
            if guards.count >= 2, others.count >= 2, standBeside(g, others[0]) != nil {
                let foe = others[0], plain = others[1]
                let home = g.world.region(containing: g.x, g.y, 0)
                func spot(_ d: Int, avoiding taken: [(Int, Int)]) -> (Int, Int)? {
                    for dy in -d...d { for dx in -d...d where max(abs(dx), abs(dy)) == d {
                        let (px, py) = (g.x + dx, g.y + dy)
                        func open(_ qx: Int, _ qy: Int) -> Bool {
                            g.world.isPassable(qx, qy, 0) && g.world.npc(at: qx, qy, 0) == nil && home.contains(qx, qy)
                                && g.world.feature(qx, qy, 0) != .door
                        }
                        // With the straight step towards the Avatar open.
                        if open(px, py), open(px - dx.signum(), py - dy.signum()), open(px - dx.signum(), py), open(px, py - dy.signum()),
                           !taken.contains(where: { $0 == (px, py) }) { return (px, py) }
                    } }
                    return nil
                }
                // Every other guard out of the way.
                for k in guards.dropFirst(2) { k.x = g.x + 40; k.y = g.y + 40 }
                let (near, far) = (guards[0], guards[1])
                if let a = spot(3, avoiding: []), let b = spot(5, avoiding: [a]) {
                    (near.x, near.y) = a; (far.x, far.y) = b
                    plain.friendliness = -100
                    let (px, py) = (plain.x, plain.y)
                    plain.x = foe.x; plain.y = foe.y
                    foe.x = g.x + 40; foe.y = g.y + 40
                    g.startCombat(against: plain, startedByEnemy: true)
                    check(g.combat?.allies.isEmpty == true, "the watch keeps out of a quarrel that isn't with Draconian's people")
                    g.combat = nil
                    (foe.x, foe.y) = (plain.x, plain.y)
                    (plain.x, plain.y) = (px, py)
                    plain.friendliness = 50
                    foe.servesDraconian = true; foe.friendliness = -100; foe.maxHP = 500; foe.hp = 500
                    g.startCombat(against: foe, startedByEnemy: true)
                    let allies = g.combat?.allies ?? []
                    check(allies.contains { $0 === near } && !allies.contains { $0 === far },
                          "a guard within 3 paces comes to the Avatar's aid against Draconian's people; one 5 paces off does not")
                    check(g.messages.contains { $0 == "\(near.shortName.capitalizedFirst) comes to your aid!" }, "and the log says so")
                    let before = max(abs(near.x - foe.x), abs(near.y - foe.y))
                    g.waitTurn()
                    check(max(abs(near.x - foe.x), abs(near.y - foe.y)) < before || before <= 1, "the guard closes in on Draconian's servant")
                    let xp = g.experience, purse = g.gold
                    foe.gold = 7; foe.weapon = .axe
                    foe.hp = 1
                    dice = 0
                    g.strike(near, foe)
                    check(foe.hp == 0 && g.experience == xp && g.gold == purse && foe.gold == 7 && foe.weapon != nil,
                          "when the guard lands the killing blow, the party gains no experience and takes no purse or weapon")
                } else { check(false, "found room for the watch") }
            } else { check(false, "a town watch to test") }
        }

        do {
            // Newcomers: the dead are replaced, a place at a time, never past the first roll.
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            let home = g.world.region(RegionKey(x: 0, y: 0, z: 0))
            check(Populace.roster(home, seed: g.world.seed, avatarHealth: g.maxHP).map(\.id) == home.npcs.map(\.id),
                  "a region's first roll of people is the same each time it is drawn up (\(home.npcs.count) people)")
            for ry in -3...3 { for rx in -3...3 { _ = g.world.region(RegionKey(x: rx, y: ry, z: 0)) } }
            g.teleport(g.x + 6 * Region.size, g.y, 0)
            let everyone = { g.world.regions.values.flatMap(\.npcs) }
            let total = everyone().count
            check(g.fillEmptyPlaces(day: 2).isEmpty, "no one comes while no one is missing")
            let all = everyone()
            var gone: [NPC] = []
            gone += all.filter { $0.role == "mercenary" }.prefix(3)
            gone += all.filter { $0.guardRank != nil }.prefix(3)
            gone += all.filter { $0.race == .orc && $0.servesDraconian && $0.role != "mercenary" }.prefix(2)
            gone += all.filter { $0.race == .wolf }.prefix(2)
            gone += all.filter { $0.isAdventurer }.prefix(1)
            gone += all.filter { $0.role == "blacksmith" || $0.role == "barkeep" }.prefix(2)
            let kinds = Set(gone.map { $0.race == .wolf ? "wolf" : $0.guardRank != nil ? "guard" : $0.role })
            check(gone.count >= 8 && kinds.contains("mercenary") && kinds.contains("guard") && kinds.contains("wolf"),
                  "some of everyone to lose (\(gone.count): \(kinds.sorted().joined(separator: ", ")))")
            let goneIDs = Set(gone.map(\.id))
            for r in g.world.regions.values { r.npcs.removeAll { goneIDs.contains($0.id) } }
            var came: [NPC] = [], days: [Int] = []
            for d in 3...90 {
                let c = g.fillEmptyPlaces(day: d)
                came += c; days += c.map { _ in d }
            }
            check(came.count == gone.count && Set(came.compactMap(\.slot)) == goneIDs,
                  "in time every empty place is filled, each just once (\(came.count) of \(gone.count))")
            check(everyone().count == total, "so the land holds as many people as it began with, and no more")
            check(Set(days).count > 2, "they come by ones and twos, a chance each day (days \(days))")
            let was = Dictionary(uniqueKeysWithValues: gone.map { ($0.id, $0) })
            check(came.allSatisfy { n in
                guard let o = was[n.slot ?? -1] else { return false }
                return n.id != o.id && n.race == o.race && n.home == o.home && n.guardRank == o.guardRank
                    && n.servesDraconian == o.servesDraconian && n.warband == o.warband && n.bounds == o.bounds
                    && (o.guardRank != nil || n.role == o.role)
            }, "each newcomer is a stranger of the same kind, living where the one they replace lived")
            check(came.allSatisfy { n in g.world.region(containing: n.x, n.y, n.z).npcs.contains { $0 === n }
                && max(abs(n.x - g.x), abs(n.y - g.y)) >= Game.newcomerClearance },
                  "and arrives in their own region, out of the Avatar's sight")
            if let newcomer = came.first(where: { $0.race != .wolf }) {
                let region = g.world.region(containing: newcomer.x, newcomer.y, 0)
                region.npcs.removeAll { $0 === newcomer }
                g.teleport(newcomer.x, newcomer.y + 1, 0)
                check((100...160).allSatisfy { g.fillEmptyPlaces(day: $0).isEmpty }, "no one arrives where the Avatar would see it")
                g.teleport(g.x + 6 * Region.size, g.y, 0)
                check((161...260).contains { !g.fillEmptyPlaces(day: $0).isEmpty }, "a newcomer's place, emptied, is filled again")
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-newcomers-\(ProcessInfo.processInfo.processIdentifier).plist")
                try? SaveGame.save(g, to: url)
                let back = SaveGame.load(from: url)
                let slots = { (h: Game?) in Set((h?.world.regions.values.flatMap(\.npcs) ?? []).compactMap(\.slot)) }
                check(!slots(g).isEmpty && slots(back) == slots(g), "newcomers keep their places through a save")
                try? FileManager.default.removeItem(at: url)
            } else { check(false, "a newcomer to follow") }
            let watch = Game(seed: seed)
            watch.confirmName(); watch.confirmLook()
            watch.newcomersDay = nil
            watch.welcomeNewcomers()
            check(watch.newcomersDay == watch.day, "the count of days starts on the first turn played")
        }

        do {
            // Storekeepers never start a fight: no ambush, no joining in, no coming to blows
            // over words, however much they hate the Avatar, until the Avatar strikes them.
            let (g, _) = arena()
            let folk = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
            g.roll = { 0 }
            g.claude = mock
            mock.availableOverride = false
            if let smith = folk.first(where: { NPC.storekeepers.contains($0.role) }), let side = standBeside(g, smith) {
                for n in folk where n !== smith { n.x = g.x + 40; n.y = g.y + 40 }
                smith.friendliness = -100
                g.checkAmbush()
                check(g.combat == nil, "a storekeeper who loathes the Avatar, standing beside them, never ambushes them (\(smith.role))")
                g.startConversation(with: smith)
                g.say(.insult)
                check(g.combat == nil, "nor comes to blows over an insult")
                g.endConversation()
                if let other = folk.first(where: { $0 !== smith && $0.guardRank == nil && !NPC.storekeepers.contains($0.role) }) {
                    other.friendliness = -100; other.maxHP = 500; other.hp = 500
                    other.x = g.x - side.0; other.y = g.y - side.1
                    if g.world.isPassable(other.x, other.y, 0) {
                        g.startCombat(against: other, startedByEnemy: true)
                        g.waitTurn()
                        check(g.combat?.enemies.contains { $0 === smith } == false, "nor joins someone else's fight against the Avatar")
                        g.combat = nil
                    }
                    other.x = g.x + 40; other.y = g.y + 40
                }
                smith.maxHP = 500; smith.hp = 500
                g.roll = { 0.999 }
                g.attack(dx: side.0, dy: side.1)
                check(g.combat?.enemies.contains { $0 === smith } == true && smith.struckByAvatar && !smith.keepsThePeace,
                      "attacked, a storekeeper fights back")
                g.combat = nil
                g.roll = { 0 }
                g.checkAmbush()
                check(g.combat != nil, "and once attacked, no longer keeps the peace")
            } else { check(false, "a storekeeper to test") }
        }

        do {
            // No one blocks a doorway: whoever stands before a door steps clear, and someone
            // the Avatar walks into there steps out of the way instead of stopping them to talk.
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            let home = g.world.region(RegionKey(x: 0, y: 0, z: 0))
            for n in home.npcs { n.friendliness = 10; n.servesDraconian = false }
            var found: (door: Point, inner: Point, outer: Point)?
            for b in home.roofed where found == nil {
                for yy in b.y...(b.y + b.h - 1) { for xx in b.x...(b.x + b.w - 1) where found == nil && g.world.feature(xx, yy, 0) == .door {
                    for (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                        let o = Point(x: xx + dx, y: yy + dy), i = Point(x: xx - dx, y: yy - dy)
                        if !b.contains(o.x, o.y), b.contains(i.x, i.y), g.world.isPassable(o.x, o.y, 0), g.world.isPassable(i.x, i.y, 0) {
                            found = (Point(x: xx, y: yy), i, o)
                            break
                        }
                    }
                } }
            }
            if let (door, inner, outer) = found, let blocker = home.npcs.first(where: { $0.guardRank == nil }) {
                for m in home.npcs where m !== blocker && max(abs(m.x - door.x), abs(m.y - door.y)) <= 2 { m.x = g.x + 30; m.y = g.y + 30 }
                (blocker.x, blocker.y) = (outer.x, outer.y)
                g.teleport(inner.x, inner.y, 0)
                g.move(dx: door.x - inner.x, dy: door.y - inner.y)
                check(g.x == door.x && g.y == door.y && g.inDoorway(blocker.x, blocker.y) == false,
                      "someone standing outside a door steps clear as the Avatar comes through it")
                (blocker.x, blocker.y) = (outer.x, outer.y)
                g.move(dx: outer.x - door.x, dy: outer.y - door.y)
                check(g.x == outer.x && g.y == outer.y && g.conversation == nil && !(blocker.x == outer.x && blocker.y == outer.y),
                      "walking into someone in a doorway, they step out of the way rather than stopping the Avatar to talk")
                // Out and about, after a while no one stands in a doorway.
                g.teleport(door.x, door.y, 0)
                g.move(dx: inner.x - door.x, dy: inner.y - door.y)
                var lingering = 0
                for _ in 0..<12 {
                    g.waitTurn()
                    lingering = g.world.npcs(near: g.x, g.y, 0, radius: 18).filter { !$0.following && g.inDoorway($0.x, $0.y) }.count
                }
                check(lingering == 0, "people round about never linger in doorways")
            } else { check(false, "a door to test") }
        }

        do {
            // Wolves: packs in the wilds, 10-50 health, -100 to -50, nothing carried, no talk.
            let w = World(seed: seed)
            var wolves: [NPC] = [], townLands = 0, wolfTownLands = 0
            for ry in -6...6 { for rx in -6...6 {
                let r = w.region(RegionKey(x: rx, y: ry, z: 0))
                let mine = r.npcs.filter { $0.race == .wolf }
                wolves += mine
                if r.places.contains(where: { $0.kind == .town }) { townLands += 1; if !mine.isEmpty { wolfTownLands += 1 } }
            } }
            check(wolves.count >= 30, "wolves roam the wilds (\(wolves.count) of them in 169 lands)")
            check(wolfTownLands == 0 && wolves.allSatisfy { $0.home == nil }, "but never in lands with a town (\(townLands) such lands)")
            check(wolves.allSatisfy { Populace.wolfHealth.contains($0.maxHP) && Populace.wolfFriendliness.contains($0.friendliness) },
                  "every wolf has 10-50 health and friendliness from -100 to -50")
            check(wolves.allSatisfy { $0.weapon == nil && $0.gold == 0 && $0.pack.isEmpty }, "wolves carry no weapon and no gold")
            check(wolves.allSatisfy { a in wolves.contains { $0 !== a && max(abs($0.x - a.x), abs($0.y - a.y)) <= Combat.wolfScent } },
                  "wolves come in packs: every wolf has a packmate close by")
            check(Set(wolves.map(\.maxHP)).count > 10, "their health varies")
            if let wolf = wolves.first {
                wolf.changeFriendliness(by: 80)
                check(wolf.friendliness == -50, "nothing makes a wolf friendlier than -50")
                check(wolf.description == "a wolf" && wolf.armedWith == "its fangs" && wolf.shortName == "the wolf",
                      "a wolf is \"the wolf\", and bites with its fangs")
            }
            // Talking to a wolf is no good; fighting one brings in its pack.
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            var pack: [NPC] = []
            for ry in -6...6 { for rx in -6...6 where pack.isEmpty {
                let r = g.world.region(RegionKey(x: rx, y: ry, z: 0))
                if let a = r.npcs.first(where: { $0.race == .wolf }) {
                    pack = r.npcs.filter { $0.race == .wolf && max(abs($0.x - a.x), abs($0.y - a.y)) <= Combat.wolfScent }
                }
            } }
            if pack.count >= 2, let lead = pack.first, let (dx, dy) = standBeside(g, lead) {
                g.talk()
                _ = (dx, dy)
                check(g.conversation == nil && g.messages.last == "The wolf only growls at you.", "a wolf can't be talked to")
                g.roll = { 0.999 }
                let gold = g.gold
                lead.hp = 1
                g.startCombat(against: lead, startedByEnemy: false)
                let c = g.combat
                check(pack.dropFirst().allSatisfy { m in c?.enemies.contains { $0 === m } == true || m.hp == 0 },
                      "attack one wolf and its pack joins the fight (\(pack.count) wolves)")
                g.roll = { 0.0 }
                if lead.hp > 0 { g.strike(nil, lead) }
                check(lead.hp == 0 && g.gold == gold && !g.messages.contains { $0.contains("gold") && $0.contains("wolf") || $0.hasPrefix("It carried") },
                      "a slain wolf leaves no gold")
                let biter = pack.dropFirst().first!
                g.hp = 100
                g.strike(biter, nil)
                check(g.hp >= 90 && g.hp < 100 && g.messages.last?.hasPrefix("The wolf hits you with its fangs") == true,
                      "a wolf bites for 1-10")
                g.combat = nil
            } else { check(false, "found a wolf pack to meet") }
        }

        do {
            // Trading weapons: shops keep every weapon, merchants a few; 10 gold a point of damage, half back.
            check(Trade.value(.weapon(.longSword)) == 60 && Trade.value(.weapon(.staff)) == 30 && Trade.value(.weapon(.axe)) == 50
                  && Trade.value(.weapon(.hammer)) == 40 && Trade.value(.weapon(.sharpSword)) == 100,
                  "a weapon is worth 10 gold for each point of damage it adds, but a sharp sword 100")
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            g.claude = mock
            mock.availableOverride = false
            var smiths: [NPC] = [], merchants: [NPC] = []
            for ry in -3...3 { for rx in -3...3 {
                let r = g.world.region(RegionKey(x: rx, y: ry, z: 0))
                smiths += r.npcs.filter(Trade.sellsWeapons)
                merchants += r.npcs.filter(Trade.isMerchant)
            } }
            check(!merchants.isEmpty && merchants.allSatisfy { Trade.merchantStock.contains($0.pack.count) },
                  "merchants and pedlars carry 1-5 things to sell (\(merchants.count) of them)")
            check(merchants.contains { Set($0.pack.compactMap(\.weapon)).count < $0.pack.count }, "sometimes the same thing twice")
            if let smith = smiths.first {
                smith.friendliness = 10
                g.gold = 250
                g.startConversation(with: smith)
                check(Screen.showsTrade(g.conversation!) && Screen.talkFields(trading: false, wares: true).trade.w > 0,
                      "talking to a smith, a Trade button shows")
                let f = Screen.talkFields(trading: false, wares: true)
                check(f.say.x + f.say.w < f.trade.x && f.trade.x + f.trade.w <= Screen.talkBox.x + Screen.talkBox.w, "beside the line you type")
                for ch in "What do you have for sale?" { g.typeInConversation(ch) }
                g.submitConversation()
                check(g.shopping && g.shopkeeper === smith, "asking to buy opens the shop")
                let goods = g.wares(smith)
                check(goods.compactMap(\.weapon) == (Trade.sellsSharpSwords(smith) ? Weapon.allCases : Weapon.common).sorted()
                      && goods.first == .weapon(.staff), "a smith sells every weapon, weakest first")
                let sharpShops = smiths.filter(Trade.sellsSharpSwords).count
                check(sharpShops > 0 && sharpShops < smiths.count && smiths.allSatisfy { s in
                    g.wares(s).contains(.weapon(.sharpSword)) == Trade.sellsSharpSwords(s) },
                      "some weapon shops carry sharp swords and some don't (\(sharpShops) of \(smiths.count))")
                var mrng = 0, mswords = 0
                for id in 0..<3000 { for w in Trade.merchantGoods(id: id).compactMap(\.weapon) where w.isSword {
                    mswords += 1; if w == .sharpSword { mrng += 1 } } }
                check(abs(Double(mrng) / Double(max(1, mswords)) - 1.0 / 6) < 0.03,
                      "one in six of the swords merchants carry is sharp (\(mrng) of \(mswords))")
                let ls = goods.firstIndex(of: .weapon(.longSword)) ?? 0
                if let buy = Screen.shopButtons(g).first(where: { $0.shop == .buy(ls) }),
                   let a = Screen.shopAction(g, atX: buy.rect.x + 5, y: buy.rect.y + 5) {
                    g.perform(a)
                } else { check(false, "the Buy button can be clicked (\(Screen.shopButtons(g).map(\.label)))") }
                check(g.gold == 190 && g.weapon == .longSword && smith.friendliness == 11 && g.wares(smith).count == goods.count,
                      "a long sword costs 60, goes into empty hands, pleases the smith by 1, and the shop still has more")
                g.perform(.sell(0))
                check(g.gold == 220 && g.weapon == nil, "and sells back for half: 30")
                g.pack = []
                g.perform(.buy(0)); g.perform(.buy(0)); g.perform(.sell(1))
                check(g.gold == 220 - 60 + 15 && g.carried(0) == 1, "a staff costs 30 and sells for 15")
                g.gold = 30
                g.perform(.buy(ls))
                check(g.gold == 30 && g.shopNotice?.contains("can't afford") == true, "you can't buy what you can't pay for")
                g.gold = 1000
                g.pack = Array(repeating: .weapon(.dagger), count: 9)
                g.perform(.buy(0))
                check(g.gold == 1000 && g.shopNotice?.contains("carry no more") == true, "or more than you can carry")
                g.pack = []; g.weapon = nil
                g.perform(.leave)
                check(!g.shopping && g.conversation != nil, "Done goes back to the conversation")
                g.endConversation()
                smith.friendliness = -20
                g.startConversation(with: smith); g.openShop()
                check(g.askingPrice(.weapon(.longSword), smith) == 64 && g.offerFor(.weapon(.longSword), smith) == 24,
                      "a smith who dislikes you asks more (64 at -20) and pays less (24)")
                check([-100, -50, -29, -20, -10, -9, 0, 40, 49, 50, 70, 100].map { Trade.buybackRate(friendliness: $0) }
                        == [0, 50, 80, 80, 90, 100, 100, 100, 100, 110, 130, 140],
                      "buyback falls 10% for every 10 points below 0 and rises 10% for every 10 above 40")
                check(Trade.buyback(base: 60, friendliness: 0) == 30 && Trade.buyback(base: 60, friendliness: 60) == 36
                      && Trade.buyback(base: 100, friendliness: -50) == 25, "a long sword fetches 30 from a neutral smith, 36 from a fond one")
                check([0, 40, 49, 50, 60, 75, 100].map { Trade.price(base: 60, friendliness: $0) } == [60, 60, 60, 57, 54, 51, 42]
                      && Trade.price(base: 5, friendliness: 100) == 4,
                      "friendly traders give 5% off for every 10 points above 40")
                check([80, 90, 100].allSatisfy { Trade.buyback(base: 60, friendliness: $0) == 42 }
                      && Item.remedies.map(Trade.value).allSatisfy { b in (-50...100).allSatisfy { Trade.buyback(base: b, friendliness: $0) <= Trade.price(base: b, friendliness: $0) } }
                      && (-50...100).allSatisfy { f in (1...10).allSatisfy { Trade.buyback(base: $0 * 10, friendliness: f) <= Trade.price(base: $0 * 10, friendliness: f) } },
                      "buyback stops rising at 80 (42 for a long sword), so it never tops the asking price")
                g.endConversation()
                check(!g.shopping, "leaving the conversation closes the shop")
                smith.friendliness = -60
                g.startConversation(with: smith); g.openShop()
                check(!g.shopping && g.conversation?.lines.last?.text.isEmpty == false, "below -50 a trader won't deal")
                g.endConversation()
                smith.friendliness = 10
                check(AIDialogue.prompt(smith, game: g, history: [], said: "hello").contains("every kind of weapon"), "Claude is told the smith sells weapons")
            } else { check(false, "found a smith") }
            if let m = merchants.first {
                m.friendliness = 10
                let stock = m.pack
                g.gold = 500; g.weapon = nil; g.pack = []
                g.startConversation(with: m); g.openShop()
                check(g.wares(m) == stock, "a merchant sells what they carry")
                g.perform(.buy(0))
                check(m.pack.count == stock.count - 1 && g.carried(0) == 1, "what you buy from a merchant is gone from their pack")
                g.perform(.sell(0))
                check(m.pack.count == stock.count && m.pack.last == stock[0], "and what you sell them goes into it")
                g.endConversation()
            } else { check(false, "found a merchant") }
            if let other = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.first(where: { !Trade.trades($0) && !$0.race.isBeast }) {
                g.startConversation(with: other)
                check(g.conversation.map(Screen.showsTrade) == false, "people who don't trade show no Trade button")
                g.openShop()
                check(!g.shopping, "and have no shop to open")
                g.endConversation()
            }
        }

        do {
            // Remedies: apothecaries and alchemists sell salves (10, heal 50) and ointments (5, heal 25).
            check(Trade.value(.salve) == 10 && Trade.value(.ointment) == 5 && Item.salve.heals == 50 && Item.ointment.heals == 25,
                  "a health salve costs 10 and heals 50; an ointment costs 5 and heals 25")
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            g.claude = mock
            mock.availableOverride = false
            var sellers: [NPC] = [], merchants: [NPC] = [], towns = 0, townsWith = 0
            for ry in -5...5 { for rx in -5...5 {
                let r = g.world.region(RegionKey(x: rx, y: ry, z: 0))
                sellers += r.npcs.filter(Trade.sellsRemedies)
                merchants += r.npcs.filter(Trade.isMerchant)
                if r.places.contains(where: { $0.kind == .town }) {
                    towns += 1
                    if r.places.contains(where: { $0.name.contains("Apothecary") || $0.name.contains("Mortar") || $0.name.contains("Alembic") || $0.name.contains("Alchemy") }) { townsWith += 1 }
                }
            } }
            check(sellers.contains { $0.role == "apothecary" } && sellers.contains { $0.role == "alchemist" } && townsWith > 0 && townsWith < towns,
                  "some towns (\(townsWith) of \(towns)) have an apothecary or an alchemist")
            check(merchants.contains { $0.pack.contains(.salve) || $0.pack.contains(.ointment) } && merchants.contains { $0.pack.contains { $0.weapon != nil } },
                  "merchants carry remedies as well as weapons")
            if let shop = sellers.first {
                shop.friendliness = 10
                g.gold = 100; g.weapon = .dagger; g.pack = []
                g.startConversation(with: shop); g.openShop()
                check(g.shopping && g.wares(shop) == [.ointment, .salve], "an \(shop.role) sells ointments and health salves")
                g.perform(.buy(1)); g.perform(.buy(0)); g.perform(.buy(1))
                check(g.gold == 75 && g.pack == [.salve, .ointment, .salve], "two salves and an ointment cost 25")
                check(!g.buys(.weapon(.dagger), shop) && g.buys(.salve, shop) && !Screen.shopButtons(g).contains { $0.shop == .sell(0) },
                      "they buy remedies, but not weapons")
                g.perform(.sell(2))
                check(g.gold == 77 && g.pack == [.salve, .salve], "and pay half: 2 for an ointment")
                g.endConversation()
                // Using them, from the sheet.
                g.hp = 20
                g.openSheet()
                let use = Screen.sheetButtons(g).first { $0.action == .use(1) }
                check(use?.label == "Use", "a salve on the sheet has a Use button")
                g.perform(.use(1))
                check(g.hp == 70 && g.pack == [.salve], "a health salve heals 50 at once, and is used up")
                g.hp = g.maxHP - 10
                g.perform(.use(1))
                check(g.hp == g.maxHP && g.pack.isEmpty, "no further than whole")
                g.pack = [.ointment]; g.hp = 20
                g.perform(.use(1))
                check(g.hp == 45, "an ointment heals 25")
                g.perform(.close)
                // In a fight, using one takes the turn.
                let foes = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.filter { !Trade.trades($0) }
                if let foe = foes.first {
                    g.pack = [.salve]; g.hp = 20
                    foe.hp = 999; foe.maxHP = 999
                    g.combat = Combat(enemies: [foe], order: [nil, foe])
                    g.roll = { 0.999 }
                    let turn = g.turn
                    g.openSheet()
                    g.perform(.use(1))
                    check(g.hp == 70 && g.sheet == nil && g.turn == turn + 1, "in a fight a salve can be used, which takes your turn")
                    g.combat = nil
                }
                let saved = try? JSONDecoder().decode([Item].self, from: JSONEncoder().encode([Item.salve, .ointment, .weapon(.axe)]))
                check(saved == [.salve, .ointment, .weapon(.axe)], "remedies survive a save")
            } else { check(false, "found an apothecary or alchemist") }
            if let m = merchants.first(where: { $0.pack.contains { $0.heals != nil } }) {
                m.friendliness = 10
                g.gold = 100; g.weapon = .dagger; g.pack = []
                g.startConversation(with: m); g.openShop()
                check(g.buys(.weapon(.dagger), m) && g.buys(.salve, m), "a merchant buys weapons and remedies alike")
                let i = m.pack.firstIndex { $0.heals != nil }!, item = m.pack[i]
                g.perform(.buy(i))
                check(g.gold == 100 - Trade.value(item), "and sells remedies at the same prices")
                g.endConversation()
            }
        }

        do {
            // Experience: a tenth of a slain foe's health, rounded up, for everyone in the party.
            check(Experience.award(forHealth: 8) == 1 && Experience.award(forHealth: 10) == 1 && Experience.award(forHealth: 11) == 2
                  && Experience.award(forHealth: 200) == 20, "a foe is worth a tenth of their health in experience, rounded up")
            check(Experience.healthGained(99) == 0 && Experience.healthGained(100) == 1 && Experience.healthGained(209) == 1
                  && Experience.healthGained(210) == 2 && Experience.healthGained(330) == 2 && Experience.healthGained(331) == 3,
                  "the first point of health takes 100 experience, the second 210 in all, the third 331")
            check((1..<12).allSatisfy { abs(Double(Experience.step($0)) / Double(Experience.step($0 - 1)) - 1.1) < 0.01 },
                  "each point needs 10% more experience than the last")
            let g = Game(seed: seed)
            g.confirmName(); g.confirmLook()
            let folk = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.filter { !$0.servesDraconian && $0.guardRank == nil }
            if folk.count >= 3, let (dx, dy) = standBeside(g, folk[0]) {
                let foe = folk[0], mate = folk[2]
                g.addToParty(mate)
                mate.experience = 95
                let mateMax = mate.maxHP, mateHP = mate.hp
                g.experience = 90
                foe.maxHP = 95; foe.hp = 1; foe.friendliness = 50
                g.roll = { 0.0 }
                g.attack(dx: dx, dy: dy)
                check(foe.hp == 0 && g.experience == 100 && g.maxHP == 101 && g.hp == 101,
                      "slaying a 95-health foe earns 10 experience; at 100 the Avatar gains a point of health")
                check(mate.experience == 105 && mate.maxHP == mateMax + 1 && mate.hp == mateHP + 1, "companions earn it too")
                g.combat = nil
                g.removeFromParty(mate, lockOut: false)
                let saved = try? PropertyListDecoder().decode(NPC.self, from: PropertyListEncoder().encode(mate))
                check(saved?.experience == 105, "a companion's experience survives a save")
            } else { check(false, "found a foe and a companion") }
        }

        // Keys reach the game the same way they do in the window.
        let keyGame = Game(seed: seed)
        let view = GameView(game: keyGame)
        check(keyGame.nameEntry == "", "a new game asks for the character's name")
        func press(_ code: UInt16, _ chars: String = "") {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                            context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                            isARepeat: false, keyCode: code) {
                    type == .keyDown ? view.keyDown(with: e) : view.keyUp(with: e)
                }
            }
        }
        let (nx, ny) = (keyGame.x, keyGame.y)
        press(124)
        check(keyGame.x == nx && keyGame.y == ny, "the Avatar can't walk while the name is being asked")
        for (code, ch) in [(45, "n"), (14, "e"), (17, "t"), (17, "t"), (4, "h"), (51, ""), (34, "i"), (11, "b")] { press(UInt16(code), ch) }
        press(36, "\r")
        check(keyGame.playerName == "Nettib" && keyGame.nameEntry == nil, "typing a name and pressing Return names the Avatar")
        press(124)
        check(keyGame.x == nx && keyGame.y == ny && keyGame.lookEntry == 1, "an arrow moves the highlight over the portraits instead of walking")
        press(125)
        check(keyGame.lookEntry == 6, "down moves from the men to the women")
        press(123); press(123)
        check(keyGame.lookEntry == 9, "left wraps around within the row")
        press(36, "\r")
        check(keyGame.female && keyGame.avatarLook == 4 && !keyGame.creatingCharacter, "Return takes the highlighted choice")
        let (kx, ky, kturn) = (keyGame.x, keyGame.y, keyGame.turn)
        for code: UInt16 in [124, 125, 123, 126] { press(code) }   // right, down, left, up
        check(keyGame.turn > kturn, "arrow keys walk the Avatar")
        check(abs(keyGame.x - kx) <= 1 && abs(keyGame.y - ky) <= 1, "each arrow press is a single step")
        keyGame.endConversation()   // (in case a step bumped into someone)
        press(46, "m")
        check(keyGame.showMap, "M opens the map")
        press(46, "m")
        press(4, "h")
        check(keyGame.showHelp && !keyGame.showMap, "H opens help, M closes the map")

        // Save, reload and compare.
        game.weapon = .dagger
        game.pack = [.weapon(.staff), .weapon(.axe), .salve]
        game.experience = 345
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-selftest-\(ProcessInfo.processInfo.processIdentifier).plist")
        do {
            try SaveGame.save(game, to: url)
            let loaded = SaveGame.load(from: url)
            check(loaded != nil, "save file loads")
            if let loaded {
                check(loaded.world.regions.count == game.world.regions.count, "all regions survive a save")
                let r = loaded.world.region(target)
                check(r.terrain == east.terrain && r.features == east.features && r.name == east.name,
                      "a saved region reloads identically")
                check(loaded.world.region(RegionKey(x: 0, y: 0, z: 0)).places.filter { $0.roof != nil }.count
                      == home.places.filter { $0.roof != nil }.count, "roofs survive a save")
                check(loaded.x == game.x && loaded.y == game.y, "the Avatar's position is restored")
                let saved = home.npcs, back = loaded.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
                check(saved.count == back.count && zip(saved, back).allSatisfy { $0.friendliness == $1.friendliness && $0.x == $1.x && $0.name == $1.name },
                      "people, where they stand and how they feel survive a save")
                check(loaded.playerName == game.playerName && !loaded.creatingCharacter, "the name is restored without asking again")
                check(loaded.female == game.female && loaded.avatarLook == game.avatarLook && loaded.avatarLook == 3,
                      "how the Avatar looks survives a save")
                check(loaded.weapon == game.weapon && loaded.pack == game.pack, "the Avatar's weapon and belongings survive a save")
                check(loaded.experience == 345, "the Avatar's experience survives a save")
                check(zip(saved, back).allSatisfy { $0.weapon == $1.weapon }, "what people carry survives a save")
            }
        } catch {
            check(false, "save succeeds (\(error))")
        }
        return ok
    }

    /// Breadth-first route of single steps to the nearest tile satisfying `goal`.
    private static func route(_ world: World, from start: (Int, Int), goal: (Int, Int) -> Bool,
                              throughGoal: Bool = false) -> [(Int, Int)]? {
        let s = Point(x: start.0, y: start.1)
        var came: [Point: Point] = [s: s]
        var queue = [s]
        var i = 0
        while i < queue.count && i < 60000 {
            let c = queue[i]; i += 1
            if goal(c.x, c.y) {
                var steps: [(Int, Int)] = []
                var p = c
                while p != s { let q = came[p]!; steps.append((p.x - q.x, p.y - q.y)); p = q }
                return steps.reversed()
            }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = Point(x: c.x + dx, y: c.y + dy)
                guard came[n] == nil, abs(n.y - start.1) < 90, abs(n.x - start.0) < 90, world.isPassable(n.x, n.y, 0),
                      world.npc(at: n.x, n.y, 0) == nil || (throughGoal && goal(n.x, n.y)),
                      world.feature(n.x, n.y, 0) != .caveEntrance else { continue }
                came[n] = c
                queue.append(n)
            }
        }
        return nil
    }

    private static func reachable(_ world: World, from start: (Int, Int), toBuilding p: Place) -> Bool {
        var seen: Set<Point> = [Point(x: start.0, y: start.1)]
        var queue = [Point(x: start.0, y: start.1)]
        var i = 0
        while i < queue.count {
            let c = queue[i]; i += 1
            if p.contains(c.x, c.y) && world.feature(c.x, c.y, 0) != .door { return true }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let n = Point(x: c.x + dx, y: c.y + dy)
                guard abs(n.x - start.0) < 70, abs(n.y - start.1) < 70, !seen.contains(n),
                      world.isPassable(n.x, n.y, 0), world.feature(n.x, n.y, 0) != .caveEntrance else { continue }
                seen.insert(n)
                queue.append(n)
            }
        }
        return false
    }
}

extension DevTools {
    /// Fights many duels with the real combat code: the Avatar walks up to a random
    /// townsman or townswoman, attacks, and keeps striking until someone falls.
    static func duels(seed: UInt64, count: Int, chain: Bool, walkTurns: Int = 0, pickFights: Bool = false) {
        ClaudeClient.shared.availableOverride = false
        var wins = 0, losses = 0, hpLeft = 0, rounds = 0, streaks: [Int] = []
        var streak = 0
        var game = Game(seed: seed)
        game.confirmName(); game.confirmLook()
        for i in 0..<count {
            if !chain || game.gameOver {
                if chain { streaks.append(streak); streak = 0 }
                game = Game(seed: seed &+ UInt64(i))
                game.confirmName(); game.confirmLook()
            }
            // Time passes between fights (about the walk to the next foe).
            if chain {
                let before = game.hp
                for _ in 0..<walkTurns where !game.inCombat { game.waitTurn() }
                _ = before
            }
            let folk = game.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs.filter { $0.hp > 0 }
            guard let foe = folk.randomElement() else { continue }
            foe.maxHP = Populace.health(Double.random(in: 0..<1)); foe.hp = foe.maxHP
            if pickFights && foe.maxHP >= 80 { continue }   // a player who looks first avoids sturdy foes
            var placed = false
            for (dx, dy) in [(0, 1), (1, 0), (-1, 0), (0, -1)] where game.world.isPassable(foe.x + dx, foe.y + dy, 0)
                && game.world.npc(at: foe.x + dx, foe.y + dy, 0) == nil {
                game.teleport(foe.x + dx, foe.y + dy, 0)
                game.attack(dx: -dx, dy: -dy)
                placed = true
                break
            }
            guard placed else { continue }
            var n = 0
            while game.inCombat && !game.gameOver && n < 500 {
                n += 1
                let dx = (foe.x - game.x).signum(), dy = (foe.y - game.y).signum()
                if max(abs(foe.x - game.x), abs(foe.y - game.y)) <= 1 { game.attack(dx: dx, dy: dy) } else { game.waitTurn() }
            }
            rounds += n
            if game.gameOver { losses += 1 } else { wins += 1; hpLeft += game.hp; streak += 1 }
        }
        print("duels: \(wins) won, \(losses) lost; average health left after a win \(wins > 0 ? hpLeft / wins : 0); average rounds \(rounds / max(1, count))")
        if chain { print("fights survived in a row before dying: \(streaks.isEmpty ? "-" : String(Double(streaks.reduce(0, +)) / Double(streaks.count)))") }
    }
}
