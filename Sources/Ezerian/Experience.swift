import Foundation

/// Experience, kept quietly and never shown: slaying a foe earns everyone in the party a
/// tenth of the foe's health, rounded up, and enough of it adds a point of health. The
/// first point takes 100, the next 110 more (210 in all), and each after that 10% more
/// than the one before.
enum Experience {
    /// Experience earned for defeating a foe of this much health.
    static func award(forHealth health: Int) -> Int { (health + 9) / 10 }

    /// Experience needed for the `n`th extra point of health (from 0), on top of the last.
    static func step(_ n: Int) -> Int { Int((100 * pow(1.1, Double(n))).rounded()) }

    /// How many extra points of health this much experience has earned.
    static func healthGained(_ xp: Int) -> Int {
        var n = 0, total = step(0)
        while xp >= total {
            n += 1
            total += step(n)
        }
        return n
    }
}

extension Game {
    /// Everyone in the party shares in a foe's defeat: each gains the experience, and any
    /// point of health it brings (their health rises with it).
    func shareExperience(forDefeating foe: NPC) {
        let xp = Experience.award(forHealth: foe.maxHP)
        let gained = Experience.healthGained(experience + xp) - Experience.healthGained(experience)
        experience += xp
        maxHP += gained
        hp += gained
        for m in party where m.hp > 0 {
            let had = m.experience
            m.experience += xp
            let more = Experience.healthGained(m.experience) - Experience.healthGained(had)
            m.maxHP += more
            m.hp += more
        }
    }
}
