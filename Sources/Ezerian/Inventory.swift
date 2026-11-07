import Foundation

/// Something a person carries: a weapon, or a remedy (a health salve or an ointment)
/// that heals whoever uses it at once.
enum Item: Codable, Equatable {
    case weapon(Weapon)
    case salve, ointment

    /// Remedies sold by apothecaries and alchemists, cheapest first.
    static let remedies: [Item] = [.ointment, .salve]

    var name: String {
        switch self {
        case let .weapon(w): return w.name
        case .salve: return "health salve"
        case .ointment: return "ointment"
        }
    }

    var article: String {
        switch self {
        case let .weapon(w): return w.article
        case .salve: return "a"
        case .ointment: return "an"
        }
    }

    var weapon: Weapon? {
        switch self {
        case let .weapon(w): return w
        default: return nil
        }
    }

    /// Health restored on use, for remedies: a salve 50, an ointment 25.
    var heals: Int? {
        switch self {
        case .salve: return 50
        case .ointment: return 25
        case .weapon: return nil
        }
    }

    /// What it says about itself on a list: "+6" for a weapon, "heals 50" for a remedy.
    var detail: String {
        if let w = weapon { return "+\(w.bonus)" }
        return heals.map { "heals \($0)" } ?? ""
    }
}

/// What the Avatar and the companions carry: a weapon in hand, and a pack. Everyone
/// can carry ten things at most, the weapon in hand among them. The character sheet
/// shows one person at a time: 0 is the Avatar, then each companion in turn.
extension Game {
    static let carryLimit = 10

    /// One line of someone's belongings: the weapon in hand comes first.
    struct Belonging: Equatable {
        var item: Item
        var inHand: Bool
    }

    /// What the character sheet can do, from its buttons (and keys).
    enum SheetAction: Equatable {
        case previous, next, close
        case equip(Int), unequip, drop(Int), give(Int), use(Int)
        case giveTo(Int), cancelGive
        /// Talk with the companion whose sheet this is.
        case talk
    }

    /// Everyone whose sheet can be shown: the Avatar, then the companions.
    var sheetCount: Int { 1 + party.count }

    /// The name on someone's sheet.
    func sheetName(_ k: Int) -> String { k == 0 ? playerName : party[k - 1].name }

    func inHand(_ k: Int) -> Weapon? { k == 0 ? weapon : party[k - 1].weapon }

    func packOf(_ k: Int) -> [Item] { k == 0 ? pack : party[k - 1].pack }

    private func setInHand(_ k: Int, _ w: Weapon?) {
        if k == 0 { weapon = w } else { party[k - 1].weapon = w }
    }

    private func setPack(_ k: Int, _ items: [Item]) {
        if k == 0 { pack = items } else { party[k - 1].pack = items }
    }

    func belongings(_ k: Int) -> [Belonging] {
        (inHand(k).map { [Belonging(item: .weapon($0), inHand: true)] } ?? [])
            + packOf(k).map { Belonging(item: $0, inHand: false) }
    }

    func carried(_ k: Int) -> Int { belongings(k).count }

    /// Opens the character sheet: the Avatar's, or a companion's. In a fight it can be
    /// opened too, to use a remedy or change weapons, but either takes the Avatar's turn.
    func openSheet(_ k: Int = 0) {
        guard conversation == nil, !creatingCharacter, !gameOver else { return }
        sheet = max(0, min(sheetCount - 1, k))
        sheetGiving = nil
        showHelp = false
        showMap = false
    }

