import Foundation
import simd

/// Draws the map view: the cached ground picture shaded with its textures, then
/// every object and the Avatar, depth-tested against it, then the light of the hour.
final class MapRenderer {
    static let tile = 32
    static let viewW = Game.viewW
    static let viewH = Game.viewH
    static let pixelW = viewW * tile
    static let pixelH = viewH * tile

    let ground: GroundRenderer
    let lighting = Lighting()
    private let tex = TextureBank.shared
    var zbuf = [Float](repeating: 0, count: MapRenderer.pixelW * MapRenderer.pixelH)
    var glow = [Bool](repeating: false, count: MapRenderer.pixelW * MapRenderer.pixelH)
    /// Which tile's object covers each pixel (for looking at things with the mouse).
    var owner = [Int32](repeating: -1, count: MapRenderer.pixelW * MapRenderer.pixelH)
    private(set) var camX = 0
    private(set) var camY = 0
    /// Tile that `owner` indices count from.
    var ownerOrigin = (0, 0)

    init(world: World) {
        ground = GroundRenderer(world: world)
    }

    /// The world pixel at the top-left of the view when the Avatar stands at (x, y).
    static func camera(x: Double, y: Double) -> (Int, Int) {
        (Int((x * Double(tile)).rounded()) + tile / 2 - pixelW / 2 - 8,
         Int((y * Double(tile)).rounded()) + tile / 2 - pixelH / 2 - 10)
    }

