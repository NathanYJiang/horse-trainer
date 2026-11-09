import Testing
@testable import PokerCore

@Suite struct EvaluatorTests {
    func v(_ s: String) -> HandValue { HandEvaluator.evaluate(Card.parse(s)) }

    @Test func categories() {
        #expect(v("AsKsQsJsTs2c3d").category == .straightFlush)
        #expect(v("AsAdAhAc2c3d4h").category == .quads)
        #expect(v("AsAdAh2c2d3d4h").category == .fullHouse)
        #expect(v("As9s7s4s2s3d4h").category == .flush)
        #expect(v("Ad2c3h4s5d9cKh").category == .straight)
        #expect(v("7d7c7h2s5dKcJh").category == .trips)
        #expect(v("7d7cKhKs5d2c3h").category == .twoPair)
        #expect(v("7d7cKh9s5d2c3h").category == .pair)
        #expect(v("Ad7cKh9s5d2c3h").category == .highCard)
    }

    @Test func ordering() {
        #expect(v("Ad2c3h4s5d") < v("2d3c4h5s6d"))  // wheel < six-high straight
        #expect(v("AsAdKcQd2h") > v("AsAdKcJd2h"))  // kicker
        #expect(v("KsKdKc2d2h") < v("AsAdAc2d2h"))
        #expect(v("AsAd2c2d3h3c9s") == v("AsAd3c3d9h2c2s"))  // best two pair + kicker
        #expect(v("2s2d2c3d3h3cAs").description.hasPrefix("Full House, Threes"))
    }

    @Test func handRead() {
        let r = HandRead(hole: Card.parse("AhKd"), board: Card.parse("Kc7s2d"))
        #expect(r.madeDescription == "Top pair, top kicker")
        #expect(r.tier() >= .strong)
        let set = HandRead(hole: Card.parse("7h7d"), board: Card.parse("Kc7s2d"))
        #expect(set.tier() == .monster)
        let fd = HandRead(hole: Card.parse("AhTh"), board: Card.parse("Kh7h2d"))
        #expect(fd.draw == .strong)
        #expect(fd.outs >= 9)
        let air = HandRead(hole: Card.parse("5c4d"), board: Card.parse("KhQh9d"))
        #expect(air.tier() == .air)
    }
}

