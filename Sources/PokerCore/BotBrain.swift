import Foundation

/// Summary of preflop action so far, from the perspective of the player to act.
public struct PreflopSituation: Sendable {
    public let raises: Int
    public let limpers: [Int]
    public let lastRaiser: Int?
    public let lastRaiserLimpedFirst: Bool
    public let myPriorAction: ActionType?
    public let iLimped: Bool
    public let callersOfLastRaise: Int
    public let facingTo: Int

    public init(state: HandState, seat: Int) {
        let acts = state.actions(on: .preflop).filter { $0.type.isVoluntary }
        var raises = 0
        var limpers: [Int] = []
        var lastRaiser: Int?
        var callersAfterRaise = 0
        var myPrior: ActionType?
        var iLimped = false
        for a in acts {
            if a.type == .raise || a.type == .bet {
                raises += 1
                lastRaiser = a.seat
                callersAfterRaise = 0
            } else if a.type == .call {
                if raises == 0 { limpers.append(a.seat) } else { callersAfterRaise += 1 }
            }
            if a.seat == seat {
                myPrior = a.type
                if a.type == .call && raises == 0 { iLimped = true }
            }
        }
        self.raises = raises
        self.limpers = limpers
        self.lastRaiser = lastRaiser
        if let r = lastRaiser {
            lastRaiserLimpedFirst = acts.contains { $0.seat == r && $0.type == .call } && raises >= 1
                && (acts.first { $0.seat == r }?.type == .call)
        } else {
            lastRaiserLimpedFirst = false
        }
        myPriorAction = myPrior
        self.iLimped = iLimped
        callersOfLastRaise = callersAfterRaise
        facingTo = state.currentBet
    }
}

public enum BotBrain {
    static let rangeModels: [PlayerType: RangeModel] = {
        var m: [PlayerType: RangeModel] = [:]
        for t in PlayerType.allCases { m[t] = RangeModel(bonus: Profile.base(t).handBonus) }
        return m
    }()

    public static func rangeModel(for t: PlayerType) -> RangeModel { rangeModels[t]! }

    /// Rounds a bet amount the way live players do: whole dollars when small, $5 chips when larger.
    public static func liveRound(_ x: Double) -> Int {
        if x < 20 { return max(1, Int(x.rounded())) }
        if x < 100 { return Int((x / 5).rounded()) * 5 }
        return Int((x / 25).rounded()) * 25
    }

    public static func decide<R: RandomNumberGenerator>(state: HandState, seat: Int, profile: Profile, rng: inout R) -> Decision {
        guard state.legalActions() != nil, state.player(seat: seat) != nil else { return .fold }
        if state.street == .preflop {
            return preflop(state: state, seat: seat, p: profile, rng: &rng)
        }
        return postflop(state: state, seat: seat, p: profile, rng: &rng)
    }

    // MARK: - Preflop

