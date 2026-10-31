import Foundation

/// What people fight with. Every blow does 1-10 damage, plus the weapon's bonus.
enum Weapon: Int, Codable, CaseIterable, Comparable {
    case staff = 1, dagger, mace, shortSword, longSword
    /// The arms of Lord Draconian's orcs (numbered after the first five, for saves).
    case hammer, axe, spear

    var bonus: Int {
        switch self {
        case .hammer: return 4
        case .axe, .spear: return 6
        default: return rawValue * 2
        }
    }

    var name: String {
        switch self {
        case .staff: return "staff"
        case .dagger: return "dagger"
        case .mace: return "mace"
        case .shortSword: return "short sword"
        case .longSword: return "long sword"
        case .hammer: return "war hammer"
        case .axe: return "axe"
        case .spear: return "spear"
        }
    }

    var article: String { self == .axe ? "an" : "a" }

    /// Better is more damage; between equals, the later weapon.
    static func < (a: Weapon, b: Weapon) -> Bool { (a.bonus, a.rawValue) < (b.bonus, b.rawValue) }

    /// The town watch are armed by rank: watchmen with staves, serjeants with daggers,
    /// men-at-arms with maces, captains with short swords, knights with long swords.
    static func forGuard(rank: Int) -> Weapon { Weapon(rawValue: min(5, rank + 1))! }

    /// Whether someone of this much starting health carries a weapon, and which. The
    /// tougher they are, the likelier they're armed (30% at 1 health, 80% at 200) and
    /// the better the weapon: the weakest mostly carry staves and daggers, the
    /// strongest swords. Lord Draconian's people are nearly always armed.
    static func roll(health: Int, servant: Bool, child: Bool, _ rng: inout SplitMix64) -> Weapon? {
        let u = Double(max(0, min(200, health))) / 200
        let armed = child ? 0 : servant ? 0.9 : 0.3 + 0.5 * u
        let a = rng.double(), b = rng.double(), c = rng.double()
        guard a < armed else { return nil }
        // Tier 0-4 about u·4, give or take one (a triangular spread).
        let tier = Int((u * 4 + (b + c - 1) * 1.5).rounded())
        return Weapon(rawValue: max(0, min(4, tier)) + 1)
    }
}
