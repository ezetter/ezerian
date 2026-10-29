import Foundation

// The world is drawn in the oblique projection of Ultima VI and VII: a point at
// ground position (X, Y) (in pixels, 32 per tile) and height Z appears on screen
// at (X - Z, Y - Z). Tall things lean up and to the left, and the south and east
// faces of walls, cliffs and roofs are the ones we see.
//
// Walls, cliffs, roofs and water are a height field, one column per ground pixel.
// For each screen pixel we march down the ray (sx + z, sy + z, z) from the top
// until it meets a column; the surface found there, its texture coordinates and
// its shading go in a `GTile` (a deferred "G-buffer" tile) that is cached, so a
// frame only has to look up texels. The height z at which the ray hit is also
// kept: along one screen pixel's ray, a bigger z is nearer the eye, which makes
// it a depth buffer that sprites are tested against.

/// One 32x32 tile of the ground picture.
final class GTile {
    /// mat | u << 8 | v << 16 | shade << 24 (shade 128 = unlit texel).
    var surf = [UInt32](repeating: 0, count: 1024)
    var z = [Int8](repeating: 0, count: 1024)
}

/// Wrapping noise in world-pixel space that wobbles terrain borders and shapes rock.
final class GroundNoise {
    static let shared = GroundNoise()
    let dx: [Float], dy: [Float], fine: [Float], crag: [Float], bump: [Float]
    /// Rock heights: a field of boulders, domed, with crevices between them.
    let boulder: [Float]

    private init() {
        var rng = SplitMix64(seed: 0x5EED_6A0D)
        dx = fbmField(&rng, [8, 16, 32], [1, 0.5, 0.3]).map { $0 * 2 - 1 }
        dy = fbmField(&rng, [8, 16, 32], [1, 0.5, 0.3]).map { $0 * 2 - 1 }
        fine = fbmField(&rng, [64, 128], [1, 0.8]).map { $0 * 2 - 1 }
        crag = fbmField(&rng, [8, 16, 32, 64], [1, 0.6, 0.4, 0.25])
        bump = fbmField(&rng, [16, 32, 64], [1, 0.5, 0.25])
        let vor = Voronoi(&rng, cells: 11, jitter: 0.9)
        let lift = (0..<(11 * 11)).map { _ in rng.float() }
        var b = [Float](repeating: 0, count: 65536)
        for i in 0..<65536 {
            let dome = smoothstep(0, 9, vor.f2[i] - vor.f1[i])
            b[i] = lift[Int(vor.id[i])] * 0.45 + dome * 0.55
        }
        boulder = b
    }

    @inline(__always) static func at(_ a: [Float], _ x: Int, _ y: Int) -> Float { a[((y & 255) << 8) | (x & 255)] }
}

/// What stands at one ground pixel.
struct Column {
    var h: Int8 = 0
    /// The packed surface seen on top.
    var top: UInt32 = 0
    /// Face material below `split`, and from `split` up (roof eaves).
    var face: UInt8 = 0
    var faceHi: UInt8 = 0
    var split: Int8 = 127
    /// A picture on the faces (door, window, cave mouth), or 0.
    var overlay: UInt8 = 0
    /// Tall natural ground (terrain casts shade onto lower ground at its foot).
    var kind: UInt8 = 0
}

@inline(__always)
func surface(_ m: Mat, _ u: Int, _ v: Int, _ shade: Int) -> UInt32 {
    UInt32(m.rawValue) | (UInt32(u & 255) << 8) | (UInt32(v & 255) << 16) | (UInt32(max(0, min(255, shade))) << 24)
}

final class GroundRenderer {
    static let T = 32
    static let hMax = 32
    static let zMin = -6
    static let wallH = 24
    static let roofH = 28

    let world: World
    let tex = TextureBank.shared
    private let noise = GroundNoise.shared

    struct Key: Hashable { var x: Int; var y: Int; var z: Int; var roofs: Bool }
    private var cache: [Key: GTile] = [:]
    private var order: [Key] = []

    /// The door the Avatar is standing in (drawn open).
    private(set) var openDoor: Point?

