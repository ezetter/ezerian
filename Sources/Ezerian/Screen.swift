import Foundation
import simd

/// Composes the whole 960x540 game screen: the framed map view, the side panel
/// (portrait, sky, whereabouts and the message scroll) and the overlays. Pixel art
/// goes in `fb`; words go in `texts`, to be set in real fonts on top.
final class Screen {
    static let width = 960
    static let height = 540
    static let mapX = 12
    static let mapY = 12
    static let panelX = 700
    static let panelW = 248

    let fb = Framebuffer(width: Screen.width, height: Screen.height)
    private(set) var map: MapRenderer
    private(set) var texts: [TextItem] = []
    private lazy var backdrop: [UInt32] = makeBackdrop()
    private let parchment: Canvas
    private var frameCount = 0

    private let gold = rgb(0xD8B050), goldDark = rgb(0x6A4A14), goldLight = rgb(0xF8E8A0)
    static let ink: UInt32 = 0xEADFC4, dim: UInt32 = 0xA89A7E, accent: UInt32 = 0xF2D27A, brown: UInt32 = 0x3A2412

    init(world: World) {
        map = MapRenderer(world: world)
        var rng = SplitMix64(seed: 41)
        let f = fbmField(&rng, [4, 8, 16, 32, 64], [1, 0.6, 0.4, 0.3, 0.2])
        var p = Canvas(256, hex(0xE6D3A8))
        for i in 0..<65536 { p.c[i] = mix(hex(0xC8AE7C), hex(0xF0E2BE), f[i]) }
        for _ in 0..<1600 { p.blend(rng.int(256), rng.int(256), hex(0x9A7A4A), 0.35) }
        parchment = p
    }

    /// Starts afresh with another world (a new game).
    func attach(_ world: World) { map = MapRenderer(world: world) }

    var mapPixelWidth: Int { MapRenderer.pixelW }
    var mapPixelHeight: Int { MapRenderer.pixelH }

    func render(_ game: Game, pose: AvatarPose, npcT: Double = 1, frame: Int, clock: Double) -> Framebuffer {
        texts.removeAll(keepingCapacity: true)
        fb.pixels = backdrop
        if game.showMap {
            drawOverview(game, frame: frame)
        } else {
            map.draw(game, pose: pose, npcT: npcT, into: fb, at: Screen.mapX, Screen.mapY, frame: frame, clock: clock)
        }
        frameCount = frame
        if !game.showMap, game.inCombat { drawCombat(game, pose: pose) }
        if let c = game.conversation, !game.showMap { drawConversation(c, game) }
        if game.gameOver { drawGameOver(game) }
        if game.showHelp { drawHelp() }
        if let entry = game.nameEntry { drawNamePrompt(entry, frame: frame) }
        if let chosen = game.lookEntry { drawLookPrompt(game.playerName, chosen: chosen) }
        drawPanel(game, frame: frame)
        let hint = game.showMap ? "M or Esc closes the map  ·  + and − zoom"
            : game.gameOver ? "Press Return to begin a new adventure"
            : game.attackPending ? "Press a direction to attack  ·  Esc to cancel"
            : game.inCombat ? "Your turn: walk into a foe to strike  ·  F + direction attack  ·  Space wait  ·  walk away to flee"
            : game.conversation.map { $0.price != nil && !$0.over } == true
                ? "Type what you say  ·  Tab or click between words and gold  ·  Return or Give gold. to pay  ·  Esc to leave"
            : game.conversation != nil ? "Type what you say  ·  Return to say it  ·  Esc to leave"
            : "Arrows walk  ·  T talk  ·  F fight  ·  Space wait  ·  L look  ·  M map  ·  H help"
        texts.append(TextItem(text: hint, x: Double(Screen.mapX + 4), y: 502, size: 12, color: Screen.dim))
        return fb
    }

    // MARK: Chrome

    private func makeBackdrop() -> [UInt32] {
        let bg = Framebuffer(width: Screen.width, height: Screen.height)
        var rng = SplitMix64(seed: 99)
        let f = fbmField(&rng, [8, 16, 32, 64], [1, 0.6, 0.4, 0.3])
        for y in 0..<Screen.height {
            for x in 0..<Screen.width {
                // Dark carved wood, a little lighter towards the middle.
                let g = f[(y & 255) * 256 + (x & 255)]
                let grain = 0.5 + 0.5 * sin(Float(y) * 0.9 + g * 7)
                var c = mix(hex(0x1A120C), hex(0x33241A), g * 0.7 + grain * 0.3)
                let vx = Float(x) / Float(Screen.width) - 0.5, vy = Float(y) / Float(Screen.height) - 0.5
                c *= 1 - (vx * vx + vy * vy) * 0.6
                bg.pixels[y * Screen.width + x] = pack(c)
            }
        }
        let old = fb.pixels
        fb.pixels = bg.pixels
        gild(Screen.mapX, Screen.mapY, MapRenderer.pixelW, MapRenderer.pixelH, thick: true)
        let out = fb.pixels
        fb.pixels = old
        return out
    }

