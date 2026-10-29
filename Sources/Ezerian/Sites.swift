import Foundation

/// Smaller points of interest scattered through the wilderness. Each returns the
/// tile a road may lead to (or nil when no road is wanted or no spot was found).
enum Sites {
    static func roadsideInn(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 15, h: 12, margin: 6, allowedBad: 4) else { return nil }
        b.clear(p.x, p.y, 15, 12)
        b.reserve(p.x, p.y, 15, 12)
        let front = Buildings.build(b, kind: .tavern, x: p.x + 2, y: p.y + 1, w: 11, h: 8)
        b.setF(p.x + 1, p.y + 10, .well)
        b.setF(p.x + 13, p.y + 9, .woodpile)
        b.setF(p.x + 13, p.y + 10, .barrel)
        for x in [p.x, p.x + 14] { b.setF(x, p.y + 2, .oakTree) }
        return Point(x: front.x, y: p.y + 12)
    }

    static func farm(_ b: RegionBuilder) -> Point? {
        let w = 22, h = 15
        guard let p = b.findSpot(w: w, h: h, margin: 4, allowedBad: 6, accept: { [.grass, .brush, .dirt].contains($0) })
        else { return nil }
        b.clear(p.x, p.y, w, h)
        b.reserve(p.x, p.y, w, h)
        let owner = Names.person(&b.rng)
        let front = Buildings.build(b, kind: .home, x: p.x + 1, y: p.y + 1, w: 8, h: 6,
                                    name: "\(owner)'s Farmhouse", roof: .thatch)
        b.setF(p.x + 10, p.y + 2, .well)
        b.setF(p.x + 3, p.y + 12, .beehive)
        b.setF(p.x + 1, p.y + 13, .beehive)
        b.setF(p.x + 1, p.y + 9, .haystack)
        b.setF(p.x + 2, p.y + 10, .haystack)
        b.setF(p.x + 10, p.y + 5, .woodpile)
        // Two fenced fields of crops.
        for (fx, crop) in [(p.x + 12, Feature.wheat), (p.x + 5, b.rng.chance(0.5) ? .cabbage : .wheat)] {
            let fy = fx == p.x + 12 ? p.y + 1 : p.y + 9
            let fw = fx == p.x + 12 ? 9 : 10, fh = fx == p.x + 12 ? 7 : 5
            for y in fy..<(fy + fh) {
                for x in fx..<(fx + fw) {
                    let edge = x == fx || y == fy || x == fx + fw - 1 || y == fy + fh - 1
                    if edge {
                        let gate = y == fy + fh - 1 && x == fx + fw / 2
                        b.setF(x, y, gate ? .none : .fence)
                    } else {
                        b.setT(x, y, .field)
                        b.setF(x, y, crop)
                    }
                }
            }
            if crop == .wheat { b.setF(fx + fw / 2, fy + fh / 2, .scarecrow) }
        }
        b.addPlace(.landmark, "\(owner)'s Farm", p.x, p.y, w, h)
        return Point(x: front.x, y: p.y + h)
    }

    static func shrine(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 11, h: 11, margin: 5) else { return nil }
        b.clear(p.x, p.y, 11, 11)
        b.reserve(p.x, p.y, 11, 11)
        let cx = p.x + 5, cy = p.y + 5
        for y in p.y..<(p.y + 11) {
            for x in p.x..<(p.x + 11) {
                let d = Double((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                if d <= 3.2 { b.setT(x, y, .dirt) }
                else if d > 4.2 && d < 5 && b.rng.chance(0.3) { b.setF(x, y, .flowersWhite) }
            }
        }
        b.setF(cx, cy, .shrine)
        for (dx, dy) in [(0, -4), (3, -3), (4, 0), (3, 3), (-3, 3), (-4, 0), (-3, -3)] {
            b.setF(cx + dx, cy + dy, .standingStone)
        }
        b.addPlace(.landmark, "the Shrine of \(Names.virtue(&b.rng))", p.x, p.y, 11, 11)
        return Point(x: cx, y: p.y + 11)
    }

    static func ruins(_ b: RegionBuilder) -> Point? {
        let w = 10 + b.rng.int(5), h = 8 + b.rng.int(4)
        guard let p = b.findSpot(w: w + 2, h: h + 2, margin: 4, allowedBad: 6) else { return nil }
        b.reserve(p.x, p.y, w + 2, h + 2)
        let x0 = p.x + 1, y0 = p.y + 1
        for y in y0..<(y0 + h) {
            for x in x0..<(x0 + w) {
                b.setF(x, y, .none)
                let edge = x == x0 || y == y0 || x == x0 + w - 1 || y == y0 + h - 1
                if edge {
                    if b.rng.chance(0.62) { b.setT(x, y, .stoneWall) }
                    else { b.setT(x, y, .grass); if b.rng.chance(0.5) { b.setF(x, y, .rubble) } }
                } else {
                    b.setT(x, y, b.rng.chance(0.6) ? .cobble : .grass)
                    let r = b.rng.double()
                    if r < 0.06 { b.setF(x, y, .rubble) }
                    else if r < 0.09 { b.setF(x, y, .brokenColumn) }
                    else if r < 0.11 { b.setF(x, y, .bush) }
                }
            }
        }
        // Keep a way in through the south wall.
        b.setT(x0 + w / 2, y0 + h - 1, .grass)
        b.setF(x0 + w / 2, y0 + h - 1, .none)
        b.setF(x0 + w / 2, y0 + h - 2, .none)
        b.setF(p.x, p.y, .deadTree)
        b.addPlace(.landmark, "ancient ruins", x0, y0, w, h)
        return Point(x: x0 + w / 2, y: y0 + h + 1)
    }

    static func graveyard(_ b: RegionBuilder) -> Point? {
        let w = 11, h = 9
        guard let p = b.findSpot(w: w, h: h, margin: 4, allowedBad: 3) else { return nil }
        b.clear(p.x, p.y, w, h)
        b.reserve(p.x, p.y, w, h)
        for y in p.y..<(p.y + h) {
            for x in p.x..<(p.x + w) {
                let edge = x == p.x || y == p.y || x == p.x + w - 1 || y == p.y + h - 1
                if edge {
                    if !(y == p.y + h - 1 && x == p.x + w / 2) { b.setF(x, y, .fence) }
                } else if (y - p.y) % 2 == 0 && (x - p.x) % 2 == 0 && x != p.x + w / 2 {
                    b.setF(x, y, b.rng.chance(0.6) ? .gravestone : .graveCross)
                }
            }
        }
        b.setF(p.x + 1, p.y + 1, .deadTree)
        b.addPlace(.landmark, "a graveyard", p.x, p.y, w, h)
        return Point(x: p.x + w / 2, y: p.y + h)
    }

    static func campsite(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 6, h: 5, margin: 3, accept: { [.grass, .brush, .sand, .hills].contains($0) })
        else { return nil }
        b.clear(p.x, p.y, 6, 5, to: b.t(p.x + 2, p.y + 2) == .sand ? .sand : .grass)
        b.reserve(p.x, p.y, 6, 5)
        b.setF(p.x + 1, p.y + 1, .tent)
        b.setF(p.x + 3, p.y + 3, .campfire)
        b.setF(p.x + 2, p.y + 3, .logSeat)
        b.setF(p.x + 4, p.y + 3, .logSeat)
        b.setF(p.x + 3, p.y + 4, .logSeat)
        b.setF(p.x + 5, p.y + 1, .woodpile)
        b.addPlace(.landmark, "an abandoned campsite", p.x, p.y, 6, 5)
        return nil
    }

    static func standingStones(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 9, h: 9, margin: 4, accept: { [.grass, .brush, .hills].contains($0) })
        else { return nil }
        b.clear(p.x, p.y, 9, 9)
        b.reserve(p.x, p.y, 9, 9)
        let cx = p.x + 4, cy = p.y + 4
        for (dx, dy) in [(0, -3), (2, -2), (3, 0), (2, 2), (0, 3), (-2, 2), (-3, 0), (-2, -2)] {
            b.setF(cx + dx, cy + dy, .standingStone)
        }
        b.setF(cx, cy, .boulder)
        b.addPlace(.landmark, "a ring of standing stones", p.x, p.y, 9, 9)
        return nil
    }

    static func cottage(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 12, h: 10, margin: 4, allowedBad: 4) else { return nil }
        b.clear(p.x, p.y, 12, 10)
        b.reserve(p.x, p.y, 12, 10)
        let owner = Names.person(&b.rng)
        let front = Buildings.build(b, kind: .home, x: p.x + 1, y: p.y + 1, w: 7, h: 6,
                                    name: "\(owner)'s Cottage")
        for y in (p.y + 2)...(p.y + 5) { b.setF(p.x + 9, y, .cabbage); b.setF(p.x + 10, y, .cabbage) }
        b.setF(p.x + 9, p.y + 7, .woodpile)
        b.setF(p.x + 2, p.y + 8, .flowersRed)
        b.setF(p.x + 6, p.y + 8, .flowersYellow)
        return Point(x: front.x, y: p.y + 10)
    }

    static func orchard(_ b: RegionBuilder) -> Point? {
        guard let p = b.findSpot(w: 11, h: 9, margin: 4, accept: { [.grass, .brush].contains($0) }) else { return nil }
        b.clear(p.x, p.y, 11, 9)
        b.reserve(p.x, p.y, 11, 9)
        for y in stride(from: p.y + 1, to: p.y + 9, by: 2) {
            for x in stride(from: p.x + 1, to: p.x + 11, by: 2) where b.rng.chance(0.9) { b.setF(x, y, .appleTree) }
        }
        b.addPlace(.landmark, "an apple orchard", p.x, p.y, 11, 9)
        return nil
    }

    /// Cave mouths in a mountainside facing open ground.
    static func caveEntrances(_ b: RegionBuilder, count: Int) {
        var spots: [Point] = []
        for y in 4..<(b.n - 5) {
            for x in 4..<(b.n - 4) where b.t(x, y) == .mountain && !b.isReserved(x, y) {
                let below = b.t(x, y + 1)
                guard !below.blocksMovement, !below.isWater, b.f(x, y + 1) == .none || !b.f(x, y + 1).blocksMovement,
                      b.t(x - 1, y) == .mountain, b.t(x + 1, y) == .mountain, b.t(x, y - 1) == .mountain else { continue }
                spots.append(Point(x: x, y: y))
            }
        }
        b.rng.shuffle(&spots)
        var made: [Point] = []
        for s in spots where made.count < count {
            if made.contains(where: { abs($0.x - s.x) + abs($0.y - s.y) < 20 }) { continue }
            b.setF(s.x, s.y, .caveEntrance)
            b.setF(s.x, s.y + 1, .none)
            b.reserve(s.x - 1, s.y - 1, 3, 3)
            b.addPlace(.landmark, "a cave mouth", s.x, s.y, 1, 1)
            made.append(s)
        }
    }
}
