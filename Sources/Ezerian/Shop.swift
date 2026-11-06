import Foundation

/// Buying and selling things. Blacksmiths and armourers keep every kind of weapon and
/// will buy any; apothecaries and alchemists keep health salves and ointments, and buy
/// those (only half of weapon shops have sharp swords). Merchants and pedlars carry a few things of their own (their pack), weapons
/// and remedies alike, and take whatever they buy into it. A weapon is worth 10 gold
/// for each point of damage it adds, a salve 10 and an ointment 5; a trader sells at
/// that, except the sharp sword, 100 (more if they dislike the Avatar: see `Trade.price`) and buys at half its own asking price.
extension Trade {
    static let goldPerDamage = 10
    /// Merchants and pedlars carry this many things for sale, chosen at random.
    static let merchantStock = 1...5

    /// What something is worth.
    static func value(_ item: Item) -> Int {
        switch item {
        case .weapon(.sharpSword): return 100
        case let .weapon(w): return goldPerDamage * w.bonus
        case .salve: return 10
        case .ointment: return 5
        }
    }

    /// Keepers of a smithy or an armoury: every weapon, always in stock.
    static func sellsWeapons(_ npc: NPC) -> Bool { npc.role == "blacksmith" || npc.role == "armourer" }

    /// Apothecaries and alchemists: every remedy, always in stock.
    /// Half of weapon shops keep sharp swords (fixed by who keeps them).
    static func sellsSharpSwords(_ npc: NPC) -> Bool { sellsWeapons(npc) && Hash.of(0x5AA4, npc.id, 0) & 1 == 0 }

    static func sellsRemedies(_ npc: NPC) -> Bool { npc.role == "apothecary" || npc.role == "alchemist" }

    /// Keepers of a shop, whose stock never runs out.
    static func keepsShop(_ npc: NPC) -> Bool { sellsWeapons(npc) || sellsRemedies(npc) }

    /// Merchants met in the streets and pedlars on the roads: what they carry.
    static func isMerchant(_ npc: NPC) -> Bool { npc.role == "merchant" || npc.role == "pedlar" }

    static func trades(_ npc: NPC) -> Bool { keepsShop(npc) || isMerchant(npc) }

    /// A merchant's goods: a few things at random, weapons and remedies about equally,
    /// duplicates and all (fixed by who they are).
    static func merchantGoods(id: Int) -> [Item] {
        var rng = SplitMix64(seed: Hash.of(0x5A1E5, id, 0))
        let n = merchantStock.lowerBound + rng.int(merchantStock.count)
        return (0..<n).map { k in
            if rng.chance(0.5) { return rng.pick(Item.remedies) }
            let u = Double(Hash.of(0x5AA5, id, k) % 1_000_000) / 1_000_000
            return .weapon(rng.pick(Weapon.common).sharpened(u))
        }
    }
}

extension Game {
    enum ShopAction: Equatable { case buy(Int), sell(Int), leave }

    /// The trader the Avatar is shopping with, while the shop is open.
    var shopkeeper: NPC? { shopping ? conversation?.npc : nil }

    /// What the trader has for sale.
    func wares(_ npc: NPC) -> [Item] {
        Trade.sellsWeapons(npc) ? (Trade.sellsSharpSwords(npc) ? Weapon.allCases : Weapon.common).sorted().map { .weapon($0) }
            : Trade.sellsRemedies(npc) ? Item.remedies : npc.pack
    }

    /// Whether the trader will buy something: a shop only what it sells; a merchant anything.
    func buys(_ item: Item, _ npc: NPC) -> Bool {
        Trade.sellsWeapons(npc) ? item.weapon != nil : Trade.sellsRemedies(npc) ? item.heals != nil : true
    }

    /// What the trader asks for something.
    func askingPrice(_ item: Item, _ npc: NPC) -> Int { Trade.price(base: Trade.value(item), friendliness: npc.friendliness) }

    /// What the trader pays for something: half what they would sell it for.
    func offerFor(_ item: Item, _ npc: NPC) -> Int { askingPrice(item, npc) / 2 }

    /// Opens the trader's wares from a conversation (the Trade button, or asking to trade).
    func openShop() {
        guard var c = conversation, !c.over, !c.pending, Trade.trades(c.npc) else { return }
        let npc = c.npc
        guard Trade.willTrade(npc) else {
            c.lines.append(Conversation.Line(text: Dialogue.trader(npc, refuse: true, player: playerName), fromAvatar: false))
            conversation = c
            return
        }
        c.lines.append(Conversation.Line(text: Dialogue.trader(npc, refuse: false, player: playerName), fromAvatar: false))
        c.healingAsked = false
        conversation = c
        shopping = true
        shopNotice = nil
    }

    func perform(_ a: ShopAction) {
        guard let npc = shopkeeper else { return }
        switch a {
        case .leave:
            shopping = false
            shopNotice = nil
        case let .buy(r):
            let goods = wares(npc)
            guard goods.indices.contains(r) else { return }
            let item = goods[r], price = askingPrice(item, npc)
            guard price <= gold else {
                shopNotice = "You can't afford the \(item.name): it costs \(price) gold, and you have \(gold)."
                return
            }
            guard carried(0) < Game.carryLimit else {
                shopNotice = "You can carry no more. Sell or drop something first."
                return
            }
            gold -= price
            npc.gold += price
            if Trade.isMerchant(npc) { npc.pack.remove(at: r) }
            receive(item, k: 0)
            // Paying the asking price pleases any merchant a little.
            npc.changeFriendliness(by: 1)
            shopNotice = "You buy \(item.article) \(item.name) for \(price) gold."
            log("You buy \(item.article) \(item.name) from \(npc.shortName) for \(price) gold. You have \(gold) gold left.")
        case let .sell(r):
            let rows = belongings(0)
            guard rows.indices.contains(r) else { return }
            let item = rows[r].item, price = offerFor(item, npc)
            guard buys(item, npc) else { return }
            guard !Trade.isMerchant(npc) || npc.pack.count < Game.carryLimit else {
                shopNotice = "\(npc.shortName.capitalizedFirst) has no room for more."
                return
            }
            take(row: r, from: 0)
            gold += price
            npc.gold = max(0, npc.gold - price)
            if Trade.isMerchant(npc) { npc.pack.append(item) }
            shopNotice = "You sell your \(item.name) for \(price) gold."
            log("You sell your \(item.name) to \(npc.shortName) for \(price) gold. You now have \(gold) gold.")
        }
    }
}
