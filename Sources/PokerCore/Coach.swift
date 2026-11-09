import Foundation

public enum Grade: String, Sendable, Codable, CaseIterable {
    case good, okay, inaccuracy, mistake

    public var label: String {
        switch self {
        case .good: "Good"
        case .okay: "Note"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        }
    }

    public var symbol: String {
        switch self {
        case .good: "✅"
        case .okay: "💡"
        case .inaccuracy: "⚠️"
        case .mistake: "❌"
        }
    }
}

public struct CoachNote: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let handNumber: Int
    public let street: Street
    public let grade: Grade
    public let principle: Principle?
    public let headline: String
    public let detail: String
    public let heroAction: String
    /// Index of the hero action in `HandState.actions` this note refers to.
    public let actionIndex: Int

    public init(handNumber: Int, street: Street, grade: Grade, principle: Principle?, headline: String, detail: String, heroAction: String, actionIndex: Int) {
        id = UUID()
        self.handNumber = handNumber
        self.street = street
        self.grade = grade
        self.principle = principle
        self.headline = headline
        self.detail = detail
        self.heroAction = heroAction
        self.actionIndex = actionIndex
    }
}

/// Rule-based exploit coach. Grades a single hero decision given the state *before* it was applied.
public enum Coach {
    static func openThreshold(_ pos: Position) -> Double {
        switch pos {
        case .utg: 0.12
        case .utg1: 0.13
        case .mp: 0.15
        case .lj: 0.18
        case .hj: 0.22
        case .co: 0.28
        case .btn: 0.42
        case .sb: 0.30
        case .bb: 0.5
        }
    }

    public static func describe(_ d: Decision, legal: LegalActions, pot: Int) -> String {
        switch d {
        case .fold: return "Fold"
        case .check: return "Check"
        case .call: return "Call $\(legal.callAmount)"
        case .raise(let to):
            if legal.isBet {
                let pct = pot > 0 ? Int(Double(to - legal.committed) / Double(pot) * 100) : 0
                return "Bet $\(to) (\(pct)% pot)"
            }
            return "Raise to $\(to)"
        }
    }

    /// `profiles` should be what the hero could know (see `TypeEstimate`), not the bots' hidden profiles.
    /// `labels` describes each read in the note text ("likely Fish"); defaults to the profile's type name.
    public static func grade(state: HandState, heroSeat: Int, decision: Decision, profiles: [Int: Profile],
                             labels: [Int: String] = [:]) -> CoachNote? {
        guard let legal = state.legalActions(), let hero = state.player(seat: heroSeat) else { return nil }
        let action = describe(decision, legal: legal, pot: state.pot)
        func note(_ g: Grade, _ p: Principle?, _ h: String, _ d: String) -> CoachNote {
            CoachNote(handNumber: state.handNumber, street: state.street, grade: g, principle: p, headline: h, detail: d, heroAction: action, actionIndex: state.actions.count)
        }
        func name(_ seat: Int) -> String {
            let n = state.player(seat: seat)?.name ?? "Villain"
            if let l = labels[seat] { return "\(n) (\(l))" }
            guard let t = profiles[seat]?.type else { return n }
            return "\(n) (\(t.name))"
        }
        if state.street == .preflop {
            return preflop(state: state, hero: hero, decision: decision, legal: legal, profiles: profiles, note: note, name: name)
        }
        return postflop(state: state, hero: hero, decision: decision, legal: legal, profiles: profiles, note: note, name: name)
    }

    // MARK: Preflop

