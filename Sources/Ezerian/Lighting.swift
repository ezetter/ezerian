import Foundation
import simd

/// The light of the hour: sunshine by day, blue moonlight by night, warm pools
/// round torches, lamps and hearths, and the Avatar's own lantern after dark or
/// underground. Computed on a coarse grid and blended smoothly across the view.
final class Lighting {
    struct Source {
        var x: Float
        var y: Float
        var radius: Float
        var color: Col
        /// Index of the building the light is in (it lights only that room), or -1.
        var building: Int
    }

    static let cell = 8
    private let cw = MapRenderer.pixelW / Lighting.cell + 2
    private let ch = MapRenderer.pixelH / Lighting.cell + 2
    private var grid: [Col]

    init() { grid = Array(repeating: Col(repeating: 1), count: (MapRenderer.pixelW / Lighting.cell + 2) * (MapRenderer.pixelH / Lighting.cell + 2)) }

    /// Colour multiplier of the open sky at an hour (0..<24).
    static func sky(_ hour: Double) -> Col {
        let night = Col(0.30, 0.34, 0.54), dawn = Col(0.92, 0.70, 0.62), dusk = Col(1.0, 0.70, 0.52), day = Col(1, 1, 1)
        let h = Float(hour)
        switch h {
        case 4.5..<6: return mix(night, dawn, (h - 4.5) / 1.5)
        case 6..<7.5: return mix(dawn, day, (h - 6) / 1.5)
        case 7.5..<17.5: return day
        case 17.5..<19: return mix(day, dusk, (h - 17.5) / 1.5)
        case 19..<20.5: return mix(dusk, night, (h - 19) / 1.5)
        default: return night
        }
    }

    /// How strong the sun's shadows are at an hour.
    static func sunShadow(_ hour: Double) -> Float {
        let h = Float(hour)
        return smoothstep(5.5, 7.5, h) * (1 - smoothstep(17, 19.5, h))
    }

    /// Light that objects give off: how far it reaches (in pixels) and its colour.
    static func emitter(_ f: Feature) -> (radius: Float, color: Col)? {
        switch f {
        case .wallTorch: return (120, Col(1.25, 0.86, 0.5))
        case .lampPost: return (150, Col(1.2, 1.0, 0.66))
        case .fireplace: return (170, Col(1.4, 0.78, 0.42))
        case .campfire: return (170, Col(1.45, 0.82, 0.45))
        case .forge: return (140, Col(1.4, 0.7, 0.36))
        case .candelabra: return (110, Col(1.15, 0.9, 0.58))
        case .tableCandle, .nightstand: return (80, Col(1.1, 0.88, 0.58))
        case .altar: return (90, Col(1.1, 0.9, 0.6))
        case .shrine: return (110, Col(1.1, 0.5, 1.05))
        case .cauldron: return (70, Col(0.6, 1.0, 0.5))
        case .ladderUp: return (130, Col(1.0, 0.98, 0.9))
        default: return nil
        }
    }

    /// Fills the grid for this frame. `ambient` is the multiplier of unlit ground.
    func compute(ambient: Col, sources: [Source], camX: Int, camY: Int, buildingAt: (Int, Int) -> Int) {
        let c = Lighting.cell
        var cellBuilding = [Int](repeating: -1, count: cw * ch)
        let needRooms = sources.contains { $0.building >= 0 }
        if needRooms {
            for j in 0..<ch {
                for i in 0..<cw {
                    let wx = camX + i * c, wy = camY + j * c
                    cellBuilding[j * cw + i] = buildingAt(floorDiv(wx, MapRenderer.tile), floorDiv(wy, MapRenderer.tile))
                }
            }
        }
        for j in 0..<ch {
            for i in 0..<cw {
                var l = ambient
                let px = Float(i * c), py = Float(j * c)
                for s in sources {
                    if s.building >= 0 && cellBuilding[j * cw + i] != s.building { continue }
                    let dx = px - s.x, dy = py - s.y
                    let d2 = dx * dx + dy * dy
                    let r2 = s.radius * s.radius
                    if d2 >= r2 { continue }
                    let f = 1 - (d2 / r2).squareRoot()
                    l += s.color * (f * f * (3 - 2 * f))
                }
                grid[j * cw + i] = simd_min(l, Col(repeating: 1.6))
            }
        }
    }

    /// Multiplies the map by the light grid (skipping pixels that glow by themselves).
    func apply(to fb: Framebuffer, at mapX: Int, _ mapY: Int, glow: [Bool]) {
        let c = Lighting.cell, W = MapRenderer.pixelW, H = MapRenderer.pixelH
        let inv = 1 / Float(c)
        grid.withUnsafeBufferPointer { g in
            fb.pixels.withUnsafeMutableBufferPointer { px in
                for y in 0..<H {
                    let gy = Float(y) * inv
                    let j = min(ch - 2, Int(gy)), fy = gy - Float(j)
                    for x in 0..<W where !glow[y * W + x] {
                        let gx = Float(x) * inv
                        let i = min(cw - 2, Int(gx)), fx = gx - Float(i)
                        let a = g[j * cw + i], b = g[j * cw + i + 1], cc = g[(j + 1) * cw + i], d = g[(j + 1) * cw + i + 1]
                        let l = (a * (1 - fx) + b * fx) * (1 - fy) + (cc * (1 - fx) + d * fx) * fy
                        let k = (mapY + y) * fb.width + mapX + x
                        let p = px[k]
                        let r = min(255, Int(Float(p & 0xFF) * l.x))
                        let gg = min(255, Int(Float((p >> 8) & 0xFF) * l.y))
                        let bb = min(255, Int(Float((p >> 16) & 0xFF) * l.z))
                        px[k] = 0xFF00_0000 | UInt32(bb) << 16 | UInt32(gg) << 8 | UInt32(r)
                    }
                }
            }
        }
    }
}
