import Foundation

/// One way of seeing the opponents while grading a decision.
public struct SimLens: Sendable, Codable, Equatable {
    public let name: String
    /// Simulated EV of each option in dollars (only differences matter).
    public let evs: [Double]
    /// Standard error of each option's EV difference vs the hero's choice.
    public let se: [Double]
    public var best: Int { evs.indices.max { evs[$0] < evs[$1] } ?? 0 }
}

/// A hero decision graded by simulation: every reasonable option, played out hundreds of times against the opponents'
/// likely hands (inferred from how they've played this hand) and their likely types.
public struct SimEval: Sendable, Codable, Identifiable, Equatable {
    public var id: String { "\(handNumber)-\(actionIndex)" }
    public let handNumber: Int
    public let actionIndex: Int
    public let street: Street
    public let pot: Int
    public let options: [String]
    public let chosen: Int
    /// Default (no read: a random 1/2 player), Your read (what you could know), Real types.
    public let lenses: [SimLens]
    /// Paired SEs within one lens: real types (truth best − read best), and your read (read best − no-read best).
    public var readGapSE = 0.0
    public var exploitGapSE = 0.0

    public var baseline: SimLens { lenses[0] }
    public var read: SimLens { lenses[1] }
    public var truth: SimLens { lenses[2] }
    public var heroAction: String { options[chosen] }

    /// Dollars given up vs the best option, if the gap is bigger than the noise and big enough to matter.
    public func loss(_ lens: SimLens, bigBlind: Int = 2) -> Double {
        let b = lens.best
        guard b != chosen else { return 0 }
        let gap = lens.evs[b] - lens.evs[chosen]
        let noise = 2 * lens.se[b]
        return gap > noise && gap >= max(Double(bigBlind), 0.03 * Double(pot)) ? gap : 0
    }

    public func grade(bigBlind: Int = 2) -> Grade {
        let l = loss(read, bigBlind: bigBlind)
        if l == 0 { return read.best == chosen ? .good : .okay }
        return l < max(4 * Double(bigBlind), 0.12 * Double(pot)) ? .inaccuracy : .mistake
    }

    /// What perfect reads would have been worth here: the real-types EV of the real best option over the option your read liked best.
    public func readCost(bigBlind: Int = 2) -> Double {
        let r = read.best, t = truth.best
        guard r != t else { return 0 }
        let gap = truth.evs[t] - truth.evs[r]
        return gap > 2 * readGapSE && gap >= max(Double(bigBlind), 0.03 * Double(pot)) ? gap : 0
    }

    /// Exploit vs default: the best play changes once you account for who you're up against.
    public var exploitDiffers: Bool {
        baseline.best != read.best && read.evs[read.best] - read.evs[baseline.best] > 2 * exploitGapSE
    }
}

public enum SimGrader {
    /// For each opponent still in the hand, a mix of profiles that could describe them (weights sum to 1).
    public typealias Lens = (name: String, villains: [Int: [(profile: Profile, weight: Double)]])

    static let combosPerVillain = 120
    static let likelihoodSamples = 3

