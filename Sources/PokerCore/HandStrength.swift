import Foundation

public enum StrengthTier: Int, Comparable, Sendable, Codable, CaseIterable {
    case air, weak, medium, good, strong, monster

    public static func < (a: StrengthTier, b: StrengthTier) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .air: "air"
        case .weak: "weak showdown value"
        case .medium: "medium strength"
        case .good: "good hand"
        case .strong: "strong value"
        case .monster: "nutted"
        }
    }

    /// Rough continue-score used by bots.
    var score: Double {
        switch self {
        case .air: 0.0
        case .weak: 0.25
        case .medium: 0.45
        case .good: 0.62
        case .strong: 0.8
        case .monster: 0.96
        }
    }
}

public enum DrawStrength: Int, Comparable, Sendable, Codable {
    case none, weak, strong
    public static func < (a: DrawStrength, b: DrawStrength) -> Bool { a.rawValue < b.rawValue }
}

public struct BoardTexture: Sendable, Codable {
    public let cards: [Card]
    public let isPaired: Bool
    public let maxSuitCount: Int
    public let highRank: Int
    public let straighty: Bool

    public init(_ board: [Card]) {
        cards = board
        let ranks = board.map(\.rankIndex)
        isPaired = Set(ranks).count < ranks.count
        var suitCounts = [0, 0, 0, 0]
        for c in board { suitCounts[c.suit.rawValue] += 1 }
        maxSuitCount = suitCounts.max() ?? 0
        highRank = ranks.max() ?? 0
        // Any 3 distinct ranks inside a 5-rank window means a straight is possible.
        let uniq = Set(ranks + (ranks.contains(12) ? [-1] : []))
        var s = false
        for lo in -1...8 {
            if uniq.filter({ $0 >= lo && $0 <= lo + 4 }).count >= 3 { s = true; break }
        }
        straighty = s
    }

    public var isAceHigh: Bool { highRank == 12 }
    public var isMonotone: Bool { cards.count >= 3 && maxSuitCount >= 3 && cards.prefix(3).allSatisfy { $0.suit == cards[0].suit } }
    public var flushPossible: Bool { maxSuitCount >= 3 }
    public var isWet: Bool { (maxSuitCount >= 2 && cards.count == 3) || straighty || flushPossible }
    public var isDry: Bool { !straighty && maxSuitCount < 2 + (cards.count > 3 ? 1 : 0) }

    public var summary: String {
        var parts: [String] = []
        if cards.count == 3 {
            if isMonotone { parts.append("monotone") } else if maxSuitCount == 2 { parts.append("two-tone") } else { parts.append("rainbow") }
        } else if maxSuitCount >= 4 { parts.append("four-flush") } else if maxSuitCount == 3 { parts.append("flush possible") }
        if isPaired { parts.append("paired") }
        if straighty { parts.append("connected") }
        return parts.joined(separator: ", ")
    }
}

/// Everything a bot or the coach needs to know about a holding on a given board.
public struct HandRead: Sendable {
    public let hole: [Card]
    public let board: [Card]
    public let value: HandValue
    /// Fraction of random opponent holdings we currently beat (ties count half).
    public let hs: Double
    public let outs: Int
    public let draw: DrawStrength
    public let madeDescription: String

    public init(hole: [Card], board: [Card]) {
        precondition(hole.count == 2 && board.count >= 3)
        self.hole = hole
        self.board = board
        let known = mask(hole) | mask(board)
        let boardMask = mask(board)
        let myValue = HandEvaluator.evaluate(known)
        value = myValue

        let remaining = Card.all.filter { known & $0.bit == 0 }
        var wins = 0.0
        var total = 0.0
        for i in 0..<remaining.count {
            for j in (i + 1)..<remaining.count {
                let opp = HandEvaluator.evaluate(boardMask | remaining[i].bit | remaining[j].bit)
                if myValue > opp { wins += 1 } else if myValue == opp { wins += 0.5 }
                total += 1
            }
        }
        hs = total > 0 ? wins / total : 0

        var o = 0
        if board.count < 5 {
            for c in remaining {
                let nv = HandEvaluator.evaluate(known | c.bit)
                guard nv.category >= .straight, nv.category > myValue.category else { continue }
                let boardOnly = HandEvaluator.evaluate(boardMask | c.bit)
                if boardOnly.category < nv.category || board.count + 1 < 5 { o += 1 }
            }
        }
        outs = o
        if board.count >= 5 || myValue.category >= .straight {
            draw = .none
        } else if o >= 8 {
            draw = .strong
        } else if o >= 4 {
            draw = .weak
        } else {
            draw = .none
        }
        madeDescription = HandRead.describe(hole: hole, board: board, value: myValue)
    }

