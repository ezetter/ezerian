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
            if token.hasPrefix("type:") {
                for ch in token.dropFirst(5).replacingOccurrences(of: "_", with: " ") { game.typeInConversation(ch) }
                continue
            }
            if token == "send" { game.submitConversation(); continue }
            if token == "warband" || token == "mercenary" {
                // Stand a few paces from the nearest warband orc (or mercenary).
                var best: NPC?
                for ry in -4...4 {
                    for rx in -4...4 {
                        for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs
                        where token == "warband" ? n.warband != nil : n.role == "mercenary" {
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
            if token.hasPrefix("npc:"), let race = Race(rawValue: String(token.dropFirst(4))) {
                // Stand beside the nearest NPC of a race, facing them.
                var best: NPC?
                for ry in -2...2 {
                    for rx in -2...2 {
                        for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs where n.race == race {
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
        for d in Direction.allCases { for s in 0..<3 { arts.append(("avatar", bank.avatar[d.rawValue][s])) } }
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
        if !options.contains("name") { game.confirmName() } else { game.nameEntry = "Iola" }
        walk(game, script)
        if let hour {
            let target = Int(hour * 60)
            game.wait(turns: floorMod(target - game.minutes, 24 * 60) / 2)
        }
        game.showMap = options.contains("map")
        game.showGrid = options.contains("grid")
        game.showHelp = options.contains("help")
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
        game.confirmName()
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
        let avatar = bank.avatar[Direction.south.rawValue][0]
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
        // Never touch the real keychain (or network) from tests.
        ClaudeClient.shared.availableOverride = false
        let game = Game(seed: seed)
        game.nameEntry = "Iolanthe"
        game.confirmName()
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

        // Walk (by pathfinding) into a neighbouring region, then back to where we started.
        let startX = game.x, startY = game.y
        var target = RegionKey(x: 1, y: 0, z: 0)
        for (nx, ny) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let path = route(game.world, from: (game.x, game.y), goal: { x, y in
                floorDiv(x, Region.size) == nx && floorDiv(y, Region.size) == ny
            })
            guard let path else { continue }
            target = RegionKey(x: nx, y: ny, z: 0)
            for (dx, dy) in path { game.move(dx: dx, dy: dy) }
            break
        }
        check(game.regionKey == target, "walked across a border into region (\(target.x),\(target.y))")
        let east = game.world.region(target)
        let generatedBefore = generated.count
        if let path = route(game.world, from: (game.x, game.y), goal: { x, y in x == startX && y == startY }) {
            for (dx, dy) in path { game.move(dx: dx, dy: dy) }
        }
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
        for race in Race.allCases {
            let samples = (0..<4000).map { _ in Populace.friendliness(race, &rng) }
            let mean = Double(samples.reduce(0, +)) / Double(samples.count)
            check(abs(mean - Double(race.meanFriendliness)) < 3,
                  "\(race.name)s average a friendliness of \(race.meanFriendliness) (sampled \(String(format: "%.1f", mean)))")
        }
        var seen = Set<Race>()
        for ry in -2...2 { for rx in -2...2 { for n in game.world.region(RegionKey(x: rx, y: ry, z: 0)).npcs { seen.insert(n.race) } } }
        check(seen.count == 4, "all four races live in the lands around home (\(seen.map(\.name).sorted().joined(separator: ", ")))")

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
        }
        game.claude = ClaudeClient.shared

        // The party.
        check(Party.chance(0) == 0 && Party.chance(-40) == 0 && Party.chance(100) == 1
              && Party.chance(30) < Party.chance(60) && Party.chance(1) > 0,
              "joining: no chance at friendliness 0 or below, rising with friendliness, certain at 100")
        game.endConversation()
        let partyTest = Game(seed: seed)
        partyTest.confirmName()
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
        if townsfolk.count >= 5 {
            let a = townsfolk[0], b = townsfolk[1], c = townsfolk[2], d = townsfolk[3], e = townsfolk[4]
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
            // Following.
            partyTest.teleport(partyTest.x, partyTest.y, 0)
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
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-party.plist")
            partyTest.endConversation()
            try? SaveGame.save(partyTest, to: url)
            let back = SaveGame.load(from: url)
            check(back?.party.map(\.name) == partyTest.party.map(\.name) && back?.party.allSatisfy(\.following) == true,
                  "the party survives a save")
        } else {
            check(false, "enough townsfolk to test the party")
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
            g.confirmName()
            let folk = g.world.region(RegionKey(x: 0, y: 0, z: 0)).npcs
            for n in folk { n.friendliness = 50 }
            return (g, folk)
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
                      "each landed blow reports the foe's remaining health")
                check(g.hp <= hpBefore.0 - 1, "the foe strikes back on their turn")
                g.move(dx: dx, dy: dy)
                check(foe.hp == 0 && !g.inCombat && !folk.contains { $0 === foe && g.world.npc(at: $0.x, $0.y, 0) === foe },
                      "a foe at 0 health dies, and the fight ends")
            } else { check(false, "found room to fight") }
        }
        do {
            // Companions join in; a companion who falls leaves the party.
            let (g, folk) = arena()
            var k = 0
            g.roll = { k += 1; return k % 2 == 1 ? 0.0 : 0.99 }
            let friend = folk[1], foe = folk[2]
            g.addToParty(friend)
            friend.hp = 5; friend.maxHP = 50
            foe.maxHP = 200; foe.hp = 200
            if let (dx, dy) = standBeside(g, foe) {
                g.regroupParty()
                // Put the companion beside the foe so the foe's blows land on it first.
                for (ex, ey) in [(1, 1), (-1, 1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let px = foe.x + ex, py = foe.y + ey
                    if g.world.isPassable(px, py, 0), g.world.npc(at: px, py, 0) == nil, (px, py) != (g.x, g.y) {
                        friend.x = px; friend.y = py
                        break
                    }
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
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-dead.plist")
                try? SaveGame.save(g, to: url)
                check(SaveGame.load(from: url) == nil, "a slain Avatar's save is not resumed")
            } else { check(false, "found room for the ambush") }
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
            for _ in 0..<20 { g.waitTurn() }
            check(g.hp == 50, "out of a fight the Avatar heals 1 health every 2 turns (40 -> \(g.hp) in 20 turns)")
            let foe = folk[5]
            foe.maxHP = 200; foe.hp = 200; foe.friendliness = 50
            if let (dx, dy) = standBeside(g, foe) {
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
            } else { check(false, "found room to run") }
            check(foe.build.contains("formidable"), "looking at someone tells how tough they are")
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
            let servants = all.filter(\.servesDraconian)
            let mercs = servants.filter { $0.race != .orc }
            let orcs = all.filter { $0.race == .orc }
            let theirOrcs = orcs.filter(\.servesDraconian), freeOrcs = orcs.filter { !$0.servesDraconian }
            func mean(_ a: [NPC]) -> Double { Double(a.map(\.friendliness).reduce(0, +)) / Double(max(1, a.count)) }
            check(!mercs.isEmpty && servants.allSatisfy { (-100...0).contains($0.friendliness) },
                  "Draconian's people (\(servants.count) of \(all.count)) are always between -100 and 0")
            check(townMercs > 0 && wildMercs > 0, "his mercenaries are met in towns (\(townMercs)) and the countryside (\(wildMercs))")
            let share = Double(theirOrcs.count) / Double(max(1, orcs.count))
            check(abs(share - 0.5) < 0.08, "about half of all orcs serve him (\(theirOrcs.count) of \(orcs.count))")
            var srng = SplitMix64(seed: 5)
            let sample = (0..<4000).map { _ in Populace.servantFriendliness(.orc, &srng) }
            let sm = Double(sample.reduce(0, +)) / Double(sample.count)
            check(abs(sm + 75) < 3, "his orcs are 50% more unfriendly than other orcs: mean \(String(format: "%.1f", sm)) vs -50 (in the world: \(Int(mean(theirOrcs))) vs \(Int(mean(freeOrcs))))")
            check(!bands.isEmpty && all.filter { $0.warband != nil }.allSatisfy { $0.race == .orc && $0.servesDraconian && $0.home == nil },
                  "roving warbands of his orcs roam the wilds (\(bands.count) bands)")
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
            }
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
        let (kx, ky, kturn) = (keyGame.x, keyGame.y, keyGame.turn)
        for code: UInt16 in [124, 125, 123, 126] { press(code) }   // right, down, left, up
        check(keyGame.turn > kturn, "arrow keys walk the Avatar")
        check(abs(keyGame.x - kx) <= 1 && abs(keyGame.y - ky) <= 1, "each arrow press is a single step")
        press(46, "m")
        check(keyGame.showMap, "M opens the map")
        press(46, "m")
        press(4, "h")
        check(keyGame.showHelp && !keyGame.showMap, "H opens help, M closes the map")

        // Save, reload and compare.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ezerian2-selftest.plist")
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
                check(loaded.playerName == game.playerName && loaded.nameEntry == nil, "the name is restored without asking again")
            }
        } catch {
            check(false, "save succeeds (\(error))")
        }
        return ok
    }

    /// Breadth-first route of single steps to the nearest tile satisfying `goal`.
    private static func route(_ world: World, from start: (Int, Int), goal: (Int, Int) -> Bool) -> [(Int, Int)]? {
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
    /// townsperson, attacks, and keeps striking until someone falls.
    static func duels(seed: UInt64, count: Int, chain: Bool, walkTurns: Int = 0, pickFights: Bool = false) {
        ClaudeClient.shared.availableOverride = false
        var wins = 0, losses = 0, hpLeft = 0, rounds = 0, streaks: [Int] = []
        var streak = 0
        var game = Game(seed: seed)
        game.confirmName()
        for i in 0..<count {
            if !chain || game.gameOver {
                if chain { streaks.append(streak); streak = 0 }
                game = Game(seed: seed &+ UInt64(i))
                game.confirmName()
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
