import Foundation
import PokerCore

/// One training rep: a multiple-choice question on a fresh, randomly generated spot.
struct Rep: Identifiable {
    enum Scene {
        case spot(SpotDrill)
        case value(ValueDrill)
        case hand(HandClass, [Card])
        case profile(BotPlayer, PlayerStats, [String])
    }

    let id = UUID()
    let scene: Scene
    let prompt: String
    let options: [String]
    let correct: Set<Int>
    let explanation: String
    let principle: Principle?
    let skill: String
    let villain: PlayerType?

    var skillTitle: String {
        if let c = DrillConcept(rawValue: skill) { return c.title }
        switch skill {
        case "value": return "Inverse question (value)"
        case "range-inout": return "Ranges: in or out"
        case "classify": return "Spot the type"
        default: return skill
        }
    }
}

struct Round: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    var reps: [Rep]
}

/// The daily workout: 3 rounds × 5 reps. Skills you miss show up more often.
@MainActor
@Observable
final class WorkoutSession {
    static let repsPerRound = 5

    private(set) var rounds: [Round] = []
    private(set) var roundIndex = 0
    private(set) var repIndex = 0
    private(set) var answers: [UUID: Int] = [:]
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var xpEarned = 0
    private(set) var finished = false
    var showingRoundSummary = false

    private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    let store: ProgressStore

    init(store: ProgressStore) {
        self.store = store
        rounds = [
            Round(title: "Preflop", subtitle: "Iso-raises, opens, limp-raises, ranges", reps: []),
            Round(title: "Reads", subtitle: "Spot the type, bluff-catching, sizing tells", reps: []),
            Round(title: "Value", subtitle: "Bet sizes, thin value, barrels, bluffs", reps: []),
        ]
        let preflop: [String] = ["isoLimpers", "vsOpen", "limpRaise", "cold4Bet", "range-inout"]
        let reads: [String] = ["classify", "riverBluffCatch", "sizingTell", "flopRaise", "classify"]
        let value: [String] = ["value", "riverValueSize", "thinValue", "turnBarrel", "riverBluff", "flopCbet"]
        for (i, pool) in [preflop, reads, value].enumerated() {
            rounds[i].reps = pick(pool, count: Self.repsPerRound).map(makeRep)
        }
    }

    var round: Round { rounds[roundIndex] }
    var rep: Rep { round.reps[repIndex] }
    var picked: Int? { answers[rep.id] }
    var totalReps: Int { rounds.reduce(0) { $0 + $1.reps.count } }
    var answeredCount: Int { answers.count }
    var correctCount: Int { rounds.flatMap(\.reps).filter { r in answers[r.id].map { r.correct.contains($0) } ?? false }.count }
    var multiplier: Int { min(3, 1 + combo / 3) }

    func roundScore(_ r: Round) -> Int { r.reps.filter { rep in answers[rep.id].map { rep.correct.contains($0) } ?? false }.count }

    /// Weighted pick: skills with lower recent accuracy are more likely.
    private func pick(_ pool: [String], count: Int) -> [String] {
        var out: [String] = []
        let weights = pool.map { 1.6 - (store.skillRate($0) ?? 0.6) }
        while out.count < count {
            let total = weights.reduce(0, +)
            var x = Double.random(in: 0..<total, using: &rng)
            for (i, w) in weights.enumerated() {
                if x < w { out.append(pool[i]); break }
                x -= w
            }
        }
        return out
    }