    static func preflop(state: HandState, hero: SeatState, decision: Decision, legal: LegalActions, profiles: [Int: Profile],
                        note: (Grade, Principle?, String, String) -> CoachNote, name: (Int) -> String) -> CoachNote? {
        let hc = HandClass(hero.hole)
        let pct = RangeModel.standard.percentile(of: hc)
        let pos = state.position(of: hero.seat)
        let sit = PreflopSituation(state: state, seat: hero.seat)
        let continues: Bool = {
            switch decision {
            case .call, .raise: return true
            default: return false
            }
        }()
        let isRaise: Bool = { if case .raise = decision { return true }; return false }()
        let raiseTo: Int = { if case .raise(let t) = decision { return t }; return 0 }()

        switch sit.raises {
        case 0:
            let limperTypes = sit.limpers.compactMap { profiles[$0]?.type }
            let fishLimpers = limperTypes.contains { $0 == .fish || $0 == .whale }
            let trapLimper = sit.limpers.first { (profiles[$0]?.limpTrapPremiums ?? 0) >= 0.3 }
            if decision == .call && sit.limpers.isEmpty && !pos.isBlind {
                return note(.mistake, .dontOpenLimp, "Don't open-limp \(hc)", "First in from \(pos.short): raise to about $12 or fold. Open-limping lets the whole table in cheap while you're out of position.")
            }
            if isRaise {
                let straddled = state.straddleSeat != nil
                let rec = (straddled ? 20 : 12) + 5 * sit.limpers.count
                if let t = trapLimper, pct > 0.1 {
                    return note(.inaccuracy, .respectLimpTraps, "Careful isolating \(name(t))",
                                "You've already seen this player limp-raise this session, so their limps include big pairs. Iso-raising \(hc) gets you limp-raised off your hand. Against a known limp-trapper, iso much tighter and overlimp or fold your marginal hands.")
                }
                if raiseTo < Int(Double(rec) * 0.7) {
                    return note(.inaccuracy, .liveOpenSizing, "Size up to ~$\(rec)",
                                "Raising to $\(raiseTo) at a live 1/2 table invites a multiway pot. Standard is $10–15 plus $5 per limper\(straddled ? " (double it in a straddled pot)" : "").")
                }
                if sit.limpers.isEmpty && pct > openThreshold(pos) * 1.4 {
                    return note(.inaccuracy, nil, "\(hc) is loose from \(pos.short)",
                                "That's outside a solid \(pos.short) opening range (top ~\(Int(openThreshold(pos) * 100))%). With players left to act who can wake up with something, stick to stronger hands up front.")
                }
                if fishLimpers {
                    return note(.good, .isolateFishLimps, "Nice iso-raise", "Isolating the weak limper\(sit.limpers.count > 1 ? "s" : "") with initiative and position is exactly how you print vs fish.")
                }
                return nil
            }
            if (decision == .fold || decision == .call || decision == .check) && fishLimpers && trapLimper == nil
                && pos.lateness >= 0.55 && !pos.isBlind && pct <= 0.35 {
                return note(.inaccuracy, .isolateFishLimps, "Isolate here",
                            "\(sit.limpers.map(name).joined(separator: ", ")) limped. \(hc) in \(pos.short) is a profitable iso-raise to about $\(15 + 5 * max(0, sit.limpers.count - 1)). Fish limp weak hands, and you get position plus initiative.")
            }
            if decision == .fold && sit.limpers.isEmpty && !pos.isBlind && pct <= openThreshold(pos) * 0.5 {
                return note(.inaccuracy, nil, "Too tight: open \(hc)", "\(hc) is a standard open from \(pos.short). Folding it gives up easy profit.")
            }
            return nil

        case 1:
            guard let raiser = sit.lastRaiser else { return nil }
            if sit.lastRaiserLimpedFirst && continues && !hc.isBigPair && profiles[raiser]?.type != .whale {
                return note(.mistake, .limpRaiseIsNuts, "Limp-raise = AA/KK",
                            "\(name(raiser)) limped and then raised. At 1/2 that's almost always AA/KK. Fold \(hc). Even JJ/AQ are crushed.")
            }
            guard let rt = profiles[raiser]?.type else { return nil }
            if rt == .nit && continues && pct > 0.06 {
                let setMine = hc.isPair && decision == .call && legal.callAmount * 15 <= min(hero.stack, state.player(seat: raiser)?.stack ?? 0)
                if !setMine {
                    return note(.inaccuracy, .respectNitRanges, "Tighten vs the nit's open",
                                "\(name(raiser)) opens about 6–10%. \(hc) is dominated by that range way too often. Fold it, or only set-mine pairs when the stacks are deep.")
                }
            }
            if rt == .whale {
                if decision == .fold && pct <= 0.1 {
                    return note(.inaccuracy, .threeBetWhalesWide, "3-bet the whale", "\(hc) crushes a whale's opening range. 3-bet big for value. They'll call with worse.")
                }
                if decision == .call && hc.isPremium {
                    return note(.inaccuracy, .threeBetWhalesWide, "Re-raise your premium", "Against a whale, flatting \(hc) wastes value. 3-bet big, because they call wide and stack off light.")
                }
                if isRaise && pct <= 0.15 {
                    return note(.good, .threeBetWhalesWide, "Good value 3-bet", "Building the pot with a strong hand against the biggest loser at the table.")
                }
            }
            return nil

        case 2:
            guard let raiser = sit.lastRaiser, let rt = profiles[raiser]?.type else { return nil }
            if (rt == .nit || rt == .tryingRec) && continues && !(hc.isPair && hc.high >= 10) && !(hc.high == 12 && hc.low == 11) {
                return note(.inaccuracy, .respectNitRanges, "Their 3-bet is QQ+/AK",
                            "\(name(raiser)) only 3-bets the top of their range. \(hc) is in bad shape. Fold.")
            }
            return nil

        default:
            let voluntarilyIn = state.actions(on: .preflop).contains { $0.seat == hero.seat && ($0.type == .raise || $0.type == .call) }
            if !voluntarilyIn && continues && !hc.isBigPair {
                return note(.mistake, .cold4BetIsAces, "Cold 4-bet = AA/KK", "A cold 4-bet at 1/2 is AA/KK almost every time. Fold \(hc).")
            }
            if continues && !hc.isBigPair && !(hc.isPremium), let r = sit.lastRaiser, let t = profiles[r]?.type, t != .whale {
                return note(.inaccuracy, .respectNitRanges, "4-bets are narrow", "\(name(r)) is very rarely 4-betting light. \(hc) is behind their range.")
            }
            return nil
        }
    }

