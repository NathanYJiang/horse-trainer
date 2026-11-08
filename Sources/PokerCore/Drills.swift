import Foundation

public enum DrillConcept: String, CaseIterable, Sendable, Codable, Identifiable {
    case riverBluffCatch, sizingTell, flopRaise, riverValueSize, riverBluff, isoLimpers, vsOpen, limpRaise, cold4Bet, turnBarrel, thinValue, flopCbet

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .riverBluffCatch: "River bluff-catch"
        case .sizingTell: "Sizing tells"
        case .flopRaise: "Facing a flop raise"
        case .riverValueSize: "River value sizing"
        case .riverBluff: "River bluff or give up"
        case .isoLimpers: "Isolating limpers"
        case .vsOpen: "Facing an open"
        case .limpRaise: "Facing a limp-raise"
        case .cold4Bet: "Cold 4-bets"
        case .turnBarrel: "Turn barrel"
        case .thinValue: "Thin value"
        case .flopCbet: "Flop c-bet framework"
        }
    }

    public var isPreflop: Bool { [.isoLimpers, .vsOpen, .limpRaise, .cold4Bet].contains(self) }

    var types: [PlayerType] {
        switch self {
        case .sizingTell: [.fish, .tryingRec, .whale]
        case .isoLimpers: [.fish, .whale, .nit, .tryingRec]
        case .limpRaise: [.fish, .nit, .tryingRec, .whale]
        case .flopCbet: [.fish, .tryingRec, .whale, .reg]
        default: PlayerType.allCases
        }
    }
}

public struct SpotDrill: Sendable, Identifiable {
    public let id = UUID()
    public let concept: DrillConcept
    public let villainType: PlayerType
    public let villainName: String
    public let villainAppearance: String
    public let heroCards: [Card]
    public let board: [Card]
    public let heroPosition: Position
    public let villainPosition: Position
    public let pot: Int
    public let villainBet: Int?
    public let effectiveStack: Int
    public let history: [String]
    public let prompt: String
    public let options: [String]
    public let correct: Set<Int>
    public let explanation: String
    public let principle: Principle
    /// What the right play would be against each other type — the "it depends on who" lesson.
    public let perType: [(type: PlayerType, answer: String, why: String)]

    public var heroHandText: String {
        if board.count >= 3 {
            let r = HandRead.describe(hole: heroCards, board: board, value: HandEvaluator.evaluate(heroCards + board))
            return r
        }
        return HandClass(heroCards).description
    }

    /// Plain-text version for the Claude coach.
    public var asText: String {
        var s = "Drill: \(concept.title)\nVillain: \(villainName), a \(villainType.name) (\(villainPosition.short)). Hero: \(heroPosition.short) with \(heroCards.map(\.pretty).joined())"
        if !board.isEmpty { s += "\nBoard: \(board.map(\.pretty).joined(separator: " "))" }
        s += "\nPot: $\(pot)\(villainBet.map { ", villain bet $\($0)" } ?? ""). Effective stack $\(effectiveStack)\n"
        s += history.joined(separator: "\n")
        s += "\nQuestion: \(prompt)\nOptions: \(options.joined(separator: " / "))\nCorrect: \(correct.sorted().map { options[$0] }.joined(separator: " or "))"
        return s
    }
}

struct Key {
    let correct: [String]
    let why: String
}

public enum DrillFactory {
    public static func make<R: RandomNumberGenerator>(concept: DrillConcept? = nil, type: PlayerType? = nil, rng: inout R) -> SpotDrill {
        let c = concept ?? DrillConcept.allCases.randomElement(using: &rng)!
        let t = (type.flatMap { c.types.contains($0) ? $0 : nil }) ?? c.types.randomElement(using: &rng)!
        let villain = Roster.makeBot(type: t, usedNames: [], rng: &rng)
        switch c {
        case .riverBluffCatch: return riverBluffCatch(t, villain, &rng)
        case .sizingTell: return sizingTell(t, villain, &rng)
        case .flopRaise: return flopRaise(t, villain, &rng)
        case .riverValueSize: return riverValue(t, villain, &rng)
        case .riverBluff: return riverBluff(t, villain, &rng)
        case .isoLimpers: return isoLimpers(t, villain, &rng)
        case .vsOpen: return vsOpen(t, villain, &rng)
        case .limpRaise: return limpRaise(t, villain, &rng)
        case .cold4Bet: return cold4Bet(t, villain, &rng)
        case .turnBarrel: return turnBarrel(t, villain, &rng)
        case .thinValue: return thinValue(t, villain, &rng)
        case .flopCbet: return flopCbet(t, villain, &rng)
        }
    }

