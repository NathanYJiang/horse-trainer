import Foundation

/// Real table situations the hero can practice on repeat at the live table.
public enum SpotKind: String, CaseIterable, Sendable, Identifiable {
    case any, isoLimpers, facingOpen, blindDefense, facing3Bet, cbet, facingCbet, barrel, facingRaise, riverValue, multiway

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .any: "Full hands"
        case .isoLimpers: "Limpers in front"
        case .facingOpen: "Facing an open"
        case .blindDefense: "Defending the blinds"
        case .facing3Bet: "Facing a 3-bet"
        case .cbet: "C-bet or check"
        case .facingCbet: "Facing a c-bet"
        case .barrel: "Facing turn/river bets"
        case .facingRaise: "Your bet got raised"
        case .riverValue: "River value bet"
        case .multiway: "Multiway pots"
        }
    }

    public var detail: String {
        switch self {
        case .any: "Every hand, folds and all, like a real session."
        case .isoLimpers: "Preflop, one or more limpers, no raise yet. Iso, overlimp or fold."
        case .facingOpen: "Preflop, someone opened in front of you."
        case .blindDefense: "You're in the small or big blind facing a single raise."
        case .facing3Bet: "You opened and got re-raised."
        case .cbet: "You raised preflop and it's checked to you on the flop."
        case .facingCbet: "The preflop raiser bets the flop into you."
        case .barrel: "Someone bets the turn or river at you."
        case .facingRaise: "You bet and got raised. The live 'it's always the nuts' spot."
        case .riverValue: "River, checked to you with a good hand. How much value?"
        case .multiway: "Three or more players see the flop and it's your decision."
        }
    }
}

public struct FoundSpot: Sendable {
    public let session: TableSession
    public let hand: HandState
    /// Seats of the players the spot is "against" (limpers, the raiser, the bettor...).
    public let villains: [Int]
    public let attempts: Int
}

public enum SpotFinder {
    /// The villain seats if the hero's current decision is this kind of spot, otherwise nil.
    public static func match(_ kind: SpotKind, state h: HandState, hero: Int) -> [Int]? {
        guard !h.isComplete, h.currentSeat == hero, let me = h.player(seat: hero), let legal = h.legalActions() else { return nil }
        let opponents = h.opponents(of: hero).map(\.seat)
        let heroActsThisStreet = h.actions(on: h.street).filter { $0.seat == hero && $0.type.isVoluntary }
        switch kind {
        case .any:
            return opponents
        case .isoLimpers, .facingOpen, .blindDefense, .facing3Bet:
            guard h.street == .preflop else { return nil }
            let sit = PreflopSituation(state: h, seat: hero)
            let pos = h.position(of: hero)
            let blind = pos == .sb || pos == .bb
            switch kind {
            case .isoLimpers:
                return sit.raises == 0 && !sit.limpers.isEmpty && sit.myPriorAction == nil && pos != .bb ? sit.limpers : nil
            case .facingOpen:
                return sit.raises == 1 && sit.myPriorAction == nil && !blind ? sit.lastRaiser.map { [$0] } : nil
            case .blindDefense:
                return sit.raises == 1 && sit.myPriorAction == nil && blind ? sit.lastRaiser.map { [$0] } : nil
            default:
                return sit.raises >= 2 && sit.myPriorAction == .raise ? sit.lastRaiser.map { [$0] } : nil
            }
        case .cbet:
            guard h.street == .flop, h.preflopRaiser == hero, legal.toCall == 0, heroActsThisStreet.isEmpty else { return nil }
            return opponents
        case .facingCbet:
            guard h.street == .flop, legal.toCall > 0, let pfr = h.preflopRaiser, pfr != hero,
                  h.lastAggressorThisStreet == pfr, heroActsThisStreet.isEmpty else { return nil }
            return [pfr]
        case .barrel:
            guard h.street == .turn || h.street == .river, legal.toCall > 0, heroActsThisStreet.isEmpty,
                  let v = h.lastAggressorThisStreet else { return nil }
            return [v]
        case .facingRaise:
            guard h.street != .preflop, legal.toCall > 0, heroActsThisStreet.contains(where: { $0.type.isAggressive }),
                  let v = h.lastAggressorThisStreet, v != hero else { return nil }
            return [v]
        case .riverValue:
            guard h.street == .river, legal.toCall == 0 else { return nil }
            let tier = HandRead(hole: me.hole, board: h.board).tier(opponents: opponents.count)
            return tier >= .good ? opponents : nil
        case .multiway:
            guard h.street != .preflop, opponents.count >= 2 else { return nil }
            return opponents
        }
    }

    /// Deals hands on a copy of `session` (the hero is played by a solid-reg autopilot until the spot comes up)
    /// and returns the first hand that reaches the spot. Hands that never get there are thrown away.
    public static func find(_ kind: SpotKind, against type: PlayerType?, from session: TableSession, maxHands: Int = 4000) -> FoundSpot? {
        var base = session
        let hero = TableSession.heroSeat
        // A calling-ish autopilot reaches "facing a bet" spots far more often; a reg reaches raiser spots.
        let autopilot = Profile.base([.facingCbet, .barrel, .multiway].contains(kind) ? .tryingRec : .reg)
        for attempt in 1...maxHands {
            var trial = base
            trial.rng = SplitMix64(seed: base.rng.next())
            trial.moveButtonRandomly()
            var h = trial.startHand()
            var steps = 0
            while !h.isComplete, let seat = h.currentSeat, steps < 400 {
                steps += 1
                if seat == hero {
                    if let v = match(kind, state: h, hero: hero),
                       type == nil || v.contains(where: { trial.bot(at: $0)?.type == type }) {
                        let villains = type == nil ? v : v.filter { trial.bot(at: $0)?.type == type }
                        return FoundSpot(session: trial, hand: h, villains: villains, attempts: attempt)
                    }
                    h.apply(BotBrain.decide(state: h, seat: hero, profile: autopilot, rng: &trial.rng))
                    if h.player(seat: hero)?.folded ?? true { break }
                } else if let d = trial.botDecision(h) {
                    h.apply(d)
                } else {
                    break
                }
            }
        }
        return nil
    }
}
