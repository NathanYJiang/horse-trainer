import Foundation

public enum Street: Int, Comparable, Sendable, Codable, CaseIterable {
    case preflop, flop, turn, river, showdown

    public static func < (a: Street, b: Street) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .preflop: "Preflop"
        case .flop: "Flop"
        case .turn: "Turn"
        case .river: "River"
        case .showdown: "Showdown"
        }
    }
}

public enum ActionType: String, Sendable, Codable {
    case postSB, postBB, postStraddle, fold, check, call, bet, raise

    public var isVoluntary: Bool { ![.postSB, .postBB, .postStraddle].contains(self) }
    public var isAggressive: Bool { self == .bet || self == .raise }
}

public struct PlayerAction: Sendable, Codable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let seat: Int
    public let street: Street
    public let type: ActionType
    /// Chips added to the pot by this action.
    public let added: Int
    /// Player's total commitment on this street after the action ("raise to" amount).
    public let toAmount: Int
    /// Pot size (including all bets so far) before this action.
    public let potBefore: Int
    public let toCallBefore: Int
    public let isAllIn: Bool
}

public enum Decision: Sendable, Equatable, Hashable {
    case fold
    case check
    case call
    /// Bet or raise to this total street commitment.
    case raise(to: Int)
}

public struct LegalActions: Sendable {
    public let toCall: Int
    public let callAmount: Int
    public let canCheck: Bool
    public let canRaise: Bool
    public let minRaiseTo: Int
    public let maxRaiseTo: Int
    public let committed: Int
    public let isBet: Bool
}

public struct TableConfig: Sendable, Codable, Equatable {
    public var smallBlind = 1
    public var bigBlind = 2
    public var straddleAmount = 5
    public var minBuyIn = 100
    public var maxBuyIn = 300
    public init() {}
}

public struct SeatState: Sendable, Codable, Identifiable {
    public var id: Int { seat }
    public let seat: Int
    public let name: String
    public let startingStack: Int
    public var stack: Int
    public var hole: [Card]
    public var committedStreet = 0
    public var committedTotal = 0
    public var folded = false
    public var allIn = false
    public var actedThisStreet = false
    public var actedAtRaiseCount = -1

    public var inHand: Bool { !folded }
    public var canAct: Bool { !folded && !allIn }
}

public struct PotAward: Sendable, Codable {
    public let amount: Int
    public let eligible: [Int]
    public let winners: [Int]
    public let winningHand: String?
}

public struct HandResult: Sendable, Codable {
    public let pots: [PotAward]
    /// seat -> net chips won/lost this hand
    public let net: [Int: Int]
    /// seat -> hand value description for players who showed down
    public let shown: [Int: String]
    public let wentToShowdown: Bool
    public let endedOn: Street
}

public struct HandState: Sendable {
    public let config: TableConfig
    public let handNumber: Int
    public private(set) var players: [SeatState]
    public let buttonSeat: Int
    public let positions: [Int: Position]
    public private(set) var board: [Card] = []
    public private(set) var street: Street = .preflop
    public private(set) var currentBet = 0
    public private(set) var minRaiseIncrement: Int
    public private(set) var fullRaiseCount = 0
    public private(set) var toActIndex: Int?
    public private(set) var actions: [PlayerAction] = []
    public private(set) var preflopRaiser: Int?
    public private(set) var lastAggressorThisStreet: Int?
    public private(set) var lastAggressor: Int?
    public private(set) var raisesThisStreet = 0
    public private(set) var result: HandResult?
    public let straddleSeat: Int?
    private var deck: Deck
    private var presetBoard: [Card] = []

    public var isComplete: Bool { result != nil }
    public var pot: Int { players.reduce(0) { $0 + $1.committedTotal } }
    public var currentSeat: Int? { toActIndex.map { players[$0].seat } }

