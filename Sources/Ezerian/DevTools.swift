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