    /// Grades `chosen` at `state` (the hero to act). The hero plays later streets like a solid reg.
    public static func evaluate(state: HandState, heroSeat: Int, chosen: Decision, lenses: [Lens],
                                rollouts: Int = 140, seed: UInt64) -> SimEval? {
        guard lenses.count == 3, state.currentSeat == heroSeat, let legal = state.legalActions(),
              let hero = state.player(seat: heroSeat) else { return nil }
        var rng = SplitMix64(seed: seed)
        let cands = candidates(state: state, legal: legal, chosen: normalize(chosen, legal))
        let history = state.actions.filter(\.type.isVoluntary)
        let villains = state.opponents(of: heroSeat).map(\.seat)
        let known = Set(hero.hole + state.board)
        let deck = Card.all.filter { !known.contains($0) }
        let seats = state.players.map { (seat: $0.seat, name: $0.name, stack: $0.startingStack) }

        func replay(holes: [Int: [Card]], board: [Card], rng: inout SplitMix64, until stop: (HandState, PlayerAction) -> Bool = { _, _ in false }) -> HandState? {
            var h = HandState(config: state.config, handNumber: state.handNumber, seats: seats, buttonSeat: state.buttonSeat,
                              straddle: state.straddleSeat != nil, rng: &rng, presetHoles: holes, presetBoard: board)
            for a in history {
                if stop(h, a) { return h }
                guard h.currentSeat == a.seat else { return nil }
                h.apply(decision(for: a))
            }
            return h
        }

        // 1. Each villain's likely hands under each profile: P(their actions this hand | hand, profile).
        var weighted: [Int: (profiles: [Profile], combos: [[Card]], like: [[Double]])] = [:]
        for v in villains {
            let profiles = uniqueProfiles(lenses.compactMap { $0.villains[v] }.flatMap { $0 }.map(\.profile))
            let combos = sampleCombos(from: deck, count: combosPerVillain, rng: &rng)
            let acts = history.filter { $0.seat == v }
            var like = Array(repeating: Array(repeating: 1.0, count: combos.count), count: profiles.count)
            if !acts.isEmpty {
                for (ci, c) in combos.enumerated() {
                    var drng = SplitMix64(seed: seed &+ UInt64(ci))
                    _ = replay(holes: [heroSeat: hero.hole, v: c], board: state.board, rng: &drng) { h, a in
                        guard a.seat == v else { return false }
                        for (pi, p) in profiles.enumerated() {
                            var hits = 0.0
                            for _ in 0..<likelihoodSamples {
                                hits += match(BotBrain.decide(state: h, seat: v, profile: p, rng: &rng), a, in: h)
                            }
                            like[pi][ci] *= (hits + 0.05) / (Double(likelihoodSamples) + 0.1)
                        }
                        return false
                    }
                }
            }
            weighted[v] = (profiles, combos, like)
        }

        // 2. Per lens, a joint (profile, hand) distribution for each villain; play every option out with common random numbers.
        var out: [SimLens] = []
        var lensSamples: [[[Double]]] = []
        for lens in lenses {
            var dist: [Int: [(profile: Profile, combo: [Card], cum: Double)]] = [:]
            for v in villains {
                var entries: [(Profile, [Card], Double)] = []
                var total = 0.0
                guard let wv = weighted[v] else { continue }
                for (p, pw) in lens.villains[v] ?? [] {
                    guard let pi = wv.profiles.firstIndex(of: p) else { continue }
                    for (ci, c) in wv.combos.enumerated() where wv.like[pi][ci] > 0 {
                        total += pw * wv.like[pi][ci]
                        entries.append((p, c, total))
                    }
                }
                dist[v] = total > 0 ? entries.map { ($0.0, $0.1, $0.2 / total) } : []
            }
            var samples = Array(repeating: [Double](), count: cands.count)
            for r in 0..<rollouts {
                var srng = SplitMix64(seed: seed &+ UInt64(r) &* 0x9E37_79B9_7F4A_7C15)
                var holes: [Int: [Card]] = [heroSeat: hero.hole]
                var profiles: [Int: Profile] = [:]
                var used = known
                var ok = true
                for v in villains {
                    guard let d = dist[v], !d.isEmpty else { ok = false; break }
                    var picked = false
                    for _ in 0..<25 {
                        let x = Double.random(in: 0..<1, using: &srng)
                        let e = d[d.firstIndex { $0.cum >= x } ?? d.count - 1]
                        if !used.contains(e.combo[0]) && !used.contains(e.combo[1]) {
                            holes[v] = e.combo
                            profiles[v] = e.profile
                            used.formUnion(e.combo)
                            picked = true
                            break
                        }
                    }
                    if !picked { ok = false; break }
                }
                guard ok else { continue }
                let runout = Array(deck.filter { !used.contains($0) }.shuffled(using: &srng).prefix(5 - state.board.count))
                for (i, c) in cands.enumerated() {
                    var prng = srng
                    guard var h = replay(holes: holes, board: state.board + runout, rng: &prng), h.currentSeat == heroSeat else { continue }
                    h.apply(c.decision)
                    var steps = 0
                    while !h.isComplete, let s = h.currentSeat, steps < 200 {
                        steps += 1
                        let p = s == heroSeat ? Profile.base(.reg) : (profiles[s] ?? Profile.base(.fish))
                        h.apply(BotBrain.decide(state: h, seat: s, profile: p, rng: &prng))
                    }
                    samples[i].append(Double(h.result?.net[heroSeat] ?? 0))
                }
            }
            let n = samples.map(\.count).min() ?? 0
            guard n > 10 else { return nil }
            let evs = samples.map { $0.prefix(n).reduce(0, +) / Double(n) }
            let base = samples[cands.firstIndex { $0.isChosen } ?? 0]
            out.append(SimLens(name: lens.name, evs: evs, se: samples.map { pairedSE($0, base, n) }))
            lensSamples.append(samples.map { Array($0.prefix(n)) })
        }
        var e = SimEval(handNumber: state.handNumber, actionIndex: state.actions.count, street: state.street, pot: state.pot,
                        options: cands.map(\.label), chosen: cands.firstIndex { $0.isChosen } ?? 0, lenses: out)
        let t = lensSamples[2], r = lensSamples[1]
        e.readGapSE = pairedSE(t[e.truth.best], t[e.read.best], min(t[e.truth.best].count, t[e.read.best].count))
        e.exploitGapSE = pairedSE(r[e.read.best], r[e.baseline.best], min(r[e.read.best].count, r[e.baseline.best].count))
        return e
    }