    /// Renders the ground for a view whose top-left is world pixel (cx, cy).
    func drawGround(_ game: Game, into fb: Framebuffer, at mapX: Int, _ mapY: Int,
                    camX cx: Int, camY cy: Int, frame: Int, roofs: Bool) {
        camX = cx
        camY = cy
        let T = MapRenderer.tile, W = MapRenderer.pixelW, H = MapRenderer.pixelH
        let z = game.z
        let tx0 = floorDiv(cx, T), ty0 = floorDiv(cy, T)
        let tx1 = floorDiv(cx + W - 1, T) + 1, ty1 = floorDiv(cy + H - 1, T) + 1
        ground.prepare(x0: tx0, y0: ty0, x1: tx1, y1: ty1, z: z, roofs: roofs)

        var remap = [Int](repeating: 0, count: 256)
        for m in Mat.allCases { remap[Int(m.rawValue)] = tex.slot(m, frame: frame) << 16 }
        let texels = tex.data
        let fbw = fb.width
        fb.pixels.withUnsafeMutableBufferPointer { dst in
            zbuf.withUnsafeMutableBufferPointer { zb in
                for ty in ty0..<ty1 {
                    for tx in tx0..<tx1 {
                        guard let g = ground.tile(tx, ty, z, roofs: roofs) else { continue }
                        let px0 = max(0, tx * T - cx), py0 = max(0, ty * T - cy)
                        let px1 = min(W, tx * T + T - cx), py1 = min(H, ty * T + T - cy)
                        guard px0 < px1, py0 < py1 else { continue }
                        g.surf.withUnsafeBufferPointer { surf in
                            g.z.withUnsafeBufferPointer { gz in
                                for py in py0..<py1 {
                                    let ly = (py + cy) - ty * T
                                    var d = (mapY + py) * fbw + mapX + px0
                                    var zi = py * W + px0
                                    for px in px0..<px1 {
                                        let lx = (px + cx) - tx * T
                                        let s = surf[ly * T + lx]
                                        let t = texels[remap[Int(s & 0xFF)] | Int((s >> 16) & 0xFF) << 8 | Int((s >> 8) & 0xFF)]
                                        let k = Int(s >> 24)
                                        let r = min(255, (Int(t & 0xFF) * k) >> 7)
                                        let gg = min(255, (Int((t >> 8) & 0xFF) * k) >> 7)
                                        let b = min(255, (Int((t >> 16) & 0xFF) * k) >> 7)
                                        dst[d] = 0xFF00_0000 | UInt32(b) << 16 | UInt32(gg) << 8 | UInt32(r)
                                        zb[zi] = Float(gz[ly * T + lx])
                                        d += 1
                                        zi += 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        for i in glow.indices { glow[i] = false }
        for i in owner.indices { owner[i] = -1 }
    }
}

private struct DrawItem {
    var art: Art
    var x: Int
    var y: Int
    var owner: Int32
    var ghost: Bool
}

/// Where and how to draw the Avatar this frame (position in tiles, may be between two).
struct AvatarPose {
    var x: Double
    var y: Double
    var facing: Direction
    var step: Int
}

extension MapRenderer {
    /// Draws every object in view and the Avatar, back to front, each pixel tested
    /// against the depth of what is already there. Objects inside a building are
    /// left out while its roof is on.
    func drawObjects(_ game: Game, into fb: Framebuffer, at mapX: Int, _ mapY: Int,
                     frame: Int, roofs: Bool, avatar: AvatarPose, shadowStrength: Float = 1) {
        let bank = SpriteBank.shared
        let T = MapRenderer.tile, W = MapRenderer.pixelW, H = MapRenderer.pixelH
        let world = game.world, z = game.z
        let tx0 = floorDiv(camX, T) - 1, ty0 = floorDiv(camY, T) - 1
        let tx1 = floorDiv(camX + W - 1, T) + 4, ty1 = floorDiv(camY + H - 1, T) + 4
        var items: [DrawItem] = []
        let avatarRow = Int(avatar.y.rounded(.up))
        var avatarDone = false
        for ty in ty0..<ty1 {
            for tx in tx0..<tx1 {
                let f = world.feature(tx, ty, z)
                // Woods are thick with trees, each a little off the grid.
                if z == 0, world.terrain(tx, ty, z) == .forest {
                    let h = Hash.of(world.seed, tx, ty, 11)
                    if h % 100 < 82 {
                        let kind: Feature = h % 7 < 4 ? .oakTree : (h % 7 < 6 ? .pineTree : .birchTree)
                        let jx = Int((h >> 8) % 11) - 5, jy = Int((h >> 16) % 9) - 4
                        if let a = bank.art(kind, variant: Int((h >> 24) % 7), frame: 0) {
                            items.append(DrawItem(art: a, x: tx * T - camX + jx, y: ty * T - camY + jy,
                                                  owner: Int32((ty - ty0) * 256 + (tx - tx0)), ghost: false))
                        }
                    }
                }
                guard f != .none, f != .door, f != .window, f != .stainedGlass, f != .bedFoot else { continue }
                if roofs, world.building(at: tx, ty, z) != nil { continue }
                let h = Hash.of(world.seed, tx, ty, 3)
                let v = variant(f, tx, ty, z, world, h)
                let fr = frame / 2 + Int(h % 4)
                var art = bank.art(f, variant: v, frame: fr)
                if f == .hangingSign, let icon = world.sign(tx, ty, z)?.icon, let s = bank.signs[icon] { art = s }
                guard let a = art else { continue }
                items.append(DrawItem(art: a, x: tx * T - camX, y: ty * T - camY,
                                      owner: Int32((ty - ty0) * 256 + (tx - tx0)), ghost: false))
            }
            if ty == avatarRow {
                items.append(avatarItem(avatar, bank))
                avatarDone = true
            }
        }
        if !avatarDone { items.append(avatarItem(avatar, bank)) }
        ownerOrigin = (tx0, ty0)

        if shadowStrength > 0.05 {
            for it in items { if let s = it.art.shadow { drawShadow(s, it.x, it.y, fb, mapX, mapY, shadowStrength) } }
        }
        for it in items { drawSprite(it.art.sprite, it.x, it.y, owner: it.owner, ghost: it.ghost, fb, mapX, mapY) }
    }

    private func avatarItem(_ p: AvatarPose, _ bank: SpriteBank) -> DrawItem {
        let a = bank.avatar[p.facing.rawValue][p.step % 3]
        let T = Double(MapRenderer.tile)
        return DrawItem(art: a, x: Int((p.x * T).rounded()) - camX, y: Int((p.y * T).rounded()) - camY, owner: -2, ghost: true)
    }

    private func variant(_ f: Feature, _ tx: Int, _ ty: Int, _ z: Int, _ world: World, _ h: UInt64) -> Int {
        switch f {
        case .fence:
            var mask = 0
            for (bit, (dx, dy)) in [(1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))]
                where world.feature(tx + dx, ty + dy, z) == .fence { mask |= bit }
            return mask
        case .counter, .pew:
            return (world.feature(tx - 1, ty, z) == f ? 1 : 0) | (world.feature(tx + 1, ty, z) == f ? 2 : 0)
        case .chair:
            let isTable: (Feature) -> Bool = { [.table, .tableMug, .tableFood, .tableCandle].contains($0) }
            let east = isTable(world.feature(tx + 1, ty, z)) || !isTable(world.feature(tx - 1, ty, z))
            return (east ? 0 : 1) + Int(h % 2) * 2
        case .wallTorch, .banner, .painting:
            let ewWall = world.terrain(tx - 1, ty, z).isWall || world.terrain(tx + 1, ty, z).isWall
            return (f == .painting ? Int(h % 3) * 2 : 0) + (ewWall ? 0 : 1)
        default:
            return Int(h % UInt64(SpriteBank.shared.variantCount(f)))
        }
    }

    private func drawShadow(_ s: Sprite, _ x: Int, _ y: Int, _ fb: Framebuffer, _ mapX: Int, _ mapY: Int, _ k: Float) {
        let W = MapRenderer.pixelW, H = MapRenderer.pixelH
        let ox = x - s.ax, oy = y - s.ay
        guard ox < W, oy < H, ox + s.w > 0, oy + s.h > 0 else { return }
        for py in max(0, -oy)..<min(s.h, H - oy) {
            for px in max(0, -ox)..<min(s.w, W - ox) {
                let a = s.px[py * s.w + px] >> 24
                guard a > 0 else { continue }
                let mx = ox + px, my = oy + py
                guard zbuf[my * W + mx] <= 1.5 else { continue }
                let i = (mapY + my) * fb.width + mapX + mx
                fb.pixels[i] = shade(fb.pixels[i], Double(1 - Float(a) / 255 * k))
            }
        }
    }

    private func drawSprite(_ s: Sprite, _ x: Int, _ y: Int, owner who: Int32, ghost: Bool,
                            _ fb: Framebuffer, _ mapX: Int, _ mapY: Int) {
        let W = MapRenderer.pixelW, H = MapRenderer.pixelH
        let ox = x - s.ax, oy = y - s.ay
        guard ox < W, oy < H, ox + s.w > 0, oy + s.h > 0 else { return }
        for py in max(0, -oy)..<min(s.h, H - oy) {
            for px in max(0, -ox)..<min(s.w, W - ox) {
                let si = py * s.w + px
                let c = s.px[si]
                guard c >> 24 != 0 else { continue }
                let mx = ox + px, my = oy + py
                let zi = my * W + mx
                let d = s.depth[si]
                let i = (mapY + my) * fb.width + mapX + mx
                if d >= zbuf[zi] - 1 {
                    fb.pixels[i] = c | 0xFF00_0000
                    zbuf[zi] = d
                    glow[zi] = s.glow[si]
                    owner[zi] = who
                } else if ghost {
                    fb.pixels[i] = blend(fb.pixels[i], c, 0.38)
                }
            }
        }
    }

    /// The tile a map pixel shows: an object's tile if one covers it, otherwise the
    /// ground under whatever surface is there.
    func tileAt(mapPixel mx: Int, _ my: Int) -> (x: Int, y: Int)? {
        let W = MapRenderer.pixelW, H = MapRenderer.pixelH
        guard mx >= 0, my >= 0, mx < W, my < H else { return nil }
        let o = owner[my * W + mx]
        if o >= 0 { return (ownerOrigin.0 + Int(o) % 256, ownerOrigin.1 + Int(o) / 256) }
        let zh = max(0, Int(zbuf[my * W + mx]))
        return (floorDiv(camX + mx + zh, MapRenderer.tile), floorDiv(camY + my + zh, MapRenderer.tile))
    }
}

extension MapRenderer {
    /// One complete frame of the map: ground, objects, Avatar and the light of the hour.
    func draw(_ game: Game, pose: AvatarPose, into fb: Framebuffer, at mapX: Int, _ mapY: Int,
              frame: Int, clock: Double) {
        let world = game.world, z = game.z
        let roofs = z == 0 && !game.isIndoors
        ground.setOpenDoor(world.feature(game.x, game.y, z) == .door ? Point(x: game.x, y: game.y) : nil, z: z)
        let (cx, cy) = MapRenderer.camera(x: pose.x, y: pose.y)
        drawGround(game, into: fb, at: mapX, mapY, camX: cx, camY: cy, frame: frame, roofs: roofs)
        let hour = game.hourOfDay
        let under = game.isUnderground
        drawObjects(game, into: fb, at: mapX, mapY, frame: frame, roofs: roofs, avatar: pose,
                    shadowStrength: under ? 0 : Lighting.sunShadow(hour))

        let sky = under ? Col(0.12, 0.1, 0.09) : Lighting.sky(hour)
        if under || simd_reduce_min(sky) < 0.995 {
            let sources = lightSources(game, pose: pose, roofs: roofs, clock: clock, night: under ? 1 : 1 - Lighting.sunShadow(hour))
            lighting.compute(ambient: sky, sources: sources, camX: camX, camY: camY) { tx, ty in
                guard let b = world.building(at: tx, ty, z) else { return -1 }
                return MapRenderer.buildingKey(b)
            }
            lighting.apply(to: fb, at: mapX, mapY, glow: glow)
        }
        if game.showGrid { drawRegionGrid(game, fb, mapX, mapY) }
    }

    static func buildingKey(_ b: Place) -> Int { b.x &* 100_003 &+ b.y }

    private func lightSources(_ game: Game, pose: AvatarPose, roofs: Bool, clock: Double, night: Float) -> [Lighting.Source] {
        let world = game.world, z = game.z, T = MapRenderer.tile
        var out: [Lighting.Source] = []
        let tx0 = floorDiv(camX, T) - 5, ty0 = floorDiv(camY, T) - 5
        let tx1 = floorDiv(camX + MapRenderer.pixelW, T) + 6, ty1 = floorDiv(camY + MapRenderer.pixelH, T) + 6
        for ty in ty0..<ty1 {
            for tx in tx0..<tx1 {
                let f = world.feature(tx, ty, z)
                guard f != .none else { continue }
                let b = world.building(at: tx, ty, z)
                if f == .window || f == .stainedGlass {
                    // Lit windows glow out into the night while the roofs are on.
                    guard roofs, night > 0.3, let b else { continue }
                    let (dx, dy): (Float, Float)
                    if ty == b.y + b.h - 1 { (dx, dy) = (16, 42) }
                    else if tx == b.x + b.w - 1 { (dx, dy) = (42, 16) }
                    else if ty == b.y { (dx, dy) = (16, -4) }
                    else if tx == b.x { (dx, dy) = (-4, 16) }
                    else { continue }
                    out.append(Lighting.Source(x: Float(tx * T - camX) + dx, y: Float(ty * T - camY) + dy, radius: 44,
                                               color: Col(0.9, 0.62, 0.3) * night, building: -1))
                    continue
                }
                guard let e = Lighting.emitter(f) else { continue }
                if b != nil && roofs { continue }
                // Light falls round the object's foot; a wall torch's out from its wall.
                var (dx, dy): (Float, Float) = (16, 17)
                if f == .wallTorch {
                    let ew = world.terrain(tx - 1, ty, z).isWall || world.terrain(tx + 1, ty, z).isWall
                    (dx, dy) = ew ? (16, 38) : (38, 16)
                }
                let h = Float(Hash.unit(world.seed, tx, ty, 9))
                let flicker: Float = 0.92 + 0.08 * Float(sin(clock * 9 + Double(h) * 40))
                out.append(Lighting.Source(x: Float(tx * T - camX) + dx, y: Float(ty * T - camY) + dy,
                                           radius: e.radius, color: e.color * flicker,
                                           building: b.map(MapRenderer.buildingKey) ?? -1))
            }
        }
        // The Avatar's lantern, or torch underground.
        let ax = Float(pose.x * Double(T)) - Float(camX) + 16, ay = Float(pose.y * Double(T)) - Float(camY) + 17
        if game.isUnderground {
            let fl: Float = 0.94 + 0.06 * Float(sin(clock * 7.3))
            out.append(Lighting.Source(x: ax, y: ay, radius: 250, color: Col(1.15, 0.92, 0.62) * fl, building: -1))
        } else if night > 0.2 {
            out.append(Lighting.Source(x: ax, y: ay, radius: 120, color: Col(0.62, 0.52, 0.36) * night, building: -1))
        }
        return out
    }

    private func drawRegionGrid(_ game: Game, _ fb: Framebuffer, _ mapX: Int, _ mapY: Int) {
        let line = rgb(0xFFE070)
        let W = MapRenderer.pixelW, H = MapRenderer.pixelH, n = Region.size * MapRenderer.tile
        for px in 0..<W where floorMod(camX + px, n) == 0 {
            for py in stride(from: 0, to: H, by: 2) { fb.set(mapX + px, mapY + py, line) }
        }
        for py in 0..<H where floorMod(camY + py, n) == 0 {
            for px in stride(from: 0, to: W, by: 2) { fb.set(mapX + px, mapY + py, line) }
        }
    }
}
