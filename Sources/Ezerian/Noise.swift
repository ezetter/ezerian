import Foundation

/// Small, fast, seedable PRNG (SplitMix64). Deterministic across runs and platforms.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform integer in 0..<n.
    mutating func int(_ n: Int) -> Int {
        precondition(n > 0)
        return Int(next() % UInt64(n))
    }

    /// Uniform integer in the closed range.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + int(range.upperBound - range.lowerBound + 1)
    }

    /// Uniform double in [0, 1).
    mutating func double() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func chance(_ p: Double) -> Bool { double() < p }

    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }

    mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, int(i + 1))
        }
    }
}

/// Stateless integer hashing used for per-tile decisions that must be stable
/// regardless of the order in which regions are generated.
enum Hash {
    @inline(__always)
    static func mix(_ v: UInt64) -> UInt64 {
        var z = v &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    @inline(__always)
    static func of(_ seed: UInt64, _ a: Int, _ b: Int, _ c: Int = 0) -> UInt64 {
        var h = mix(seed ^ 0x51_7CC1_B727_220A)
        h = mix(h ^ UInt64(bitPattern: Int64(a)))
        h = mix(h ^ UInt64(bitPattern: Int64(b)) &* 0x2545_F491_4F6C_DD1D)
        h = mix(h ^ UInt64(bitPattern: Int64(c)) &* 0x9E37_79B9)
        return h
    }

    /// Uniform double in [0, 1) derived from the coordinates.
    @inline(__always)
    static func unit(_ seed: UInt64, _ a: Int, _ b: Int, _ c: Int = 0) -> Double {
        Double(of(seed, a, b, c) >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

/// Classic 2D gradient (Perlin) noise with fractal sums.
struct Perlin {
    private let perm: [Int]

    init(seed: UInt64) {
        var rng = SplitMix64(seed: seed)
        var p = Array(0..<256)
        rng.shuffle(&p)
        perm = p + p
    }

    @inline(__always) private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    @inline(__always) private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    @inline(__always) private func grad(_ h: Int, _ x: Double, _ y: Double) -> Double {
        switch h & 7 {
        case 0: return x + y
        case 1: return -x + y
        case 2: return x - y
        case 3: return -x - y
        case 4: return x
        case 5: return -x
        case 6: return y
        default: return -y
        }
    }

    /// Roughly in [-1, 1].
    func noise(_ x: Double, _ y: Double) -> Double {
        let xf = x.rounded(.down), yf = y.rounded(.down)
        let xi = Int(xf) & 255, yi = Int(yf) & 255
        let x = x - xf, y = y - yf
        let u = fade(x), v = fade(y)
        let a = perm[xi] + yi, b = perm[xi + 1] + yi
        let x1 = lerp(grad(perm[a], x, y), grad(perm[b], x - 1, y), u)
        let x2 = lerp(grad(perm[a + 1], x, y - 1), grad(perm[b + 1], x - 1, y - 1), u)
        return lerp(x1, x2, v)
    }

    /// Fractal Brownian motion, normalised to roughly [-0.7, 0.7].
    func fbm(_ x: Double, _ y: Double, octaves: Int, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += amp * noise(x * freq, y * freq)
            norm += amp
            amp *= gain
            freq *= 2
        }
        return sum / norm
    }
}

/// Tileable value noise on a square grid, used to build seamless pixel textures.
struct PeriodicNoise {
    let size: Int
    let cells: Int
    private let lattice: [Double]

    init(size: Int, cells: Int, rng: inout SplitMix64) {
        self.size = size
        self.cells = cells
        lattice = (0..<(cells * cells)).map { _ in rng.double() }
    }

    /// Smoothly interpolated value in [0, 1] at a pixel coordinate (wraps at `size`).
    func value(_ x: Int, _ y: Int) -> Double {
        let fx = Double(((x % size) + size) % size) * Double(cells) / Double(size)
        let fy = Double(((y % size) + size) % size) * Double(cells) / Double(size)
        let x0 = Int(fx), y0 = Int(fy)
        let tx = fx - Double(x0), ty = fy - Double(y0)
        let x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
        let a = lattice[y0 * cells + x0], b = lattice[y0 * cells + x1]
        let c = lattice[y1 * cells + x0], d = lattice[y1 * cells + x1]
        let top = a + (b - a) * sx, bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }
}