    /// - Parameters:
    ///   - seats: (seat number, name, stack) for each player dealt in. Seat numbers can be sparse.
    public init<R: RandomNumberGenerator>(
        config: TableConfig,
        handNumber: Int,
        seats: [(seat: Int, name: String, stack: Int)],
        buttonSeat: Int,
        straddle: Bool,
        rng: inout R,
        presetHoles: [Int: [Card]] = [:],
        presetBoard: [Card] = []
    ) {
        precondition(seats.count >= 2)
        self.config = config
        self.handNumber = handNumber
        self.buttonSeat = buttonSeat
        minRaiseIncrement = config.bigBlind

        let sorted = seats.sorted { $0.seat < $1.seat }
        // Order clockwise starting with the first seat after the button.
        let startIdx = sorted.firstIndex { $0.seat > buttonSeat } ?? 0
        let ordered = Array(sorted[startIdx...] + sorted[..<startIdx])

        let preset = Set(presetHoles.values.flatMap { $0} + presetBoard)
        var d = Deck(rng: &rng, excluding: preset)
        var ps: [SeatState] = []
        for s in ordered {
            let hole = presetHoles[s.seat] ?? d.deal(2)
            ps.append(SeatState(seat: s.seat, name: s.name, startingStack: s.stack, stack: s.stack, hole: hole))
        }
        deck = d
        self.presetBoard = presetBoard
        players = ps
        straddleSeat = straddle && ordered.count >= 4 ? ordered[2].seat : nil

        var pos: [Int: Position] = [:]
        if ordered.count == 2 {
            // Heads-up: button is the small blind.
            let btn = ordered.first { $0.seat == buttonSeat } ?? ordered[1]
            let other = ordered.first { $0.seat != btn.seat }!
            pos[btn.seat] = .sb
            pos[other.seat] = .bb
            // Reorder so SB acts first preflop.
            players = [players.first { $0.seat == btn.seat }!, players.first { $0.seat == other.seat }!]
        } else {
            for (i, p) in Position.layout(playerCount: ordered.count).enumerated() {
                pos[ordered[i].seat] = p
            }
        }
        positions = pos

        // Blinds
        post(index: 0, amount: config.smallBlind, type: .postSB)
        post(index: 1, amount: config.bigBlind, type: .postBB)
        var lastBlind = 1
        if straddleSeat != nil {
            post(index: 2, amount: config.straddleAmount, type: .postStraddle)
            lastBlind = 2
        }
        currentBet = players.map(\.committedStreet).max() ?? 0
        minRaiseIncrement = straddleSeat != nil ? config.straddleAmount : config.bigBlind
        toActIndex = nextToAct(after: lastBlind)
        if toActIndex == nil { closeRound() }
    }

    // MARK: - Queries

    public func player(seat: Int) -> SeatState? { players.first { $0.seat == seat } }
    public func index(of seat: Int) -> Int? { players.firstIndex { $0.seat == seat } }
    public func position(of seat: Int) -> Position { positions[seat] ?? .mp }

    public var activePlayers: [SeatState] { players.filter(\.inHand) }

    public func legalActions() -> LegalActions? {
        guard let i = toActIndex else { return nil }
        let p = players[i]
        let toCall = max(0, currentBet - p.committedStreet)
        let callAmount = min(toCall, p.stack)
        let othersCanAct = players.enumerated().contains { $0.offset != i && $0.element.canAct }
        let reopened = !p.actedThisStreet || p.actedAtRaiseCount < fullRaiseCount
        let canRaise = p.stack > toCall && reopened && othersCanAct
        let maxTo = p.committedStreet + p.stack
        let minTo = min(maxTo, currentBet == 0 ? config.bigBlind : currentBet + minRaiseIncrement)
        return LegalActions(toCall: toCall, callAmount: callAmount, canCheck: toCall == 0, canRaise: canRaise,
                            minRaiseTo: minTo, maxRaiseTo: maxTo, committed: p.committedStreet, isBet: currentBet == 0)
    }

    /// Opponents still in the hand from the perspective of `seat`.
    public func opponents(of seat: Int) -> [SeatState] { players.filter { $0.inHand && $0.seat != seat } }