@Suite struct EngineTests {
    @Test func blindsAndFold() {
        var rng = SplitMix64(seed: 1)
        var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "A", 100), (1, "B", 100), (2, "C", 100)],
                          buttonSeat: 0, straddle: false, rng: &rng)
        #expect(h.pot == 3)
        #expect(h.currentSeat == 0)  // button acts first 3-handed preflop
        h.apply(.fold)
        h.apply(.fold)  // SB folds
        #expect(h.isComplete)
        #expect(h.result?.net[2] == 1)
        #expect(h.players.reduce(0) { $0 + $1.stack } == 300)
    }

    @Test func straddleActionOrder() {
        var rng = SplitMix64(seed: 2)
        let seats = (0..<6).map { ($0, "P\($0)", 200) }
        var h = HandState(config: .noRake, handNumber: 1, seats: seats, buttonSeat: 0, straddle: true, rng: &rng)
        #expect(h.straddleSeat == 3)
        #expect(h.currentBet == 5)
        #expect(h.currentSeat == 4)
        #expect(h.legalActions()?.minRaiseTo == 10)
        // Everyone calls around to the straddler, who gets the option.
        for _ in 0..<5 { h.apply(.call) }
        #expect(h.currentSeat == 3)
        #expect(h.legalActions()?.canCheck == true)
        h.apply(.check)
        #expect(h.street == .flop)
    }

    @Test func sidePots() {
        var rng = SplitMix64(seed: 3)
        let holes: [Int: [Card]] = [0: Card.parse("AsAd"), 1: Card.parse("KsKd"), 2: Card.parse("QsQd")]
        var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "A", 50), (1, "B", 100), (2, "C", 200)],
                          buttonSeat: 2, straddle: false, rng: &rng, presetHoles: holes, presetBoard: Card.parse("2c7h9dJc3s"))
        // Order: SB=0, BB=1, BTN=2 acts first.
        h.apply(.raise(to: 200))
        h.apply(.call)
        h.apply(.call)
        #expect(h.isComplete)
        let r = h.result!
        #expect(r.net[0] == 100)  // wins main pot 150 - 50
        #expect(r.net[1] == 0)  // wins side pot 100 (2x50) - 100... B put in 100, gets 100
        #expect(r.net[2] == -100)  // uncalled 100 returned
        #expect(h.players.reduce(0) { $0 + $1.stack } == 350)
    }

    @Test func incompleteAllInDoesNotReopen() {
        var rng = SplitMix64(seed: 4)
        var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "A", 500), (1, "B", 500), (2, "C", 23)],
                          buttonSeat: 2, straddle: false, rng: &rng)
        // C (button) opens to 20; SB re-raise not allowed scenario: A calls, B calls.
        h.apply(.raise(to: 20))  // C
        h.apply(.call)  // A (SB)
        h.apply(.call)  // B (BB)
        #expect(h.street == .flop)
        h.apply(.raise(to: 2))  // A bets 2
        h.apply(.call)  // B calls
        h.apply(.raise(to: 3))  // C all-in for 3: increment 1 < min raise 2 → incomplete
        #expect(h.currentSeat == 0)
        #expect(h.legalActions()?.canRaise == false)
        h.apply(.call)
        h.apply(.call)
        #expect(h.street == .turn)
    }

    @Test func chipConservationRandomPlay() {
        var rng = SplitMix64(seed: 99)
        for n in 0..<3000 {
            let count = Int.random(in: 2...9, using: &rng)
            let seats = (0..<count).map { ($0, "P\($0)", Int.random(in: 1...400, using: &rng)) }
            let total = seats.reduce(0) { $0 + $1.2 }
            var h = HandState(config: .noRake, handNumber: n, seats: seats, buttonSeat: Int.random(in: 0..<count, using: &rng),
                              straddle: Bool.random(using: &rng), rng: &rng)
            var steps = 0
            while !h.isComplete {
                let legal = h.legalActions()!
                let r = Double.random(in: 0..<1, using: &rng)
                if r < 0.2 { h.apply(.fold) } else if r < 0.6 { h.apply(legal.canCheck ? .check : .call) } else if legal.canRaise {
                    h.apply(.raise(to: Int.random(in: legal.minRaiseTo...legal.maxRaiseTo, using: &rng)))
                } else { h.apply(.call) }
                steps += 1
                #expect(steps < 400)
                if steps >= 400 { break }
            }
            #expect(h.players.reduce(0) { $0 + $1.stack } == total)
            #expect(h.result!.net.values.reduce(0, +) == 0)
        }
    }

    @Test func rakeIsConservedAndCapped() {
        var rng = SplitMix64(seed: 5)
        for n in 0..<2000 {
            let count = Int.random(in: 2...9, using: &rng)
            let seats = (0..<count).map { ($0, "P\($0)", Int.random(in: 1...400, using: &rng)) }
            let total = seats.reduce(0) { $0 + $1.2 }
            var h = HandState(config: TableConfig(), handNumber: n, seats: seats, buttonSeat: 0, straddle: false, rng: &rng)
            while !h.isComplete {
                let legal = h.legalActions()!
                let r = Double.random(in: 0..<1, using: &rng)
                if r < 0.15 { h.apply(.fold) } else if r < 0.7 { h.apply(legal.canCheck ? .check : .call) } else if legal.canRaise {
                    h.apply(.raise(to: Int.random(in: legal.minRaiseTo...legal.maxRaiseTo, using: &rng)))
                } else { h.apply(.call) }
            }
            let res = h.result!
            #expect(h.players.reduce(0) { $0 + $1.stack } + res.rake == total)
            #expect(res.net.values.reduce(0, +) == -res.rake)
            #expect(res.rake <= 6)
            if h.board.count < 3 { #expect(res.rake == 0) }
            #expect(h.players.allSatisfy { $0.stack >= 0 })
        }
    }
}