    static func preflop<R: RandomNumberGenerator>(state: HandState, seat: Int, p: Profile, rng: inout R) -> Decision {
        let legal = state.legalActions()!
        let me = state.player(seat: seat)!
        let hc = HandClass(me.hole)
        let model = rangeModel(for: p.type)
        let pct = model.percentile(of: hc)
        let pos = state.position(of: seat)
        let sit = PreflopSituation(state: state, seat: seat)
        let bb = Double(state.config.bigBlind)
        func roll() -> Double { Double.random(in: 0..<1, using: &rng) }
        func posAdj(_ base: Double) -> Double { (base * (1 + p.positional * (pos.lateness - 0.5) * 1.2)).clamped(0.01, 1) }

        func raise(to x: Double) -> Decision {
            var to = liveRound(x)
            // If the raise commits a big chunk of the stack, just ship it.
            if Double(to) > Double(legal.maxRaiseTo) * 0.45 { to = legal.maxRaiseTo }
            return .raise(to: max(legal.minRaiseTo, min(to, legal.maxRaiseTo)))
        }

        switch sit.raises {
        case 0:
            // Recs and nits overlimp behind limpers with hands they'd open; only their best hands raise.
            let overlimps = !sit.limpers.isEmpty && (p.type == .fish || p.type == .tryingRec || p.type == .nit)
            let pfrRange = posAdj(p.pfr) * (overlimps ? 0.5 : 1)
            let vpipRange = posAdj(p.vpip)
            if pct <= pfrRange || (hc.isPremium && pct <= 0.05) {
                if hc.isBigPair && sit.limpers.isEmpty && !pos.isBlind && roll() < p.limpTrapPremiums {
                    return .call  // limp-trap
                }
                var size = Double.random(in: p.openSizeLow...p.openSizeHigh, using: &rng) * bb
                if hc.isPremium { size *= p.premiumOpenBump }
                if state.straddleSeat != nil { size *= 2 }
                let perLimper: Double = p.type == .fish ? bb : (p.type == .whale ? bb * Double.random(in: 1...5, using: &rng) : 2.5 * bb)
                size += perLimper * Double(sit.limpers.count)
                return raise(to: size)
            }
            if legal.canCheck { return .check }
            // Completing the small blind is cheap, so it's a bit wider than the normal playing range.
            if pos == .sb && pct <= vpipRange * 1.3 { return .call }
            if pct <= vpipRange {
                let limpProb = sit.limpers.isEmpty ? p.limpPreference : min(1, p.limpPreference + 0.3)
                return roll() < limpProb ? .call : .fold
            }
            // Cheap SB completes for loose players.
            if pos == .sb && p.vpip > 0.4 && roll() < 0.5 { return .call }
            return .fold

        case 1:
            let facingBB = Double(sit.facingTo) / bb
            if sit.iLimped && hc.isBigPair { return raise(to: Double(sit.facingTo) * Double.random(in: 3.2...4.2, using: &rng)) }
            let ip = pos == .btn || pos == .co
            if pct <= p.threeBet || (hc.isPremium && roll() < 0.85) {
                let mult = ip ? 3.0 : 4.0
                var to = Double(sit.facingTo) * mult + Double(sit.callersOfLastRaise * sit.facingTo)
                if p.type == .whale && roll() < 0.3 { to = Double(legal.maxRaiseTo) }
                return raise(to: to)
            }
            // Sticky players don't care about size; tight players shrink their range as the raise grows.
            let sizePenalty = pow(5.0 / max(facingBB, 5.0), 1 - p.stickiness)
            var callWidth = p.coldCall * sizePenalty * (1 + p.positional * (pos.lateness - 0.5))
            if sit.iLimped { callWidth = max(callWidth, p.vpip * (0.5 + p.stickiness * 0.5)) }
            if pos == .bb { callWidth *= 1.4 }
            if legal.callAmount <= Int(bb) * 2 { callWidth *= 1.5 }
            return pct <= callWidth ? .call : .fold

        case 2:
            let facing = Double(sit.facingTo)
            let isNitty = p.type == .nit || p.type == .tryingRec
            if hc.isBigPair || (hc.isPremium && !isNitty && roll() < 0.5) || (p.type == .whale && pct <= 0.08 && roll() < 0.3) {
                return raise(to: facing * 2.3)
            }
            let callRange = 0.035 + 0.12 * p.stickiness * (1 - p.foldTo3Bet)
            if pct <= callRange || hc.isPremium { return .call }
            if sit.myPriorAction == .raise && hc.isPair && Double(legal.callAmount) < Double(me.stack) * 0.12 { return .call }
            return .fold

        default:
            if hc.isBigPair { return raise(to: Double(legal.maxRaiseTo)) }
            let loose = p.type == .whale || p.type == .fish
            if loose && (hc.isPremium || (hc.isPair && hc.high >= 9)) { return .call }
            if p.type == .reg && hc.isPremium && roll() < 0.5 { return .call }
            return .fold
        }
    }