    /// Standard error of the mean of (a − b) over paired rollouts.
    static func pairedSE(_ a: [Double], _ b: [Double], _ n: Int) -> Double {
        guard n > 1 else { return 0 }
        let diffs = (0..<n).map { a[$0] - b[$0] }
        let m = diffs.reduce(0, +) / Double(n)
        let v = diffs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n - 1)
        return (v / Double(n)).squareRoot()
    }

    // MARK: - Options

    struct Candidate {
        let label: String
        let decision: Decision
        var isChosen = false
    }

    /// The same coercion `HandState.apply` does, so the chosen option lines up with what actually happened.
    static func normalize(_ d: Decision, _ legal: LegalActions) -> Decision {
        switch d {
        case .check: return legal.canCheck ? .check : .fold
        case .call: return legal.toCall == 0 ? .check : .call
        case .fold: return legal.canCheck ? .check : .fold
        case .raise(let to):
            guard legal.canRaise else { return legal.toCall == 0 ? .check : .call }
            return .raise(to: min(legal.maxRaiseTo, max(legal.minRaiseTo, to)))
        }
    }

    static func candidates(state: HandState, legal: LegalActions, chosen: Decision) -> [Candidate] {
        var list: [Decision] = legal.canCheck ? [.check] : [.fold, .call]
        if legal.canRaise {
            let pot = Double(state.pot)
            var targets: [Int] = []
            if state.street == .preflop {
                let sit = PreflopSituation(state: state, seat: state.currentSeat ?? 0)
                let facing = Double(state.currentBet)
                switch sit.raises {
                case 0: targets = [(state.straddleSeat != nil ? 20 : 12) + 5 * sit.limpers.count]
                case 1:
                    let ip = [.btn, .co].contains(state.position(of: state.currentSeat ?? 0))
                    targets = [Int(facing * (ip ? 3 : 4)) + sit.callersOfLastRaise * Int(facing)]
                default: targets = [Int(facing * 2.3), legal.maxRaiseTo]
                }
            } else if legal.toCall == 0 {
                targets = [0.33, 0.66, 1.0].map { legal.committed + BotBrain.liveRound(max(Double(state.config.bigBlind), pot * $0)) }
            } else {
                targets = [Int(Double(state.currentBet) * 3)]
            }
            for t in targets {
                // Anything over ~70% of the stack is effectively a shove.
                let to = Double(t) > Double(legal.maxRaiseTo) * 0.7 ? legal.maxRaiseTo : min(legal.maxRaiseTo, max(legal.minRaiseTo, t))
                if !list.contains(.raise(to: to)) { list.append(.raise(to: to)) }
            }
        }
        var cands = list.map { Candidate(label: Coach.describe($0, legal: legal, pot: state.pot), decision: $0) }
        if let i = cands.firstIndex(where: { $0.decision == chosen }) {
            cands[i].isChosen = true
        } else if case .raise(let to) = chosen,
                  let i = cands.firstIndex(where: { if case .raise(let t) = $0.decision { return abs(t - to) <= max(2, t / 8) }; return false }) {
            cands[i] = Candidate(label: Coach.describe(chosen, legal: legal, pot: state.pot), decision: chosen, isChosen: true)
        } else {
            cands.append(Candidate(label: Coach.describe(chosen, legal: legal, pot: state.pot), decision: chosen, isChosen: true))
        }
        return cands
    }

    // MARK: - Inference helpers

    static func decision(for a: PlayerAction) -> Decision {
        switch a.type {
        case .fold: .fold
        case .check: .check
        case .call: .call
        default: .raise(to: a.toAmount)
        }
    }

    /// How well a sampled bot decision matches what the player actually did (bet sizes are a tell too).
    static func match(_ d: Decision, _ a: PlayerAction, in h: HandState) -> Double {
        guard let legal = h.legalActions() else { return 0 }
        switch (normalize(d, legal), a.type) {
        case (.fold, .fold), (.check, .check), (.call, .call): return 1
        case (.raise(let to), .bet), (.raise(let to), .raise):
            let size = max(1, a.toAmount - legal.committed)
            return Double(abs(to - a.toAmount)) <= max(Double(h.config.bigBlind) * 2, Double(size) * 0.3) ? 1 : 0.35
        default: return 0
        }
    }

    static func sampleCombos(from deck: [Card], count: Int, rng: inout SplitMix64) -> [[Card]] {
        var all: [[Card]] = []
        for i in 0..<deck.count { for j in (i + 1)..<deck.count { all.append([deck[i], deck[j]]) } }
        return Array(all.shuffled(using: &rng).prefix(count))
    }

    static func uniqueProfiles(_ ps: [Profile]) -> [Profile] {
        var out: [Profile] = []
        for p in ps where !out.contains(p) { out.append(p) }
        return out
    }
}
