import Foundation
import simd

/// The five weapons, modelled in the hand of whoever carries them, so the map shows
/// what each person really fights with. Each is drawn as its own sprite over the figure.
enum WeaponArt {
    /// Whose hand: the four races' ordinary folk, the town watch, and the Avatar.
    enum Carrier: Int, CaseIterable {
        case human, elf, dwarf, orc, guardsman, avatarMan, avatarWoman

        static func of(_ race: Race) -> Carrier { Carrier(rawValue: race.index)! }

        /// Where the weapon hand is (in the figure's frame, facing south) on a stride frame.
        func hand(step: Int) -> V3 {
            let armSwing = -Float(step) * 2.4 * 0.7
            switch self {
            case .guardsman: return V3(-6.3, 1.9, 13.6)
            case .avatarMan: return V3(-6.3, 1.7 + armSwing, 13.5)
            case .avatarWoman: return V3(-5.8, 1.7 + armSwing, 13.5)
            default: return V3(-6.2, 1.8 + armSwing, 13.4)
            }
        }

        var scale: V3 {
            switch self {
            case .avatarMan, .avatarWoman: return V3(repeating: 1.16)
            case .guardsman: return PeopleArt.build(.human)
            default: return PeopleArt.build(Race.allCases[rawValue])
            }
        }
    }

    static func model(_ w: Weapon, carrier: Carrier, facing: Direction, step: Int) -> Model {
        Posing.stand(held(w, at: carrier.hand(step: step)), facing: facing, scale: carrier.scale)
    }

    /// The weapon gripped at `h`, in a figure facing south.
    static func held(_ w: Weapon, at h: V3) -> Model {
        var m = Model()
        m.seed = Hash.of(31, w.rawValue, 0)
        let steel = Paint(0xD0D4DC, .metal, jitter: 0.02, shine: 0.75)
        let iron = Paint(0x6A6E78, .metal, jitter: 0.05, shine: 0.35)
        let gold = Paint(0xC8A040, .metal, shine: 0.5)
        let grip = Paint(0x4A2C18, jitter: 0.05)
        let wood = Paint(0x7A5A32, .wood(2))
        let (x, y, z) = (h.x, h.y, h.z)
        switch w {
        case .staff:
            m.rod(V3(x, y, 0.4), V3(x, y, 30.5), 0.75, wood)
            m.ball(x, y, 31, 1.1, wood)
        case .dagger:
            m.rod(V3(x, y + 0.2, z + 1.2), V3(x, y + 0.2, z - 0.6), 0.45, grip)
            m.box(x - 1, y - 0.1, z - 1.1, x + 1, y + 0.6, z - 0.6, gold)
            m.rod(V3(x, y + 0.4, z - 1), V3(x - 0.2, y + 1.6, z - 5.4), 0.5, steel)
        case .mace:
            m.rod(V3(x, y, z + 1.4), V3(x - 0.3, y + 1.2, z - 6.6), 0.5, wood)
            m.ball(x - 0.35, y + 1.4, z - 7.6, 1.6, iron)
            for (dx, dy) in [(1.2, 0.0), (-1.2, 0.0), (0.0, 1.2), (0.0, -1.2)] as [(Float, Float)] {
                m.ball(x - 0.35 + dx, y + 1.4 + dy, z - 7.6, 0.6, iron)
            }
        case .shortSword:
            m.rod(V3(x, y + 0.2, z + 1.4), V3(x, y + 0.3, z - 0.4), 0.5, grip)
            m.box(x - 1.3, y - 0.1, z - 1, x + 1.3, y + 0.8, z - 0.4, gold)
            m.rod(V3(x, y + 0.6, z - 0.8), V3(x - 0.6, y + 4.2, z - 8.4), 0.75, steel)
        case .longSword:
            m.ball(x, y + 0.1, z + 2.6, 0.7, gold)
            m.rod(V3(x, y + 0.2, z + 2.2), V3(x, y + 0.3, z - 0.4), 0.5, grip)
            m.box(x - 1.8, y - 0.1, z - 1, x + 1.8, y + 0.8, z - 0.4, gold)
            m.rod(V3(x, y + 0.6, z - 0.8), V3(x - 1, y + 6.4, max(1.6, z - 11.8)), 0.8, steel)
        }
        return m
    }
}