    init(world: World) { self.world = world }

    func setOpenDoor(_ p: Point?, z: Int) {
        guard p != openDoor else { return }
        for d in [openDoor, p].compactMap({ $0 }) {
            for ty in (d.y - 1)...(d.y + 1) {
                for tx in (d.x - 1)...(d.x + 1) {
                    for roofs in [false, true] { cache.removeValue(forKey: Key(x: tx, y: ty, z: z, roofs: roofs)) }
                }
            }
        }
        openDoor = p
    }

    func tile(_ tx: Int, _ ty: Int, _ z: Int, roofs: Bool) -> GTile? {
        cache[Key(x: tx, y: ty, z: z, roofs: roofs)]
    }

    /// Makes sure every tile in the rectangle is rendered, doing the missing ones in
    /// as few batches as possible (batches share their neighbourhood work).
    func prepare(x0: Int, y0: Int, x1: Int, y1: Int, z: Int, roofs: Bool) {
        var missing: [(Int, Int)] = []
        for ty in y0..<y1 {
            for tx in x0..<x1 where cache[Key(x: tx, y: ty, z: z, roofs: roofs)] == nil { missing.append((tx, ty)) }
        }
        guard !missing.isEmpty else { return }
        let total = (x1 - x0) * (y1 - y0)
        if missing.count * 2 > total {
            render(x0: x0, y0: y0, x1: x1, y1: y1, z: z, roofs: roofs)
        } else {
            // Group by row strips and column strips.
            var rows: [Int: [Int]] = [:]
            for (tx, ty) in missing { rows[ty, default: []].append(tx) }
            let fullRows = rows.filter { $0.value.count * 2 > (x1 - x0) }.keys.sorted()
            if !fullRows.isEmpty {
                render(x0: x0, y0: fullRows.first!, x1: x1, y1: fullRows.last! + 1, z: z, roofs: roofs)
            }
            var cols: [Int: [Int]] = [:]
            for (tx, ty) in missing where !fullRows.contains(ty) { cols[tx, default: []].append(ty) }
            if !cols.isEmpty {
                let xs = cols.keys.sorted()
                var start = xs[0], prev = xs[0]
                for x in xs.dropFirst() + [Int.max] {
                    if x != prev + 1 {
                        let ys = (start...prev).flatMap { cols[$0] ?? [] }
                        render(x0: start, y0: ys.min()!, x1: prev + 1, y1: ys.max()! + 1, z: z, roofs: roofs)
                        start = x
                    }
                    prev = x
                }
            }
        }
        trim()
    }

    private func trim() {
        guard cache.count > 6000 else { return }
        cache.removeAll(keepingCapacity: true)
    }

    func invalidateAll() { cache.removeAll() }

    // MARK: Batch rendering

    private struct TileInfo {
        var t: Terrain = .grass
        var f: Feature = .none
        var roof: Int16 = -1
    }

