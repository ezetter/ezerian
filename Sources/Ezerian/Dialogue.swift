import Foundation

/// What the Avatar can say in a conversation (picked with the number keys).
enum Topic: Int, CaseIterable {
    case farewell = 0, name, job, news, directions, compliment, insult, join, dismiss

    var label: String {
        switch self {
        case .name: return "Name"
        case .job: return "Job"
        case .news: return "News"
        case .directions: return "Directions"
        case .compliment: return "Compliment"
        case .insult: return "Insult"
        case .farewell: return "Farewell"
        case .join: return "Join me"
        case .dismiss: return "Dismiss"
        }
    }

    static var menu: [Topic] { [.name, .job, .news, .directions, .compliment, .insult, .farewell] }
}

/// A talk in progress with one NPC.
struct Conversation {
    struct Line: Equatable {
        var text: String
        var fromAvatar: Bool
    }
    let npc: NPC
    var lines: [Line] = []
    /// The NPC has had enough (or said goodbye); any key closes the talk.
    var over = false
    /// What the Avatar is typing.
    var input = ""
    /// Waiting for Claude's answer.
    var pending = false
    /// The NPC has asked to join the party and awaits a yes or no.
    var offer = false
    /// The chance of an offer (or a request to join) has come up once this talk.
    var offerRolled = false
    /// Whether this talk is voiced by Claude (otherwise scripted).
    var byClaude = false
    /// A note about Claude being unreachable, shown in the window.
    var notice: String?
    static let maxInput = 160
}

/// What NPCs say. Every reply is chosen by the NPC's friendliness band, flavoured
/// by race and trade; compliments and insults move the friendliness itself.
enum Dialogue {
    private static func pick(_ options: [String], _ npc: NPC, _ salt: Int) -> String {
        options[Int(Hash.of(UInt64(bitPattern: Int64(npc.id)), npc.talks, salt) % UInt64(options.count))]
    }

    /// How the NPC addresses the Avatar.
    private static func address(_ npc: NPC, _ player: String) -> String {
        switch (npc.race, npc.disposition) {
        case (_, .adoring): return player
        case (.human, .friendly): return "friend"
        case (.human, .neutral): return "stranger"
        case (.human, _): return "knave"
        case (.elf, .friendly): return "traveller"
        case (.elf, _): return "mortal"
        case (.dwarf, .friendly): return "friend"
        case (.dwarf, .neutral): return "stranger"
        case (.dwarf, _): return "surface-dweller"
        case (.orc, .friendly): return "strong one"
        case (.orc, _): return "pinkskin"
        }
    }

    private static func fill(_ s: String, _ npc: NPC, _ player: String) -> String {
        s.replacingOccurrences(of: "{name}", with: npc.name)
            .replacingOccurrences(of: "{addr}", with: address(npc, player))
            .replacingOccurrences(of: "{player}", with: player)
            .replacingOccurrences(of: "{role}", with: npc.title)
            .replacingOccurrences(of: "{home}", with: npc.home ?? "these parts")
    }

