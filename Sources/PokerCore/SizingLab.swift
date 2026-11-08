import Foundation

public struct LabQuestion: Sendable, Identifiable {
    public let id = UUID()
    public let prompt: String
    public let options: [String]
    public let correct: Set<Int>
    public let explanation: String
}

/// "The inverse question": before reacting to a bet, ask how this player would bet each part of their range.
public struct InverseDrill: Sendable, Identifiable {
    public let id = UUID()
    public let villainType: PlayerType
    public let villainName: String
    public let heroCards: [Card]
    public let board: [Card]
    public let pot: Int
    public let bet: Int
    public let history: [String]
    public let questions: [LabQuestion]

    public var betPct: Int { Int(Double(bet) / Double(pot) * 100) }

    public var asText: String {
        "Inverse-question drill vs \(villainName) (\(villainType.name)). Hero \(heroCards.map(\.pretty).joined()) on \(board.map(\.pretty).joined(separator: " ")). Pot $\(pot), villain bets $\(bet) (\(betPct)% pot).\n"
            + history.joined(separator: "\n")
    }
}

/// "Size it": pick a size; graded against a target band for this player type.
public struct SizeItDrill: Sendable, Identifiable {
    public let id = UUID()
    public let villainType: PlayerType
    public let villainName: String
    public let heroCards: [Card]
    public let board: [Card]
    public let pot: Int
    public let stack: Int
    public let history: [String]
    public let handText: String
    /// Inclusive band of pot fractions; `nil` lower bound means "check is correct".
    public let targetLow: Double
    public let targetHigh: Double
    public let checkIsCorrect: Bool
    public let explanation: String
    public let principle: Principle

    public func grade(fraction: Double) -> (correct: Bool, message: String) {
        if fraction <= 0 {
            return checkIsCorrect ? (true, "Correct: check.") : (false, "Checking misses \(targetText).")
        }
        if checkIsCorrect && targetHigh == 0 { return (false, "This is a check, not a bet.") }
        let ok = fraction >= targetLow - 0.001 && fraction <= targetHigh + 0.001
        return (ok, ok ? "In the target band (\(targetText))." : "Target was \(targetText); you bet \(Int(fraction * 100))%.")
    }

    public var targetText: String {
        if targetHigh == 0 { return "check" }
        return "\(Int(targetLow * 100))–\(Int(targetHigh * 100))% pot" + (checkIsCorrect ? " or check" : "")
    }
}

public enum SizingLab {
    static let sizeOptions = ["Check / no bet", "Small (25–40%)", "Medium (50–75%)", "Big (90%+)"]
    static let rangeOptions = ["Mostly nutted / strong", "Mostly medium hands & draws", "Polarized: nuts or air", "Mostly bluffs"]