    private func render(x0: Int, y0: Int, x1: Int, y1: Int, z: Int, roofs: Bool) {
        let T = GroundRenderer.T, H = GroundRenderer.hMax
        // Tiles with a margin for borders, wobble and the reach of the rays.
        let mx0 = x0 - 3, my0 = y0 - 3, mx1 = x1 + 4, my1 = y1 + 4
        let tw = mx1 - mx0
        var tiles = [TileInfo](repeating: TileInfo(), count: tw * (my1 - my0))
        var buildings: [Place] = []
        for ty in my0..<my1 {
            for tx in mx0..<mx1 {
                var info = TileInfo(t: world.terrain(tx, ty, z), f: world.feature(tx, ty, z))
                if z == 0, let b = world.building(at: tx, ty, z) {
                    if let i = buildings.firstIndex(where: { $0.x == b.x && $0.y == b.y }) { info.roof = Int16(i) }
                    else { buildings.append(b); info.roof = Int16(buildings.count - 1) }
                }
                tiles[(ty - my0) * tw + tx - mx0] = info
            }
        }
        let info: (Int, Int) -> TileInfo = { tx, ty in
            let cx = min(max(tx, mx0), mx1 - 1), cy = min(max(ty, my0), my1 - 1)
            return tiles[(cy - my0) * tw + cx - mx0]
        }

        // Columns for every ground pixel a ray of this batch can touch, with room to
        // the north-west for measuring how far rock runs back from its edge.
        let margin = H + 4
        let cx0 = x0 * T - margin, cy0 = y0 * T - margin
        let cw = (x1 - x0) * T + 2 * margin, ch = (y1 - y0) * T + 2 * margin
        var cols = [Column](repeating: Column(), count: cw * ch)
        var run = [UInt8](repeating: 0, count: cw * ch)
        for j in 0..<ch {
            for i in 0..<cw {
                let k = j * cw + i
                var c = column(cx0 + i, cy0 + j, z: z, roofs: roofs, info: info, buildings: buildings)
                if c.kind == 1 {
                    // Rock may only rise as fast as the view allows behind its edge, so
                    // it never leans out over open ground to the north or west.
                    let r = i > 0 && j > 0 && cols[k - cw - 1].kind == 1 && cols[k - cw - 1].face == c.face
                        ? min(250, Int(run[k - cw - 1]) + 1) : 1
                    run[k] = UInt8(r)
                    c.h = Int8(min(Int(c.h), r))
                }
                cols[k] = c
            }
        }
        refineColumns(&cols, cw: cw, ch: ch, x0: cx0, y0: cy0)

        // The highest column in each 32-pixel block, to skip empty sky quickly.
        let bw = (cw + T - 1) / T, bh = (ch + T - 1) / T
        var blockTop = [Int](repeating: GroundRenderer.zMin, count: bw * bh)
        for j in 0..<ch {
            for i in 0..<cw {
                let k = (j / T) * bw + i / T
                blockTop[k] = max(blockTop[k], Int(cols[j * cw + i].h))
            }
        }

        // March the rays for the batch's pixels (plus a one pixel rim for outlines).
        let ox0 = x0 * T - 1, oy0 = y0 * T - 1
        let ow = (x1 - x0) * T + 2, oh = (y1 - y0) * T + 2
        var outSurf = [UInt32](repeating: 0, count: ow * oh)
        var outZ = [Int8](repeating: 0, count: ow * oh)
        var outFace = [Bool](repeating: false, count: ow * oh)
        cols.withUnsafeBufferPointer { cp in
            for oy in 0..<oh {
                let sy = oy0 + oy
                let ly = sy - cy0
                let by0 = max(0, (ly + GroundRenderer.zMin) / T), by1 = min(bh - 1, (ly + H) / T)
                for ox in 0..<ow {
                    let sx = ox0 + ox
                    let lx = sx - cx0
                    let bx0 = max(0, (lx + GroundRenderer.zMin) / T), bx1 = min(bw - 1, (lx + H) / T)
                    var start = GroundRenderer.zMin
                    for by in by0...by1 { for bx in bx0...bx1 { start = max(start, blockTop[by * bw + bx]) } }
                    var zz = min(start, H)
                    var hit = false
                    while zz >= GroundRenderer.zMin {
                        let i = (ly + zz) * cw + lx + zz
                        if Int(cp[i].h) >= zz {
                            let c = cp[i]
                            let o = oy * ow + ox
                            outZ[o] = Int8(zz)
                            if Int(c.h) == zz {
                                outSurf[o] = c.top
                            } else {
                                let southOpen = Int(cp[i + cw].h) < zz
                                let eastOpen = Int(cp[i + 1].h) < zz
                                let east = !southOpen && eastOpen
                                let gx = sx + zz, gy = sy + zz
                                var m = zz >= Int(c.split) ? c.faceHi : c.face
                                var u = east ? gy : gx
                                if c.overlay != 0, zz < Int(c.split) {
                                    let ov = Mat(rawValue: c.overlay)!
                                    let lu = u & 31
                                    if tex.texel(ov, lu, zz) >> 24 != 0 { m = c.overlay; u = lu }
                                }
                                let isRock = m == Mat.rockFace.rawValue || m == Mat.caveFace.rawValue
                                var sh = east ? 112 : 86
                                var v = zz
                                if isRock {
                                    // Rock is not a flat wall: let its streaks hang straight down.
                                    sh = sh * (96 + min(40, zz * 2)) / 128 + 10
                                    u = sx
                                    v = sy
                                }
                                outSurf[o] = UInt32(m) | (UInt32(u & 255) << 8) | (UInt32(v & 255) << 16) | (UInt32(sh) << 24)
                                outFace[o] = true
                            }
                            hit = true
                            break
                        }
                        zz -= 1
                    }
                    if !hit { outSurf[oy * ow + ox] = surface(.void, 0, 0, 128) }
                }
            }
        }

        // Ink lines along silhouettes, and a soft shadow at the foot of faces.
        for ty in y0..<y1 {
            for tx in x0..<x1 {
                let g = GTile()
                for py in 0..<T {
                    for px in 0..<T {
                        let ox = (tx - x0) * T + px + 1, oy = (ty - y0) * T + py + 1
                        let o = oy * ow + ox
                        var s = outSurf[o]
                        let zc = Int(outZ[o])
                        var f: Int = 128
                        let up = Int(outZ[o - ow]), left = Int(outZ[o - 1])
                        let down = Int(outZ[o + ow]), right = Int(outZ[o + 1])
                        if up - zc >= 6 || left - zc >= 6 || down - zc >= 6 || right - zc >= 6 {
                            f = 34
                        } else if !outFace[o] {
                            if outFace[o - ow] && zc <= 1 { f = 92 }
                            else if oy >= 2 && outFace[o - 2 * ow] && zc <= 1 { f = 110 }
                            else if outFace[o - 1] && zc <= 1 { f = 100 }
                        }
                        if f != 128 {
                            let sh = Int(s >> 24) * f / 128
                            s = (s & 0x00FF_FFFF) | (UInt32(sh) << 24)
                        }
                        g.surf[py * T + px] = s
                        g.z[py * T + px] = outZ[o]
                    }
                }
                cache[Key(x: tx, y: ty, z: z, roofs: roofs)] = g
            }
        }
    }