    // MARK: - Postflop

    static func postflop<R: RandomNumberGenerator>(state: HandState, seat: Int, p: Profile, rng: inout R) -> Decision {
        let legal = state.legalActions()!
        let me = state.player(seat: seat)!
        let read = HandRead(hole: me.hole, board: state.board)
        let opps = state.opponents(of: seat).count
        let tier = read.tier(opponents: opps)
        let draw: DrawStrength = state.street == .river ? .none : read.draw
        let pot = Double(state.pot)
        let bb = Double(state.config.bigBlind)
        let isPFR = state.preflopRaiser == seat
        let bigPot = pot >= 60 * bb
        let texture = BoardTexture(state.board)
        func roll() -> Double { Double.random(in: 0..<1, using: &rng) }

        func betTo(fraction: Double) -> Decision {
            let raw = max(bb, pot * fraction)
            var to = liveRound(raw) + legal.committed
            if Double(to) > Double(legal.maxRaiseTo) * 0.7 { to = legal.maxRaiseTo }
            return .raise(to: max(legal.minRaiseTo, min(to, legal.maxRaiseTo)))
        }

        if legal.toCall == 0 {
            // ---- First to bet on this street ----
            let checkedToMe = state.actions(on: state.street).contains { $0.type == .check }
            var pBet: Double
            var bluffing = false
            switch tier {
            case .monster: pBet = state.street == .river ? 0.92 : 1 - p.slowplay
            case .strong: pBet = 0.55 + 0.4 * p.aggression
            case .good: pBet = 0.15 + 0.6 * p.aggression + (isPFR ? 0.15 : 0)
            case .medium: pBet = p.thinValue * 0.7 + (isPFR && state.street == .flop ? p.cbet * 0.5 : 0)
            case .weak, .air:
                bluffing = true
                pBet = p.bluff * (tier == .air ? 1 : 0.5)
                if checkedToMe { pBet += p.rope * p.bluff }
                if isPFR && state.street == .flop {
                    let cb = texture.isAceHigh && !texture.isMonotone ? p.cbet * 0.35 : p.cbet * 0.8
                    pBet = max(pBet, cb)
                }
                if bigPot { pBet *= 1 - p.bigPotCaution }
                pBet /= Double(max(1, opps))
            }
            if draw != .none {
                let semi = p.aggression * (draw == .strong ? 0.75 : 0.35)
                if semi > pBet { pBet = semi; bluffing = tier <= .medium }
            }
            guard legal.canRaise, roll() < pBet.clamped(0, 0.98) else { return .check }
            return betTo(fraction: sizing(p: p, tier: tier, bluff: bluffing, draw: draw, street: state.street, isPFR: isPFR, texture: texture, bigPot: bigPot, rng: &rng))
        }

        // ---- Facing a bet ----
        // Bet size relative to the pot before the bet (what the inverse question is about).
        let ratio = Double(legal.toCall) / max(1, pot - Double(legal.toCall))
        let holding = CallModel.classify(read, street: state.street, opponents: opps)
        var maxCall = CallModel.maxCall(p.type, holding, street: state.street, bigPot: bigPot, facingRaise: state.raisesThisStreet >= 2)
        // Per-player stickiness relative to their type, plus a little noise.
        maxCall *= (p.stickiness / max(0.05, Profile.base(p.type).stickiness)).squareRoot().clamped(0.8, 1.25)
        maxCall *= Double.random(in: 0.85...1.15, using: &rng)
        maxCall *= pow(0.85, Double(max(0, opps - 1)))
        // Tiny price: almost everyone peels with something.
        if Double(legal.callAmount) < pot * 0.1 && holding != .air { maxCall = max(maxCall, ratio) }

        if legal.canRaise {
            if tier >= .strong && roll() < p.raiseValue * (tier == .monster ? 1 : 0.55) {
                return raiseTo(legal: legal, pot: pot, p: p, rng: &rng)
            }
            if draw == .strong && roll() < p.raiseDraw {
                return raiseTo(legal: legal, pot: pot, p: p, rng: &rng)
            }
            if tier == .air && p.type == .whale && roll() < p.raiseDraw * 0.12 {
                return raiseTo(legal: legal, pot: pot, p: p, rng: &rng)
            }
        }
        if ratio <= maxCall { return .call }
        if holding != .air && roll() < p.heroCall * 0.4 { return .call }
        return .fold
    }