    public static func inverse<R: RandomNumberGenerator>(type: PlayerType? = nil, rng: inout R) -> InverseDrill {
        let t = type ?? PlayerType.allCases.randomElement(using: &rng)!
        let v = Roster.makeBot(type: t, usedNames: [], rng: &rng)
        let (hero, board) = DrillFactory.deal(boardCount: 5, rng: &rng) { _, board, d, _ in
            (d.hasPrefix("Top pair") || d == "Middle pair" || d.hasPrefix("Overpair")) && BoardTexture(board).maxSuitCount < 4
        }
        let big = Bool.random(using: &rng)
        let pot = 60
        let bet = big ? BotBrain.liveRound(Double(pot) * Double.random(in: 1.0...1.3, using: &rng)) : Int.random(in: 15...20, using: &rng)
        let history = [
            "Pre: You open to $12 on the button, \(v.name) calls from the BB.",
            "Flop \(board[0..<3].map(\.pretty).joined(separator: " ")): check, you bet $12, call.",
            "Turn \(board[3].pretty): check, check.",
            "River \(board[4].pretty): \(v.name) bets $\(bet) into $\(pot).",
        ]
        let handText = HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))

        func q(_ prompt: String, _ opts: [String], _ correct: [Int], _ why: String) -> LabQuestion {
            LabQuestion(prompt: prompt, options: opts, correct: Set(correct), explanation: why)
        }

        var qs: [LabQuestion] = []
        switch t {
        case .fish:
            qs.append(q("If \(v.name) had the NUTS here, how would they bet?", sizeOptions, [3], "Fish size by hand strength: big hands get big bets. That's the sizing tell."))
            qs.append(q("If they had a MEDIUM hand (one pair)?", sizeOptions, [0, 1], "Medium hands check or make a small 'blocker' bet."))
            qs.append(q("If they had AIR (missed draw)?", sizeOptions, [0], "Fish rarely bluff. Missed draws mostly just check and give up."))
            qs.append(q("So their actual \(big ? "big" : "small") bet means…", rangeOptions, big ? [0] : [1], big ? "Big bet from a fish = strong. That's the whole read." : "Small bet = medium hand or draw. Their strong hands would have bet bigger."))
            qs.append(q("With \(handText), you…", ["Fold", "Call", "Raise"], big ? [0] : [1, 2], big ? "Overfold to fish aggression. Your bluff catcher is beat." : "You're ahead of a small-bet range. Call, or raise your stronger hands for value."))
        case .whale:
            qs.append(q("If \(v.name) had the NUTS here, how would they bet?", sizeOptions, [2, 3], "Whales bet value big but are erratic. Medium or big."))
            qs.append(q("If they had a MEDIUM hand?", sizeOptions, [0, 1, 2], "Anything goes. Whales bet medium hands at random sizes."))
            qs.append(q("If they had AIR after you checked the turn (gave rope)?", sizeOptions, [2, 3], "This is the whale leak: they barrel air big when you check to them."))
            qs.append(q("So their actual \(big ? "big" : "small") bet means…", rangeOptions, big ? [2] : [1], big ? "Big bets are polarized: nuts or air. The size doesn't settle it." : "Small bets from whales are usually medium hands."))
            qs.append(q("With \(handText), you…", ["Fold", "Call", "Raise"], [1], "You gave rope and they took it. Bluff-catch. Raising folds out their bluffs."))
        case .tryingRec:
            qs.append(q("If \(v.name) had the NUTS here, how would they bet?", sizeOptions, [2, 3], "Trying recs bet value at standard-to-big sizes."))
            qs.append(q("If they had a MEDIUM hand?", sizeOptions, [0], "They check medium hands, hoping to get to showdown."))
            qs.append(q("If they had AIR?", sizeOptions, [0], "Trying recs rarely bluff the river, especially after you checked the turn back."))
            qs.append(q("So their actual \(big ? "big" : "small") bet means…", rangeOptions, big ? [0] : [0, 1], big ? "Strong. They don't bluff big." : "Usually thin value. Still mostly made hands."))
            qs.append(q("With \(handText), you…", ["Fold", "Call", "Raise"], big ? [0] : [1], big ? "Overfold. The inverse question says air would have checked." : "Small bet: call. It's cheap, and they sometimes bet worse for 'value'."))
        case .nit:
            qs.append(q("If \(v.name) had the NUTS here, how would they bet?", sizeOptions, [2, 3], "Nits bet their nutted hands for value."))
            qs.append(q("If they had a MEDIUM hand?", sizeOptions, [0], "Nits check medium hands and are scared of everything."))
            qs.append(q("If they had AIR?", sizeOptions, [0], "Nits essentially never bluff rivers."))
            qs.append(q("So their actual \(big ? "big" : "small") bet means…", rangeOptions, [0], "Any river bet from a nit is strong."))
            qs.append(q("With \(handText), you…", ["Fold", "Call", "Raise"], big ? [0] : [0, 1], big ? "Nit + big river bet = fold. Every time." : "Small bet from a nit: a cheap call is OK, but you're often beat."))
        case .reg:
            qs.append(q("If \(v.name) had the NUTS here, how would they bet?", sizeOptions, [2, 3], "Regs pick one size for value and bluffs."))
            qs.append(q("If they had a MEDIUM hand?", sizeOptions, [0], "Regs check medium hands for showdown value."))
            qs.append(q("If they had AIR?", sizeOptions, [2, 3], "Same size as their value. That's what balanced means."))
            qs.append(q("So their actual \(big ? "big" : "small") bet means…", rangeOptions, big ? [2] : [1, 2], "Regs are roughly balanced: size tells you little. Use pot size and line instead."))
            qs.append(q("With \(handText), you…", ["Fold", "Call", "Raise"], [1], "Small or medium pot: defend your bluff catchers vs regs. In big pots, overfold."))
        }
        return InverseDrill(villainType: t, villainName: v.name, heroCards: hero, board: board, pot: pot, bet: bet, history: history, questions: qs)
    }

    public static func sizeIt<R: RandomNumberGenerator>(type: PlayerType? = nil, rng: inout R) -> SizeItDrill {
        let t = type ?? PlayerType.allCases.randomElement(using: &rng)!
        let v = Roster.makeBot(type: t, usedNames: [], rng: &rng)
        let kind = Int.random(in: 0..<3, using: &rng)  // 0 river value, 1 river bluff, 2 flop cbet
        switch kind {
        case 0:
            let (hero, board) = DrillFactory.deal(boardCount: 5, rng: &rng) { _, board, d, val in
                (d == "Top two pair" || d.hasPrefix("Set") || d.hasPrefix("Top pair, top")) && val.category <= .trips && BoardTexture(board).maxSuitCount < 3
            }
            let hand = HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))
            let band: (Double, Double, String, Principle) = {
                switch t {
                case .fish: (0.75, 1.6, "Fish don't fold pairs. Size up and put the money in for them.", .valueBetStations)
                case .whale: (0.75, 1.6, "Whales call too much. Bet huge for value.", .valueBetStations)
                case .tryingRec: (0.4, 0.7, "Trying recs fold big river bets. Size down so one pair can call.", .sizeDownRiverVsRecs)
                case .nit: (0.3, 0.6, "Nits only call small. Take the thin value you can get.", .sizeDownRiverVsRecs)
                case .reg: (0.55, 1.0, "Standard sizing vs a reg in a normal pot.", .inverseQuestion)
                }
            }()
            return SizeItDrill(villainType: t, villainName: v.name, heroCards: hero, board: board, pot: 70, stack: 250,
                               history: ["You opened the CO, \(v.name) called the BB. You bet flop and turn, and they called both.", "River \(board[4].pretty): \(v.name) checks to you."],
                               handText: hand, targetLow: band.0, targetHigh: band.1, checkIsCorrect: false, explanation: band.2, principle: band.3)
        case 1:
            let (hero, board) = DrillFactory.deal(boardCount: 5, rng: &rng) { hole, board, _, val in
                val.category == .highCard && hole[0].suit == hole[1].suit && board[0..<3].filter { $0.suit == hole[0].suit }.count == 2
                    && board[3...].allSatisfy { $0.suit != hole[0].suit } && hole.allSatisfy { $0.rankIndex < 12 }
            }
            let stations = t == .fish || t == .whale
            return SizeItDrill(villainType: t, villainName: v.name, heroCards: hero, board: board, pot: 85, stack: 230,
                               history: ["You c-bet the flop with a flush draw and barreled the turn. \(v.name) called both.", "River \(board[4].pretty): you missed. \(v.name) checks."],
                               handText: "Missed flush draw (\(HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))))",
                               targetLow: stations ? 0 : 0.7, targetHigh: stations ? 0 : 1.6, checkIsCorrect: stations,
                               explanation: stations ? "Don't bluff stations. Check and give up." : "\(t.name)s fold to big bets. Bluff 70%+.",
                               principle: stations ? .giveUpVsStations : .bluffRecsBig)
        default:
            let aceHigh = Bool.random(using: &rng)
            let (hero, board) = DrillFactory.deal(boardCount: 3, rng: &rng) { _, board, d, _ in
                let tx = BoardTexture(board)
                guard !tx.isMonotone && !tx.isPaired && tx.isAceHigh == aceHigh else { return false }
                return aceHigh ? d.hasPrefix("Top pair, top") : true
            }
            let hand = HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))
            return SizeItDrill(villainType: t, villainName: v.name, heroCards: hero, board: board, pot: 25, stack: 288,
                               history: ["You opened the button, \(v.name) called the BB.", "Flop: \(v.name) checks to you."],
                               handText: hand, targetLow: aceHigh ? 1.3 : 0.4, targetHigh: aceHigh ? 2.0 : (t == .fish && hand.hasPrefix("Top pair") ? 0.8 : 0.6),
                               checkIsCorrect: false,
                               explanation: aceHigh ? "A-high flop with AK/AQ: overbet 1.5–2x for thick value." : "Non-A-high flop: ½-pot range bet\(t == .fish ? " (size up real value vs passive fish)" : "").",
                               principle: aceHigh ? .aceHighOverbetOrCheck : .rangeBetHalfPot)
        }
    }
}