    private static let greetings: [Race: [Disposition: [String]]] = [
        .human: [
            .adoring: ["{player}! Well met indeed — it gladdens my heart to see you!", "Ah, {player}! Come, come, what can I do for a dear friend?"],
            .friendly: ["Good day to you, {addr}.", "Welcome, {addr}. Fair weather, is it not?"],
            .neutral: ["Yes? What is it?", "Hm. Good day, I suppose."],
            .unfriendly: ["What do you want? Be quick about it.", "I've no time for strangers."],
            .hostile: ["Keep your distance, {addr}, or you'll regret it.", "Clear off before I call the guard!"],
        ],
        .elf: [
            .adoring: ["The stars smile on our meeting, {player}. Be welcome.", "{player}! The wood sings at thy coming."],
            .friendly: ["Greetings, {addr}. Thy steps are light today.", "Well met under the leaves, {addr}."],
            .neutral: ["Thou hast my attention, briefly.", "A mortal. What dost thou seek?"],
            .unfriendly: ["Thy kind tramples the green things. Speak, and go.", "Hmph. Say what thou must."],
            .hostile: ["Begone, {addr}. Thy presence offends the wood.", "One more step and my arrow finds thy heart."],
        ],
        .dwarf: [
            .adoring: ["Ha! {player}! By stone and ale, it's good to see ye!", "{player}, old friend! Ye'll drink with me later, aye?"],
            .friendly: ["Aye, well met, {addr}.", "Good to see an honest face, {addr}."],
            .neutral: ["Aye? What is it?", "Hmph. Speak up, then."],
            .unfriendly: ["Surface-dwellers. Always underfoot. What d'ye want?", "Make it quick. I've work to do."],
            .hostile: ["Another step and ye'll taste my axe, {addr}.", "I've split better skulls than yers."],
        ],
        .orc: [
            .adoring: ["You! Strong one! {name} likes you. Sit, sit!", "Hah! Little friend come back! {name} happy."],
            .friendly: ["Hah. You not so bad, {addr}.", "You smell like fighter. Good."],
            .neutral: ["What you want, {addr}?", "Hrrm. Talk."],
            .unfriendly: ["Grr. {addr} talk fast or go away.", "You lost, {addr}?"],
            .hostile: ["You come closer, {name} crush you!", "{name} eat pinkskins like you for breakfast."],
        ],
    ]

    /// The NPC's first words, or nil (with a description) when they won't talk at all.
    static func greeting(_ npc: NPC, player: String) -> (text: String, refuses: Bool) {
        if npc.friendliness <= -85 {
            let snub = npc.race == .orc ? "\(npc.shortName.capitalizedFirst) spits at your feet and turns away."
                : "\(npc.shortName.capitalizedFirst) turns \(npc.his) back on you and will not speak."
            return (snub, true)
        }
        let options = greetings[npc.race]![npc.disposition]!
        return (fill(pick(options, npc, 1), npc, player), false)
    }

    /// The Avatar's words for a topic.
    static func ask(_ t: Topic) -> String {
        switch t {
        case .name: return "What is your name?"
        case .job: return "What do you do here?"
        case .news: return "What news is there?"
        case .directions: return "Where might I find shelter and a drink?"
        case .compliment: return "You have an honest face, if I may say so."
        case .insult: return "Out of my way, you fool."
        case .farewell: return "Farewell."
        case .join: return "Will you join me on my travels?"
        case .dismiss: return "It's time we parted ways."
        }
    }

