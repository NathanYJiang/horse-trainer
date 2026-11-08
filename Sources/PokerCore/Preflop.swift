import Foundation

/// Canonical starting-hand class, e.g. "AKs", "T9o", "77".
public struct HandClass: Hashable, Sendable, Codable, CustomStringConvertible {
    public let high: Int
    public let low: Int
    public let suited: Bool

    public init(high: Int, low: Int, suited: Bool) {
        self.high = max(high, low)
        self.low = min(high, low)
        self.suited = high != low && suited
    }

    public init(_ cards: [Card]) {
        precondition(cards.count == 2)
        self.init(high: cards[0].rankIndex, low: cards[1].rankIndex, suited: cards[0].suit == cards[1].suit)
    }

    public init?(_ text: String) {
        let chars = Array(text.uppercased())
        guard chars.count >= 2,
              let h = Card.rankChars.firstIndex(of: chars[0]),
              let l = Card.rankChars.firstIndex(of: chars[1]) else { return nil }
        self.init(high: h, low: l, suited: chars.count > 2 && chars[2] == "S")
    }

    public var isPair: Bool { high == low }
    public var gap: Int { high - low - 1 }
    public var combos: Int { isPair ? 6 : (suited ? 4 : 12) }

    public var description: String {
        let base = Card.rankChar(high) + Card.rankChar(low)
        return isPair ? base : base + (suited ? "s" : "o")
    }

    /// Chen formula — a simple, well known preflop strength heuristic.
    public var chen: Double {
        func cardScore(_ r: Int) -> Double {
            switch r {
            case 12: 10
            case 11: 8
            case 10: 7
            case 9: 6
            default: Double(r + 2) / 2
            }
        }
        var s = cardScore(high)
        if isPair { return max(5, s * 2) }
        if suited { s += 2 }
        switch gap {
        case 0: break
        case 1: s -= 1
        case 2: s -= 2
        case 3: s -= 4
        default: s -= 5
        }
        if gap <= 1 && high < 10 { s += 1 }
        return s.rounded(.up)
    }

    public static let all: [HandClass] = {
        var out: [HandClass] = []
        for h in 0..<13 {
            for l in 0...h {
                if h == l { out.append(HandClass(high: h, low: l, suited: false)) } else {
                    out.append(HandClass(high: h, low: l, suited: true))
                    out.append(HandClass(high: h, low: l, suited: false))
                }
            }
        }
        return out
    }()

    // Convenience categories used by bots, coach and drills.
    public var isPremium: Bool { (isPair && high >= 10) || (high == 12 && low == 11) }  // QQ+, AK
    public var isBigPair: Bool { isPair && high >= 11 }  // KK+
    public var isAce: Bool { high == 12 }
    public var isBroadway: Bool { low >= 8 }
    public var isSuitedConnector: Bool { suited && gap <= 1 && !isPair }
}

public enum Position: Int, CaseIterable, Sendable, Codable {
    case utg, utg1, mp, lj, hj, co, btn, sb, bb

    public var short: String {
        switch self {
        case .utg: "UTG"
        case .utg1: "UTG+1"
        case .mp: "MP"
        case .lj: "LJ"
        case .hj: "HJ"
        case .co: "CO"
        case .btn: "BTN"
        case .sb: "SB"
        case .bb: "BB"
        }
    }

    /// 0 = earliest, 1 = button. Blinds are treated as "late-ish" for completing but OOP postflop.
    public var lateness: Double {
        switch self {
        case .utg: 0
        case .utg1: 0.1
        case .mp: 0.25
        case .lj: 0.4
        case .hj: 0.55
        case .co: 0.75
        case .btn: 1
        case .sb: 0.5
        case .bb: 0.6
        }
    }

    public var isBlind: Bool { self == .sb || self == .bb }

    /// Positions for an n-handed table, from first seat left of the button's SB.
    /// Index 0 is SB, 1 BB, then UTG... and the button last.
    public static func layout(playerCount n: Int) -> [Position] {
        switch n {
        case ..<2: return []
        case 2: return [.sb, .bb]  // heads-up: SB is the button
        default:
            let middle: [Position] = [.utg, .utg1, .mp, .lj, .hj, .co]
            let count = n - 3
            let mids = Array(middle.suffix(count))
            return [.sb, .bb] + mids + [.btn]
        }
    }
}

/// Ranks all 169 starting hands with an optional per-player preference tweak, and converts
/// "play the top X% of combos" into a membership test.
public struct RangeModel: Sendable {
    public let order: [HandClass]
    private let percentile: [HandClass: Double]

    /// Builds from an explicit strongest-first ordering.
    public init(order: [HandClass]) {
        self.order = order
        var pct: [HandClass: Double] = [:]
        var cum = 0
        for h in order {
            cum += h.combos
            pct[h] = Double(cum) / 1326.0
        }
        percentile = pct
    }

    public init(bonus: (HandClass) -> Double = { _ in 0 }) {
        let scored = HandClass.all.map { h -> (HandClass, Double) in
            // Tie-break on raw high card / suitedness so ordering is stable.
            let tb = Double(h.high) * 0.01 + Double(h.low) * 0.001 + (h.suited ? 0.0005 : 0)
            return (h, h.chen + bonus(h) + tb)
        }
        order = scored.sorted { $0.1 > $1.1 }.map(\.0)
        var pct: [HandClass: Double] = [:]
        var cum = 0
        for h in order {
            cum += h.combos
            pct[h] = Double(cum) / 1326.0
        }
        percentile = pct
    }

    /// Fraction of all combos at least as strong as this hand (0 = best).
    public func percentile(of h: HandClass) -> Double { percentile[h] ?? 1 }

    public func inTop(_ fraction: Double, _ h: HandClass) -> Bool { percentile(of: h) <= fraction }

    /// Equity-based ranking used for "top X%" ranges, the range builder and the coach.
    public static let standard = RangeModel(order: HandRanking.order)

    /// The top `fraction` of hands by combos.
    public func top(_ fraction: Double) -> Set<HandClass> { Set(order.filter { inTop(fraction, $0) }) }
}
