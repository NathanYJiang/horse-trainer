import Foundation

/// Simulates the bot pool and measures it against what live 1/2 actually looks like.
/// Used by the calibration tests; the targets live next to the numbers they check.
public struct PoolReport: Sendable {
    public struct TypeLine: Sendable {
        public var stats = PlayerStats()
        public var hands = 0
        public var net = 0
        public var bb100: Double { hands == 0 ? 0 : Double(net) / 2 / Double(hands) * 100 }
    }

    public var hands = 0
    public var byType: [PlayerType: TypeLine] = [:]
    public var hero = TypeLine()
    public var heroNets: [Int] = []
    public var flops = 0
    public var limpedFlops = 0
    public var playersAtFlop = 0
    public var openSizes: [Int] = []
    public var showdowns = 0
    public var rake = 0
    public var straddles = 0
    public var raisedPreflop = 0

    public var limpedFlopShare: Double { flops == 0 ? 0 : Double(limpedFlops) / Double(flops) }
    public var avgPlayersAtFlop: Double { flops == 0 ? 0 : Double(playersAtFlop) / Double(flops) }
    public var avgOpen: Double { openSizes.isEmpty ? 0 : Double(openSizes.reduce(0, +)) / Double(openSizes.count) }
    public var flopShare: Double { hands == 0 ? 0 : Double(flops) / Double(hands) }
    public var showdownShare: Double { flops == 0 ? 0 : Double(showdowns) / Double(flops) }
    public var rakePerHand: Double { hands == 0 ? 0 : Double(rake) / Double(hands) }

    /// 95% half-width of the hero's bb/100.
    public var heroInterval: Double {
        let n = Double(heroNets.count)
        guard n > 30 else { return .infinity }
        let xs = heroNets.map { Double($0) / 2 }
        let m = xs.reduce(0, +) / n
        let sd = sqrt(xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / (n - 1))
        return 1.96 * sd / sqrt(n) * 100
    }

    public var summary: String {
        var out = String(format: "POOL %d hands · flop %.0f%% · limped flops %.0f%% · players/flop %.2f · avg open $%.1f · SD/flop %.0f%% · straddled %.0f%% · rake $%.2f/hand\n",
                         hands, flopShare * 100, limpedFlopShare * 100, avgPlayersAtFlop, avgOpen, showdownShare * 100,
                         Double(straddles) / Double(max(1, hands)) * 100, rakePerHand)
        for t in PlayerType.allCases {
            guard let l = byType[t] else { continue }
            let s = l.stats
            out += "  \(t.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) VPIP \(s.vpipText) PFR \(s.pfrText) 3B \(s.threeBetText) limp \(s.limpText) cbet \(s.cbetText) F2CB \(s.foldToCbetText) AF \(s.afText) WTSD \(s.wtsdText) W$SD \(PlayerStats.pct(s.wonAtShowdown, s.wtsd)) · " + String(format: "%.1f bb/100 over %d", l.bb100, l.hands) + "\n"
        }
        if hero.hands > 0 {
            let s = hero.stats
            out += "  HERO      VPIP \(s.vpipText) PFR \(s.pfrText) AF \(s.afText) WTSD \(s.wtsdText) · " + String(format: "%.1f ± %.1f bb/100 over %d", hero.bb100, heroInterval, hero.hands) + "\n"
        }
        return out
    }
}

public enum PoolCalibration {
    /// Plays `hands` hands. If `heroProfile` is set, a bot with that profile sits in seat 0 and is reported as HERO.
    public static func run(hands n: Int, preset: TablePreset = .typical, seats: Int = 9, heroProfile: Profile? = nil, seed: UInt64 = 1) -> PoolReport {
        var session = TableSession(preset: preset, seats: seats, includeHero: heroProfile != nil, seed: seed)
        var rep = PoolReport()
        var typeOf: [UUID: PlayerType] = [:]
        for _ in 0..<n {
            for b in session.bots { typeOf[b.id] = b.type }
            var h = session.startHand()
            var guardCount = 0
            while !h.isComplete, let seat = h.currentSeat, guardCount < 500 {
                guardCount += 1
                if seat == TableSession.heroSeat, let hp = heroProfile {
                    h.apply(BotBrain.decide(state: h, seat: seat, profile: hp, rng: &session.rng))
                } else if let d = session.botDecision(h) {
                    h.apply(d)
                } else { break }
            }
            guard let r = h.result else { continue }
            rep.hands += 1
            rep.rake += r.rake
            if h.straddleSeat != nil { rep.straddles += 1 }
            let pre = h.actions(on: .preflop)
            let raises = pre.filter { $0.type == .raise }
            if !raises.isEmpty { rep.raisedPreflop += 1 }
            if h.straddleSeat == nil, let first = pre.first(where: { $0.type == .raise }),
               !pre.prefix(while: { $0.index < first.index }).contains(where: { $0.type == .call }) {
                rep.openSizes.append(first.toAmount)
            }
            if h.board.count >= 3 {
                rep.flops += 1
                let inFlop = h.players.filter { p in !h.actions.contains { $0.seat == p.seat && $0.type == .fold && $0.street == .preflop } }
                rep.playersAtFlop += inFlop.count
                if raises.isEmpty { rep.limpedFlops += 1 }
                if r.wentToShowdown { rep.showdowns += 1 }
            }
            for p in h.players {
                let net = r.net[p.seat] ?? 0
                if p.seat == TableSession.heroSeat && heroProfile != nil {
                    rep.hero.hands += 1
                    rep.hero.net += net
                    rep.heroNets.append(net)
                } else if let b = session.bot(at: p.seat) {
                    rep.byType[b.type, default: .init()].hands += 1
                    rep.byType[b.type, default: .init()].net += net
                }
            }
            session.finishHand(h)
        }
        for (id, st) in session.tracker.stats {
            if id == TableSession.heroID {
                rep.hero.stats = st
            } else if let t = typeOf[id] {
                rep.byType[t, default: .init()].stats = rep.byType[t, default: .init()].stats.adding(st)
            }
        }
        return rep
    }
}

extension PlayerStats {
    public func adding(_ o: PlayerStats) -> PlayerStats {
        var s = self
        s.hands += o.hands; s.vpip += o.vpip; s.pfr += o.pfr; s.limps += o.limps
        s.threeBetOpp += o.threeBetOpp; s.threeBets += o.threeBets; s.sawFlop += o.sawFlop
        s.cbetOpp += o.cbetOpp; s.cbets += o.cbets; s.foldToCbetOpp += o.foldToCbetOpp; s.foldToCbet += o.foldToCbet
        s.postflopAggressive += o.postflopAggressive; s.postflopCalls += o.postflopCalls
        s.wtsd += o.wtsd; s.wonAtShowdown += o.wonAtShowdown; s.straddles += o.straddles
        return s
    }
}
