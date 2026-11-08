import Foundation

public enum HandCategory: Int, Comparable, Sendable, Codable, CaseIterable {
    case highCard, pair, twoPair, trips, straight, flush, fullHouse, quads, straightFlush

    public static func < (a: HandCategory, b: HandCategory) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .highCard: "High Card"
        case .pair: "Pair"
        case .twoPair: "Two Pair"
        case .trips: "Three of a Kind"
        case .straight: "Straight"
        case .flush: "Flush"
        case .fullHouse: "Full House"
        case .quads: "Four of a Kind"
        case .straightFlush: "Straight Flush"
        }
    }
}

/// Comparable hand value: category in the top bits, then up to five 4-bit rank kickers.
public struct HandValue: Comparable, Hashable, Sendable {
    public let raw: UInt32

    public var category: HandCategory { HandCategory(rawValue: Int(raw >> 20))! }

    var ranks: [Int] {
        (0..<5).map { Int((raw >> UInt32(16 - $0 * 4)) & 0xF) }
    }

    public static func < (a: HandValue, b: HandValue) -> Bool { a.raw < b.raw }

    public var description: String {
        let r = ranks
        switch category {
        case .highCard: return "\(Card.rankName(r[0])) high"
        case .pair: return "Pair of \(Card.rankName(r[0], plural: true))"
        case .twoPair: return "Two Pair, \(Card.rankName(r[0], plural: true)) and \(Card.rankName(r[1], plural: true))"
        case .trips: return "Three \(Card.rankName(r[0], plural: true))"
        case .straight: return "Straight, \(Card.rankName(r[0])) high"
        case .flush: return "Flush, \(Card.rankName(r[0])) high"
        case .fullHouse: return "Full House, \(Card.rankName(r[0], plural: true)) full of \(Card.rankName(r[1], plural: true))"
        case .quads: return "Four \(Card.rankName(r[0], plural: true))"
        case .straightFlush: return r[0] == 12 ? "Royal Flush" : "Straight Flush, \(Card.rankName(r[0])) high"
        }
    }
}

public enum HandEvaluator {
    @inline(__always)
    static func pack(_ cat: HandCategory, _ ranks: [Int]) -> HandValue {
        var v = UInt32(cat.rawValue) << 20
        for (i, r) in ranks.prefix(5).enumerated() {
            v |= UInt32(r) << UInt32(16 - i * 4)
        }
        return HandValue(raw: v)
    }

    @inline(__always)
    static func highBit(_ m: UInt32) -> Int { 31 - m.leadingZeroBitCount }

    /// Highest `n` ranks set in the 13-bit mask, descending.
    @inline(__always)
    static func top(_ m: UInt32, _ n: Int) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(n)
        var mm = m
        while out.count < n && mm != 0 {
            let h = highBit(mm)
            out.append(h)
            mm &= ~(1 << UInt32(h))
        }
        return out
    }

    /// High card index of the best straight in a 13-bit rank mask, or nil.
    @inline(__always)
    static func straightHigh(_ m: UInt32) -> Int? {
        var high = 12
        while high >= 4 {
            let window: UInt32 = 0x1F << UInt32(high - 4)
            if m & window == window { return high }
            high -= 1
        }
        // Wheel: A-2-3-4-5
        if m & 0x100F == 0x100F { return 3 }
        return nil
    }

    /// Evaluates the best 5-card hand from a card bitmask of 5–7 cards.
    public static func evaluate(_ m: UInt64) -> HandValue {
        let s0 = UInt32(m & 0x1FFF)
        let s1 = UInt32((m >> 13) & 0x1FFF)
        let s2 = UInt32((m >> 26) & 0x1FFF)
        let s3 = UInt32((m >> 39) & 0x1FFF)

        for s in [s0, s1, s2, s3] where s.nonzeroBitCount >= 5 {
            if let h = straightHigh(s) { return pack(.straightFlush, [h]) }
            return pack(.flush, top(s, 5))
        }

        let any = s0 | s1 | s2 | s3
        let quads = s0 & s1 & s2 & s3
        let atLeast3 = (s0 & s1 & s2) | (s0 & s1 & s3) | (s0 & s2 & s3) | (s1 & s2 & s3)
        let atLeast2 = (s0 & s1) | (s0 & s2) | (s0 & s3) | (s1 & s2) | (s1 & s3) | (s2 & s3)
        let trips = atLeast3 & ~quads
        let pairs = atLeast2 & ~atLeast3

        if quads != 0 {
            let q = highBit(quads)
            return pack(.quads, [q] + top(any & ~(1 << UInt32(q)), 1))
        }
        if trips != 0 {
            let t = highBit(trips)
            let rest = (trips & ~(1 << UInt32(t))) | pairs
            if rest != 0 { return pack(.fullHouse, [t, highBit(rest)]) }
        }
        if let h = straightHigh(any) { return pack(.straight, [h]) }
        if trips != 0 {
            let t = highBit(trips)
            return pack(.trips, [t] + top(any & ~(1 << UInt32(t)), 2))
        }
        if pairs.nonzeroBitCount >= 2 {
            let p = top(pairs, 2)
            let used: UInt32 = (1 << UInt32(p[0])) | (1 << UInt32(p[1]))
            return pack(.twoPair, p + top(any & ~used, 1))
        }
        if pairs != 0 {
            let p = highBit(pairs)
            return pack(.pair, [p] + top(any & ~(1 << UInt32(p)), 3))
        }
        return pack(.highCard, top(any, 5))
    }

    public static func evaluate(_ cards: [Card]) -> HandValue { evaluate(mask(cards)) }
}
