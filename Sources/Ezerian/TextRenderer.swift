import AppKit
import CoreText

/// Words on screen are set in real fonts at the display's full resolution, laid
/// over the pixel art, rather than drawn in pixels.
enum FontKind {
    case title, body, bold, italic
}

struct TextItem: Equatable {
    enum Align { case left, center, right }
    var text: String
    /// Position in screen-art pixels: the left (or centre, or right) end of the
    /// line, and the top of its line box.
    var x: Double
    var y: Double
    var size: Double
    var font: FontKind = .body
    var color: UInt32 = 0xE8DCC0
    var align: Align = .left
    var shadow = true
}

enum TextRenderer {
    private static var fonts: [String: CTFont] = [:]
    private static let lock = NSLock()

    static func font(_ kind: FontKind, size: CGFloat) -> CTFont {
        let name: String
        switch kind {
        case .title: name = "Luminari-Regular"
        case .body: name = "IowanOldStyle-Roman"
        case .bold: name = "IowanOldStyle-Bold"
        case .italic: name = "IowanOldStyle-Italic"
        }
        let key = "\(name)@\(size)"
        lock.lock()
        defer { lock.unlock() }
        if let f = fonts[key] { return f }
        let f = CTFontCreateWithName(name as CFString, size, nil)
        fonts[key] = f
        return f
    }

    private static func line(_ s: String, _ font: CTFont, _ color: CGColor) -> CTLine {
        let attr = NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        return CTLineCreateWithAttributedString(attr)
    }

    /// Width of a string in screen-art pixels.
    static func width(_ s: String, size: Double, font kind: FontKind) -> Double {
        let f = font(kind, size: CGFloat(size))
        return CTLineGetTypographicBounds(line(s, f, CGColor(gray: 1, alpha: 1)), nil, nil, nil)
    }

    /// Breaks a string into lines no wider than `width`.
    static func wrap(_ s: String, width: Double, size: Double, font: FontKind) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in s.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if self.width(candidate, size: size, font: font) <= width || current.isEmpty {
                current = candidate
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Draws text items into a context measured in device pixels, `scale` of them to
    /// each screen-art pixel, whose y axis points up (as Core Graphics' does).
    static func draw(_ items: [TextItem], in ctx: CGContext, scale: CGFloat, height: CGFloat) {
        ctx.saveGState()
        ctx.setShouldAntialias(true)
        ctx.setShouldSmoothFonts(false)
        for item in items {
            let f = font(item.font, size: CGFloat(item.size) * scale)
            let c = item.color
            let color = CGColor(srgbRed: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255,
                                blue: CGFloat(c & 0xFF) / 255, alpha: 1)
            let l = line(item.text, f, color)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(l, &ascent, &descent, nil))
            var x = CGFloat(item.x) * scale
            switch item.align {
            case .left: break
            case .center: x -= w / 2
            case .right: x -= w
            }
            // Baseline: the top of the line box plus the font's ascent.
            let lineTop = CGFloat(item.y) * scale
            let baseline = height - (lineTop + CTFontGetAscent(f) * 1.02)
            if item.shadow {
                let dark = item.color & 0xFFFFFF < 0x606060 ? CGColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 0.35)
                    : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
                let sl = line(item.text, f, dark)
                ctx.textPosition = CGPoint(x: x + max(1, scale * 0.6), y: baseline - max(1, scale * 0.6))
                CTLineDraw(sl, ctx)
            }
            ctx.textPosition = CGPoint(x: x, y: baseline)
            CTLineDraw(l, ctx)
        }
        ctx.restoreGState()
    }
}
