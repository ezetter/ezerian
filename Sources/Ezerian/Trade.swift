import Foundation

/// Buying services (and, later, goods) from merchants: what they ask, whether they
/// take what is offered, and how the haggling sits with them.
enum Trade {
    /// Below this friendliness no merchant will do business with the Avatar.
    static let refuseBelow = -50

    static func willTrade(_ npc: NPC) -> Bool { npc.friendliness >= refuseBelow }

    /// The asking price: the usual price, plus a coin for every 5 points of
    /// friendliness below 0, or 5% off for every full 10 points above 40 (rounded).
    static func price(base: Int, friendliness: Int) -> Int {
        let off = friendliness > 40 ? 5 * ((friendliness - 40) / 10) : 0
        return (base * (100 - off) + 50) / 100 + max(0, -friendliness) / 5
    }

    /// What a trader pays for something, in percent of half its usual price: 10% less
    /// for every full 10 points of friendliness below 0, and 10% more for every full
    /// 10 points above 40, up to 140% at 80 and above.
    static func buybackRate(friendliness f: Int) -> Int {
        f < 0 ? 100 - 10 * (-f / 10) : f > 40 ? 100 + 10 * ((min(f, 80) - 40) / 10) : 100
    }

    /// What a trader pays for something worth `base`: half of it, at their buyback rate.
    /// (Capped at 140%, this never comes to more than they'd sell it for.)
    static func buyback(base: Int, friendliness: Int) -> Int {
        base * buybackRate(friendliness: friendliness) / 200
    }

    /// The healer's price for a night's rest that heals the Avatar completely, and 5 more
    /// for each wounded companion healed with them.
    static let healingBase = 10, healingPerCompanion = 5
    static func healingPrice(_ npc: NPC, companions: Int = 0) -> Int {
        price(base: healingBase + healingPerCompanion * companions, friendliness: npc.friendliness)
    }

    /// An innkeeper's price for a night in a room, which heals the Avatar and each companion
    /// by up to 50 points: 5 gold, and 2 more for each companion sharing the room.
    static let lodgingBase = 5, lodgingPerCompanion = 2, lodgingHeal = 50
    static func lodgingPrice(_ npc: NPC, companions: Int = 0) -> Int {
        price(base: lodgingBase + lodgingPerCompanion * companions, friendliness: npc.friendliness)
    }

    /// A barkeep's beer: 2 gold (1 from a barkeep whose friendliness is above 50), drunk
    /// at once, for 5 health. Any tip at all, however small, pleases them by 5. Only the first
    /// two beers of a day mend; each one after that makes the Avatar drunk and costs a point of health.
    static let beerHeal = 5, tipFriendliness = 5, healingBeers = 2, drunkHurt = 1
    static func beerPrice(_ npc: NPC) -> Int { npc.friendliness > 50 ? 1 : 2 }

    /// What an offer does. Paying the asking price pleases the merchant a little (+1),
    /// and every coin over it pleases them more (+2 each); every coin short costs 2
    /// points whether or not they take it. They always take the asking price or more;
    /// short of it, a 90% chance for one coin less, 80% for two, and so on.
    static func settle(offered: Int, price: Int) -> (friendliness: Int, acceptChance: Double) {
        let diff = offered - price
        if diff >= 0 { return (1 + 2 * diff, 1) }
        return (2 * diff, max(0, 1 + 0.1 * Double(diff)))
    }
}