    /// A gilded frame drawn just outside the rectangle.
    private func gild(_ x: Int, _ y: Int, _ w: Int, _ h: Int, thick: Bool = false) {
        let rings: [UInt32] = thick
            ? [rgb(0x0A0604), goldDark, gold, goldLight, gold, goldDark, rgb(0x0A0604)]
            : [rgb(0x0A0604), goldDark, gold, goldDark]
        for (k, c) in rings.enumerated() {
            let d = rings.count - k
            fb.fill(x - d, y - d, w + 2 * d, 1, c)
            fb.fill(x - d, y + h + d - 1, w + 2 * d, 1, c)
            fb.fill(x - d, y - d, 1, h + 2 * d, c)
            fb.fill(x + w + d - 1, y - d, 1, h + 2 * d, c)
        }
        if thick {
            for (cx, cy) in [(x - 4, y - 4), (x + w + 3, y - 4), (x - 4, y + h + 3), (x + w + 3, y + h + 3)] {
                fb.fill(cx - 3, cy - 3, 7, 7, goldDark)
                fb.fill(cx - 2, cy - 2, 5, 5, gold)
                fb.fill(cx - 1, cy - 1, 3, 3, goldLight)
            }
        }
    }

    /// A dark leather box with a gold rim.
    private func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        for yy in y..<(y + h) {
            for xx in x..<(x + w) {
                let n = Float(Hash.unit(3, xx, yy)) * 0.08
                fb.pixels[yy * Screen.width + xx] = pack(hex(0x241A12) * (0.92 + n + Float(yy - y) / Float(h) * -0.12))
            }
        }
        gild(x, y, w, h)
    }

    private func parchmentBox(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        for yy in 0..<h {
            for xx in 0..<w {
                // Darker towards the edges, like old paper.
                let ex = Float(min(xx, w - 1 - xx)), ey = Float(min(yy, h - 1 - yy))
                let edge = smoothstep(0, 14, min(ex, ey))
                let c = parchment[xx + x * 3, yy + y * 5] * (0.72 + 0.28 * edge)
                fb.pixels[(y + yy) * Screen.width + x + xx] = pack(c)
            }
        }
        gild(x, y, w, h)
    }

    // MARK: Side panel

    private func drawPanel(_ game: Game, frame: Int) {
        let px = Screen.panelX, pw = Screen.panelW
        let cx = Double(px + pw / 2)

        box(px, 12, pw, 60)
        texts.append(TextItem(text: "The Land of", x: cx, y: 15, size: 12, font: .title, color: Screen.dim, align: .center))
        texts.append(TextItem(text: "Ezerian", x: cx, y: 26, size: 31, font: .title, color: Screen.accent, align: .center))

        drawSky(game, x: px, y: 80, w: pw, h: 28)

        box(px, 116, pw, 90)
        drawPortrait(Portraits.avatarName(female: game.female, look: game.avatarLook), px + 8, 122)
        let tx = Double(px + 86)
        texts.append(TextItem(text: game.nameEntry == nil ? game.playerName : "Avatar", x: tx, y: 120, size: 20,
                              font: .title, color: Screen.accent))
        texts.append(TextItem(text: "Health \(game.hp) / \(game.maxHP)", x: tx, y: 146, size: 12, font: .bold,
                              color: healthInk(game.hp, game.maxHP)))
        healthBar(Int(tx), 163, pw - 98, 6, game.hp, game.maxHP)
        texts.append(TextItem(text: "Gold \(game.gold)", x: Double(px + pw - 10), y: 146, size: 12, font: .bold,
                              color: 0xF0C850, align: .right))
        texts.append(TextItem(text: "Day \(game.day)  ·  \(game.timeString)", x: tx, y: 172, size: 12.5, color: Screen.ink))
        texts.append(TextItem(text: timeOfDay(game.hourOfDay), x: tx, y: 188, size: 11, font: .italic, color: Screen.dim))
        texts.append(TextItem(text: game.weapon.map { "\($0.name.capitalizedFirst) +\($0.bonus)" } ?? "Bare hands",
                              x: Double(px + pw - 10), y: 188, size: 11, font: .bold, color: game.weapon == nil ? Screen.dim : Screen.ink,
                              align: .right))

        box(px, 214, pw, 72)
        let places = game.currentPlaces
        let regionName = capitalized(game.region.name)
        var y = 218.0
        for line in TextRenderer.wrap(regionName, width: Double(pw - 16), size: 13, font: .italic).prefix(2) {
            texts.append(TextItem(text: line, x: Double(px + 8), y: y, size: 13, font: .italic, color: Screen.ink))
            y += 16
        }
        let here = places.building?.name ?? places.town.map { "Town of \($0.name)" } ?? places.landmark.map { capitalized($0.name) }
        if let here, !game.isUnderground {
            for line in TextRenderer.wrap(here, width: Double(pw - 16), size: 13, font: .bold).prefix(2) {
                texts.append(TextItem(text: line, x: Double(px + 8), y: y, size: 13, font: .bold, color: Screen.accent))
                y += 16
            }
        }
        let k = game.regionKey
        let explored = game.world.regions.values.filter { $0.visited && $0.key.z == 0 }.count
        texts.append(TextItem(text: "Region \(k.x), \(k.y)\(game.isUnderground ? " (below)" : "")  ·  lands seen: \(explored)",
                              x: Double(px + 8), y: 268, size: 10.5, color: Screen.dim))

        // Companions.
        box(px, 294, pw, 70)
        texts.append(TextItem(text: "Companions (\(game.party.count) of \(Party.maxSize))", x: Double(px + 8), y: 297, size: 11.5,
                              font: .bold, color: Screen.dim))
        if game.party.isEmpty {
            texts.append(TextItem(text: "You travel alone.", x: Double(px + 8), y: 316, size: 12, font: .italic, color: Screen.dim))
        }
        for (i, n) in game.party.enumerated() {
            let ly = 314.0 + Double(i) * 16
            texts.append(TextItem(text: "\(n.name), \(n.race.name)", x: Double(px + 8), y: ly, size: 12, color: Screen.ink))
            texts.append(TextItem(text: "\(n.hp)/\(n.maxHP)", x: Double(px + 158), y: ly + 1, size: 11, color: healthInk(n.hp, n.maxHP),
                                  align: .right))
            texts.append(TextItem(text: n.disposition.word, x: Double(px + pw - 8), y: ly, size: 11.5, font: .italic,
                                  color: moodPanelInk(n.disposition), align: .right))
        }

        // The message scroll, newest at the bottom.
        let sy = 372, sh = 528 - sy
        parchmentBox(px, sy, pw, sh)
        let size = 12.5, lineH = 16.0
        var lines: [(String, Int)] = []
        let recent = Array(game.messages.suffix(14))
        for (i, m) in recent.enumerated() {
            for l in TextRenderer.wrap(m, width: Double(pw - 20), size: size, font: .body) { lines.append((l, recent.count - 1 - i)) }
        }
        let maxLines = Int(Double(sh - 12) / lineH)
        let shown = lines.suffix(maxLines)
        y = Double(sy + sh - 6) - Double(shown.count) * lineH
        for (text, age) in shown {
            let color: UInt32 = age == 0 ? 0x2A1406 : (age < 3 ? 0x4A2E18 : 0x6E5236)
            texts.append(TextItem(text: text, x: Double(px + 10), y: y, size: size, color: color, shadow: false))
            y += lineH
        }
    }

    private func timeOfDay(_ h: Double) -> String {
        switch h {
        case 5..<7: return "Dawn"
        case 7..<11.5: return "Morning"
        case 11.5..<13.5: return "Midday"
        case 13.5..<17.5: return "Afternoon"
        case 17.5..<20: return "Evening"
        default: return "Night"
        }
    }

    private func capitalized(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    /// Sky strip with the sun or moon crossing it as the hours pass.
    private func drawSky(_ game: Game, x: Int, y: Int, w: Int, h: Int) {
        let m = game.hourOfDay
        let tint = Lighting.sky(m)
        let top = mix(hex(0x0A1030), hex(0x4A7AD0), smoothstep(0.35, 1, tint.x))
        let bottom = mix(hex(0x1A2448), mix(hex(0xE8885A), hex(0xA8CCF0), smoothstep(0.75, 1, tint.z)), smoothstep(0.35, 0.8, tint.x))
        for row in 0..<h {
            let c = pack(mix(top, bottom, Float(row) / Float(h - 1)))
            fb.fill(x, y + row, w, 1, c)
        }
        let isDay = m >= 6 && m < 18
        if !isDay || tint.x < 0.6 {
            var rng = SplitMix64(seed: 5)
            for _ in 0..<26 { fb.set(x + 2 + rng.int(w - 4), y + 2 + rng.int(h - 6), rgb(0xD0D8F8)) }
        }
        let t = isDay ? (m - 6) / 12 : ((m >= 18 ? m - 18 : m + 6) / 12)
        let bx = x + 8 + Int(t * Double(w - 16)), by = y + 6 + Int(pow(abs(t - 0.5) * 2, 2) * Double(h - 12))
        for dy in -5...5 {
            for dx in -5...5 {
                let d = Double(dx * dx + dy * dy).squareRoot()
                if isDay {
                    if d < 4.2 { fb.set(bx + dx, by + dy, d < 2.4 ? rgb(0xFFF8C0) : rgb(0xFFD848)) }
                    else if d < 5.6 { fb.plot(bx + dx, by + dy, hex(0xFFE890), 0.4) }
                } else if d < 4 {
                    let dd = Double((dx - 2) * (dx - 2) + (dy + 1) * (dy + 1)).squareRoot()
                    if dd > 3.4 { fb.set(bx + dx, by + dy, rgb(0xE8ECF4)) }
                }
            }
        }
        gild(x, y, w, h)
    }

    // MARK: Overlays

    /// "By what name shalt thou be called?", asked when a new game begins.
    private func drawNamePrompt(_ entry: String, frame: Int) {
        let w = 340, h = 136
        let x = Screen.mapX + (MapRenderer.pixelW - w) / 2, y = Screen.mapY + (MapRenderer.pixelH - h) / 2
        fb.wash(Screen.mapX, Screen.mapY, MapRenderer.pixelW, MapRenderer.pixelH, hex(0x000000), 0.55)
        parchmentBox(x, y, w, h)
        let cx = Double(x + w / 2)
        texts.append(TextItem(text: "A new adventure begins", x: cx, y: Double(y + 10), size: 20, font: .title,
                              color: Screen.brown, align: .center, shadow: false))
        texts.append(TextItem(text: "By what name shalt thou be called?", x: cx, y: Double(y + 42), size: 14,
                              font: .italic, color: 0x4A3018, align: .center, shadow: false))
        let fieldW = 200, fx = x + (w - fieldW) / 2, fy = y + 68
        fb.fill(fx, fy, fieldW, 26, rgb(0x2A1C10))
        gild(fx, fy, fieldW, 26)
        let tw = entry.isEmpty ? 0 : TextRenderer.width(entry, size: 16, font: .bold)
        let left = Double(fx + fieldW / 2) - tw / 2
        if !entry.isEmpty {
            texts.append(TextItem(text: entry, x: left, y: Double(fy + 3), size: 16, font: .bold, color: Screen.accent))
        }
        if (frame / 4) % 2 == 0 { fb.fill(Int(left + tw) + 2, fy + 5, 2, 16, gold) }
        texts.append(TextItem(text: "Type a name and press Return", x: cx, y: Double(y + 104), size: 12,
                              color: 0x5A4024, align: .center, shadow: false))
    }

    /// The Avatar's painted head and shoulders in a gilded frame, 66 by 78.
    private func drawPortrait(_ name: String, _ fx: Int, _ fy: Int) {
        let fw = 66, fh = 78
        fb.fill(fx, fy, fw, fh, rgb(0x4A443C))
        gild(fx, fy, fw, fh)
        // The paintings are 236 wide: take the top of the picture at the frame's shape.
        texts.append(.picture(name, crop: CGRect(x: 0, y: 0, width: 236, height: 236 * fh / fw),
                              x: Double(fx), y: Double(fy), w: Double(fw), h: Double(fh)))
    }

    /// The second question of a new game: how the Avatar looks, from five men and five
    /// women, each shown in their painted portrait.
    private static let lookBox = (w: 560, h: 474, x: mapX + (MapRenderer.pixelW - 560) / 2, y: mapY + (MapRenderer.pixelH - 474) / 2)
    /// The button that takes the chosen look and begins the game.
    static let lookBegin = (x: lookBox.x + (lookBox.w - 200) / 2, y: lookBox.y + 400, w: 200, h: 34)

    static func onLookBegin(atX px: Int, y py: Int) -> Bool {
        let b = lookBegin
        return px >= b.x && px < b.x + b.w && py >= b.y && py < b.y + b.h
    }
    /// Where each of the ten portraits sits: the men in the top row, the women below.
    static func lookPortrait(_ i: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        let pw = 82, ph = 140, gap = 22
        let left = lookBox.x + (lookBox.w - (5 * pw + 4 * gap)) / 2
        return (left + (i % 5) * (pw + gap), lookBox.y + 66 + (i / 5) * (ph + 16), pw, ph)
    }

    /// Which of the ten portraits is at a screen pixel, if any.
    static func lookChoice(atX px: Int, y py: Int) -> Int? {
        (0..<Game.lookChoices).first { i in
            let r = lookPortrait(i)
            return px >= r.x - 6 && px < r.x + r.w + 6 && py >= r.y - 6 && py < r.y + r.h + 6
        }
    }

    private func drawLookPrompt(_ name: String, chosen: Int) {
        let (w, h, x, y) = Screen.lookBox
        fb.wash(Screen.mapX, Screen.mapY, MapRenderer.pixelW, MapRenderer.pixelH, hex(0x000000), 0.55)
        parchmentBox(x, y, w, h)
        let cx = Double(x + w / 2)
        texts.append(TextItem(text: "A new adventure begins", x: cx, y: Double(y + 10), size: 20, font: .title,
                              color: Screen.brown, align: .center, shadow: false))
        texts.append(TextItem(text: "How dost thou appear, \(name)?", x: cx, y: Double(y + 40), size: 14,
                              font: .italic, color: 0x4A3018, align: .center, shadow: false))
        for i in 0..<Game.lookChoices {
            let (fx, fy, pw, ph) = Screen.lookPortrait(i)
            let on = i == chosen
            if on { fb.fill(fx - 6, fy - 6, pw + 12, ph + 12, rgb(0xE0B048)) }
            fb.fill(fx, fy, pw, ph, rgb(0x4A443C))
            gild(fx, fy, pw, ph)
            let female = i >= AvatarArt.perSex
            texts.append(.picture(Portraits.avatarName(female: female, look: i % AvatarArt.perSex),
                                  crop: CGRect(x: 0, y: 0, width: 236, height: 236 * ph / pw),
                                  x: Double(fx), y: Double(fy), w: Double(pw), h: Double(ph), dim: on ? 0 : 0.55))
        }
        let look = AvatarArt.look(female: chosen >= AvatarArt.perSex, chosen % AvatarArt.perSex)
        texts.append(TextItem(text: look.appearance.capitalizedFirst, x: cx, y: Double(y + 372), size: 14, font: .italic,
                              color: Screen.brown, align: .center, shadow: false))
        let b = Screen.lookBegin
        box(b.x, b.y, b.w, b.h)
        texts.append(TextItem(text: "Begin thy journey", x: cx, y: Double(b.y + 8), size: 15, font: .bold,
                              color: 0xE8C878, align: .center, shadow: true))
        texts.append(TextItem(text: "Click a portrait or use the arrows  ·  Return or the button to begin", x: cx, y: Double(y + h - 24), size: 12,
                              color: 0x5A4024, align: .center, shadow: false))
    }

    private func drawHelp() {
        let x = Screen.mapX + 70, y = Screen.mapY + 46, w = MapRenderer.pixelW - 140, h = MapRenderer.pixelH - 92
        fb.wash(Screen.mapX, Screen.mapY, MapRenderer.pixelW, MapRenderer.pixelH, hex(0x000000), 0.45)
        parchmentBox(x, y, w, h)
        texts.append(TextItem(text: "How to Explore Ezerian", x: Double(x + w / 2), y: Double(y + 12), size: 22,
                              font: .title, color: Screen.brown, align: .center, shadow: false))
        let lines: [(String, String)] = [
            ("Arrow keys, WASD", "walk (hold two arrows for diagonals)"),
            ("Q E Z C, numpad", "walk diagonally"),
            ("Click or hold on the map", "walk that way"),
            ("Right-click", "look at something or someone"),
            ("T, or walk into someone", "talk to them (companions step aside)"),
            ("F, then a direction", "attack (walk into a foe in a fight)"),
            ("Space", "wait a turn"),
            ("L", "look at what is ahead"),
            ("M", "map of the explored lands"),
            ("G", "show region borders"),
            ("⌘N  /  ⌘S", "begin a new world  /  save"),
            ("H or ?", "close this help"),
        ]
        for (i, (key, what)) in lines.enumerated() {
            let ly = Double(y + 48 + i * 23)
            texts.append(TextItem(text: key, x: Double(x + 26), y: ly, size: 14, font: .bold, color: 0x5A2A10, shadow: false))
            texts.append(TextItem(text: what, x: Double(x + 222), y: ly, size: 14, color: 0x3A2412, shadow: false))
        }
        texts.append(TextItem(text: "Ask someone to join you, or tell a companion to leave, in your own words. Up to three may travel with you.",
                              x: Double(x + w / 2), y: Double(y + h - 30), size: 12.5, font: .italic,
                              color: 0x5A4024, align: .center, shadow: false))
    }

    /// The conversation window: the NPC's face, name, race and mood (with the
    /// friendliness score as a bar), the last few things said, and what to say next.
    typealias Rect = (x: Int, y: Int, w: Int, h: Int)

    /// The conversation window.
    static let talkBox: Rect = (mapX + 12, mapY + MapRenderer.pixelH - 200 - 12, MapRenderer.pixelW - 24, 200)

    /// Along the bottom of the conversation window: the line being said and, while a
    /// merchant has named a price, the gold to offer and the button that hands it over.
    static func talkFields(trading: Bool) -> (say: Rect, gold: Rect, give: Rect) {
        let b = talkBox
        let x = b.x + 116, y = b.y + b.h - 34, w = b.w - 132, h = 22
        guard trading else { return ((x, y, w, h), (0, 0, 0, 0), (0, 0, 0, 0)) }
        let give: Rect = (x + w - 104, y - 2, 104, h + 4)
        let gold: Rect = (give.x - 12 - 84, y, 84, h)
        return ((x, y, gold.x - 12 - x, h), gold, give)
    }

    static func inside(_ r: Rect, _ px: Int, _ py: Int) -> Bool { px >= r.x && px < r.x + r.w && py >= r.y && py < r.y + r.h }

    private func drawConversation(_ c: Conversation, _ game: Game) {
        let npc = c.npc
        let (x, y, w, h) = Screen.talkBox
        parchmentBox(x, y, w, h)
        // Portrait.
        let fx = x + 12, fy = y + 14, fw = 92, fh = 104
        if let painting = npc.painting {
            // The watch and the bards have painted portraits: head and shoulders from the top of the picture.
            fb.fill(fx, fy, fw, fh, rgb(0x4A443C))
            texts.append(.picture(painting, crop: CGRect(x: 0, y: 0, width: 258, height: 258 * fh / fw),
                                  x: Double(fx), y: Double(fy), w: Double(fw), h: Double(fh)))
        } else {
            let face = SpriteBank.shared.faces[npc.race.index][npc.look % Populace.looks]
            for yy in 0..<fh {
                for xx in 0..<fw {
                    let t = Float(yy) / Float(fh)
                    fb.pixels[(fy + yy) * Screen.width + fx + xx] = pack(mix(hex(0x5A6A4A), hex(0x2A2A1E), t))
                }
            }
            fb.blit(face, fx + fw / 2 - face.w / 2 + face.ax, fy + 10 + face.ay, clip: (fx, fy, fw, fh))
        }
        gild(fx, fy, fw, fh)
        let title = npc.known ? npc.name : npc.stranger
        texts.append(TextItem(text: title, x: Double(fx + fw / 2), y: Double(fy + fh + 6), size: 15, font: .title,
                              color: Screen.brown, align: .center, shadow: false))
        texts.append(TextItem(text: npc.kind.capitalizedFirst, x: Double(fx + fw / 2),
                              y: Double(fy + fh + 26), size: 11, font: .italic, color: 0x5A4024, align: .center, shadow: false))
        if npc.servesDraconian {
            texts.append(TextItem(text: "Serves Lord Draconian", x: Double(fx + fw / 2), y: Double(fy + fh + 40), size: 10.5,
                                  font: .bold, color: 0x8E1410, align: .center, shadow: false))
        }
        // Friendliness bar from hostile (red) to adoring (green).
        let bx = x + w - 196, by = y + 14, bw = 180
        texts.append(TextItem(text: "\(npc.disposition.word) (\(npc.friendliness > 0 ? "+" : "")\(npc.friendliness))",
                              x: Double(bx + bw), y: Double(by - 2), size: 12, font: .bold, color: moodInk(npc.disposition),
                              align: .right, shadow: false))
        let barY = by + 18
        for k in 0..<bw {
            let t = Float(k) / Float(bw - 1)
            let c = t < 0.5 ? mix(hex(0xB02018), hex(0xD8B040), t * 2) : mix(hex(0xD8B040), hex(0x2E9A3A), (t - 0.5) * 2)
            fb.fill(bx + k, barY, 1, 6, pack(c))
        }
        gild(bx, barY, bw, 6)
        let mark = bx + Int(Double(npc.friendliness + 100) / 200 * Double(bw - 1))
        fb.fill(mark - 1, barY - 3, 3, 12, rgb(0x1A1008))
        fb.fill(mark, barY - 2, 1, 10, rgb(0xFFF4D0))
        // What has been said.
        let tx = Double(fx + fw + 16), tw = Double(w - fw - 44)
        var rows: [(String, Bool)] = []
        for line in c.lines.suffix(8) {
            let text = line.fromAvatar ? "“\(line.text)”" : "\(npc.shortName.capitalizedFirst): “\(line.text)”"
            for l in TextRenderer.wrap(text, width: tw, size: 13, font: line.fromAvatar ? .italic : .body) { rows.append((l, line.fromAvatar)) }
        }
        var ly = Double(y + 60)
        for (l, mine) in rows.suffix(6) {
            texts.append(TextItem(text: l, x: tx, y: ly, size: 13, font: mine ? .italic : .body,
                                  color: mine ? 0x5A4A3A : 0x2A1406, shadow: false))
            ly += 17
        }
        // Who is voicing the talk, and any trouble reaching Claude.
        let voice = c.byClaude ? "Voiced by Claude" : (ClaudeClient.shared.isAvailable ? "Scripted"
            : "Scripted · add a Claude API key in the Game menu for free conversation")
        texts.append(TextItem(text: c.notice ?? voice, x: Double(x + w - 16), y: Double(y + 44), size: 10.5, font: .italic,
                              color: c.notice == nil ? 0x7A6A50 : 0x9A2A10, align: .right, shadow: false))
        // The line being typed.
        let trading = c.price != nil && !c.over && !c.offer
        let fields = Screen.talkFields(trading: trading)
        let fieldX = fields.say.x, fieldY = fields.say.y, fieldW = fields.say.w
        if trading {
            // The gold offered, and the button that hands it over.
            let g = fields.gold
            fb.fill(g.x, g.y, g.w, g.h, rgb(0x2A1C10))
            gild(g.x, g.y, g.w, g.h, thick: c.goldFocus)
            let unit = TextRenderer.width(" gold", size: 11, font: .italic)
            texts.append(TextItem(text: " gold", x: Double(g.x + g.w - 6) - unit, y: Double(g.y + 5), size: 11, font: .italic, color: 0x9A8A6A))
            let amountRight = Double(g.x + g.w - 6) - unit - 4
            let amount = c.goldInput
            texts.append(TextItem(text: amount, x: amountRight, y: Double(g.y + 3), size: 13, font: .bold, color: Screen.accent, align: .right))
            if c.goldFocus && (frameCount / 4) % 2 == 0 { fb.fill(Int(amountRight) + 1, g.y + 4, 2, 14, gold) }
            let b = fields.give
            box(b.x, b.y, b.w, b.h)
            texts.append(TextItem(text: "Give gold.", x: Double(b.x + b.w / 2), y: Double(b.y + 5), size: 13, font: .bold,
                                  color: 0xE8C878, align: .center))
        }
        if c.offer {
            fb.fill(fieldX, fieldY, fieldW, 22, rgb(0x2A1C10))
            gild(fieldX, fieldY, fieldW, 22)
            texts.append(TextItem(text: "Take \(npc.name) into your party?   Y  yes      N  no", x: tx, y: Double(fieldY + 3),
                                  size: 13, font: .bold, color: Screen.accent))
        } else if c.over {
            texts.append(TextItem(text: "Press any key to go on your way.", x: tx, y: Double(fieldY + 4), size: 12.5,
                                  font: .bold, color: 0x6A2A10, shadow: false))
        } else {
            fb.fill(fieldX, fieldY, fieldW, 22, rgb(0x2A1C10))
            gild(fieldX, fieldY, fieldW, 22)
            if c.pending {
                let dots = String(repeating: ".", count: 1 + (frameCount / 3) % 3)
                texts.append(TextItem(text: "\(npc.shortName.capitalizedFirst) is thinking\(dots)", x: tx, y: Double(fieldY + 3),
                                      size: 12.5, font: .italic, color: Screen.dim))
            } else {
                var shown = c.input
                while !shown.isEmpty && TextRenderer.width(shown, size: 13, font: .body) > Double(fieldW - 16) { shown.removeFirst() }
                let tw = shown.isEmpty ? 0 : TextRenderer.width(shown, size: 13, font: .body)
                if shown.isEmpty {
                    texts.append(TextItem(text: "Say something…", x: tx, y: Double(fieldY + 3), size: 13, font: .italic,
                                          color: 0x7A6A50, shadow: false))
                } else {
                    texts.append(TextItem(text: shown, x: tx, y: Double(fieldY + 3), size: 13, color: Screen.accent))
                }
                if !(trading && c.goldFocus) && (frameCount / 4) % 2 == 0 { fb.fill(Int(tx + tw) + 2, fieldY + 4, 2, 14, gold) }
            }
        }
    }

    private func healthInk(_ hp: Int, _ maxHP: Int) -> UInt32 {
        let f = Double(hp) / Double(max(1, maxHP))
        return f > 0.6 ? 0x9AD070 : (f > 0.3 ? 0xE0C060 : 0xE05A40)
    }

    /// A small red-to-green bar for health.
    private func healthBar(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hp: Int, _ maxHP: Int) {
        fb.fill(x - 1, y - 1, w + 2, h + 2, rgb(0x0A0604))
        fb.fill(x, y, w, h, rgb(0x3A1A14))
        let f = Float(hp) / Float(max(1, maxHP))
        let c = f > 0.5 ? mix(hex(0xD8B040), hex(0x3EAA3A), (f - 0.5) * 2) : mix(hex(0xC02018), hex(0xD8B040), f * 2)
        fb.fill(x, y, Int((Float(w) * f).rounded()), h, pack(c))
        fb.fill(x, y, Int((Float(w) * f).rounded()), 1, pack(c * 1.3))
    }

    /// Health bars over everyone in the fight, and a banner saying whose fight it is.
    private func drawCombat(_ game: Game, pose: AvatarPose) {
        guard let c = game.combat else { return }
        let T = MapRenderer.tile
        func bar(_ tx: Double, _ ty: Double, _ hp: Int, _ maxHP: Int, enemy: Bool) {
            let sx = Screen.mapX + Int(tx * Double(T)) - map.camX + 2
            let sy = Screen.mapY + Int(ty * Double(T)) - map.camY - 30
            guard sx > Screen.mapX, sy > Screen.mapY, sx + 26 < Screen.mapX + MapRenderer.pixelW,
                  sy + 6 < Screen.mapY + MapRenderer.pixelH else { return }
            healthBar(sx, sy, 24, 3, hp, maxHP)
            if enemy { fb.fill(sx - 3, sy - 1, 2, 5, rgb(0xE02010)) }
        }
        bar(pose.x, pose.y, game.hp, game.maxHP, enemy: false)
        for n in game.party where n.z == game.z { bar(Double(n.x), Double(n.y), n.hp, n.maxHP, enemy: false) }
        for n in c.enemies where n.z == game.z { bar(Double(n.x), Double(n.y), n.hp, n.maxHP, enemy: true) }
        let foes = c.enemies.map { "\($0.shortName.capitalizedFirst) \($0.hp)/\($0.maxHP)" }.joined(separator: "   ")
        fb.wash(Screen.mapX, Screen.mapY, MapRenderer.pixelW, 24, hex(0x3A0806), 0.75)
        texts.append(TextItem(text: "Combat", x: Double(Screen.mapX + 8), y: Double(Screen.mapY + 2), size: 15, font: .title,
                              color: 0xF0A060))
        texts.append(TextItem(text: foes, x: Double(Screen.mapX + MapRenderer.pixelW - 8), y: Double(Screen.mapY + 5), size: 12,
                              font: .bold, color: Screen.ink, align: .right))
    }

    private func drawGameOver(_ game: Game) {
        fb.wash(Screen.mapX, Screen.mapY, MapRenderer.pixelW, MapRenderer.pixelH, hex(0x200000), 0.65)
        let w = 380, h = 140
        let x = Screen.mapX + (MapRenderer.pixelW - w) / 2, y = Screen.mapY + (MapRenderer.pixelH - h) / 2
        parchmentBox(x, y, w, h)
        let cx = Double(x + w / 2)
        texts.append(TextItem(text: "Thou art slain", x: cx, y: Double(y + 14), size: 26, font: .title, color: 0x7A1008,
                              align: .center, shadow: false))
        texts.append(TextItem(text: game.deathMessage, x: cx, y: Double(y + 56), size: 13.5, font: .italic, color: 0x4A3018,
                              align: .center, shadow: false))
        texts.append(TextItem(text: "Press Return to begin a new adventure.", x: cx, y: Double(y + 96), size: 13, font: .bold,
                              color: 0x5A2A10, align: .center, shadow: false))
    }

    private func moodPanelInk(_ d: Disposition) -> UInt32 {
        switch d {
        case .hostile: return 0xE05A40
        case .unfriendly: return 0xE09A50
        case .neutral: return 0xC8B890
        case .friendly: return 0x9AD070
        case .adoring: return 0x70E080
        }
    }

    private func moodInk(_ d: Disposition) -> UInt32 {
        switch d {
        case .hostile: return 0x9A1A10
        case .unfriendly: return 0x8A4A10
        case .neutral: return 0x5A4A2A
        case .friendly: return 0x3A6A20
        case .adoring: return 0x1E7A2A
        }
    }

    /// Map of every tile the Avatar has seen, centred on the Avatar.
    private func drawOverview(_ game: Game, frame: Int) {
        let mx = Screen.mapX, my = Screen.mapY, mw = MapRenderer.pixelW, mh = MapRenderer.pixelH
        for yy in 0..<mh {
            for xx in 0..<mw {
                let c = parchment[xx, yy] * 0.42
                fb.pixels[(my + yy) * Screen.width + mx + xx] = pack(c)
            }
        }
        let s = [2, 3, 4, 6][max(0, min(3, game.mapScale - 1))]
        let tilesW = mw / s, tilesH = mh / s
        let left = game.x - tilesW / 2, top = game.y - tilesH / 2
        let world = game.world, z = game.z
        var cache: [RegionKey: Region] = [:]
        for ty in 0..<tilesH {
            for tx in 0..<tilesW {
                let wx = left + tx, wy = top + ty
                let key = RegionKey(x: floorDiv(wx, Region.size), y: floorDiv(wy, Region.size), z: z)
                let r: Region
                if let c = cache[key] { r = c } else if let c = world.existingRegion(key) { cache[key] = c; r = c } else { continue }
                let i = r.index(wx, wy)
                guard r.explored[i] else { continue }
                var c = r.terrain[i].mapColor
                let f = r.features[i]
                if f.isTree { c = rgb(0x1E3E16) }
                else if f != .none && f.blocksMovement && !r.terrain[i].isWall { c = shade(c, 0.75) }
                if world.building(at: wx, wy, z) != nil && !r.terrain[i].isWall && z == 0 { c = blend(c, rgb(0x8A5A3A), 0.5) }
                fb.fill(mx + tx * s, my + ty * s, s, s, c)
            }
        }
        let grid = rgb(0x8A7A50)
        for tx in 0..<tilesW where floorMod(left + tx, Region.size) == 0 {
            for py in stride(from: 0, to: mh, by: 3) { fb.set(mx + tx * s, my + py, grid) }
        }
        for ty in 0..<tilesH where floorMod(top + ty, Region.size) == 0 {
            for px in stride(from: 0, to: mw, by: 3) { fb.set(mx + px, my + ty * s, grid) }
        }
        for r in cache.values {
            for p in r.places where p.kind == .town && world.isExplored(p.x + p.w / 2, p.y + p.h / 2, z) {
                let lx = mx + (p.x + p.w / 2 - left) * s, ly = my + (p.y - top) * s - 18
                guard lx > mx + 20, lx < mx + mw - 20, ly > my + 20, ly < my + mh - 20 else { continue }
                texts.append(TextItem(text: p.name, x: Double(lx), y: Double(ly), size: 14, font: .title,
                                      color: Screen.accent, align: .center))
            }
        }
        if (frame / 3) % 2 == 0 {
            let px = mx + (game.x - left) * s, py = my + (game.y - top) * s
            fb.fill(px - 2, py - 2, s + 4, s + 4, rgb(0xFFFFFF))
            fb.fill(px - 1, py - 1, s + 2, s + 2, rgb(0xE02020))
        }
        fb.wash(mx, my, mw, 22, hex(0x000000), 0.6)
        texts.append(TextItem(text: game.isUnderground ? "Map of the Caverns" : "Map of the Explored Lands",
                              x: Double(mx + 8), y: Double(my + 2), size: 15, font: .title, color: Screen.accent))
        texts.append(TextItem(text: "1 tile = \(s) px", x: Double(mx + mw - 8), y: Double(my + 4), size: 11,
                              color: Screen.dim, align: .right))
    }
}