    private func makeRep(_ skill: String) -> Rep {
        if skill == "value" {
            let d = SizingLab.valueDrill(rng: &rng)
            let q = d.questions[1]
            return Rep(scene: .value(d), prompt: "\(d.villainName) has \(d.villainHolding.short) (\(d.villainExample.map(\.pretty).joined())). Bet the max they'll call:",
                       options: q.options, correct: q.correct, explanation: d.questions[0].explanation + " " + q.explanation,
                       principle: .inverseQuestion, skill: skill, villain: d.villainType)
        }
        if skill == "range-inout" {
            let pct = [10, 15, 20, 25, 30].randomElement(using: &rng)!
            let near = HandClass.all.filter { abs(RangeModel.standard.percentile(of: $0) - Double(pct) / 100) < 0.06 }
            let h = near.randomElement(using: &rng) ?? HandClass("A9o")!
            let p = RangeModel.standard.percentile(of: h)
            let isIn = p <= Double(pct) / 100
            return Rep(scene: .hand(h, DrillFactory.cards(for: h, rng: &rng)), prompt: "Is \(h) in the top \(pct)% of hands?",
                       options: ["In", "Out"], correct: [isIn ? 0 : 1],
                       explanation: "\(h) sits at the top \(String(format: "%.1f", p * 100))%, so it's \(isIn ? "in" : "out") at \(pct)%.",
                       principle: nil, skill: skill, villain: nil)
        }
        if skill == "classify" { return classifyRep() }
        let concept = DrillConcept(rawValue: skill) ?? .riverBluffCatch
        let d = DrillFactory.make(concept: concept, rng: &rng)
        return Rep(scene: .spot(d), prompt: d.prompt, options: d.options, correct: d.correct, explanation: d.explanation,
                   principle: d.principle, skill: skill, villain: d.villainType)
    }

    /// Simulate a real table for ~80 hands, then show one player's stats and tells: who are they?
    private func classifyRep() -> Rep {
        var session = TableSession(preset: .random, includeHero: false, seed: rng.next())
        for _ in 0..<Int.random(in: 70...120, using: &rng) { session.simulateHand() }
        let candidates = session.bots.filter { session.tracker.stats(for: $0.id).hands >= 40 }
        let bot = (candidates.isEmpty ? session.bots : candidates).randomElement(using: &rng)!
        let stats = session.tracker.stats(for: bot.id)
        let ev = session.tracker.evidence(for: bot.id).suffix(4).map(\.text)
        let types = PlayerType.allCases
        let t = bot.type
        let why = "\(t.name)s run VPIP \(Int(t.vpipBand.lowerBound * 100))–\(Int(t.vpipBand.upperBound * 100))% / PFR \(Int(t.pfrBand.lowerBound * 100))–\(Int(t.pfrBand.upperBound * 100))%. \(t.oneLiner)"
            + (bot.profile.quirks.isEmpty ? "" : " This one: " + bot.profile.quirks.prefix(2).joined(separator: "; ") + ".")
        return Rep(scene: .profile(bot, stats, ev), prompt: "After \(stats.hands) hands, what is \(bot.name)?",
                   options: types.map(\.name), correct: [types.firstIndex(of: t)!], explanation: why,
                   principle: nil, skill: "classify", villain: nil)
    }

    func answer(_ i: Int) {
        guard answers[rep.id] == nil else { return }
        answers[rep.id] = i
        let ok = rep.correct.contains(i)
        combo = ok ? combo + 1 : 0
        bestCombo = max(bestCombo, combo)
        let xp = ok ? 10 * multiplier : 2
        xpEarned += xp
        store.rep(rep.skill, correct: ok, xp: xp)
        if let c = DrillConcept(rawValue: rep.skill), let t = rep.villain {
            store.progress.drillByConcept[c.rawValue, default: Tally()].add(ok)
            store.progress.drillByType[t.rawValue, default: Tally()].add(ok)
        }
        store.save()
    }

    func next() {
        if repIndex + 1 < round.reps.count {
            repIndex += 1
        } else if !showingRoundSummary {
            showingRoundSummary = true
        } else if roundIndex + 1 < rounds.count {
            showingRoundSummary = false
            roundIndex += 1
            repIndex = 0
        } else {
            showingRoundSummary = false
            finished = true
            xpEarned += 50
            store.completeWorkout(bestCombo: bestCombo)
        }
    }
}
