import Foundation

/// What a player is holding, in the words you'd use at the table.
public enum HoldingClass: String, CaseIterable, Sendable, Codable {
    case nutted, strong, topPairTop, topPairWeak, middlePair, strongDraw, weakDraw, air

    public var label: String {
        switch self {
        case .nutted: "the nuts / near-nuts"
        case .strong: "two pair / a set"
        case .topPairTop: "top pair top kicker / overpair"
        case .topPairWeak: "top pair, weaker kicker"
        case .middlePair: "middle pair / underpair"
        case .strongDraw: "a strong draw"
        case .weakDraw: "a gutshot / weak draw"
        case .air: "air"
        }
    }

    public var short: String {
        switch self {
        case .nutted: "Nuts"
        case .strong: "Two pair+"
        case .topPairTop: "TPTK"
        case .topPairWeak: "TP weak kicker"
        case .middlePair: "Middle pair"
        case .strongDraw: "Strong draw"
        case .weakDraw: "Weak draw"
        case .air: "Air"
        }
    }
}

/// The calling model: how big a bet (as a fraction of the pot) each type will call with each holding.
/// Bots use this when facing a bet, and the Inverse Question drill teaches it — so the table plays exactly like the drill says.
public enum CallModel {
    public static func classify(_ read: HandRead, street: Street, opponents: Int) -> HoldingClass {
        let tier = read.tier(opponents: opponents)
        let desc = read.madeDescription
        var made: HoldingClass
        if tier == .monster {
            made = .nutted
        } else if read.value.category >= .twoPair && !desc.contains("one on board") && tier >= .good {
            made = .strong
        } else if desc.hasPrefix("Top pair, top") || desc.hasPrefix("Overpair") {
            made = .topPairTop
        } else if desc.hasPrefix("Top pair") {
            made = .topPairWeak
        } else if read.value.category >= .pair && !desc.hasPrefix("Board pair") {
            made = .middlePair
        } else {
            made = .air
        }
        if street != .river && made.rawThreshold < HoldingClass.strongDraw.rawThreshold {
            if read.draw == .strong { made = .strongDraw } else if read.draw == .weak && made == .air { made = .weakDraw }
        }
        return made
    }

    /// Base table: max bet (fraction of pot) each type calls with each holding.
    static func base(_ t: PlayerType, _ h: HoldingClass) -> Double {
        let row: [HoldingClass: Double]
        switch t {
        case .fish: row = [.nutted: 9, .strong: 9, .topPairTop: 1.5, .topPairWeak: 1.1, .middlePair: 0.8, .strongDraw: 1.0, .weakDraw: 0.65, .air: 0.5]
        case .whale: row = [.nutted: 9, .strong: 9, .topPairTop: 2.0, .topPairWeak: 1.3, .middlePair: 0.95, .strongDraw: 1.2, .weakDraw: 0.75, .air: 0.5]
        case .tryingRec: row = [.nutted: 9, .strong: 2.0, .topPairTop: 0.85, .topPairWeak: 0.65, .middlePair: 0.55, .strongDraw: 0.7, .weakDraw: 0.5, .air: 0.3]
        case .nit: row = [.nutted: 9, .strong: 1.5, .topPairTop: 0.7, .topPairWeak: 0.5, .middlePair: 0.45, .strongDraw: 0.55, .weakDraw: 0.5, .air: 0.25]
        case .reg: row = [.nutted: 9, .strong: 2.5, .topPairTop: 1.1, .topPairWeak: 0.8, .middlePair: 0.6, .strongDraw: 0.9, .weakDraw: 0.65, .air: 0.45]
        }
        return row[h] ?? 0
    }

    /// Max bet (fraction of the pot before the bet) this type calls with this holding in this spot.
    public static func maxCall(_ t: PlayerType, _ h: HoldingClass, street: Street, bigPot: Bool = false, facingRaise: Bool = false) -> Double {
        var x = base(t, h)
        let tight = t == .tryingRec || t == .nit || t == .reg
        if tight && [.topPairTop, .topPairWeak, .middlePair].contains(h) {
            if street == .river { x *= 0.75 } else if street == .turn { x *= 0.9 }
        }
        // Air and weak draws: people float the flop with overcards and backdoors, then give up on later streets.
        if h == .air || h == .weakDraw {
            if street == .turn { x *= 0.5 } else if street == .river { x *= h == .air ? 0.25 : 0.4 }
        }
        // Even stations slow down on the river with their weakest pairs.
        if !tight && street == .river {
            if h == .middlePair { x *= 0.75 } else if h == .topPairWeak { x *= 0.85 }
        }
        if bigPot && tight && h != .nutted { x *= t == .reg ? 0.7 : 0.8 }
        if facingRaise && h != .nutted { x *= (t == .fish || t == .whale) ? 0.85 : 0.6 }
        return x
    }

    public static func describe(_ fraction: Double) -> String {
        if fraction >= 3 { return "any size (they're not folding)" }
        return "\(Int((fraction * 100).rounded()))% pot"
    }
}

extension HoldingClass {
    var rawThreshold: Int {
        switch self {
        case .air: 0
        case .weakDraw: 1
        case .middlePair: 2
        case .strongDraw: 3
        case .topPairWeak: 4
        case .topPairTop: 5
        case .strong: 6
        case .nutted: 7
        }
    }
}