/// The inverse question, value edition: "If they have TPTK here, how much would I have to bet to fold it? Bet just under that."
public struct ValueDrill: Sendable, Identifiable {
    public let id = UUID()
    public let villainType: PlayerType
    public let villainName: String
    public let heroCards: [Card]
    public let board: [Card]
    public let street: Street
    public let pot: Int
    public let effectiveStack: Int
    public let history: [String]
    public let heroHandText: String
    public let villainHolding: HoldingClass
    public let villainExample: [Card]
    public let threshold: Double
    public let questions: [LabQuestion]
    /// What every other holding of theirs calls in this spot.
    public let callTable: [(holding: HoldingClass, maxCall: String)]
    public let plan: String

    public var asText: String {
        "Inverse-question value drill vs \(villainName) (\(villainType.name)) on the \(street.name.lowercased()). Hero \(heroCards.map(\.pretty).joined()) (\(heroHandText)) on \(board.map(\.pretty).joined(separator: " ")). Pot $\(pot), effective stack $\(effectiveStack). Assume villain has \(villainHolding.label), e.g. \(villainExample.map(\.pretty).joined()). Model max call: \(CallModel.describe(threshold)).\n"
            + history.joined(separator: "\n")
    }
}

extension SizingLab {
    static let valueSizes: [(String, Double)] = [("33%", 0.33), ("50%", 0.5), ("66%", 0.66), ("75%", 0.75), ("100%", 1.0), ("125%", 1.25), ("150%", 1.5), ("200%", 2.0)]

