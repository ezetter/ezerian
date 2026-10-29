import Foundation

/// A rendered object: its picture and its shadow on the ground.
struct Art {
    let sprite: Sprite
    let shadow: Sprite?
}

/// How to build one kind of object: some variants, each with some animation frames.
struct Recipe {
    var variants = 1
    var frames = 1
    var build: (inout SplitMix64, Int, Int) -> Model
}

/// Every object sprite, ray traced once at start-up (in parallel).
final class SpriteBank {
    static let shared = SpriteBank()

    /// [feature][variant][frame]
    private(set) var features: [[[Art]]]
    /// [facing][stride frame]
    private(set) var avatar: [[Art]]
    /// Pictures for hanging shop signs, by icon name.
    private(set) var signs: [String: Art] = [:]
    /// The Avatar's head and shoulders, for the side panel.
    private(set) var portrait = Sprite(w: 1, h: 1)

    private init() {
        struct Job { var key: Int; var variant: Int; var frame: Int; var recipe: Recipe }
        var jobs: [Job] = []
        for f in Feature.allCases {
            guard let r = SpriteBank.recipe(f) else { continue }
            for v in 0..<r.variants { for fr in 0..<r.frames { jobs.append(Job(key: Int(f.rawValue), variant: v, frame: fr, recipe: r)) } }
        }
        for d in Direction.allCases {
            for step in 0..<3 {
                jobs.append(Job(key: 1000 + d.rawValue, variant: 0, frame: step,
                                recipe: Recipe { _, _, fr in AvatarArt.model(facing: d, step: [0, -1, 1][fr]) }))
            }
        }
        jobs.append(Job(key: 3000, variant: 0, frame: 0, recipe: Recipe { _, _, _ in AvatarArt.portrait() }))
        let icons = StructureArt.signIcons
        for (k, icon) in icons.enumerated() {
            jobs.append(Job(key: 2000 + k, variant: 0, frame: 0, recipe: Recipe { _, _, _ in StructureArt.hangingSign(icon: icon) }))
        }
        var results = [Art?](repeating: nil, count: jobs.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
            let j = jobs[i]
            var rng = SplitMix64(seed: Hash.of(0xA27, j.key, j.variant))
            let model = j.recipe.build(&rng, j.variant, j.frame)
            let art = Art(sprite: Modeler.render(model), shadow: Modeler.shadow(model))
            lock.lock()
            results[i] = art
            lock.unlock()
        }
        var feats = [[[Art]]](repeating: [], count: 256)
        var av = [[Art]](repeating: [], count: 4)
        for (i, j) in jobs.enumerated() {
            guard let art = results[i] else { continue }
            if j.key == 3000 {
                portrait = art.sprite
            } else if j.key >= 2000 {
                signs[icons[j.key - 2000]] = art
            } else if j.key >= 1000 {
                av[j.key - 1000].append(art)
            } else {
                while feats[j.key].count <= j.variant { feats[j.key].append([]) }
                feats[j.key][j.variant].append(art)
            }
        }
        features = feats
        avatar = av
    }

    func art(_ f: Feature, variant: Int, frame: Int) -> Art? {
        let vs = features[Int(f.rawValue)]
        guard !vs.isEmpty else { return nil }
        let frames = vs[variant % vs.count]
        return frames.isEmpty ? nil : frames[frame % frames.count]
    }

    func variantCount(_ f: Feature) -> Int { max(1, features[Int(f.rawValue)].count) }

    // MARK: Recipes

    static func recipe(_ f: Feature) -> Recipe? {
        switch f {
        case .none: return nil
        case .oakTree: return Recipe(variants: 4) { r, _, _ in NatureArt.oak(&r) }
        case .pineTree: return Recipe(variants: 3) { r, _, _ in NatureArt.pine(&r) }
        case .birchTree: return Recipe(variants: 3) { r, _, _ in NatureArt.birch(&r) }
        case .palmTree: return Recipe(variants: 3) { r, _, _ in NatureArt.palm(&r) }
        case .deadTree: return Recipe(variants: 3) { r, _, _ in NatureArt.deadTree(&r) }
        case .appleTree: return Recipe(variants: 3) { r, _, _ in NatureArt.apple(&r) }
        case .blossomTree: return Recipe(variants: 3) { r, _, _ in NatureArt.blossom(&r) }
        case .bush: return Recipe(variants: 4) { r, _, _ in NatureArt.bush(&r) }
        case .berryBush: return Recipe(variants: 2) { r, _, _ in NatureArt.bush(&r, berries: 0x6A1A8A) }
        case .flowersRed: return Recipe(variants: 2) { r, _, _ in NatureArt.flowers(&r, color: 0xD8302A) }
        case .flowersYellow: return Recipe(variants: 2) { r, _, _ in NatureArt.flowers(&r, color: 0xF0C830) }
        case .flowersBlue: return Recipe(variants: 2) { r, _, _ in NatureArt.flowers(&r, color: 0x6A7AE8) }
        case .flowersWhite: return Recipe(variants: 2) { r, _, _ in NatureArt.flowers(&r, color: 0xF4F0E8) }
        case .rock: return Recipe(variants: 4) { r, _, _ in NatureArt.rock(&r, big: false) }
        case .boulder: return Recipe(variants: 3) { r, _, _ in NatureArt.rock(&r, big: true) }
        case .mushrooms: return Recipe(variants: 2) { r, _, _ in NatureArt.mushrooms(&r) }
        case .cactus: return Recipe(variants: 2) { r, _, _ in NatureArt.cactus(&r) }
        case .reeds: return Recipe(variants: 3) { r, _, _ in NatureArt.reeds(&r) }
        case .lilyPad: return Recipe(variants: 2) { r, _, _ in NatureArt.lilyPad(&r) }
        case .stump: return Recipe { r, _, _ in NatureArt.stump(&r) }
        case .fern: return Recipe(variants: 3) { r, _, _ in NatureArt.fern(&r) }
        case .deadBranch: return Recipe(variants: 3) { r, _, _ in NatureArt.deadBranch(&r) }
        case .standingStone: return Recipe(variants: 3) { r, _, _ in NatureArt.standingStone(&r) }
        default: return StructureArt.recipe(f) ?? FurnitureArt.recipe(f)
        }
    }
}