    // MARK: Postflop

    static func postflop(state: HandState, hero: SeatState, decision: Decision, legal: LegalActions, profiles: [Int: Profile],
                         note: (Grade, Principle?, String, String) -> CoachNote, name: (Int) -> String) -> CoachNote? {
        let read = HandRead(hole: hero.hole, board: state.board)
        let opps = state.opponents(of: hero.seat)
        let tier = read.tier(opponents: opps.count)
        let draw: DrawStrength = state.street == .river ? .none : read.draw
        let pot = state.pot
        let bb = state.config.bigBlind
        let bigPot = pot >= 100 * bb
        let streetActs = state.actions(on: state.street)
        let heroBetThisStreet = streetActs.contains { $0.seat == hero.seat && $0.type.isAggressive }
        let heroChecked = streetActs.contains { $0.seat == hero.seat && $0.type == .check }
        let continues: Bool = { switch decision { case .call, .raise: return true; default: return false } }()
        let handText = read.madeDescription + (read.drawDescription.map { " + \($0)" } ?? "")
        let onePair = read.value.category <= .pair && tier < .monster

        if legal.toCall > 0 {
            guard let aggr = state.lastAggressorThisStreet, let vt = profiles[aggr]?.type else { return nil }
            let ratio = Double(legal.toCall) / Double(max(1, pot - legal.toCall))
            let pctText = "\(Int(ratio * 100))% pot"
            let goodDraw = draw == .strong && Double(legal.toCall) <= Double(pot) * 0.6

            switch vt {
            case .fish, .tryingRec, .nit:
                // River donk-lead from a fish
                if vt == .fish && state.street == .river && !heroBetThisStreet && state.preflopRaiser == hero.seat
                    && streetActs.first(where: { $0.type.isAggressive })?.seat == aggr && tier <= .good && continues {
                    return note(.mistake, .donkLeadIsValue, "Fish donk-lead = value",
                                "\(name(aggr)) led into you on the river. From a fish that's value almost every time. Fold \(handText).")
                }
                if heroBetThisStreet && (tier <= .good || onePair) && !goodDraw {
                    return continues
                        ? note(.mistake, .overfoldToPassiveAggression, "Overfold to the raise",
                               "\(name(aggr)) raised your bet. Passive players' raises are the nuts or close to it. \(handText) is a bluff catcher here, so fold.")
                        : note(.good, .overfoldToPassiveAggression, "Disciplined fold", "Passive player raise = strong. Good overfold with \(handText).")
                }
                if ratio >= 0.6 && (tier <= .medium || (onePair && state.street == .river && ratio >= 0.9)) && !goodDraw {
                    return continues
                        ? note(.mistake, .overfoldToPassiveAggression, "Overfold vs \(vt.name) aggression",
                               "\(name(aggr)) bet \(pctText). Inverse question: if they had a bluff here, would they bet this big? \(vt == .fish ? "Fish" : "This player") under-bluff, so this sizing is value. Fold \(handText).")
                        : note(.good, .overfoldToPassiveAggression, "Good overfold", "Big bet from a player who under-bluffs. Folding \(handText) prints long-term.")
                }
                if vt == .fish && ratio < 0.45 && tier >= .medium && decision == .fold {
                    return note(.inaccuracy, .sizingTells, "Small bet = medium hand",
                                "A fish's small bet (\(pctText)) is usually a medium hand or a draw. \(handText) is ahead often enough to call. Raise your strong hands.")
                }
            case .whale:
                if heroBetThisStreet && (tier <= .good || onePair) && !goodDraw {
                    return continues
                        ? note(.inaccuracy, .fireWithFire, "Whale raise after your bet = value",
                               "Even whales under-bluff when you take aggressive action. Their raise of your bet is mostly value. Overfold \(handText).")
                        : note(.good, .fireWithFire, "Good fold", "Respecting the whale's raise of your bet is correct. Fire-with-fire is value.")
                }
                if tier >= .medium && tier <= .good && !heroBetThisStreet {
                    return continues
                        ? note(.good, .giveWhalesRope, "Good bluff-catch", "Whales barrel air when you give them rope. \(handText) is a great bluff catcher.")
                        : note(.inaccuracy, .giveWhalesRope, "Don't fold to the whale here",
                               "You checked, and the whale bet. That's exactly when they bluff. \(handText) beats plenty of their range, so call down.")
                }
            case .reg:
                if bigPot && tier <= .good && continues && !goodDraw {
                    return note(.inaccuracy, .regsBigPots, "Regs are honest in big pots",
                                "The pot is \(pot / bb)bb. Regs bluff small and medium pots but go straightforward when the money gets deep. \(handText) is a fold.")
                }
            }
            return nil
        }

        // ---- Checked to hero / hero first to act ----
        let types = opps.compactMap { profiles[$0.seat]?.type }
        let hu = opps.count == 1
        let vt = hu ? types.first : nil
        let stationsIn = types.contains { $0 == .fish || $0 == .whale }
        let isPFR = state.preflopRaiser == hero.seat
        let ip = state.isInPosition(hero.seat)
        let texture = BoardTexture(state.board)
        let villainChecked = !streetActs.filter { $0.seat != hero.seat && $0.type == .check }.isEmpty

        if case .raise(let to) = decision {
            let frac = Double(to - legal.committed) / Double(max(1, pot))
            let pctText = "\(Int(frac * 100))% pot"
            let bluff = tier <= .weak && draw == .none

            if state.street == .flop && isPFR && hu && ip {
                if texture.isAceHigh && !texture.isMonotone {
                    if frac > 0.3 && frac < 1.2 {
                        return note(.inaccuracy, .aceHighOverbetOrCheck, "A-high flop: overbet or check",
                                    "On \(texture.cards.map(\.pretty).joined()) the framework is to overbet 1.5–2x with AQ+ and selected bluffs, and check everything else. \(handText) at \(pctText) is the in-between size that only gets called by better.")
                    }
                    if frac >= 1.2 && tier >= .strong {
                        return note(.good, .aceHighOverbetOrCheck, "Great overbet", "Thick value on an A-high board. Fish have lots of Ax and pay off big.")
                    }
                } else if frac > 0.8 && !(stationsIn && tier >= .strong) && !texture.isMonotone {
                    return note(.inaccuracy, .rangeBetHalfPot, "Use the ½-pot range bet",
                                "Non-A-high flop, heads-up, in position: about ½ pot with your whole range does the work. Big sizes fold out the weak hands you want to keep in.")
                }
            }
            if bluff, let v = vt, v == .fish || v == .whale {
                if state.street == .flop && isPFR && frac <= 0.6 { return nil }
                if frac > 0.5 {
                    return note(.mistake, .noBigBluffsVsStations, "Don't big-bluff a station",
                                "\(handText) at \(pctText) into a \(v.name.lowercased()). They don't fold pairs. If you bluff a fish at all, use small sizes to fold out their total air.")
                }
                if state.street == .river {
                    return note(.inaccuracy, .giveUpVsStations, "Give up vs the station", "River bluffs into stations rarely get through. Take the free showdown or just give up.")
                }
            }
            if bluff, let v = vt, v == .tryingRec || v == .nit || (v == .reg && bigPot) {
                if frac >= 0.66 { return note(.good, .bluffRecsBig, "Good big bluff", "\(v.name)s fold too much to big bets. This size makes them fold.") }
                if state.street != .flop {
                    return note(.inaccuracy, .bluffRecsBig, "Bluff bigger", "\(v.name)s make big folds but call small bets. Use 66–100%+ when you bluff them.")
                }
            }
            if tier >= .good && stationsIn && frac < 0.5 && !(state.street == .flop && isPFR && hu && ip && !(vt == .fish && tier >= .strong)) {
                return note(.inaccuracy, .valueBetStations, "Size up your value",
                            "\(handText) vs a station: bet 75–100%+ pot. They call anyway, so put the money in for them.")
            }
            if tier >= .strong && tier < .monster && vt == .tryingRec && state.street == .river && frac > 0.85 {
                return note(.inaccuracy, .sizeDownRiverVsRecs, "Size down vs the trying rec",
                            "Trying recs fold big river bets without a strong hand. A 50–66% bet with \(handText) gets called by their worse one-pair hands.")
            }
            if tier >= .strong && stationsIn && frac >= 0.7 {
                return note(.good, .valueBetStations, "Strong value bet", "Big value into a station. This is where your winrate comes from.")
            }
            return nil
        }

        if decision == .check {
            if state.street == .river && tier >= .strong && hu && ip, let v = vt, v == .fish || v == .whale {
                return note(.mistake, .valueBetStations, "Missed value!", "\(handText) on the river vs a \(v.name.lowercased()) who checked: bet big. They call with worse constantly.")
            }
            if state.street == .river && (tier == .medium || tier == .good) && hu && ip && villainChecked, vt == .fish {
                return note(.inaccuracy, .thinValueVsFish, "Thin value bet", "Fish call with worse pairs and ace-high. Bet \(handText) small to medium (~40–60%).")
            }
            if state.street == .flop && isPFR && hu && ip && !texture.isAceHigh && !heroChecked && vt != .whale {
                return note(.okay, .rangeBetHalfPot, "Consider the ½-pot range bet",
                            "Heads-up in position on a non-A-high flop, the default is a ½-pot bet with your whole range. It funnels weak ranges into the turn, where your barrels print.")
            }
            if state.street == .river && tier >= .strong && hu && !ip, vt == .whale {
                return note(.good, .giveWhalesRope, "Giving rope", "Checking strong hands to a whale invites a bluff you can snap off. Nice.")
            }
        }
        return nil
    }
}