    /// Tier adjusted for the number of opponents still in the pot.
    public func tier(opponents: Int = 1) -> StrengthTier {
        let eff = pow(hs, 1 + 0.6 * Double(max(0, opponents - 1)))
        switch eff {
        case 0.96...: return .monster
        case 0.88...: return .strong
        case 0.76...: return .good
        case 0.58...: return .medium
        case 0.38...: return .weak
        default: return .air
        }
    }

    public var drawDescription: String? {
        guard draw != .none else { return nil }
        if outs >= 13 { return "combo draw (\(outs) outs)" }
        return draw == .strong ? "strong draw (\(outs) outs)" : "gutshot / weak draw (\(outs) outs)"
    }

    public static func describe(hole: [Card], board: [Card], value: HandValue) -> String {
        let boardRanks = board.map(\.rankIndex).sorted(by: >)
        let holeRanks = hole.map(\.rankIndex).sorted(by: >)
        let boardValue = HandEvaluator.evaluate(board)
        let isPocketPair = holeRanks[0] == holeRanks[1]
        switch value.category {
        case .highCard:
            return holeRanks[0] == 12 ? "Ace high" : "\(Card.rankName(holeRanks[0])) high"
        case .pair:
            let p = value.ranks[0]
            if boardValue.category == .pair && boardRanks.contains(p) && !holeRanks.contains(p) {
                return "Board pair, \(Card.rankName(holeRanks[0])) kicker"
            }
            let uniqBoard = Array(Set(boardRanks)).sorted(by: >)
            if isPocketPair {
                if p > uniqBoard[0] { return "Overpair (\(Card.rankChar(p))\(Card.rankChar(p)))" }
                return p > uniqBoard.last! ? "Underpair (middle)" : "Underpair"
            }
            if p == uniqBoard[0] {
                let kicker = holeRanks.first { $0 != p } ?? 0
                let k = kicker >= 11 ? "top kicker" : (kicker >= 8 ? "good kicker" : "weak kicker")
                return "Top pair, \(k)"
            }
            if p == uniqBoard.last! { return "Bottom pair" }
            return "Middle pair"
        case .twoPair:
            let usesBoth = !isPocketPair && holeRanks.allSatisfy { r in board.contains { $0.rankIndex == r } }
            if usesBoth {
                let top = Array(Set(boardRanks)).sorted(by: >)
                return holeRanks[0] == top[0] && holeRanks[1] == top[1] ? "Top two pair" : "Two pair"
            }
            return boardValue.category == .pair ? "Two pair (one on board)" : "Two pair"
        case .trips:
            return isPocketPair ? "Set of \(Card.rankName(holeRanks[0], plural: true))" : "Trips"
        default:
            return value.description
        }
    }
}

/// Monte-Carlo equity of one hand vs N random hands (used by drills/coach explanations).
public enum Equity {
    public static func vsRandom<R: RandomNumberGenerator>(hole: [Card], board: [Card], opponents: Int, iterations: Int = 1500, rng: inout R) -> Double {
        var wins = 0.0
        let known = Set(hole + board)
        for _ in 0..<iterations {
            var deck = Deck(rng: &rng, excluding: known)
            let opps = (0..<opponents).map { _ in deck.deal(2) }
            let runout = board + deck.deal(5 - board.count)
            let me = HandEvaluator.evaluate(hole + runout)
            let best = opps.map { HandEvaluator.evaluate($0 + runout) }.max()!
            if me > best { wins += 1 } else if me == best { wins += 0.5 }
        }
        return wins / Double(iterations)
    }
}

import Synchronization

extension HandRead {
    private struct Key: Hashable { let hole: UInt64, board: UInt64 }
    private static let cache = Mutex<[Key: HandRead]>([:])

    /// Same as `init`, memoized: bots and the simulator ask about the same hand on the same board thousands of times.
    public static func cached(hole: [Card], board: [Card]) -> HandRead {
        let k = Key(hole: mask(hole), board: mask(board))
        if let r = cache.withLock({ $0[k] }) { return r }
        let r = HandRead(hole: hole, board: board)
        cache.withLock { c in
            if c.count > 50000 { c.removeAll(keepingCapacity: true) }
            c[k] = r
        }
        return r
    }
}