    /// The NPC's answer to a topic; may change their friendliness, and may end the talk.
    static func reply(_ npc: NPC, _ t: Topic, game: Game) -> (text: String, ends: Bool) {
        npc.talks += 1
        let player = game.playerName
        let d = npc.disposition
        var text: String
        var ends = false
        switch t {
        case .name:
            switch d {
            case .adoring, .friendly:
                let intro: String
                switch npc.race {
                case .human: intro = "My name is {name}, and I'm the {role} here."
                case .elf: intro = "I am called {name}, {role} of the old blood."
                case .dwarf: intro = "{name}, {role}, at yer service."
                case .orc: intro = "Me {name}. Me {role}. Good one."
                }
                text = intro
                npc.known = true
            case .neutral:
                text = npc.race == .orc ? "{name}." : "I'm {name}."
                npc.known = true
            case .unfriendly:
                text = npc.race == .orc ? "Why you want know? ...{name}. Now go." : "Name's {name}. What's it to you?"
                npc.known = true
            case .hostile:
                text = pick(["None of your business.", "You'll not have my name.", "Names are for friends. You're no friend."], npc, 2)
            }
        case .job:
            switch d {
            case .adoring, .friendly: text = jobLine(npc)
            case .neutral: text = "I'm the {role} hereabouts."
            case .unfriendly: text = pick(["I work. Unlike some.", "What I do is my own affair."], npc, 3)
            case .hostile: text = "My work is none of yours."
            }
        case .news:
            switch d {
            case .adoring, .friendly: text = news(npc, game, detailed: true)
            case .neutral: text = news(npc, game, detailed: false)
            case .unfriendly: text = pick(["Nothing worth telling you.", "Ask someone else."], npc, 4)
            case .hostile: text = "The only news is you leaving."
            }
        case .directions:
            text = directions(npc, game)
        case .compliment:
            var delta: Int
            switch npc.race {
            case .elf: delta = 8 + Int(Hash.of(1, npc.id, npc.talks) % 7)
            case .human: delta = 6 + Int(Hash.of(2, npc.id, npc.talks) % 7)
            case .dwarf: delta = 4 + Int(Hash.of(3, npc.id, npc.talks) % 6)
            case .orc: delta = 2 + Int(Hash.of(4, npc.id, npc.talks) % 6)
            }
            delta /= 1 + npc.compliments
            npc.compliments += 1
            if npc.race == .orc && d <= .unfriendly && npc.talks % 3 == 0 {
                npc.changeFriendliness(by: -3)
                text = "Soft words for soft pinkskin. Bah."
            } else {
                npc.changeFriendliness(by: max(1, delta))
                switch npc.disposition {
                case .adoring: text = pick(["You are too kind, {player}! Truly.", "Ha! Flatterer. I like you more every day."], npc, 5)
                case .friendly: text = pick(["Why, thank you, {addr}.", "Kind of you to say so."], npc, 5)
                case .neutral: text = pick(["Hm. Thank you, I suppose.", "...Thank you."], npc, 5)
                case .unfriendly: text = pick(["Flattery won't get you far with me.", "Hmph. We'll see."], npc, 5)
                case .hostile: text = "Save your sweet words."
                }
            }
        case .insult:
            let delta = npc.race == .orc ? 3 + Int(Hash.of(5, npc.id, npc.talks) % 6) : 8 + Int(Hash.of(6, npc.id, npc.talks) % 11)
            npc.changeFriendliness(by: -delta)
            switch npc.disposition {
            case .adoring, .friendly: text = pick(["That stung, {player}. I thought better of you.", "Was that meant to be a jest?"], npc, 6)
            case .neutral: text = pick(["Mind your tongue.", "Charming. Truly."], npc, 6)
            case .unfriendly: text = npc.race == .orc ? "Grr! Say again, see what happen." : "Watch yourself, {addr}."
            case .hostile:
                text = npc.race == .orc ? "{name} remember you. {name} remember." : "That's the last word you'll have from me."
                ends = true
            }
        case .join, .dismiss:
            text = "Hm."
        case .farewell:
            switch d {
            case .adoring: text = pick(["Fare thee well, {player}! Come back soon!", "Safe roads, dear friend."], npc, 7)
            case .friendly: text = pick(["Safe travels, {addr}.", "Farewell, and good fortune."], npc, 7)
            case .neutral: text = "Farewell."
            case .unfriendly: text = "Good riddance."
            case .hostile: text = npc.race == .orc ? "Run, little one. Run." : "And don't come back."
            }
            ends = true
        }
        return (fill(text, npc, player), ends)
    }

    // MARK: Joining the party

    static func joinAnswer(_ npc: NPC, _ d: Party.Decision, player: String) -> String {
        let s: String
        switch d {
        case .accept:
            switch npc.race {
            case .human: s = "Travel with you? Aye, {player}, I'd like that. Lead on!"
            case .elf: s = "Thy road and mine shall be one, {player}. I will come."
            case .dwarf: s = "Ha! Someone has to keep ye alive. I'm with ye."
            case .orc: s = "{name} come. {name} smash things for you."
            }
        case .refuse:
            s = npc.disposition >= .friendly ? "I'm flattered, but my place is here." : "Travel with you? I think not."
        case .lockedOut:
            s = "I gave you my answer already, and it hasn't changed."
        case .full:
            s = "You've three companions already. There's no room for another."
        case .already:
            s = "I'm already with you, {player}!"
        }
        return s.replacingOccurrences(of: "{player}", with: player).replacingOccurrences(of: "{name}", with: npc.name)
    }

