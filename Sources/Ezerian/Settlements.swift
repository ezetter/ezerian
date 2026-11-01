import Foundation

/// Towns: rows of buildings, each row fronting onto a cobbled street to its south,
/// crossed by a north-south avenue with a plaza where it meets the main street.
/// Every building faces south, so its door is always on the side the viewer sees.
enum Settlements {
    private struct Lot {
        var x: Int, y: Int, w: Int, h: Int
        var kind: BuildingKind?
        var area: Int { w * h }
    }

    /// Builds a town and returns the street ends that roads should connect to.
    static func buildTown(_ b: RegionBuilder, large: Bool, nearCenter: Bool, force: Bool = false) -> [Point]? {
        let rowCount = large ? 3 : 2
        var depths = (0..<rowCount).map { _ in 7 + b.rng.int(3) }
        let w = large ? 46 : 34
        var h = 2 + depths.reduce(0) { $0 + $1 + 2 }
        if h > 40 { depths = depths.map { _ in 7 }; h = 2 + rowCount * 9 }
        guard let p = b.findSpot(w: w, h: h, margin: 4, tries: 90, preferCenter: nearCenter,
                                 allowedBad: force ? w * h : w * h / 8)
        else { return nil }
        let name = Names.town(&b.rng)
        b.clear(p.x, p.y, w, h)
        b.reserve(p.x, p.y, w, h)
        b.addPlace(.town, name, p.x, p.y, w, h)

        // Streets: one below each row of lots; the main street is the middle one.
        var streets: [Int] = []
        var y = p.y + 1
        var rowTops: [Int] = []
        for d in depths {
            rowTops.append(y)
            y += d
            streets.append(y)
            y += 2
        }
        let my = streets[large ? 1 : 0]
        let mx = p.x + w / 2 - 1
        for sy in streets {
            for x in p.x..<(p.x + w) { b.setT(x, sy, .cobble); b.setT(x, sy + 1, .cobble) }
        }
        for yy in p.y..<(p.y + h) { b.setT(mx, yy, .cobble); b.setT(mx + 1, yy, .cobble) }
        for yy in (my - 2)...(my + 3) { for x in (mx - 2)...(mx + 3) { b.setT(x, yy, .cobble) } }
        b.setF(mx, my, large ? .fountain : .well)

        // Lots along the north side of every street, west and east of the avenue.
        var lots: [Lot] = []
        let spans = [(p.x + 1, mx - 3), (mx + 4, p.x + w - 2)]
        for (row, top) in rowTops.enumerated() {
            let depth = depths[row]
            for (start, end) in spans {
                var x = start
                while end - x + 1 >= 6 {
                    var lw = min(end - x + 1, 6 + b.rng.int(5))
                    if end - x + 1 - lw - 1 < 6 { lw = min(12, end - x + 1) }
                    // A strip of back yard behind each building.
                    lots.append(Lot(x: x, y: top + 1, w: lw, h: depth - 1))
                    x += lw + 1
                }
            }
        }

        // Hand out the important buildings to lots big enough for them.
        var wanted: [BuildingKind] = large
            ? [.tavern, .inn, .temple, .provisions, .smithy, .armory, .healer]
            : [.tavern, .provisions, .smithy, .healer]
        // Some towns have an apothecary or an alchemist, or (if large) both.
        let potions = b.rng.double()
        if potions < (large ? 0.85 : 0.45) { wanted.append(b.rng.chance(0.5) ? .apothecary : .alchemist) }
        if large && potions < 0.3 { wanted.append(wanted.last == .apothecary ? .alchemist : .apothecary) }
        let order = lots.indices.sorted { lots[$0].area > lots[$1].area }
        for kind in wanted {
            if let i = order.first(where: { lots[$0].kind == nil && lots[$0].w >= kind.minSize.w && lots[$0].h >= kind.minSize.h }) {
                lots[i].kind = kind
            }
        }
        var doorFronts: Set<Point> = []
        for lot in lots {
            if lot.kind == nil && b.rng.chance(0.22) {
                garden(b, x: lot.x, y: lot.y, w: lot.w, h: lot.h)
                continue
            }
            // Homes are a little smaller than their lot, leaving a yard.
            var bx = lot.x, bw = lot.w, bh = lot.h
            let kind = lot.kind ?? .home
            if lot.kind == nil {
                bw = max(6, lot.w - b.rng.int(3)); bx = lot.x + (lot.w - bw) / 2
                bh = max(6, lot.h - b.rng.int(2))
            }
            let by = lot.y + lot.h - bh
            let front = Buildings.build(b, kind: kind, x: bx, y: by, w: bw, h: bh)
            doorFronts.insert(front)
            yard(b, lot: (lot.x, lot.y - 1, lot.w, lot.h + 1), building: (bx, by, bw, bh))
        }

        // Street lamps in the gaps between lots, welcome signs at both ends.
        for sy in streets {
            for x in stride(from: p.x + 3 + b.rng.int(3), to: p.x + w - 2, by: 5) {
                let ly = sy - 1
                if abs(x - mx) <= 3 || doorFronts.contains(where: { abs($0.x - x) <= 1 && abs($0.y - sy) <= 1 }) { continue }
                if b.f(x, ly) == .none && b.t(x, ly) == .grass { b.setF(x, ly, .lampPost) }
            }
        }
        for (sx, sy) in [(p.x, my - 1), (p.x + w - 1, my + 2)] where b.f(sx, sy) == .none {
            b.setF(sx, sy, .signpost)
            b.setSign(sx, sy, "Welcome to \(name)")
        }
        if large, b.f(mx + 3, my - 2) == .none { b.setF(mx + 3, my - 2, .stocks) }
        // Trees and flowers on untouched grass inside the town.
        for yy in p.y..<(p.y + h) {
            for x in p.x..<(p.x + w) where b.t(x, yy) == .grass && b.f(x, yy) == .none {
                let edge = x == p.x || yy == p.y || x == p.x + w - 1 || yy == p.y + h - 1
                if doorFronts.contains(Point(x: x, y: yy)) || streets.contains(yy - 2) { continue }
                let r = b.rng.double()
                if edge && r < 0.16 { b.setF(x, yy, b.rng.chance(0.7) ? .oakTree : .blossomTree) }
                else if r < 0.03 { b.setF(x, yy, [.flowersRed, .flowersYellow, .flowersBlue, .bush][b.rng.int(4)]) }
            }
        }
        return [Point(x: p.x, y: my), Point(x: p.x + w - 1, y: my + 1),
                Point(x: mx, y: p.y), Point(x: mx + 1, y: p.y + h - 1)]
    }

