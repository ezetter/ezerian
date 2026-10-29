import Foundation

/// The cave level beneath a surface region, reached through its cave mouths.
/// Carved with cellular automata, then stitched together so every ladder connects.
enum CaveBuilder {
    static func build(_ key: RegionKey, surface: Region, seed: UInt64) -> Region {
        let n = Region.size
        let region = Region(key: key)
        var rng = SplitMix64(seed: Hash.of(seed, key.x, key.y, 5000 + key.z))
        var open = Array(repeating: false, count: n * n)

        var ladders: [Point] = []
        for i in 0..<(n * n) where surface.features[i] == .caveEntrance {
            ladders.append(Point(x: i % n, y: i / n))
        }
        if ladders.isEmpty { ladders.append(Point(x: n / 2, y: n / 2)) }

        for y in 2..<(n - 2) {
            for x in 2..<(n - 2) { open[y * n + x] = !rng.chance(0.45) }
        }
        for _ in 0..<5 {
            var next = open
            for y in 2..<(n - 2) {
                for x in 2..<(n - 2) {
                    var walls = 0
                    for dy in -1...1 { for dx in -1...1 where !open[(y + dy) * n + x + dx] { walls += 1 } }
                    next[y * n + x] = walls < 5
                }
            }
            open = next
        }
        func carve(_ x: Int, _ y: Int) {
            guard x >= 2, y >= 2, x < n - 2, y < n - 2 else { return }
            open[y * n + x] = true
        }
        for l in ladders {
            for dy in -1...1 { for dx in -1...1 { carve(l.x + dx, l.y + dy) } }
        }

        // Join every sizeable cavern to the first ladder's cavern with winding tunnels.
        func components() -> [[Int]] {
            var seen = Array(repeating: false, count: n * n)
            var out: [[Int]] = []
            for i in 0..<(n * n) where open[i] && !seen[i] {
                var comp: [Int] = [], stack = [i]
                seen[i] = true
                while let c = stack.popLast() {
                    comp.append(c)
                    for d in [1, -1, n, -n] {
                        let j = c + d
                        if j >= 0, j < n * n, open[j], !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
                out.append(comp)
            }
            return out
        }
        let main = ladders[0].y * n + ladders[0].x
        for comp in components() where !comp.contains(main) {
            if comp.count < 12 && !ladders.contains(where: { comp.contains($0.y * n + $0.x) }) {
                for i in comp { open[i] = false }
                continue
            }
            let startCell = comp[rng.int(comp.count)]
            var x = startCell % n, y = startCell / n
            let tx = main % n, ty = main / n
            while x != tx || y != ty {
                if rng.chance(0.5) && x != tx { x += x < tx ? 1 : -1 } else if y != ty { y += y < ty ? 1 : -1 } else { x += x < tx ? 1 : -1 }
                carve(x, y)
                if rng.chance(0.3) { carve(x + 1, y) }
            }
        }

        for i in 0..<(n * n) {
            region.terrain[i] = open[i] ? .caveFloor : .caveWall
            guard open[i] else { continue }
            let r = rng.double()
            if r < 0.03 { region.features[i] = .mushrooms }
            else if r < 0.05 { region.features[i] = .rubble }
            else if r < 0.06 { region.features[i] = .rock }
        }
        for l in ladders {
            for dy in -1...1 { for dx in -1...1 { region.features[(l.y + dy) * n + l.x + dx] = .none } }
            region.features[l.y * n + l.x] = .ladderUp
        }
        // Boulders only where they can't cut a passage in two.
        for _ in 0..<12 {
            let x = 3 + rng.int(n - 6), y = 3 + rng.int(n - 6)
            var allOpen = true
            for dy in -1...1 { for dx in -1...1 where !open[(y + dy) * n + x + dx] { allOpen = false } }
            if allOpen && region.features[y * n + x] == .none { region.features[y * n + x] = .boulder }
        }
        region.name = "the caverns beneath \(surface.name.isEmpty ? "the hills" : surface.name.replacingOccurrences(of: "the ", with: ""))"
        region.places.append(Place(kind: .landmark, name: region.name, x: region.originX, y: region.originY, w: n, h: n))
        return region
    }
}