    static func offer(_ npc: NPC, player: String) -> String {
        let s: String
        switch npc.race {
        case .human: s = "You know, {player}, I've a mind to see the world. Would you let me travel with you?"
        case .elf: s = "Thy path calls to me, {player}. Wouldst thou have my company on the road?"
        case .dwarf: s = "Bah, this place bores me. Fancy an axe at yer side, {player}?"
        case .orc: s = "You strong. {name} want to come with you. Yes?"
        }
        return s.replacingOccurrences(of: "{player}", with: player).replacingOccurrences(of: "{name}", with: npc.name)
    }

    static func welcomed(_ npc: NPC) -> String {
        switch npc.race {
        case .human: return "Wonderful! I'll fetch my pack."
        case .elf: return "Then let us walk together beneath the stars."
        case .dwarf: return "Ha! Ye won't regret it."
        case .orc: return "Good. Good! {name} ready.".replacingOccurrences(of: "{name}", with: npc.name)
        }
    }

    static func leaving(_ npc: NPC) -> String {
        switch npc.race {
        case .human: return "That's enough. I'll be going my own way from here."
        case .elf: return "I see now our roads must part. Farewell."
        case .dwarf: return "I've had my fill of ye. Find yerself another axe."
        case .orc: return "{name} done with you. Go away.".replacingOccurrences(of: "{name}", with: npc.name)
        }
    }

    static func dismissed(_ npc: NPC) -> String {
        npc.disposition >= .friendly ? "If that's your wish. Fare you well." : "Fine. I was tired of you anyway."
    }

    private static func jobLine(_ npc: NPC) -> String {
        if npc.servesDraconian {
            return npc.race == .orc ? "{name} serve Lord Draconian! Emperor of Sespooland. Soon all Ezerian burn."
                : "I take Lord Draconian's gold. When the Emperor of Sespooland comes, I'll be on the winning side."
        }
        if let rank = npc.guardRank {
            switch rank {
            case 0: return "I walk the watch in {home}, spear in hand, and keep the drunks and cutpurses honest."
            case 1: return "Serjeant of the watch in {home}. I see the watchmen do their rounds and don't sleep at their posts."
            case 2: return "I'm sworn to arms in the service of {home}. When there's real trouble, they send for us."
            case 3: return "I captain the watch of {home}. Every gate, every street, every guard: mine to answer for."
            default: return "I am a knight of the watch, sworn to defend {home} and its people, by my life if need be."
            }
        }
        switch npc.role {
        case "innkeeper": return "I keep {home}. A soft bed and a hot meal, for those who can pay."
        case "barkeep": return "I pour the ale at {home} and listen to the tales that come with it."
        case "provisioner": return "Rope, torches, bread, lamp oil — if you need it on the road, I sell it."
        case "blacksmith": return "I work the forge: horseshoes, nails, and a good blade now and then."
        case "armourer": return "I fit armour to those who'd rather keep their skin. Mail, plate, shields."
        case "healer": return "I mend what the road breaks. Herbs, bandages and a little prayer."
        case "cleric": return "I tend the temple and the virtue it honours."
        case "farmer": return "I grow wheat and cabbages, and keep the bees from the barn."
        case "guard": return "I keep the peace in {home}, such as it is."   // guards from older saves
        case "bard": return "I sing of heroes. Perhaps one day I'll sing of you!"
        case "merchant": return "I buy cheap and sell dear, like any honest merchant."
        case "miner", "prospector", "stonecutter": return "I follow the seams of the stone. There's silver in these hills, mark me."
        case "ranger", "hunter", "wanderer", "druid": return "I watch over the old woods and all that grows there."
        case "raider", "warrior", "brute", "scout", "mercenary":
            return npc.race == .orc ? "{name} fight. {name} take. Is good life." : "I sell my sword to whoever pays."
        case "child": return "I'm not working, I'm playing! Want to play?"
        case "beggar": return "I beg, good soul. A coin would not go amiss."
        case "peasant": return "I work the land, as my father did, and his before him. Back-breaking, but it feeds us."
        case "townsperson", "townsfolk": return "I live here in {home}, and mind my own business. Mostly."
        default: return "I'm a {role}. It's an honest living."
        }
    }