    /// Flower beds, bushes and a tree in an empty lot.
    static func garden(_ b: RegionBuilder, x: Int, y: Int, w: Int, h: Int) {
        for yy in (y + 1)..<(y + h - 1) {
            for xx in (x + 1)..<(x + w - 1) {
                let r = b.rng.double()
                if r < 0.22 { b.setF(xx, yy, [.flowersRed, .flowersYellow, .flowersBlue, .flowersWhite][b.rng.int(4)]) }
                else if r < 0.3 { b.setF(xx, yy, .bush) }
                else if r < 0.34 { b.setF(xx, yy, b.rng.chance(0.6) ? .appleTree : .blossomTree) }
            }
        }
        b.reserve(x, y, w, h)
    }

    /// Fills the yard around a house with a vegetable patch, woodpile or barrels.
    static func yard(_ b: RegionBuilder, lot: (Int, Int, Int, Int), building: (Int, Int, Int, Int)) {
        let (lx, ly, lw, lh) = lot
        let (bx, by, bw, _) = building
        for y in ly..<(ly + lh) {
            for x in lx..<(lx + lw) where b.inside(x, y) && b.f(x, y) == .none && b.t(x, y) == .grass {
                let beside = (x < bx - 1 || x > bx + bw) && y >= by
                let behind = y < by - 1 && x >= bx && x < bx + bw
                guard beside || behind else { continue }
                if b.rng.chance(behind ? 0.18 : 0.3) {
                    b.setF(x, y, [.cabbage, .bush, .woodpile, .barrel, .flowersYellow, .crate][b.rng.int(6)])
                }
            }
        }
    }
}