    func perform(_ a: SheetAction) {
        guard let s = sheet else { return }
        let k = min(s, sheetCount - 1)
        let rows = belongings(k)
        switch a {
        case .close:
            sheet = nil
            sheetGiving = nil
        case .previous, .next:
            sheet = (k + (a == .next ? 1 : sheetCount - 1)) % sheetCount
            sheetGiving = nil
        case let .equip(r):
            guard rows.indices.contains(r), !rows[r].inHand, let w = rows[r].item.weapon else { return }
            var p = packOf(k)
            let i = r - (inHand(k) == nil ? 0 : 1)
            if let old = inHand(k) { p[i] = .weapon(old) } else { p.remove(at: i) }
            setPack(k, p)
            setInHand(k, w)
            log(k == 0 ? "You take up your \(w.name) (+\(w.bonus) damage)." : "\(sheetName(k)) takes up \(party[k - 1].his) \(w.name).")
            spendTurnIfFighting()
        case .unequip:
            guard let w = inHand(k) else { return }
            setInHand(k, nil)
            setPack(k, [.weapon(w)] + packOf(k))
            log(k == 0 ? "You put away your \(w.name)." : "\(sheetName(k)) puts away \(party[k - 1].his) \(w.name).")
            spendTurnIfFighting()
        case let .drop(r):
            guard rows.indices.contains(r) else { return }
            take(row: r, from: k)
            log(k == 0 ? "You drop your \(rows[r].item.name)." : "\(sheetName(k)) drops \(party[k - 1].his) \(rows[r].item.name).")
            sheetGiving = nil
        case let .give(r):
            guard rows.indices.contains(r), sheetCount > 1 else { return }
            sheetGiving = r
        case .cancelGive:
            sheetGiving = nil
        case .talk:
            guard k > 0 else { return }
            talkToCompanion(party[k - 1])
        case let .use(r):
            guard rows.indices.contains(r), let amount = rows[r].item.heals else { return }
            let item = rows[r].item
            take(row: r, from: k)
            let (before, top) = k == 0 ? (hp, maxHP) : (party[k - 1].hp, party[k - 1].maxHP)
            let after = min(top, before + amount)
            if k == 0 { hp = after } else { party[k - 1].hp = after }
            let who = k == 0 ? "You use" : "\(sheetName(k)) uses"
            log("\(who) \(k == 0 ? "your" : party[k - 1].his) \(item.name) and \(after == top ? "\(k == 0 ? "are" : "is") whole again" : "\(k == 0 ? "feel" : "feels") better") (+\(after - before) health).")
            sheetGiving = nil
            spendTurnIfFighting()
        case let .giveTo(j):
            guard let r = sheetGiving, rows.indices.contains(r), j != k, j >= 0, j < sheetCount else { return }
            sheetGiving = nil
            let item = rows[r].item
            guard carried(j) < Game.carryLimit else {
                log("\(j == 0 ? "You" : sheetName(j)) can carry no more.")
                return
            }
            take(row: r, from: k)
            receive(item, k: j)
            let giver = k == 0 ? "You give" : "\(sheetName(k)) gives"
            log("\(giver) \(k == 0 ? "your" : party[k - 1].his) \(item.name) to \(j == 0 ? "you" : sheetName(j)).")
        }
    }

    /// In a fight, using something or changing weapons takes the Avatar's turn (and puts
    /// the sheet away to watch the others take theirs).
    private func spendTurnIfFighting() {
        guard inCombat else { return }
        sheet = nil
        endAvatarTurn()
    }

    /// Takes one line of belongings away from someone.
    func take(row r: Int, from k: Int) {
        if belongings(k)[r].inHand {
            setInHand(k, nil)
        } else {
            var p = packOf(k)
            p.remove(at: r - (inHand(k) == nil ? 0 : 1))
            setPack(k, p)
        }
    }

    /// Puts an item with someone: a weapon goes into an empty hand, anything else in the pack.
    @discardableResult
    func receive(_ item: Item, k: Int) -> Bool {
        guard carried(k) < Game.carryLimit else { return false }
        if inHand(k) == nil, let w = item.weapon { setInHand(k, w) } else { setPack(k, packOf(k) + [item]) }
        return true
    }

    /// The party takes everything a slain foe carried: the Avatar first, and what the
    /// Avatar has no room for goes to the companions, in order, as far as there is room.
    func loot(_ n: NPC) {
        let items = (n.weapon.map { [Item.weapon($0)] } ?? []) + n.pack
        n.weapon = nil
        n.pack = []
        for item in items {
            guard let k = (0...party.count).first(where: { carried($0) < Game.carryLimit }) else {
                log("Your party can carry no more; you leave \(n.his) \(item.name).")
                continue
            }
            let wasEmpty = inHand(k) == nil
            receive(item, k: k)
            let wields = wasEmpty && inHand(k) != nil
            if k == 0 {
                log("You take \(n.his) \(item.name)." + (wields ? " You now fight with it (+\(weapon!.bonus) damage)." : ""))
            } else {
                let c = party[k - 1]
                log("\(c.name) takes \(n.his) \(item.name)." + (wields ? " \(c.he.capitalizedFirst) now fights with it." : ""))
            }
        }
    }
}
