import Foundation
import Testing
@testable import PokerCore

@Suite struct SimGraderTests {
    /// 3-handed, checked to the river, then the button bets into the hero.
    func riverSpot(heroHole: String, board: String) -> HandState {
        var rng = SplitMix64(seed: 7)
        var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "Hero", 200), (1, "Bea", 200), (2, "Cal", 200)],
                          buttonSeat: 2, straddle: false, rng: &rng,
                          presetHoles: [0: Card.parse(heroHole)], presetBoard: Card.parse(board))
        h.apply(.call); h.apply(.call); h.apply(.check)
        for _ in 0..<2 { h.apply(.check); h.apply(.check); h.apply(.check) }
        h.apply(.check); h.apply(.check); h.apply(.raise(to: 6))
        return h
    }

    func lenses(_ t: PlayerType) -> [SimGrader.Lens] {
        let mix: [Int: [(profile: Profile, weight: Double)]] = [1: [(Profile.base(t), 1)], 2: [(Profile.base(t), 1)]]
        return [("Default", mix), ("Your read", mix), ("Real types", mix)]
    }

    @Test func foldingTheNutsIsAMistake() throws {
        let h = riverSpot(heroHole: "JhTh", board: "AhKhQh2c3d")
        #expect(h.currentSeat == 0)
        let start = Date()
        let e = try #require(SimGrader.evaluate(state: h, heroSeat: 0, chosen: .fold, lenses: lenses(.fish), seed: 1))
        print("sim took \(Date().timeIntervalSince(start))s", e.options, e.read.evs)
        #expect(e.options[e.chosen] == "Fold")
        #expect(e.read.best != e.chosen)
        #expect(e.grade() == .mistake)
    }

    @Test func callingWithTheNutsIsBest() throws {
        let h = riverSpot(heroHole: "JhTh", board: "AhKhQh2c3d")
        let e = try #require(SimGrader.evaluate(state: h, heroSeat: 0, chosen: .raise(to: 18), lenses: lenses(.fish), seed: 2))
        #expect(e.read.evs[e.chosen] > e.read.evs[0])
        #expect(e.grade() != .mistake)
    }

    @Test func preflopDecisionRuns() throws {
        var session = TableSession(preset: .typical, seed: 3)
        session.tableTurnover = false
        var h = session.startHand()
        var steps = 0
        while !h.isComplete, h.currentSeat != 0, steps < 50, let d = session.botDecision(h) { h.apply(d); steps += 1 }
        guard h.currentSeat == 0 else { return }
        var mix: [Int: [(profile: Profile, weight: Double)]] = [:]
        for o in h.opponents(of: 0) { mix[o.seat] = TypeEstimate.population.map { (Profile.base($0.key), $0.value) } }
        let start = Date()
        let e = try #require(SimGrader.evaluate(state: h, heroSeat: 0, chosen: .fold, lenses: [("D", mix), ("R", mix), ("T", mix)], seed: 4))
        print("preflop sim took \(Date().timeIntervalSince(start))s", e.options, e.read.evs)
        #expect(e.options.count >= 2)
    }
}
