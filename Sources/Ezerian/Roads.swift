import Foundation

/// Dirt roads joining a region's towns and sites to the points where roads cross
/// into neighbouring regions. Both neighbours agree on those crossing points, so
/// roads continue seamlessly from one map grid to the next.
enum Roads {
    static func build(_ b: RegionBuilder, hubs: [Point], sites: [Point]) {
        let g = b.generator, key = b.region.key, n = b.n
        var edges: [Point] = []
        if let y = g.verticalCrossing(key.x - 1, key.y) { edges.append(Point(x: 0, y: y)) }
        if let y = g.verticalCrossing(key.x, key.y) { edges.append(Point(x: n - 1, y: y)) }
        if let x = g.horizontalCrossing(key.x, key.y - 1) { edges.append(Point(x: x, y: 0)) }
        if let x = g.horizontalCrossing(key.x, key.y) { edges.append(Point(x: x, y: n - 1)) }

        var groups: [[Point]] = hubs.isEmpty ? [] : [hubs]
        var sites = sites
        if groups.isEmpty {
            if edges.count >= 2, let c = crossroads(b, edges: edges) { groups.append([c]) }
            else if !edges.isEmpty, let s = sites.first { groups.append([s]); sites.removeFirst() }
        }
        guard !groups.isEmpty else { return }

        func nearest(_ p: Point) -> Point {
            groups.flatMap { $0 }.min { dist($0, p) < dist($1, p) }!
        }
        for e in edges { connect(b, e, nearest(e)) }
        for s in sites where dist(s, nearest(s)) < 45 { connect(b, s, nearest(s)) }
    }

    private static func dist(_ a: Point, _ b: Point) -> Int { abs(a.x - b.x) + abs(a.y - b.y) }

    /// Picks open ground between the border crossings and puts up a signpost.
    private static func crossroads(_ b: RegionBuilder, edges: [Point]) -> Point? {
        let cx = edges.map(\.x).reduce(0, +) / edges.count
        let cy = edges.map(\.y).reduce(0, +) / edges.count
        var best: Point?
        for r in 0..<20 where best == nil {
            for dy in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dy) == r {
                    let x = max(6, min(b.n - 7, (cx + 32) / 2 + dx)), y = max(6, min(b.n - 7, (cy + 32) / 2 + dy))
                    if best == nil, cost(b, x, y) != nil, cost(b, x + 1, y - 1) != nil, !b.isReserved(x + 1, y - 1) {
                        best = Point(x: x, y: y)
                    }
                }
            }
        }
        guard let c = best else { return nil }
        let dirs = edges.map { e -> String in
            e.x == 0 ? "west" : e.x == b.n - 1 ? "east" : e.y == 0 ? "north" : "south"
        }
        let list = dirs.count == 2 ? "\(dirs[0]) and \(dirs[1])"
            : dirs.dropLast().joined(separator: ", ") + " and " + dirs.last!
        b.setT(c.x + 1, c.y - 1, b.t(c.x + 1, c.y - 1) == .forest ? .grass : b.t(c.x + 1, c.y - 1))
        b.setF(c.x + 1, c.y - 1, .signpost)
        b.setSign(c.x + 1, c.y - 1, "Crossroads. The roads lead \(list).")
        b.reserve(c.x + 1, c.y - 1, 1, 1)
        return c
    }

    /// Movement cost for laying road, or nil where a road can't go.
    private static func cost(_ b: RegionBuilder, _ x: Int, _ y: Int) -> Double? {
        guard b.inside(x, y) else { return nil }
        let t = b.t(x, y), f = b.f(x, y)
        if b.isReserved(x, y) && t != .cobble { return nil }
        var c: Double
        switch t {
        case .dirt, .cobble, .bridge: c = 1
        case .grass, .sand: c = 2.5
        case .brush: c = 3
        case .hills, .forest: c = 5
        case .swamp: c = 7
        case .shallowWater: c = 14
        default: return nil
        }
        if f != .none {
            if f.mirrorsRandomly || f == .reeds || f == .lilyPad { c += 3 } else { return nil }
        }
        return c
    }

    private static func connect(_ b: RegionBuilder, _ from: Point, _ to: Point) {
        guard let path = findPath(b, from, to) else { return }
        for p in path {
            let t = b.t(p.x, p.y)
            if t == .cobble || t == .bridge { continue }
            b.setT(p.x, p.y, t == .shallowWater ? .bridge : .dirt)
            b.setF(p.x, p.y, .none)
        }
    }

    /// A* over the region grid (4-way, so roads stay continuous).
    private static func findPath(_ b: RegionBuilder, _ start: Point, _ goal: Point) -> [Point]? {
        let n = b.n
        guard cost(b, start.x, start.y) != nil, cost(b, goal.x, goal.y) != nil else { return nil }
        var best = Array(repeating: Double.infinity, count: n * n)
        var came = Array(repeating: -1, count: n * n)
        var heap = MinHeap()
        let s = start.y * n + start.x, g = goal.y * n + goal.x
        best[s] = 0
        heap.push(Double(dist(start, goal)), s)
        while let (_, cur) = heap.pop() {
            if cur == g { break }
            let cx = cur % n, cy = cur / n
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard let c = cost(b, nx, ny) else { continue }
                let ni = ny * n + nx
                let nb = best[cur] + c
                if nb < best[ni] {
                    best[ni] = nb
                    came[ni] = cur
                    heap.push(nb + Double(abs(nx - goal.x) + abs(ny - goal.y)), ni)
                }
            }
        }
        guard best[g].isFinite else { return nil }
        var path: [Point] = []
        var cur = g
        while cur != -1 {
            path.append(Point(x: cur % n, y: cur / n))
            cur = came[cur]
        }
        return path
    }
}

/// Binary min-heap of (priority, value) pairs.
struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ priority: Double, _ value: Int) {
        items.append((priority, value))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            if items[parent].0 <= items[i].0 { break }
            items.swapAt(parent, i)
            i = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count && items[l].0 < items[m].0 { m = l }
                if r < items.count && items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i)
                i = m
            }
        }
        return top
    }
}
