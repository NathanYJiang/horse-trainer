import Foundation

/// End-of-session feedback built from your stats and the coach's grades, benchmarked against a winning live 1/2 profile.
public struct SessionFeedback: Sendable {
    public enum Level: Sendable { case good, watch, leak }

    public struct Finding: Sendable, Identifiable {
        public let id = UUID()
        public let level: Level
        public let title: String
        public let detail: String
        /// Drill concept that targets this finding, if any.
        public let drill: DrillConcept?
    }

    public struct Benchmark: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let value: Double?
        public let target: ClosedRange<Double>
        public let display: String

        public var status: Level {
            guard let v = value else { return .watch }
            if target.contains(v) { return .good }
            let width = target.upperBound - target.lowerBound
            return (v < target.lowerBound - width * 0.5 || v > target.upperBound + width * 0.5) ? .leak : .watch
        }
    }

    public let headline: String
    public let benchmarks: [Benchmark]
    public let findings: [Finding]
    public let leaksByPrinciple: [(principle: String, mistakes: Int, inaccuracies: Int)]

    static func pct(_ a: Int, _ b: Int) -> Double? { b < 8 ? nil : Double(a) / Double(b) * 100 }

    public static func make(stats s: SessionStats, hero h: PlayerStats, notes: [CoachNote], bigBlind: Int) -> SessionFeedback {
        let bb100 = s.hands > 0 ? Double(s.net) / Double(bigBlind) / Double(s.hands) * 100 : 0
        let af: Double? = h.postflopCalls + h.postflopAggressive < 8 ? nil : Double(h.postflopAggressive) / Double(max(1, h.postflopCalls))
        let benchmarks = [
            Benchmark(name: "VPIP", value: pct(h.vpip, h.hands), target: 18...27, display: h.vpipText + "%"),
            Benchmark(name: "PFR", value: pct(h.pfr, h.hands), target: 14...22, display: h.pfrText + "%"),
            Benchmark(name: "Limp", value: pct(h.limps, h.hands), target: 0...3, display: h.limpText + "%"),
            Benchmark(name: "3-bet", value: pct(h.threeBets, h.threeBetOpp), target: 4...10, display: h.threeBetText + "%"),
            Benchmark(name: "C-bet", value: pct(h.cbets, h.cbetOpp), target: 50...75, display: h.cbetText + "%"),
            Benchmark(name: "AF", value: af, target: 2...4.5, display: h.afText),
            Benchmark(name: "WTSD", value: pct(h.wtsd, h.sawFlop), target: 24...34, display: h.wtsdText + "%"),
        ]

        var f: [Finding] = []
        func bench(_ n: String) -> Benchmark { benchmarks.first { $0.name == n }! }
        if let v = bench("VPIP").value, v > 30 {
            f.append(Finding(level: .leak, title: "Playing too many hands", detail: "VPIP \(Int(v))%. Winning live 1/2 players are around 18–27%. Fold the offsuit trash and weak aces up front.", drill: .vsOpen))
        } else if let v = bench("VPIP").value, v < 15 {
            f.append(Finding(level: .watch, title: "Very tight", detail: "VPIP \(Int(v))%. You're giving up profitable spots, especially isolating fish limps in position.", drill: .isoLimpers))
        }
        if let v = bench("VPIP").value, let p = bench("PFR").value, v - p > 9 {
            f.append(Finding(level: .leak, title: "Too passive preflop", detail: "VPIP \(Int(v))% vs PFR \(Int(p))%. You're calling and limping instead of raising. Raise or fold first in, and iso-raise limpers.", drill: .isoLimpers))
        }
        if let l = bench("Limp").value, l > 4 {
            f.append(Finding(level: .leak, title: "Open-limping", detail: "You limped \(Int(l))% of hands. Raise to $10–15 or fold.", drill: .isoLimpers))
        }
        if let w = bench("WTSD").value, w > 38 {
            f.append(Finding(level: .leak, title: "Calling down too much", detail: "WTSD \(Int(w))%. Live pools under-bluff, so overfold to big bets from fish, trying recs and nits.", drill: .riverBluffCatch))
        }
        if let a = af, a < 1.5 {
            f.append(Finding(level: .watch, title: "Passive postflop", detail: String(format: "AF %.1f. Bet your value. Stations pay big bets, and checking lets them see free cards.", a), drill: .riverValueSize))
        }

        var byPrinciple: [String: (Int, Int)] = [:]
        var drillFor: [String: DrillConcept] = [:]
        for n in notes where n.grade == .mistake || n.grade == .inaccuracy {
            let k = n.principle?.title ?? n.headline
            let cur = byPrinciple[k] ?? (0, 0)
            byPrinciple[k] = n.grade == .mistake ? (cur.0 + 1, cur.1) : (cur.0, cur.1 + 1)
            if let p = n.principle, let d = drill(for: p) { drillFor[k] = d }
        }
        let leaks = byPrinciple.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 * 2 + $0.2 > $1.1 * 2 + $1.2 }
        for l in leaks.prefix(3) {
            f.append(Finding(level: l.1 > 0 ? .leak : .watch, title: l.0,
                             detail: "Flagged \(l.1 + l.2)× this session (\(l.1) mistake\(l.1 == 1 ? "" : "s"), \(l.2) inaccurac\(l.2 == 1 ? "y" : "ies")).",
                             drill: drillFor[l.0]))
        }
        let goods = notes.filter { $0.grade == .good }
        if let top = Dictionary(grouping: goods, by: { $0.principle?.title ?? $0.headline }).max(by: { $0.value.count < $1.value.count }), top.value.count >= 2 {
            f.append(Finding(level: .good, title: "Strength: \(top.key)", detail: "You got this right \(top.value.count)× this session.", drill: nil))
        }
        if f.isEmpty {
            f.append(Finding(level: .good, title: "Clean session", detail: "No major leaks flagged. Play more hands for a better read on your stats.", drill: nil))
        }

        let graded = notes.filter { $0.grade != .okay }.count
        let goodRate = graded == 0 ? 0 : Double(goods.count) / Double(graded)
        let headline: String
        if s.hands < 20 {
            headline = "Short session: \(s.hands) hands. The stats are still noisy."
        } else if bb100 >= 0 && goodRate >= 0.6 {
            headline = String(format: "Won %.1f bb/100 and played well. That's the goal.", bb100)
        } else if bb100 >= 0 {
            headline = String(format: "Won %.1f bb/100, but the coach flagged leaks. Some of the result was luck.", bb100)
        } else if goodRate >= 0.6 {
            headline = String(format: "Lost %.1f bb/100, but your decisions were mostly good. That's variance.", -bb100)
        } else {
            headline = String(format: "Lost %.1f bb/100. Fix the leaks below first.", -bb100)
        }
        return SessionFeedback(headline: headline, benchmarks: benchmarks, findings: f, leaksByPrinciple: leaks.map { ($0.0, $0.1, $0.2) })
    }

    public static func drill(for p: Principle) -> DrillConcept? {
        switch p {
        case .overfoldToPassiveAggression, .sizingTells, .donkLeadIsValue: .riverBluffCatch
        case .giveWhalesRope: .riverBluffCatch
        case .fireWithFire: .flopRaise
        case .valueBetStations, .sizeDownRiverVsRecs: .riverValueSize
        case .noBigBluffsVsStations, .giveUpVsStations, .bluffRecsBig: .riverBluff
        case .barrelVsFolders: .turnBarrel
        case .rangeBetHalfPot, .aceHighOverbetOrCheck: .flopCbet
        case .isolateFishLimps, .respectLimpTraps, .dontOpenLimp, .liveOpenSizing: .isoLimpers
        case .limpRaiseIsNuts: .limpRaise
        case .cold4BetIsAces: .cold4Bet
        case .respectNitRanges, .threeBetWhalesWide: .vsOpen
        case .thinValueVsFish: .thinValue
        case .regsBigPots: .riverBluffCatch
        case .inverseQuestion, .handVsRange: nil
        }
    }
}
