import Foundation

public enum Suit: Int, CaseIterable, Sendable, Codable {
    case clubs, diamonds, hearts, spades

    public var symbol: String {
        switch self {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    public var letter: String {
        switch self {
        case .clubs: "c"
        case .diamonds: "d"
        case .hearts: "h"
        case .spades: "s"
        }
    }
}

/// Card encoded as `suit * 13 + rankIndex`, rankIndex 0 = deuce ... 12 = ace.
public struct Card: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let id: UInt8

    public init(id: UInt8) {
        precondition(id < 52)
        self.id = id
    }

    public init(rankIndex: Int, suit: Suit) {
        self.id = UInt8(suit.rawValue * 13 + rankIndex)
    }

    public init?(_ text: String) {
        let chars = Array(text)
        guard chars.count == 2,
              let r = Card.rankChars.firstIndex(of: Character(chars[0].uppercased())),
              let s = Suit.allCases.first(where: { $0.letter == String(chars[1]).lowercased() })
        else { return nil }
        self.init(rankIndex: r, suit: s)
    }

    public var rankIndex: Int { Int(id) % 13 }
    public var suit: Suit { Suit(rawValue: Int(id) / 13)! }
    public var bit: UInt64 { 1 << UInt64(id) }

    static let rankChars: [Character] = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"]
    public static func rankChar(_ index: Int) -> String { String(rankChars[index]) }
    public static func rankName(_ index: Int, plural: Bool = false) -> String {
        let names = ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King", "Ace"]
        let n = names[index]
        if !plural { return n }
        return index == 4 ? "Sixes" : n + "s"
    }

    public var rankText: String { Card.rankChar(rankIndex) }
    public var description: String { rankText + suit.letter }
    public var pretty: String { rankText + suit.symbol }

    public static func < (a: Card, b: Card) -> Bool {
        a.rankIndex == b.rankIndex ? a.suit.rawValue < b.suit.rawValue : a.rankIndex < b.rankIndex
    }

    public static let all: [Card] = (0..<52).map { Card(id: UInt8($0)) }

    public static func parse(_ text: String) -> [Card] {
        var out: [Card] = []
        var chars = Array(text.filter { !$0.isWhitespace })
        while chars.count >= 2 {
            if let c = Card(String(chars[0...1])) { out.append(c) }
            chars.removeFirst(2)
        }
        return out
    }
}

public func mask(_ cards: [Card]) -> UInt64 {
    cards.reduce(0) { $0 | $1.bit }
}

/// Deterministic, seedable RNG so hands and tests are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct Deck: Sendable {
    private var cards: [Card]

    public init<R: RandomNumberGenerator>(rng: inout R, excluding: Set<Card> = []) {
        cards = Card.all.filter { !excluding.contains($0) }.shuffled(using: &rng)
    }

    public var remaining: Int { cards.count }

    public mutating func deal() -> Card { cards.removeLast() }

    public mutating func deal(_ n: Int) -> [Card] { (0..<n).map { _ in deal() } }

    public mutating func remove(_ card: Card) { cards.removeAll { $0 == card } }
}

extension Double {
    /// Clamp into [lo, hi].
    public func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, self)) }
}