    // MARK: Columns

    /// Natural terrain kinds that cast a little shade onto lower ground beside them.
    private static func standsHigh(_ t: Terrain) -> Bool {
        t == .grass || t == .brush || t == .forest || t == .hills || t == .swamp
    }

    private func wallMaterials(_ t: Terrain) -> (face: Mat, cap: Mat) {
        switch t {
        case .stoneWall: return (.stoneFace, .stoneCap)
        case .brickWall: return (.brickFace, .stoneCap)
        case .timberWall: return (.timberFace, .woodCap)
        default: return (.logFace, .woodCap)
        }
    }

    private func groundMat(_ t: Terrain) -> Mat {
        switch t {
        case .deepWater: return .deepWater
        case .shallowWater: return .water
        case .grass: return .grass
        case .brush: return .scrub
        case .forest: return .forestFloor
        case .swamp: return .swamp
        case .sand: return .sand
        case .dirt: return .dirt
        case .hills: return .hillGrass
        case .mountain: return .rockTop
        case .cobble: return .cobble
        case .woodFloor: return .woodFloor
        case .stoneFloor: return .flagstone
        case .brickFloor: return .brickFloor
        case .carpet: return .carpetBlue
        case .redCarpet: return .carpetRed
        case .marble: return .marble
        case .field: return .field
        case .bridge: return .deck
        case .caveFloor: return .caveFloor
        case .caveWall: return .caveTop
        case .stoneWall, .brickWall, .timberWall, .logWall: return .flagstone
        }
    }