    static func raiseTo<R: RandomNumberGenerator>(legal: LegalActions, pot: Double, p: Profile, rng: inout R) -> Decision {
        let mult: Double = p.type == .fish ? Double.random(in: 2...2.5, using: &rng) : Double.random(in: 2.6...3.4, using: &rng)
        let facing = Double(legal.committed + legal.toCall)
        var to = liveRound(facing * mult)
        if Double(to) > Double(legal.maxRaiseTo) * 0.55 { to = legal.maxRaiseTo }
        return .raise(to: max(legal.minRaiseTo, min(to, legal.maxRaiseTo)))
    }

    /// Bet size as a fraction of the pot. This is the "sizing tell" model shared with the drills.
    public static func sizing<R: RandomNumberGenerator>(p: Profile, tier: StrengthTier, bluff: Bool, draw: DrawStrength, street: Street,
                                                       isPFR: Bool, texture: BoardTexture, bigPot: Bool, rng: inout R) -> Double {
        func r(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &rng) }
        if p.type == .reg {
            if street == .flop && isPFR {
                if texture.isAceHigh && !texture.isMonotone { return tier >= .strong || bluff ? r(1.3, 1.8) : r(0.3, 0.4) }
                return r(0.4, 0.55)
            }
            if street == .turn { return r(0.6, 0.8) }
            return bigPot ? r(0.55, 0.75) : r(0.65, 1.0)
        }
        let tellful = Double.random(in: 0..<1, using: &rng) < p.sizingTell
        guard tellful else { return r(0.4, 0.85) }
        if bluff && draw == .none {
            switch p.type {
            case .fish: return r(0.25, 0.45)
            case .whale: return r(0.8, 1.5)
            default: return r(0.5, 0.7)
            }
        }
        if draw != .none && tier <= .medium { return r(0.35, 0.6) }
        switch tier {
        case .monster: return street == .river ? r(0.9, 1.6) : r(0.8, 1.2)
        case .strong: return r(0.7, 1.0)
        case .good: return r(0.5, 0.7)
        default: return r(0.25, 0.4)
        }
    }

    /// What this profile does first-in from `position` (no limpers): the raise range and the limp range.
    /// Mirrors the unopened branch of `preflop(...)` so the Range Builder shows exactly how the bots play.
    public static func unopenedRanges(profile p: Profile, position pos: Position) -> (raise: Set<HandClass>, limp: Set<HandClass>) {
        let model = rangeModel(for: p.type)
        func posAdj(_ base: Double) -> Double { (base * (1 + p.positional * (pos.lateness - 0.5) * 1.2)).clamped(0.01, 1) }
        var raise = Set<HandClass>()
        var limp = Set<HandClass>()
        for h in HandClass.all {
            let pct = model.percentile(of: h)
            if pct <= posAdj(p.pfr) || (h.isPremium && pct <= 0.05) {
                raise.insert(h)
            } else if pct <= posAdj(p.vpip) && p.limpPreference >= 0.3 {
                limp.insert(h)
            }
        }
        return (raise, limp)
    }

    /// Whether a bot posts the straddle this hand.
    public static func wantsStraddle<R: RandomNumberGenerator>(_ p: Profile, rng: inout R) -> Bool {
        Double.random(in: 0..<1, using: &rng) < p.straddleFreq
    }
}