    public func actions(on street: Street) -> [PlayerAction] { actions.filter { $0.street == street } }

    /// Is `seat` last to act postflop among players still in (i.e. in position on everyone)?
    public func isInPosition(_ seat: Int) -> Bool {
        let live = players.filter(\.inHand)
        return live.last?.seat == seat
    }

    // MARK: - Mutation

    private mutating func post(index i: Int, amount: Int, type: ActionType) {
        let amt = min(amount, players[i].stack)
        let potBefore = pot
        players[i].stack -= amt
        players[i].committedStreet += amt
        players[i].committedTotal += amt
        if players[i].stack == 0 { players[i].allIn = true }
        actions.append(PlayerAction(index: actions.count, seat: players[i].seat, street: .preflop, type: type, added: amt,
                                    toAmount: players[i].committedStreet, potBefore: potBefore, toCallBefore: 0, isAllIn: players[i].allIn))
    }

    /// Applies a decision for the player to act. Invalid decisions are coerced to the closest legal one.
    public mutating func apply(_ decision: Decision) {
        guard let i = toActIndex, let legal = legalActions() else { return }
        var d = decision
        if case .check = d, !legal.canCheck { d = .fold }
        if case .call = d, legal.toCall == 0 { d = .check }
        if case .fold = d, legal.canCheck { d = .check }
        if case .raise = d, !legal.canRaise { d = legal.toCall == 0 ? .check : .call }

        let potBefore = pot
        let seat = players[i].seat
        var type: ActionType
        var added = 0
        switch d {
        case .fold:
            players[i].folded = true
            type = .fold
        case .check:
            type = .check
        case .call:
            added = legal.callAmount
            type = .call
        case .raise(let rawTo):
            let to = min(max(rawTo, legal.minRaiseTo), legal.maxRaiseTo)
            added = to - players[i].committedStreet
            type = currentBet == 0 ? .bet : .raise
            let increment = to - currentBet
            if increment >= minRaiseIncrement {
                minRaiseIncrement = increment
                fullRaiseCount += 1
            }
            currentBet = max(currentBet, to)
            lastAggressorThisStreet = seat
            lastAggressor = seat
            raisesThisStreet += 1
            if street == .preflop { preflopRaiser = seat }
        }
        players[i].stack -= added
        players[i].committedStreet += added
        players[i].committedTotal += added
        if players[i].stack == 0 && !players[i].folded { players[i].allIn = true }
        players[i].actedThisStreet = true
        players[i].actedAtRaiseCount = fullRaiseCount
        actions.append(PlayerAction(index: actions.count, seat: seat, street: street, type: type, added: added,
                                    toAmount: players[i].committedStreet, potBefore: potBefore, toCallBefore: legal.toCall,
                                    isAllIn: players[i].allIn))

        if players.filter(\.inHand).count == 1 {
            returnUncalled()
            finish(showdown: false)
            return
        }
        if let next = nextToAct(after: i) {
            toActIndex = next
        } else {
            closeRound()
        }
    }

    private func needsToAct(_ p: SeatState) -> Bool {
        p.canAct && (!p.actedThisStreet || p.committedStreet < currentBet)
    }

    private func nextToAct(after i: Int) -> Int? {
        let n = players.count
        for step in 1...n {
            let j = (i + step) % n
            if needsToAct(players[j]) {
                // A lone player who can act with nothing to call has no one to bet against.
                let othersCanAct = players.enumerated().contains { $0.offset != j && $0.element.canAct }
                if !othersCanAct && players[j].committedStreet >= currentBet { return nil }
                return j
            }
        }
        return nil
    }

    private mutating func returnUncalled() {
        guard let topIdx = players.indices.max(by: { players[$0].committedStreet < players[$1].committedStreet }) else { return }
        let top = players[topIdx].committedStreet
        let second = players.indices.filter { $0 != topIdx }.map { players[$0].committedStreet }.max() ?? 0
        if top > second {
            let refund = top - second
            players[topIdx].stack += refund
            players[topIdx].committedStreet -= refund
            players[topIdx].committedTotal -= refund
            if players[topIdx].stack > 0 { players[topIdx].allIn = false }
        }
    }