    private func column(_ X: Int, _ Y: Int, z: Int, roofs: Bool,
                        info: (Int, Int) -> TileInfo, buildings: [Place]) -> Column {
        let T = GroundRenderer.T
        let tx = X >> 5, ty = Y >> 5, lx = X & 31, ly = Y & 31
        let me = info(tx, ty)
        var col = Column()

        // Roofs cover the whole building, walls and all, while the Avatar is outside.
        if roofs, me.roof >= 0 {
            let b = buildings[Int(me.roof)]
            let L = b.x * T + 24, R = (b.x + b.w) * T, Tp = b.y * T + 24, B = (b.y + b.h) * T
            if X >= L && X < R && Y >= Tp && Y < B {
                return roofColumn(b, X, Y, L: L, R: R, Tp: Tp, B: B, me: me, lx: lx, ly: ly, info: info, tx: tx, ty: ty)
            }
        }

        if me.t.isWall {
            let n = info(tx, ty - 1).t.isWall, w = info(tx - 1, ty).t.isWall
            let inPost = lx >= 24 && ly >= 24
            let inWest = ly >= 24 && lx < 24 && w
            let inNorth = lx >= 24 && ly < 24 && n
            if inPost || inWest || inNorth {
                let (face, cap) = wallMaterials(me.t)
                let open = me.f == .door && openDoor == Point(x: tx, y: ty)
                col.h = open ? 0 : Int8(GroundRenderer.wallH)
                col.top = open ? surface(groundMat(info(tx, ty - 1).t), X, Y, 120) : surface(cap, X, Y, 128)
                col.face = face.rawValue
                col.faceHi = face.rawValue
                switch me.f {
                case .door: col.overlay = Mat.door.rawValue
                case .window: col.overlay = Mat.window.rawValue
                case .stainedGlass: col.overlay = Mat.stainedGlass.rawValue
                default: break
                }
                return col
            }
            // Ground beside a thin wall: whatever lies on that side of it.
            var ground = info(tx, ty - 1).t
            for c in [ly < 24 ? (tx, ty - 1) : (tx, ty), lx < 24 ? (tx - 1, ty) : (tx, ty), (tx - 1, ty - 1), (tx + 1, ty), (tx, ty + 1)] {
                let t = info(c.0, c.1).t
                if !t.isWall { ground = t; break }
            }
            col.top = surface(groundMat(ground), X, Y, 128)
            col.face = Mat.bank.rawValue
            col.faceHi = col.face
            return col
        }

        // Natural ground melts into its neighbours in rounded, ragged blobs.
        let t = me.t.isNatural ? blendedTerrain(X, Y, me: me.t, info: info) : me.t

        let m = groundMat(t)
        var shade = 128
        switch t {
        case .deepWater:
            col.h = -5
        case .shallowWater:
            col.h = -3
        case .mountain, .caveWall:
            // Craggy rock; render() keeps it from leaning over open ground.
            let cave = t == .caveWall
            let c = GroundNoise.at(noise.crag, X, Y)
            let h = cave ? 17 + Int(c * 7)
                : 11 + Int(GroundNoise.at(noise.boulder, X, Y) * 17 + c * 5)
            col.h = Int8(h)
            col.kind = 1
            col.face = (cave ? Mat.caveFace : Mat.rockFace).rawValue
            col.faceHi = col.face
            col.top = surface(m, X, Y, 128)
            return col
        case .bridge:
            let west = info(tx - 1, ty).t, east = info(tx + 1, ty).t
            let horizontal = !west.isWater || !east.isWater
            let edge = horizontal ? (ly < 2 || ly >= 30) : (lx < 2 || lx >= 30)
            let post = horizontal ? (lx % 16 < 3) : (ly % 16 < 3)
            col.h = edge ? (post ? 9 : 7) : 0
            col.top = edge ? surface(.rail, X, Y, 128) : (horizontal ? surface(.deck, X, Y, 128) : surface(.deck, Y, X, 128))
            col.face = Mat.rail.rawValue
            col.faceHi = col.face
            return col
        case .hills:
            let b = { (x: Int, y: Int) -> Float in GroundNoise.at(self.noise.bump, x, y) }
            let gx = b(X + 2, Y) - b(X - 2, Y), gy = b(X, Y + 2) - b(X, Y - 2)
            shade = Int(128 * (1.0 - 1.1 * (gx + gy)))
        case .carpet, .redCarpet:
            // A gold border where the carpet ends.
            var d = 99, edgeU = X
            if info(tx, ty - 1).t != t, ly < d { d = ly; edgeU = X }
            if info(tx, ty + 1).t != t, 31 - ly < d { d = 31 - ly; edgeU = X }
            if info(tx - 1, ty).t != t, lx < d { d = lx; edgeU = Y }
            if info(tx + 1, ty).t != t, 31 - lx < d { d = 31 - lx; edgeU = Y }
            if d < 7 {
                col.top = surface(.carpetBorder, edgeU, d, 128)
                return col
            }
        default:
            break
        }
        col.top = surface(m, X, Y, shade)
        col.face = (t == .sand ? Mat.sandBank : Mat.bank).rawValue
        col.faceHi = col.face
        col.kind = GroundRenderer.standsHigh(t) ? 2 : (t.isWater ? 3 : 0)
        return col
    }