    /// Talk of the land around: the nearest town or landmark, or a rumour.
    private static func news(_ npc: NPC, _ game: Game, detailed: Bool) -> String {
        let rumours = ["They say strange lights dance over the marshes at night.",
                       "Orcs have been seen near the old roads. Keep your blade close.",
                       "The harvest was good this year, praise the virtues.",
                       "There are caves in the mountains that go down further than any map.",
                       "A shrine of virtue stands somewhere in these lands, ringed with stones.",
                       "They say Lord Draconian, the Wizard Lord of Sespooland, means to conquer Ezerian. His sellswords are everywhere.",
                       "Watch for anyone in black and red. That's Draconian's livery, and they'll knife you for a silver piece.",
                       "Orc warbands roam the wilds under Draconian's banner. Travel in company if you can."]
        guard detailed, let (place, dir, dist) = nearestPlace(game, from: (npc.x, npc.y), wantShelter: false) else {
            return pick(rumours, npc, 8)
        }
        let far = dist < 30 ? "not far" : "a good walk"
        return "This is \(game.region.name). You'll find \(place) \(far) to the \(dir). " + pick(rumours, npc, 9)
    }

    /// Where to find a tavern or inn: true, vague or an outright lie, by mood.
    private static func directions(_ npc: NPC, _ game: Game) -> String {
        guard let (place, dir, dist) = nearestPlace(game, from: (npc.x, npc.y), wantShelter: true) else {
            return npc.disposition >= .neutral ? "I know of no inn near here, I'm afraid." : "Find it yourself."
        }
        switch npc.disposition {
        case .adoring, .friendly: return "\(place) lies about \(dist) paces to the \(dir). Tell them I sent you!"
        case .neutral: return "Somewhere off to the \(dir), I believe."
        case .unfriendly: return "Find it yourself."
        case .hostile:
            let opposite = ["north": "south", "south": "north", "east": "west", "west": "east",
                            "north-east": "south-west", "south-west": "north-east", "north-west": "south-east", "south-east": "north-west"]
            return "Oh, it's off to the \(opposite[dir] ?? "west"). Far, far to the \(opposite[dir] ?? "west")."
        }
    }

    /// The nearest known place (an inn or tavern, or else a town or landmark) in the
    /// regions around: its name, compass direction and distance in paces.
    static func nearestPlace(_ game: Game, from p: (Int, Int), wantShelter: Bool) -> (String, String, Int)? {
        let world = game.world
        var best: (Place, Int)?
        let rx = floorDiv(p.0, Region.size), ry = floorDiv(p.1, Region.size)
        for dy in -1...1 {
            for dx in -1...1 {
                guard let r = world.existingRegion(RegionKey(x: rx + dx, y: ry + dy, z: 0)) else { continue }
                for pl in r.places {
                    let shelter = pl.kind == .building && (Names.isInn(pl.name) || (pl.name.hasPrefix("The ") && !pl.name.contains("Anvil")))
                    if wantShelter ? !shelter : (pl.kind == .building || pl.contains(p.0, p.1)) { continue }
                    let d = abs(pl.x + pl.w / 2 - p.0) + abs(pl.y + pl.h / 2 - p.1)
                    if best == nil || d < best!.1 { best = (pl, d) }
                }
            }
        }
        guard let (pl, d) = best else { return nil }
        let vx = Double(pl.x + pl.w / 2 - p.0), vy = Double(pl.y + pl.h / 2 - p.1)
        let names = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
        let octant = Int((atan2(vy, vx) / (.pi / 4)).rounded())
        let name = pl.kind == .town ? "the town of \(pl.name)" : pl.name
        return (name, names[(octant + 8) % 8], max(1, d))
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