    public static func valueDrill<R: RandomNumberGenerator>(type: PlayerType? = nil, rng: inout R) -> ValueDrill {
        let t = type ?? PlayerType.allCases.randomElement(using: &rng)!
        let v = Roster.makeBot(type: t, usedNames: [], rng: &rng)
        let street: Street = [.flop, .turn, .river, .river].randomElement(using: &rng)!
        let boardCount = street == .flop ? 3 : (street == .turn ? 4 : 5)
        let (hero, board) = DrillFactory.deal(boardCount: boardCount, rng: &rng) { hole, board, d, val in
            (d.hasPrefix("Set") || d == "Top two pair") && val.category <= .trips && BoardTexture(board).maxSuitCount < 3 && !BoardTexture(board).isPaired
        }
        let holding: HoldingClass = [.topPairTop, .topPairTop, .topPairTop, .topPairWeak, .middlePair].randomElement(using: &rng)!
        // Find a concrete villain combo with that holding.
        var example: [Card] = []
        for _ in 0..<5000 {
            var d = Deck(rng: &rng, excluding: Set(hero + board))
            let c = d.deal(2)
            if CallModel.classify(HandRead(hole: c, board: board), street: street, opponents: 1) == holding { example = c; break }
        }
        if example.isEmpty { return valueDrill(type: t, rng: &rng) }

        let pot: Int = street == .flop ? 25 : (street == .turn ? 55 : 115)
        let stack = 300 - (street == .flop ? 12 : (street == .turn ? 27 : 57))
        let bigPot = pot >= 120
        let thr = CallModel.maxCall(t, holding, street: street, bigPot: bigPot)
        let stackFrac = Double(stack) / Double(pot)
        let heroText = HandRead.describe(hole: hero, board: board, value: HandEvaluator.evaluate(hero + board))

        let sizes = valueSizes.filter { $0.1 < stackFrac * 0.9 } + [("All-in $\(stack)", stackFrac)]
        let labels = sizes.map { $0.0 }
        // Q1: the fold point.
        let neverFolds = thr >= stackFrac
        var q1Opts = labels
        q1Opts.append("They never fold it")
        let foldIdx: Int = neverFolds ? q1Opts.count - 1 : (sizes.firstIndex { $0.1 > thr } ?? q1Opts.count - 1)
        // Q2: bet just under the fold point.
        var best = Set(sizes.indices.filter { sizes[$0].1 <= thr && sizes[$0].1 >= thr * 0.72 })
        if best.isEmpty, let i = sizes.indices.last(where: { sizes[$0].1 <= thr }) { best = [i] }
        if neverFolds { best = Set(sizes.indices.filter { sizes[$0].1 >= stackFrac * 0.5 }) }
        if best.isEmpty { best = [0] }

        let streetsLeft = street == .flop ? 3 : (street == .turn ? 2 : 1)
        let geo = (pow(2 * stackFrac + 1, 1 / Double(streetsLeft)) - 1) / 2
        let plan: String
        if streetsLeft == 1 {
            plan = neverFolds ? "River: they call off with \(holding.short), so just put it all in." : "River: one bet left. Take the biggest size they still call."
        } else {
            plan = "Stacks plan: to get \(stack) in by the river over \(streetsLeft) streets you'd bet ~\(Int(geo * 100))% pot each street. "
                + (geo <= thr ? "That's under their \(holding.short) fold point, so you can play for stacks." : "That's above their \(holding.short) fold point, so you can't get stacks from this hand. Take the max they'll pay instead.")
        }
        let why: [PlayerType: String] = [
            .fish: "Fish don't fold top pair. 'What does my hand want?' It wants their stack.",
            .whale: "Whales call huge with any pair. Overbets get paid.",
            .tryingRec: "Trying recs fold big bets, especially on the river. Stay under their fold line.",
            .nit: "Nits fold one pair to anything big. Small, steady bets get paid.",
            .reg: "Regs call 'correctly' in normal pots but tighten up when it gets big.",
        ]
        let q1 = LabQuestion(prompt: "Inverse question: if \(v.name) has \(holding.label) (like \(example.map(\.pretty).joined())), what's the smallest bet that folds it?",
                             options: q1Opts, correct: [foldIdx],
                             explanation: "\(t.name) with \(holding.short) on the \(street.name.lowercased()) calls up to about \(CallModel.describe(thr)). \(why[t]!)")
        let q2 = LabQuestion(prompt: "So what do you bet with your \(heroText)?", options: labels, correct: best,
                             explanation: neverFolds ? "They're never folding, so get the stack in." : "Bet just under their fold point. That's the most you get paid by \(holding.short).")
        let table = [HoldingClass.topPairTop, .topPairWeak, .middlePair, .strongDraw, .air]
            .filter { street != .river || $0 != .strongDraw }
            .map { ($0, CallModel.describe(CallModel.maxCall(t, $0, street: street, bigPot: bigPot))) }
        let history: [String] = {
            var h = ["Pre: You open to $12 on the button, \(v.name) calls from the BB."]
            h.append("Flop \(board[0..<3].map(\.pretty).joined(separator: " ")): \(street == .flop ? "\(v.name) checks to you ($\(pot))." : "check, you bet $15, call.")")
            if board.count >= 4 { h.append("Turn \(board[3].pretty): \(street == .turn ? "\(v.name) checks to you ($\(pot))." : "check, you bet $30, call.")") }
            if board.count >= 5 { h.append("River \(board[4].pretty): \(v.name) checks to you ($\(pot)).") }
            return h
        }()
        return ValueDrill(villainType: t, villainName: v.name, heroCards: hero, board: board, street: street, pot: pot, effectiveStack: stack,
                          history: history, heroHandText: heroText, villainHolding: holding, villainExample: example, threshold: thr,
                          questions: [q1, q2], callTable: table, plan: plan)
    }
}