    /// Which natural terrain shows at a ground pixel. Each tile's terrain reaches out
    /// from the tile's centre and fades towards its neighbours', and ragged noise
    /// settles the contest, so borders come out rounded and frayed rather than square.
    private func blendedTerrain(_ X: Int, _ Y: Int, me: Terrain, info: (Int, Int) -> TileInfo) -> Terrain {
        let jag = GroundNoise.at(noise.fine, X, Y) * 2
        var wx = Float(X) + GroundNoise.at(noise.dx, X, Y) * 5 + jag
        var wy = Float(Y) + GroundNoise.at(noise.dy, X, Y) * 5 + jag
        var fx = (wx - 16) / 32, fy = (wy - 16) / 32
        var i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down))
        var corner = [info(i, j).t, info(i + 1, j).t, info(i, j + 1).t, info(i + 1, j + 1).t]
        let tidy = me == .cobble || corner.contains(.cobble)
        if tidy {
            // Cobbled streets keep straight kerbs.
            wx = Float(X); wy = Float(Y)
            fx = (wx - 16) / 32; fy = (wy - 16) / 32
            i = Int(fx.rounded(.down)); j = Int(fy.rounded(.down))
            corner = [info(i, j).t, info(i + 1, j).t, info(i, j + 1).t, info(i + 1, j + 1).t]
        }
        for k in 0..<4 where !corner[k].isNatural { corner[k] = me }
        if corner[0] == corner[1] && corner[0] == corner[2] && corner[0] == corner[3] { return corner[0] }
        let ax = smoothstep(0, 1, fx - Float(i)), ay = smoothstep(0, 1, fy - Float(j))
        let w = [(1 - ax) * (1 - ay), ax * (1 - ay), (1 - ax) * ay, ax * ay]
        var best = me, bestScore = -Float.greatestFiniteMagnitude
        for k in 0..<4 {
            let t = corner[k]
            if k > 0 && corner[0..<k].contains(t) { continue }
            var wt: Float = 0
            for q in 0..<4 where corner[q] == t { wt += w[q] }
            let r = Int(t.rawValue)
            let ragged = GroundNoise.at(noise.fine, X + 37 * r, Y + 91 * r) * (tidy ? 0.04 : 0.16)
                + (tidy ? 0 : GroundNoise.at(noise.dx, X + 53 * r, Y + 17 * r) * 0.12)
            let score = wt + ragged + GroundRenderer.edgeBias(t)
            if score > bestScore { bestScore = score; best = t }
        }
        return best
    }

    /// Grass creeps over paths a little; water gives way to its banks.
    private static func edgeBias(_ t: Terrain) -> Float {
        switch t {
        case .grass, .forest: return 0.04
        case .brush, .hills: return 0.02
        case .dirt: return -0.02
        case .shallowWater, .deepWater: return -0.02
        default: return 0
        }
    }

    private func roofColumn(_ b: Place, _ X: Int, _ Y: Int, L: Int, R: Int, Tp: Int, B: Int, me: TileInfo,
                            lx: Int, ly: Int, info: (Int, Int) -> TileInfo, tx: Int, ty: Int) -> Column {
        var col = Column()
        col.h = Int8(GroundRenderer.roofH)
        let dN = Y - Tp, dS = B - 1 - Y, dW = X - L, dE = R - 1 - X
        let ds = [dN, dS, dW, dE]
        var first = 0
        for k in 1..<4 where ds[k] < ds[first] { first = k }
        var second = Int.max
        for k in 0..<4 where k != first { second = min(second, ds[k]) }
        let m: Mat
        switch b.roof ?? .shingle {
        case .shingle: m = .shingle
        case .slate: m = .slate
        case .thatch: m = .thatch
        case .tile: m = .tile
        }
        var shade: Int = [134, 104, 124, 114][first]
        if second - ds[first] <= 1 { shade = shade * 62 / 100 }
        else if second - ds[first] <= 2 { shade = shade * 112 / 100 }
        if ds[first] < 2 { shade = shade * 80 / 100 }
        let (u, v) = first < 2 ? (X, ds[first]) : (Y, ds[first])
        col.top = surface(m, u, v, shade)
        // The walls below the eaves keep their faces (and doors and windows).
        let t = me.t.isWall ? me.t : info(tx, ty + 1).t
        let wallT = t.isWall ? t : Terrain.timberWall
        col.face = wallMaterials(wallT).face.rawValue
        col.faceHi = Mat.eave.rawValue
        col.split = Int8(GroundRenderer.wallH)
        if me.t.isWall {
            switch me.f {
            case .door: col.overlay = Mat.door.rawValue
            case .window: col.overlay = Mat.window.rawValue
            case .stainedGlass: col.overlay = Mat.stainedGlass.rawValue
            default: break
            }
        }
        return col
    }

    /// Second pass over the columns: surf on the shore, wet sand, and the shade that
    /// grass and rock cast onto the bare ground at their feet.
    private func refineColumns(_ cols: inout [Column], cw: Int, ch: Int, x0: Int, y0: Int) {
        let n = cw * ch
        var out = cols
        for j in 2..<(ch - 2) {
            for i in 2..<(cw - 2) {
                let k = j * cw + i
                let c = cols[k]
                if c.kind == 1 {
                    // Crags lit from the upper left.
                    let gx = Int(cols[k + 1].h) - Int(cols[k - 1].h)
                    let gy = Int(cols[k + cw].h) - Int(cols[k - cw].h)
                    let sh = max(40, min(200, 128 + (gx + gy) * 9))
                    out[k].top = (c.top & 0x00FF_FFFF) | (UInt32(sh) << 24)
                    continue
                }
                if c.kind == 3 {
                    // Water: foam where land is within two pixels.
                    var near = 9
                    for (dx, dy, d) in [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1), (2, 0, 2), (-2, 0, 2), (0, 2, 2), (0, -2, 2), (1, 1, 2), (-1, -1, 2), (1, -1, 2), (-1, 1, 2)] {
                        let q = k + dy * cw + dx
                        if q >= 0 && q < n && cols[q].kind != 3 && cols[q].h >= 0 { near = min(near, d) }
                    }
                    if near <= 2 {
                        let X = x0 + i, Y = y0 + j
                        let lace = GroundNoise.at(noise.fine, X * 2, Y * 2)
                        if near == 1 || lace > 0 { out[k].top = surface(.foam, X, Y, near == 1 ? 128 : 112) }
                    }
                    continue
                }
                guard c.h == 0, c.kind == 0 else { continue }
                let m = Mat(rawValue: UInt8(c.top & 0xFF)) ?? .void
                guard m == .dirt || m == .sand || m == .cobble || m == .field || m == .caveFloor || m == .flagstone else { continue }
                var f: Int = 128
                for (dx, dy, s) in [(-1, -1, 76), (-2, -1, 96), (-1, -2, 96), (-2, -2, 108), (0, -1, 100), (-1, 0, 100)] {
                    let q = k + dy * cw + dx
                    if cols[q].kind == 2 || (cols[q].kind == 1 && cols[q].h > 0) { f = min(f, s) }
                }
                // Wet ground at the water's edge.
                for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] where cols[k + dy * cw + dx].kind == 3 { f = min(f, 92) }
                if f != 128 {
                    let sh = Int(c.top >> 24) * f / 128
                    out[k].top = (c.top & 0x00FF_FFFF) | (UInt32(sh) << 24)
                }
            }
        }
        cols = out
    }
}
