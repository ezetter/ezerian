import Foundation

/// Something a person carries. So far only weapons; more kinds will follow.
enum Item: Codable, Equatable {
    case weapon(Weapon)

    var name: String {
        switch self {
        case let .weapon(w): return w.name
        }
    }

    var article: String {
        switch self {
        case let .weapon(w): return w.article
        }
    }

    var weapon: Weapon? {
        switch self {
        case let .weapon(w): return w
        }
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
        case equip(Int), unequip, drop(Int), give(Int)
        case giveTo(Int), cancelGive
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

    /// Opens the character sheet: the Avatar's, or a companion's.
    func openSheet(_ k: Int = 0) {
        guard !inCombat, conversation == nil, !creatingCharacter, !gameOver else {
            if inCombat { log("There's no time for that in the middle of a fight!") }
            return
        }
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
        case .unequip:
            guard let w = inHand(k) else { return }
            setInHand(k, nil)
            setPack(k, [.weapon(w)] + packOf(k))
            log(k == 0 ? "You put away your \(w.name)." : "\(sheetName(k)) puts away \(party[k - 1].his) \(w.name).")
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

    /// Takes one line of belongings away from someone.
    private func take(row r: Int, from k: Int) {
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

    /// The Avatar takes everything a slain foe carried, as far as there is room.
    func loot(_ n: NPC) {
        let items = (n.weapon.map { [Item.weapon($0)] } ?? []) + n.pack
        n.weapon = nil
        n.pack = []
        for item in items {
            let wasEmpty = weapon == nil
            if receive(item, k: 0) {
                log("You take \(n.his) \(item.name)." + (wasEmpty && weapon != nil ? " You now fight with it (+\(weapon!.bonus) damage)." : ""))
            } else {
                log("You can carry no more; you leave \(n.his) \(item.name).")
            }
        }
    }
}