    // MARK: - Card generation

    /// Rejection-samples a hand + board where the predicate holds on the full board.
    static func deal<R: RandomNumberGenerator>(boardCount: Int, rng: inout R, _ pred: ([Card], [Card], String, HandValue) -> Bool) -> ([Card], [Card]) {
        for _ in 0..<20000 {
            var d = Deck(rng: &rng)
            let hole = d.deal(2)
            let board = d.deal(boardCount)
            let v = HandEvaluator.evaluate(hole + board)
            let desc = HandRead.describe(hole: hole, board: board, value: v)
            if pred(hole, board, desc, v) { return (hole, board) }
        }
        var d = Deck(rng: &rng)
        return (d.deal(2), d.deal(boardCount))
    }

    public static func cards<R: RandomNumberGenerator>(for h: HandClass, rng: inout R) -> [Card] {
        let s1 = Suit.allCases.randomElement(using: &rng)!
        var s2 = s1
        if !h.suited {
            s2 = Suit.allCases.filter { $0 != s1 }.randomElement(using: &rng)!
        }
        return [Card(rankIndex: h.high, suit: s1), Card(rankIndex: h.low, suit: s2)]
    }

    static func flopIsSafe(_ board: [Card]) -> Bool {
        let t = BoardTexture(board)
        return t.maxSuitCount < 4
    }

    static func build(_ c: DrillConcept, _ t: PlayerType, _ v: BotPlayer, hero: [Card], board: [Card], heroPos: Position, villainPos: Position,
                      pot: Int, bet: Int?, stack: Int, history: [String], prompt: String, options: [String],
                      principle: Principle, key: (PlayerType) -> Key) -> SpotDrill {
        let k = key(t)
        let correct = Set(options.indices.filter { k.correct.contains(options[$0]) })
        let per = c.types.map { pt -> (PlayerType, String, String) in
            let kk = key(pt)
            return (pt, kk.correct.joined(separator: " / "), kk.why)
        }
        return SpotDrill(concept: c, villainType: t, villainName: v.name, villainAppearance: v.appearance, heroCards: hero, board: board,
                         heroPosition: heroPos, villainPosition: villainPos, pot: pot, villainBet: bet, effectiveStack: stack,
                         history: history, prompt: prompt, options: options, correct: correct, explanation: k.why,
                         principle: principle, perType: per)
    }

    static func b(_ board: [Card], _ range: Range<Int>) -> String { board[range].map(\.pretty).joined(separator: " ") }

    // MARK: - Templates