    private mutating func dealStreet(_ s: Street) {
        let need: Int
        switch s {
        case .flop: need = 3
        case .turn, .river: need = 1
        default: need = 0
        }
        for _ in 0..<need {
            if board.count < presetBoard.count {
                board.append(presetBoard[board.count])
            } else {
                board.append(deck.deal())
            }
        }
    }

    private mutating func closeRound() {
        returnUncalled()
        let canAct = players.filter(\.canAct).count
        if street == .river {
            finish(showdown: true)
            return
        }
        if canAct <= 1 {
            // Everyone (or all but one) is all-in: run it out.
            while street < .river {
                street = Street(rawValue: street.rawValue + 1)!
                dealStreet(street)
            }
            finish(showdown: true)
            return
        }
        street = Street(rawValue: street.rawValue + 1)!
        dealStreet(street)
        for i in players.indices {
            players[i].committedStreet = 0
            players[i].actedThisStreet = false
            players[i].actedAtRaiseCount = -1
        }
        currentBet = 0
        minRaiseIncrement = config.bigBlind
        fullRaiseCount = 0
        raisesThisStreet = 0
        lastAggressorThisStreet = nil
        // Postflop, first to act is the first live player after the button (index 0 onward).
        // Heads-up the button (index 0, the SB) acts last postflop.
        let start = players.count == 2 ? 0 : players.count - 1
        if let next = nextToAct(after: start) {
            toActIndex = next
        } else {
            closeRound()
        }
    }

    private mutating func finish(showdown: Bool) {
        toActIndex = nil
        let endedOn = street
        var awards: [PotAward] = []
        var won: [Int: Int] = [:]
        var shown: [Int: String] = [:]
        let live = players.filter(\.inHand)

        if !showdown || live.count == 1 {
            let w = live[0].seat
            awards.append(PotAward(amount: pot, eligible: [w], winners: [w], winningHand: nil))
            won[w] = pot
        } else {
            street = .showdown
            var values: [Int: HandValue] = [:]
            for p in live {
                let v = HandEvaluator.evaluate(p.hole + board)
                values[p.seat] = v
                shown[p.seat] = v.description
            }
            let levels = Array(Set(live.map(\.committedTotal))).sorted()
            var prev = 0
            var distributed = 0
            for level in levels {
                let amount = players.reduce(0) { $0 + min($1.committedTotal, level) - min($1.committedTotal, prev) }
                prev = level
                guard amount > 0 else { continue }
                let eligible = live.filter { $0.committedTotal >= level }.map(\.seat)
                let best = eligible.map { values[$0]! }.max()!
                // Winners in clockwise order from the button (players array is already in that order).
                let winners = players.map(\.seat).filter { eligible.contains($0) && values[$0]! == best }
                let share = amount / winners.count
                var odd = amount - share * winners.count
                for w in winners {
                    won[w, default: 0] += share + (odd > 0 ? 1 : 0)
                    if odd > 0 { odd -= 1 }
                }
                distributed += amount
                awards.append(PotAward(amount: amount, eligible: eligible, winners: winners, winningHand: best.description))
            }
            let leftover = pot - distributed
            if leftover > 0, let last = awards.last {
                let w = last.winners[0]
                won[w, default: 0] += leftover
                awards[awards.count - 1] = PotAward(amount: last.amount + leftover, eligible: last.eligible, winners: last.winners, winningHand: last.winningHand)
            }
        }

        var net: [Int: Int] = [:]
        for i in players.indices {
            let w = won[players[i].seat] ?? 0
            players[i].stack += w
            net[players[i].seat] = w - players[i].committedTotal
        }
        result = HandResult(pots: awards, net: net, shown: shown, wentToShowdown: showdown && live.count > 1, endedOn: endedOn)
    }
}
