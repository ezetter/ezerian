import Foundation

/// Buying services (and, later, goods) from merchants: what they ask, whether they
/// take what is offered, and how the haggling sits with them.
enum Trade {
    /// Below this friendliness no merchant will do business with the Avatar.
    static let refuseBelow = -50

    static func willTrade(_ npc: NPC) -> Bool { npc.friendliness >= refuseBelow }

    /// The asking price: the usual price, plus a coin for every 5 points of
    /// friendliness below 0.
    static func price(base: Int, friendliness: Int) -> Int {
        base + max(0, -friendliness) / 5
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
