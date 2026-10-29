import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import simd

// Pixels are 32-bit RGBA in memory order (R in the lowest byte).

typealias Col = SIMD3<Float>

/// A colour from 0xRRGGBB, as floats in 0...1.
@inline(__always)
func hex(_ h: UInt32) -> Col {
    Col(Float((h >> 16) & 0xFF), Float((h >> 8) & 0xFF), Float(h & 0xFF)) / 255
}

@inline(__always)
func pack(_ c: Col, alpha: UInt32 = 255) -> UInt32 {
    let s = simd_clamp(c * 255 + 0.5, Col(repeating: 0), Col(repeating: 255))
    return (alpha << 24) | (UInt32(s.z) << 16) | (UInt32(s.y) << 8) | UInt32(s.x)
}

@inline(__always)
func unpack(_ p: UInt32) -> Col {
    Col(Float(p & 0xFF), Float((p >> 8) & 0xFF), Float((p >> 16) & 0xFF)) / 255
}

@inline(__always) func alphaOf(_ c: UInt32) -> UInt32 { c >> 24 }

@inline(__always) func mix(_ a: Col, _ b: Col, _ t: Float) -> Col { a + (b - a) * t }
@inline(__always) func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }
@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

/// Multiplies a colour's brightness by `f` (f < 1 darkens, f > 1 brightens).
@inline(__always)
func shade(_ c: UInt32, _ f: Double) -> UInt32 {
    let r = min(255, Double(c & 0xFF) * f)
    let g = min(255, Double((c >> 8) & 0xFF) * f)
    let b = min(255, Double((c >> 16) & 0xFF) * f)
    return (c & 0xFF00_0000) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
}

/// Linear blend between two colours (t = 0 gives `a`); the result is opaque.
@inline(__always)
func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func ch(_ s: UInt32) -> UInt32 {
        let x = Double((a >> s) & 0xFF), y = Double((b >> s) & 0xFF)
        return UInt32(max(0, min(255, x + (y - x) * t))) << s
    }
    return 0xFF00_0000 | ch(16) | ch(8) | ch(0)
}

/// A picture of an object. `depth` holds, for every opaque pixel, the height above
/// the ground of the surface seen there (see `MapRenderer` for why that works as a
/// depth buffer). `(ax, ay)` is where the object's origin (the top-left ground
/// corner of its tile) falls in the picture.
struct Sprite {
    var w: Int
    var h: Int
    var px: [UInt32]
    var depth: [Float]
    var ax: Int
    var ay: Int
    /// Pixels that give off their own light (flames) and ignore the darkness.
    var glow: [Bool]

    init(w: Int, h: Int, ax: Int = 0, ay: Int = 0) {
        self.w = w
        self.h = h
        self.ax = ax
        self.ay = ay
        px = Array(repeating: 0, count: w * h)
        depth = Array(repeating: -1000, count: w * h)
        glow = Array(repeating: false, count: w * h)
    }
}

final class Framebuffer {
    let width: Int
    let height: Int
    var pixels: [UInt32]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: rgb(0x000000), count: width * height)
    }

    func clear(_ c: UInt32) {
        for i in pixels.indices { pixels[i] = c }
    }

    @inline(__always)
    func set(_ x: Int, _ y: Int, _ c: UInt32) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        pixels[y * width + x] = c
    }

    @inline(__always)
    func get(_ x: Int, _ y: Int) -> UInt32 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return pixels[y * width + x]
    }

    /// Alpha-blends a colour onto one pixel.
    @inline(__always)
    func plot(_ x: Int, _ y: Int, _ c: Col, _ a: Float) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = y * width + x
        pixels[i] = pack(mix(unpack(pixels[i]), c, a))
    }

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
        let x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            let row = yy * width
            for xx in x0..<x1 { pixels[row + xx] = c }
        }
    }

    func hline(_ x: Int, _ y: Int, _ w: Int, _ c: UInt32) { fill(x, y, w, 1, c) }
    func vline(_ x: Int, _ y: Int, _ h: Int, _ c: UInt32) { fill(x, y, 1, h, c) }

    /// Darkens (f < 1) or lightens (f > 1) a rectangle in place.
    func tint(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ f: Double) {
        let x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { pixels[yy * width + xx] = shade(pixels[yy * width + xx], f) }
        }
    }

    /// Blends a translucent colour over a rectangle.
    func wash(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Col, _ a: Float) {
        let x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 { pixels[yy * width + xx] = pack(mix(unpack(pixels[yy * width + xx]), c, a)) }
        }
    }

    /// Draws a sprite with its anchor at (x, y), blending translucent pixels.
    func blit(_ s: Sprite, _ x: Int, _ y: Int, clip: (x: Int, y: Int, w: Int, h: Int)? = nil) {
        let ox = x - s.ax, oy = y - s.ay
        let cx0 = clip?.x ?? 0, cy0 = clip?.y ?? 0
        let cx1 = clip.map { $0.x + $0.w } ?? width, cy1 = clip.map { $0.y + $0.h } ?? height
        let x0 = max(ox, max(0, cx0)), y0 = max(oy, max(0, cy0))
        let x1 = min(ox + s.w, min(width, cx1)), y1 = min(oy + s.h, min(height, cy1))
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 {
                let c = s.px[(yy - oy) * s.w + xx - ox]
                let a = c >> 24
                if a == 255 { pixels[yy * width + xx] = c }
                else if a > 0 { plot(xx, yy, unpack(c), Float(a) / 255) }
            }
        }
    }

    /// Blits a sprite scaled up by an integer factor (top-left at x, y).
    func blitScaled(_ s: Sprite, _ x: Int, _ y: Int, scale: Int) {
        for sy in 0..<s.h {
            for sx in 0..<s.w {
                let c = s.px[sy * s.w + sx]
                if c >> 24 > 127 { fill(x + sx * scale, y + sy * scale, scale, scale, c | 0xFF00_0000) }
            }
        }
    }

    func makeImage() -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Writes the buffer as a PNG, enlarged by an integer factor (handy for previews).
    @discardableResult
    func writePNG(to path: String, scale: Int = 1) -> Bool {
        guard let image = makeImage() else { return false }
        return Framebuffer.writePNG(image, to: path, scale: scale)
    }

    @discardableResult
    static func writePNG(_ image: CGImage, to path: String, scale: Int = 1) -> Bool {
        var out = image
        if scale != 1,
           let ctx = CGContext(data: nil, width: image.width * scale, height: image.height * scale,
                               bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale))
            if let scaled = ctx.makeImage() { out = scaled }
        }
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest)
    }
}