    static func riverBluffCatch<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 5, rng: &rng) { _, board, d, _ in
            (d == "Top pair, weak kicker" || d == "Middle pair" || d == "Top pair, good kicker") && BoardTexture(board).maxSuitCount < 4
        }
        let bigPot = Bool.random(using: &rng) && t == .reg
        let flopBet = bigPot ? 40 : 12
        let potRiver = bigPot ? 25 + flopBet * 2 + 160 : 25 + flopBet * 2
        let bet = BotBrain.liveRound(Double(potRiver) * Double.random(in: 0.85...1.2, using: &rng))
        let history = [
            "Pre: You open to $12 on the button, \(v.name) calls in the BB.",
            "Flop \(b(board, 0..<3)): \(v.name) checks, you bet $\(flopBet), \(v.name) calls.",
            bigPot ? "Turn \(board[3].pretty): \(v.name) checks, you bet $80, \(v.name) calls." : "Turn \(board[3].pretty): \(v.name) checks, you check back.",
            "River \(board[4].pretty): \(v.name) bets $\(bet) into $\(potRiver).",
        ]
        return build(.riverBluffCatch, t, v, hero: hero, board: board, heroPos: .btn, villainPos: .bb, pot: potRiver, bet: bet, stack: 300,
                     history: history, prompt: "You have \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))). What's your play?",
                     options: ["Fold", "Call", "Raise"], principle: t == .whale ? .giveWhalesRope : .overfoldToPassiveAggression) { pt in
            switch pt {
            case .fish: Key(correct: ["Fold"], why: "Fish bluff far too little, and a pot-sized river bet from a fish is value. Overfold massively.")
            case .tryingRec: Key(correct: ["Fold"], why: "Trying recs rarely bluff rivers, especially big. That size is a strong hand. Fold.")
            case .nit: Key(correct: ["Fold"], why: "A nit betting big on the river = nutted. They essentially never bluff here.")
            case .whale: Key(correct: ["Call"], why: "\(bigPot ? "You bet the turn, but" : "You checked the turn, giving rope, and") whales over-bluff when given rope. One pair is a fine bluff catcher. Call (don't raise: their value doesn't fold and their bluffs do).")
            case .reg: bigPot
                ? Key(correct: ["Fold"], why: "Big pot (100bb+). Regs get straightforward when the money goes in. Overfold.")
                : Key(correct: ["Call"], why: "Small/medium pot: regs bluff at reasonable frequencies after you show weakness on the turn. Defend your bluff catchers.")
            }
        }
    }

    static func sizingTell<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 5, rng: &rng) { _, board, d, _ in
            d.hasPrefix("Top pair, good") || d.hasPrefix("Top pair, top") ? BoardTexture(board).maxSuitCount < 4 : false
        }
        let small = Bool.random(using: &rng)
        let pot = 64
        let bet = small ? Int.random(in: 15...22, using: &rng) : BotBrain.liveRound(Double(pot) * Double.random(in: 1.0...1.4, using: &rng))
        let history = [
            "Pre: \(v.name) limps from MP, you raise to $15 in the CO, \(v.name) calls.",
            "Flop \(b(board, 0..<3)): \(v.name) checks, you bet $15, \(v.name) calls.",
            "Turn \(board[3].pretty): check, check.",
            "River \(board[4].pretty): \(v.name) leads for $\(bet) into $\(pot) (\(Int(Double(bet) / Double(pot) * 100))% pot).",
        ]
        return build(.sizingTell, t, v, hero: hero, board: board, heroPos: .co, villainPos: .mp, pot: pot, bet: bet, stack: 285, history: history,
                     prompt: "Read the size. You hold \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))).",
                     options: ["Fold", "Call", "Raise"], principle: .sizingTells) { pt in
            switch (pt, small) {
            case (.fish, true): Key(correct: ["Call", "Raise"], why: "Fish small leads = medium hands, weak pairs and draws (a 'blocker bet'). Top pair is ahead of most of that. Call, or raise for value.")
            case (.fish, false): Key(correct: ["Fold"], why: "A fish leading big on the river is the nuts or close to it. Their sizing tells are reliable. Fold top pair.")
            case (.tryingRec, true): Key(correct: ["Call"], why: "Small sizing from a trying rec is thin value or a blocker. Call; raising only gets called by better.")
            case (.tryingRec, false): Key(correct: ["Fold"], why: "Trying recs size up with strong hands and almost never bluff big. Fold.")
            case (.whale, true): Key(correct: ["Call", "Raise"], why: "Whales size less reliably, but a small lead is rarely the nuts. Top pair is a happy call, or a value raise.")
            case (.whale, false): Key(correct: ["Call"], why: "Whales bet big with air too: their sizing is polarized, not honest. Top pair is a bluff catcher you should use.")
            default: Key(correct: ["Call"], why: "")
            }
        }
    }

    static func flopRaise<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 3, rng: &rng) { _, board, d, _ in
            (d.hasPrefix("Top pair, good") || d.hasPrefix("Top pair, top")) && !BoardTexture(board).isPaired
        }
        let raise = Int.random(in: 40...48, using: &rng)
        let history = [
            "Pre: You open to $12 in the HJ, \(v.name) calls on the button. Blinds fold.",
            "Flop \(b(board, 0..<3)) ($29): you c-bet $15, \(v.name) raises to $\(raise).",
        ]
        return build(.flopRaise, t, v, hero: hero, board: board, heroPos: .hj, villainPos: .btn, pot: 29 + 15 + raise, bet: raise, stack: 288,
                     history: history, prompt: "You have \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))). Action on you.",
                     options: ["Fold", "Call", "3-bet"], principle: t == .whale ? .fireWithFire : .overfoldToPassiveAggression) { pt in
            switch pt {
            case .fish: Key(correct: ["Fold"], why: "A fish raising the flop has two pair or better almost every time. They don't raise top pair, and they play draws passively.")
            case .tryingRec: Key(correct: ["Fold"], why: "Trying recs raise for value, not as bluffs. One pair is crushed.")
            case .nit: Key(correct: ["Fold"], why: "Nit flop raise = set / two pair. Easy fold.")
            case .whale: Key(correct: ["Call"], why: "Whales raise draws, worse top pairs and air. Call and re-evaluate. Don't 3-bet and fold out the hands you beat.")
            case .reg: Key(correct: ["Call"], why: "Regs raise draws and some bluffs in small pots. Call. In a big pot later, respect their aggression more.")
            }
        }
    }

    static func riverValue<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 5, rng: &rng) { _, board, d, val in
            (d == "Top two pair" || d.hasPrefix("Set") || d == "Two pair") && val.category <= .trips && BoardTexture(board).maxSuitCount < 3
        }
        let pot = 70
        let history = [
            "Pre: You open to $12 in the CO, \(v.name) calls from the BB.",
            "Flop \(b(board, 0..<3)): check, you bet $12, call.",
            "Turn \(board[3].pretty): check, you bet $25, call.",
            "River \(board[4].pretty) ($\(pot)): \(v.name) checks.",
        ]
        return build(.riverValueSize, t, v, hero: hero, board: board, heroPos: .co, villainPos: .bb, pot: pot, bet: nil, stack: 250, history: history,
                     prompt: "You have \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))). Choose your size.",
                     options: ["Check", "Bet 33%", "Bet 60%", "Bet 100%", "Overbet 150%"], principle: t == .tryingRec ? .sizeDownRiverVsRecs : .valueBetStations) { pt in
            switch pt {
            case .fish: Key(correct: ["Bet 100%", "Overbet 150%"], why: "Fish don't fold pairs. Put the money in for them. Go big.")
            case .whale: Key(correct: ["Bet 100%", "Overbet 150%"], why: "Whales call too much and spew. Bet huge for value.")
            case .tryingRec: Key(correct: ["Bet 60%"], why: "Trying recs fold big river bets, since they rarely see big bluffs and have learned to fold. Size down so their one pair hands pay.")
            case .nit: Key(correct: ["Bet 33%", "Bet 60%"], why: "A nit's check-call range is narrow and scared. Small to medium sizes get called by their one pair; big ones don't.")
            case .reg: Key(correct: ["Bet 60%", "Bet 100%"], why: "Regs call correctly in small pots. A standard 60–100% size is fine. Don't get cute.")
            }
        }
    }

    static func riverBluff<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        // Hero had a flush draw on the flop and missed.
        let (hero, board) = deal(boardCount: 5, rng: &rng) { hole, board, _, val in
            guard val.category == .highCard, hole[0].suit == hole[1].suit else { return false }
            let flopSuit = board[0..<3].filter { $0.suit == hole[0].suit }.count
            return flopSuit == 2 && board[3...].allSatisfy { $0.suit != hole[0].suit } && hole.allSatisfy { $0.rankIndex < 12 }
        }
        let bigPot = t == .reg && Bool.random(using: &rng)
        let pot = bigPot ? 210 : 85
        let history = [
            "Pre: You open to $12 on the button, \(v.name) calls from the BB.",
            "Flop \(b(board, 0..<3)): check, you bet $15 with your flush draw, call.",
            bigPot ? "Turn \(board[3].pretty): check, you bet $60, call." : "Turn \(board[3].pretty): check, you bet $20, call.",
            "River \(board[4].pretty) ($\(pot)): you missed. \(v.name) checks.",
        ]
        return build(.riverBluff, t, v, hero: hero, board: board, heroPos: .btn, villainPos: .bb, pot: pot, bet: nil, stack: 230, history: history,
                     prompt: "Missed flush draw, \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))). Bluff?",
                     options: ["Check", "Bet 33%", "Bet 75%", "Overbet 150%"], principle: [.fish, .whale].contains(t) ? .giveUpVsStations : .bluffRecsBig) { pt in
            switch pt {
            case .fish: Key(correct: ["Check"], why: "A fish who check-called twice has a pair they won't fold. Don't bluff stations. Give up.")
            case .whale: Key(correct: ["Check"], why: "Whales call too much. A river bluff into their sticky range just lights money on fire.")
            case .tryingRec: Key(correct: ["Bet 75%", "Overbet 150%"], why: "Trying recs fold one pair to big river bets. Bluff, and bluff big.")
            case .nit: Key(correct: ["Bet 75%", "Overbet 150%"], why: "Nits fold everything but the nuts to a big bet. Their range is capped after check-calling. Fire big.")
            case .reg: bigPot
                ? Key(correct: ["Bet 75%", "Overbet 150%"], why: "Big pot vs a reg: they don't call off marginal hands for big money. Make them uncomfortable.")
                : Key(correct: ["Bet 75%", "Check"], why: "Small pot vs a reg is closer to a balanced spot. A bigger bluff or giving up are both fine. Small bluffs just get called.")
            }
        }
    }

    static func isoLimpers<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let hands = ["K9s", "86s", "QTo", "76s", "55", "A8s", "KJo", "J9s", "44", "A5s"].compactMap { HandClass($0) }
        let hc = hands.randomElement(using: &rng)!
        let hero = cards(for: hc, rng: &rng)
        let history = [
            "\(v.name) limps UTG for $2.\(t == .nit || t == .tryingRec ? " (You've seen them limp-raise AA earlier tonight.)" : "")",
            "Folds to you on the button.",
        ]
        return build(.isoLimpers, t, v, hero: hero, board: [], heroPos: .btn, villainPos: .utg, pot: 5, bet: 2, stack: 300, history: history,
                     prompt: "\(hc) on the button vs a \(t.name.lowercased()) limp.", options: ["Fold", "Overlimp", "Iso to $15"],
                     principle: [.fish, .whale].contains(t) ? .isolateFishLimps : .respectLimpTraps) { pt in
            switch pt {
            case .fish: Key(correct: ["Iso to $15"], why: "Fish limp weak hands. Isolate wide in position, sized up so you play heads-up with initiative.")
            case .whale: Key(correct: ["Iso to $15"], why: "Get heads-up with the whale in position. Iso wide and big. They'll call and pay you postflop.")
            case .nit: Key(correct: ["Overlimp", "Fold"], why: "This nit limp-traps premiums. Iso-raising a marginal hand gets you limp-raised off it. Overlimp cheap in position or fold.")
            case .tryingRec: Key(correct: ["Overlimp", "Fold"], why: "A tight player who limps (and has shown a limp-raise) is trappy. Don't bloat the pot with marginal hands.")
            case .reg: Key(correct: ["Iso to $15"], why: "")
            }
        }
    }

    static func vsOpen<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let hands = ["AQo", "AJs", "TT", "99", "KQs", "AJo"].compactMap { HandClass($0) }
        let hc = hands.randomElement(using: &rng)!
        let hero = cards(for: hc, rng: &rng)
        let open = t == .whale ? [20, 25, 30].randomElement(using: &rng)! : (t == .fish ? 8 : 12)
        let history = ["\(v.name) opens to $\(open) from the LJ. Folds to you in the CO."]
        let isPair = hc.isPair
        return build(.vsOpen, t, v, hero: hero, board: [], heroPos: .co, villainPos: .lj, pot: open + 3, bet: open, stack: 300, history: history,
                     prompt: "\(hc) in the CO.", options: ["Fold", "Call", "3-bet"],
                     principle: t == .whale ? .threeBetWhalesWide : (t == .nit ? .respectNitRanges : .handVsRange)) { pt in
            switch pt {
            case .nit: Key(correct: isPair ? ["Call", "Fold"] : ["Fold"], why: isPair ? "Nit open = 6–10% range. Pairs can set-mine when deep, but never 3-bet them." : "A nit's opening range dominates \(hc). Fold. You aren't getting paid by worse.")
            case .whale: Key(correct: ["3-bet"], why: "Whale opens are wide and they call 3-bets with junk. \(hc) is a value 3-bet. Size it big ($80+).")
            case .fish: Key(correct: ["Call", "3-bet"], why: "Fish limp most hands, and their rare raises are stronger but still loose. Calling in position or a value 3-bet both work.")
            case .tryingRec: Key(correct: ["Call"], why: "A trying rec's open is solid, and their 3-bet calls are strong. Flat in position and play postflop, where they fold too much.")
            case .reg: Key(correct: ["Call", "3-bet"], why: "Regs open a standard range. Both flat and 3-bet are fine. Mix it up.")
            }
        }
    }

    static func limpRaise<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let hands = ["JJ", "TT", "AQs", "AQo", "AJs"].compactMap { HandClass($0) }
        let hc = hands.randomElement(using: &rng)!
        let hero = cards(for: hc, rng: &rng)
        let lr = [55, 60, 65].randomElement(using: &rng)!
        let history = ["\(v.name) limps UTG. You raise to $15 on the button.", "Blinds fold. \(v.name) re-raises to $\(lr)."]
        return build(.limpRaise, t, v, hero: hero, board: [], heroPos: .btn, villainPos: .utg, pot: 3 + 15 + lr, bet: lr, stack: 300, history: history,
                     prompt: "\(hc) facing a limp-raise.", options: ["Fold", "Call", "Jam"], principle: .limpRaiseIsNuts) { pt in
            switch pt {
            case .whale: Key(correct: ["Call", "Jam"], why: "Whales limp-raise with all sorts of hands. \(hc) is well ahead. Get it in or call and play.")
            default: Key(correct: ["Fold"], why: "Limp-raise at 1/2 = AA/KK. \(hc) is drawing nearly dead to a set. Fold.")
            }
        }
    }

    static func cold4Bet<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let hands = ["QQ", "AKo", "JJ", "AKs"].compactMap { HandClass($0) }
        let hc = hands.randomElement(using: &rng)!
        let hero = cards(for: hc, rng: &rng)
        let history = ["UTG opens to $12. MP 3-bets to $40. \(v.name) cold 4-bets to $110 from the button. Back to you in the BB."]
        return build(.cold4Bet, t, v, hero: hero, board: [], heroPos: .bb, villainPos: .btn, pot: 1 + 2 + 12 + 40 + 110, bet: 110, stack: 300, history: history,
                     prompt: "\(hc) facing a cold 4-bet.", options: ["Fold", "Call", "Jam"], principle: .cold4BetIsAces) { pt in
            switch pt {
            case .whale: Key(correct: ["Jam", "Call"], why: "Whales cold 4-bet light. \(hc) is ahead of their range. Get it in.")
            default: Key(correct: ["Fold"], why: "A cold 4-bet at 1/2 is AA/KK. With a 3-bettor still behind, \(hc) is in terrible shape. Fold.")
            }
        }
    }

    static func turnBarrel<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 4, rng: &rng) { hole, board, _, val in
            let r = HandRead(hole: hole, board: board)
            return val.category == .highCard && r.draw == .none && BoardTexture(Array(board[0..<3])).highRank < 12 && !BoardTexture(board).isPaired
        }
        let history = [
            "Pre: You open to $12 on the button, \(v.name) calls in the BB.",
            "Flop \(b(board, 0..<3)): check, you c-bet $12, \(v.name) calls.",
            "Turn \(board[3].pretty) ($53): \(v.name) checks.",
        ]
        return build(.turnBarrel, t, v, hero: hero, board: board, heroPos: .btn, villainPos: .bb, pot: 53, bet: nil, stack: 276, history: history,
                     prompt: "No pair, no draw. Barrel?", options: ["Check", "Bet 50%", "Bet 75%"],
                     principle: [.fish, .whale].contains(t) ? .giveUpVsStations : .barrelVsFolders) { pt in
            switch pt {
            case .fish: Key(correct: ["Check"], why: "The fish called the flop with any piece. They don't fold it on the turn. Give up and take the free card.")
            case .whale: Key(correct: ["Check"], why: "Whales don't fold. And checking gives them rope to bluff the river into your showdown hands later.")
            case .tryingRec: Key(correct: ["Bet 75%"], why: "Trying recs call flop with medium hands and fold them to a big turn barrel. Keep firing, sized up.")
            case .nit: Key(correct: ["Bet 75%"], why: "Nits fold one pair to pressure. Barrel big.")
            case .reg: Key(correct: ["Bet 50%", "Bet 75%"], why: "Regs float wide in position-less spots and fold to continued pressure in small pots often enough. Barreling is fine.")
            }
        }
    }

    static func thinValue<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let (hero, board) = deal(boardCount: 5, rng: &rng) { _, board, d, _ in
            (d == "Middle pair" || d == "Top pair, weak kicker") && BoardTexture(board).maxSuitCount < 3 && !BoardTexture(board).isPaired
        }
        let history = [
            "Pre: You open to $12 in the CO, \(v.name) calls in the BB.",
            "Flop \(b(board, 0..<3)): check, check.",
            "Turn \(board[3].pretty): check, check.",
            "River \(board[4].pretty) ($27): \(v.name) checks.",
        ]
        return build(.thinValue, t, v, hero: hero, board: board, heroPos: .co, villainPos: .bb, pot: 27, bet: nil, stack: 288, history: history,
                     prompt: "You have \(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))). Value bet?",
                     options: ["Check", "Bet 33%", "Bet 66%"], principle: .thinValueVsFish) { pt in
            switch pt {
            case .fish: Key(correct: ["Bet 33%", "Bet 66%"], why: "Fish call with worse pairs and ace-high. Thin value prints.")
            case .whale: Key(correct: ["Bet 33%", "Bet 66%"], why: "Whales call too much. Bet for thin value.")
            case .tryingRec: Key(correct: ["Check"], why: "Trying recs only call with better. Worse hands fold. Take the showdown.")
            case .nit: Key(correct: ["Check"], why: "A nit only continues with better. Check back and win at showdown.")
            case .reg: Key(correct: ["Check"], why: "Regs won't pay you off with worse here and can check-raise bluff. Showdown value: check.")
            }
        }
    }

    static func flopCbet<R: RandomNumberGenerator>(_ t: PlayerType, _ v: BotPlayer, _ rng: inout R) -> SpotDrill {
        let aceHigh = Bool.random(using: &rng)
        let (hero, board) = deal(boardCount: 3, rng: &rng) { hole, board, d, _ in
            let tx = BoardTexture(board)
            guard !tx.isMonotone && !tx.isPaired else { return false }
            if aceHigh {
                guard tx.isAceHigh else { return false }
                return d.hasPrefix("Top pair, top") || d.hasPrefix("Top pair, good") || (d.contains("high") && !hole.contains { $0.rankIndex == 12 })
            }
            return !tx.isAceHigh && tx.highRank >= 8
        }
        let d = HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))
        let value = d.hasPrefix("Top pair")
        let history = [
            "Pre: You open to $12 on the button, \(v.name) calls in the BB.",
            "Flop \(b(board, 0..<3)) ($25): \(v.name) checks.",
        ]
        let opts = ["Check", "Bet 33%", "Bet 50%", "Bet 75%", "Overbet 150%"]
        return build(.flopCbet, t, v, hero: hero, board: board, heroPos: .btn, villainPos: .bb, pot: 25, bet: nil, stack: 288, history: history,
                     prompt: "\(aceHigh ? "Ace-high" : "Non-A-high") flop, heads-up in position. You have \(d).", options: opts,
                     principle: aceHigh ? .aceHighOverbetOrCheck : .rangeBetHalfPot) { pt in
            if aceHigh {
                if value && d.hasPrefix("Top pair, top") {
                    return Key(correct: ["Overbet 150%"], why: "Ace-high board, thick value (AK/AQ): overbet. Fish have lots of Ax and pay off big.")
                }
                if value { return Key(correct: ["Check"], why: "Weaker Ax on an A-high board: check. The overbet is for AQ+ and selected bluffs. Medium hands check.") }
                return Key(correct: ["Check", "Overbet 150%"], why: "No pair on an A-high board: mostly check. Overbet-bluff selectively with blockers or backdoors. Never use the in-between size.")
            }
            if pt == .fish && d.hasPrefix("Top pair") {
                return Key(correct: ["Bet 50%", "Bet 75%"], why: "Range-bet ½ pot is the default. Against very passive fish, size up with real value.")
            }
            return Key(correct: ["Bet 50%"], why: "Non-A-high flop, IP heads-up: ½-pot range bet. It funnels their wide range to the turn, where they cap themselves.")
        }
    }
}