@Suite struct BotTests {
    @Test func tableSimulationMatchesTypeBands() {
        var totals: [PlayerType: PlayerStats] = [:]
        for preset in TablePreset.allCases {
            var session = TableSession(preset: preset, includeHero: false, seed: 7)
            for _ in 0..<2000 {
                let hand = session.simulateHand()
                #expect(hand.players.reduce(0) { $0 + $1.stack } + hand.result!.rake == hand.players.reduce(0) { $0 + $1.startingStack })
            }
            for bot in session.bots + session.departed {
                let s = session.tracker.stats(for: bot.id)
                var t = totals[bot.type] ?? PlayerStats()
                t.hands += s.hands; t.vpip += s.vpip; t.pfr += s.pfr; t.threeBets += s.threeBets; t.threeBetOpp += s.threeBetOpp
                t.cbets += s.cbets; t.cbetOpp += s.cbetOpp; t.postflopAggressive += s.postflopAggressive; t.postflopCalls += s.postflopCalls
                t.wtsd += s.wtsd; t.sawFlop += s.sawFlop; t.limps += s.limps
                totals[bot.type] = t
            }
        }
        for t in PlayerType.allCases {
            let s = totals[t]!
            print("STAT", t, s.hands, "vpip", s.vpipText, "pfr", s.pfrText, "3b", s.threeBetText, "cbet", s.cbetText, "af", s.afText, "wtsd", s.wtsdText, "limp", s.limpText)
            #expect(t.vpipBand.contains(s.vpipValue), "\(t) VPIP \(s.vpipValue) out of band \(t.vpipBand)")
            #expect(t.pfrBand.contains(s.pfrValue), "\(t) PFR \(s.pfrValue) out of band \(t.pfrBand)")
        }
    }
}

@Suite struct ToolTests {
    @Test func equityAAvsKK() {
        let r = EquityCalculator.run(players: [.cards(Card.parse("AsAh")), .cards(Card.parse("KsKh"))], board: [], iterations: 60000)!
        #expect(abs(r.equity[0] - 0.82) < 0.02)
    }

    @Test func equityExactOnFlop() {
        let r = EquityCalculator.run(players: [.cards(Card.parse("AhKh")), .cards(Card.parse("7c7d"))], board: Card.parse("7h2h9s"))!
        #expect(r.exact)
        #expect(r.samples == 990)
        #expect(r.equity[0] > 0.2 && r.equity[0] < 0.35)
    }

    @Test func rangeParser() {
        #expect(RangeParser.parse("QQ+")?.count == 3)
        #expect(RangeParser.parse("ATs+")?.count == 4)
        #expect(RangeParser.parse("AK")?.count == 2)
        #expect(RangeParser.parse("76s-54s")?.count == 3)
        #expect(RangeParser.parse("22-55")?.count == 4)
        #expect(RangeParser.comboCount(RangeParser.parse("QQ+, AKs")!) == 22)
        #expect(RangeParser.parse("garbage") == nil)
    }

    @Test func drillsAreWellFormed() {
        var rng = SplitMix64(seed: 5)
        for c in DrillConcept.allCases {
            for t in PlayerType.allCases {
                let d = DrillFactory.make(concept: c, type: t, rng: &rng)
                #expect(!d.correct.isEmpty, "\(c) vs \(t) has no correct answer")
                #expect(d.heroCards.count == 2)
            }
        }
        for t in PlayerType.allCases {
            let inv = SizingLab.inverse(type: t, rng: &rng)
            #expect(inv.questions.allSatisfy { !$0.correct.isEmpty })
            _ = SizingLab.sizeIt(type: t, rng: &rng)
        }
    }

    @Test func coachFlagsCallingFishRaise() {
        var rng = SplitMix64(seed: 11)
        // Hero (seat 0) on button with top pair, fish (seat 1) raises hero's c-bet.
        var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "You", 300), (1, "Fishy", 300), (2, "Other", 300)],
                          buttonSeat: 0, straddle: false, rng: &rng,
                          presetHoles: [0: Card.parse("KhJd"), 1: Card.parse("7c7d"), 2: Card.parse("2c3d")], presetBoard: Card.parse("Kc7s2dTh4c"))
        h.apply(.raise(to: 12))  // hero BTN
        h.apply(.call)  // SB fish
        h.apply(.fold)  // BB
        h.apply(.check)  // fish
        h.apply(.raise(to: 13))  // hero bets
        h.apply(.raise(to: 45))  // fish raises
        var rng2 = SplitMix64(seed: 1)
        let fish = Profile.random(.fish, rng: &rng2)
        let note = Coach.grade(state: h, heroSeat: 0, decision: .call, profiles: [1: fish])
        #expect(note?.grade == .mistake)
        #expect(note?.principle == .overfoldToPassiveAggression)
    }
}

