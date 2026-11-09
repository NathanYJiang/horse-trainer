import Foundation
import Testing
@testable import PokerCore

/// Keeps the bot pool looking like a real live 1/2 game. Reference bands are typical live low-stakes numbers:
/// most hands see a multiway flop, lots of limping, $10-15 opens, stations that call c-bets, and win rates where
/// recs lose, nits and trying recs hover near break-even after rake, and solid regs win.
@Suite struct CalibrationTests {
    /// Full printout: `HT_CAL_HANDS=30000 swift test -c release -Xswiftc -enable-testing --filter poolReport`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HT_CAL_HANDS"] != nil))
    func poolReport() {
        let n = Int(ProcessInfo.processInfo.environment["HT_CAL_HANDS"] ?? "") ?? 20000
        for preset in [TablePreset.typical, .weekday, .juicy] {
            let r = PoolCalibration.run(hands: n, preset: preset, heroProfile: Profile.base(.reg), seed: 21)
            print("== \(preset.rawValue)\n" + r.summary)
        }
    }

    @Test func typicalTableLooksLikeLive12() {
        let r = PoolCalibration.run(hands: 6000, preset: .typical, heroProfile: Profile.base(.reg), seed: 21)
        print(r.summary)
        #expect((0.68...0.9).contains(r.flopShare))
        #expect((2.6...3.6).contains(r.avgPlayersAtFlop))
        #expect((0.18...0.45).contains(r.limpedFlopShare))
        #expect((10.0...16.0).contains(r.avgOpen))
        #expect((2.5...5.0).contains(r.rakePerHand))
        let fish = r.byType[.fish]!.stats, whale = r.byType[.whale]!.stats
        let rec = r.byType[.tryingRec]!.stats, nit = r.byType[.nit]!.stats, reg = r.byType[.reg]!.stats
        func pct(_ a: Int, _ b: Int) -> Double { Double(a) / Double(max(1, b)) }
        #expect(pct(fish.foldToCbet, fish.foldToCbetOpp) < 0.5)
        #expect(pct(whale.foldToCbet, whale.foldToCbetOpp) < 0.5)
        #expect(pct(nit.foldToCbet, nit.foldToCbetOpp) > pct(fish.foldToCbet, fish.foldToCbetOpp))
        #expect(pct(rec.foldToCbet, rec.foldToCbetOpp) > pct(reg.foldToCbet, reg.foldToCbetOpp))
        #expect(pct(fish.wtsd, fish.sawFlop) > pct(reg.wtsd, reg.sawFlop))
        // Money flows from the recs to the regs.
        #expect(r.byType[.whale]!.bb100 < 0)
        #expect(r.byType[.fish]!.bb100 < 0)
        #expect(r.byType[.reg]!.bb100 > r.byType[.fish]!.bb100)
    }
}