@Suite struct RangeAndValueTests {
    @Test func compactRoundTrips() {
        for pct in [0.05, 0.1, 0.15, 0.2, 0.3, 0.5] {
            let r = RangeModel.standard.top(pct)
            let text = RangeParser.compact(r)
            #expect(RangeParser.parse(text) == r, "round trip failed for \(pct): \(text)")
        }
        #expect(RangeParser.compact(RangeParser.parse("QQ+, AKs")!) == "QQ+, AKs")
    }

    @Test func rankingIsSane() {
        let order = RangeModel.standard.order
        #expect(order.count == 169)
        #expect(order.first == HandClass("AA"))
        #expect(RangeModel.standard.inTop(0.05, HandClass("AKs")!))
        #expect(!RangeModel.standard.inTop(0.2, HandClass("72o")!))
    }

    @Test func callModelOrdering() {
        // Stations call bigger than tight players with the same hand; everyone calls less with worse hands.
        for street in [Street.flop, .turn, .river] {
            #expect(CallModel.maxCall(.fish, .topPairTop, street: street) > CallModel.maxCall(.tryingRec, .topPairTop, street: street))
            #expect(CallModel.maxCall(.whale, .topPairTop, street: street) > CallModel.maxCall(.nit, .topPairTop, street: street))
            for t in PlayerType.allCases {
                #expect(CallModel.maxCall(t, .topPairTop, street: street) >= CallModel.maxCall(t, .middlePair, street: street))
            }
        }
    }

    @Test func valueDrillsWellFormed() {
        var rng = SplitMix64(seed: 21)
        for t in PlayerType.allCases {
            for _ in 0..<4 {
                let d = SizingLab.valueDrill(type: t, rng: &rng)
                #expect(d.questions.count == 2)
                #expect(d.questions.allSatisfy { !$0.correct.isEmpty })
                #expect(CallModel.classify(HandRead(hole: d.villainExample, board: d.board), street: d.street, opponents: 1) == d.villainHolding)
            }
        }
    }

    @Test func botsCallLikeTheModelSays() {
        // A fish with TPTK on the river calls a pot-sized bet; a nit folds it.
        var rng = SplitMix64(seed: 77)
        var fishCalls = 0, nitCalls = 0
        for _ in 0..<40 {
            var h = HandState(config: .noRake, handNumber: 1, seats: [(0, "Hero", 300), (1, "V", 300)], buttonSeat: 0, straddle: false, rng: &rng,
                              presetHoles: [0: Card.parse("7h7d"), 1: Card.parse("AsKd")], presetBoard: Card.parse("Kc7s2d9h3c"))
            h.apply(.raise(to: 6)); h.apply(.call)
            while h.street != .river { h.apply(.check) }
            if h.currentSeat == 1 { h.apply(.check) }
            h.apply(.raise(to: h.pot))  // hero bets pot
            for (t, counter) in [(PlayerType.fish, 0), (.nit, 1)] {
                if BotBrain.decide(state: h, seat: 1, profile: Profile.base(t), rng: &rng) != .fold {
                    if counter == 0 { fishCalls += 1 } else { nitCalls += 1 }
                }
            }
        }
        #expect(fishCalls >= 30)
        #expect(nitCalls <= 10)
    }
}

@Suite struct SpotFinderTests {
    @Test func everySpotIsReachable() {
        for seats in [6, 9] {
            let session = TableSession(preset: .typical, seats: seats, seed: 42)
            for kind in SpotKind.allCases {
                let found = SpotFinder.find(kind, against: nil, from: session)
                #expect(found != nil, "\(kind) not found at \(seats)-handed")
                if let f = found {
                    #expect(f.hand.currentSeat == TableSession.heroSeat)
                    #expect(SpotFinder.match(kind, state: f.hand, hero: TableSession.heroSeat) != nil)
                    print("SPOT \(seats) \(kind.rawValue): \(f.attempts) hands")
                }
            }
        }
    }

    @Test func villainFilterHolds() {
        let session = TableSession(preset: .typical, seed: 7)
        for t in [PlayerType.fish, .nit] {
            guard let f = SpotFinder.find(.facingCbet, against: t, from: session) else { continue }
            #expect(f.villains.allSatisfy { f.session.bot(at: $0)?.type == t })
        }
    }
}

@Suite struct EngineEdgeCaseTests {
    func hand(_ stacks: [Int], button: Int = 0, seed: UInt64 = 1, config: TableConfig = .noRake,
              holes: [Int: [Card]] = [:], board: [Card] = []) -> HandState {
        var rng = SplitMix64(seed: seed)
        return HandState(config: config, handNumber: 1, seats: stacks.enumerated().map { ($0.offset, "P\($0.offset)", $0.element) },
                         buttonSeat: button, straddle: false, rng: &rng, presetHoles: holes, presetBoard: board)
    }

    @Test func shortBigBlindStillCostsFullBlind() {
        // Seats 0 (BTN), 1 (SB), 2 (BB with $1).
        let h = hand([100, 100, 1])
        #expect(h.currentBet == 2)
        #expect(h.legalActions()?.toCall == 2)
    }

    @Test func checkerCanRaiseAfterShortAllInBet() {
        var h = hand([100, 100, 100, 3])
        // Preflop: everyone calls / checks to the flop.
        while h.street == .preflop { h.apply(h.legalActions()!.canCheck ? .check : .call) }
        // Seat 3 has $1 left. Flop order: SB(1), BB(2), UTG(3), BTN(0).
        h.apply(.check)  // seat 1
        h.apply(.check)  // seat 2
        h.apply(.raise(to: 1))  // seat 3 all-in for $1: a short bet
        h.apply(.call)  // seat 0
        #expect(h.currentSeat == 1)
        #expect(h.legalActions()?.canRaise == true)
    }

    @Test func shortAllInsThatAddUpToAFullRaiseReopen() {
        // Flop: A bets 10, B all-in +5, C all-in +6: together a full raise, so A may re-raise.
        var h = hand([500, 500, 17, 23])
        while h.street == .preflop { h.apply(h.legalActions()!.canCheck ? .check : .call) }
        let a = h.currentSeat!
        h.apply(.raise(to: 10))
        h.apply(.raise(to: 15))  // short all-in (+5)
        h.apply(.raise(to: 21))  // short all-in (+6)
        while h.currentSeat != a, !h.isComplete { h.apply(.call) }
        #expect(h.currentSeat == a)
        #expect(h.legalActions()?.canRaise == true)
    }

    @Test func headsUpButtonIsInPositionAndBBGetsOddChip() {
        let h = hand([100, 100], button: 0)
        #expect(h.isInPosition(0))
        #expect(!h.isInPosition(1))
        // Chop with an odd pot: both play the board.
        var c = hand([100, 100], button: 0, holes: [0: Card.parse("2c3d"), 1: Card.parse("2d3c")], board: Card.parse("AsKsQsJsTs"))
        c.apply(.raise(to: 3))  // SB/button raises to 3
        c.apply(.call)
        while !c.isComplete { c.apply(.check) }
        let r = c.result!
        #expect(r.net[0] == 0 && r.net[1] == 0)
    }

    @Test func chopsShareTheRake() {
        var c = hand([100, 100, 100], button: 0, config: TableConfig(),
                     holes: [1: Card.parse("2c3d"), 2: Card.parse("2d3c"), 0: Card.parse("4h5h")], board: Card.parse("AsKsQsJsTs"))
        c.apply(.fold)  // button
        c.apply(.raise(to: 50))  // SB
        c.apply(.call)  // BB
        while !c.isComplete { c.apply(.check) }
        let r = c.result!
        #expect(r.rake == 6)
        #expect(r.net[1] == -3 && r.net[2] == -3)
    }

    @Test func sittingOutAtSmallestTableDoesNotCrash() {
        var s = TableSession(preset: .typical, seats: 2, seed: 3)
        #expect(s.seatCount == 3)
        let h = s.startHand(heroSittingOut: true)
        #expect(h.players.count >= 2)
    }
}
