import Foundation

public enum PlayerType: String, CaseIterable, Sendable, Codable, Identifiable {
    case whale, fish, tryingRec, nit, reg

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .whale: "Whale"
        case .fish: "Fish"
        case .tryingRec: "Trying Rec"
        case .nit: "Nit / OMC"
        case .reg: "Reg"
        }
    }

    public var emoji: String {
        switch self {
        case .whale: "🐋"
        case .fish: "🐟"
        case .tryingRec: "🤓"
        case .nit: "🪨"
        case .reg: "🦈"
        }
    }

    public var oneLiner: String {
        switch self {
        case .whale: "Loose-aggressive station. Biggest loser in the game. Bluffs when given rope, calls too much."
        case .fish: "Loose-passive station. Calls too much, folds too little, bluffs too little. Sizing tells."
        case .tryingRec: "Tight-passive, trying to play right. Folds too much, rarely bluffs, folds to big bets."
        case .nit: "Super tight. Plays big pairs and big cards. Raises = nuts. Never bluffs rivers."
        case .reg: "Winning TAG. Correct in small pots, too straightforward in big pots."
        }
    }

    /// Measured live-1/2-style bands (see CalibrationTests); used by explanations and the reads quiz.
    public var vpipBand: ClosedRange<Double> {
        switch self {
        case .whale: 0.55...0.85
        case .fish: 0.38...0.65
        case .tryingRec: 0.17...0.32
        case .nit: 0.08...0.18
        case .reg: 0.18...0.32
        }
    }

    public var pfrBand: ClosedRange<Double> {
        switch self {
        case .whale: 0.14...0.45
        case .fish: 0.02...0.14
        case .tryingRec: 0.07...0.20
        case .nit: 0.03...0.12
        case .reg: 0.13...0.30
        }
    }
}

/// All the knobs that make a bot behave like its type. Probabilities and fractions in 0...1.
public struct Profile: Sendable, Codable, Equatable {
    public var type: PlayerType

    // Preflop
    public var vpip: Double
    public var pfr: Double
    public var threeBet: Double
    public var limpPreference: Double
    public var openSizeLow: Double
    public var openSizeHigh: Double
    public var premiumOpenBump: Double
    public var limpTrapPremiums: Double
    public var straddleFreq: Double
    public var coldCall: Double
    public var positional: Double
    public var foldTo3Bet: Double

    // Postflop
    public var aggression: Double
    public var bluff: Double
    public var rope: Double
    public var cbet: Double
    public var slowplay: Double
    public var stickiness: Double
    public var foldToBigBet: Double
    public var raiseValue: Double
    public var raiseDraw: Double
    public var sizingTell: Double
    public var bigPotCaution: Double
    public var donkValue: Double
    public var thinValue: Double
    public var heroCall: Double

    public static func base(_ t: PlayerType) -> Profile {
        switch t {
        case .whale:
            Profile(type: t, vpip: 0.85, pfr: 0.28, threeBet: 0.10, limpPreference: 0.85, openSizeLow: 6, openSizeHigh: 15,
                    premiumOpenBump: 1.0, limpTrapPremiums: 0.05, straddleFreq: 0.6, coldCall: 0.8, positional: 0.1, foldTo3Bet: 0.2,
                    aggression: 0.75, bluff: 0.3, rope: 0.55, cbet: 0.8, slowplay: 0.1, stickiness: 0.75, foldToBigBet: 0.1,
                    raiseValue: 0.55, raiseDraw: 0.35, sizingTell: 0.35, bigPotCaution: 0, donkValue: 0.4, thinValue: 0.5, heroCall: 0.25)
        case .fish:
            Profile(type: t, vpip: 0.6, pfr: 0.07, threeBet: 0.02, limpPreference: 0.95, openSizeLow: 3, openSizeHigh: 5,
                    premiumOpenBump: 1.4, limpTrapPremiums: 0.12, straddleFreq: 0.15, coldCall: 0.5, positional: 0.15, foldTo3Bet: 0.35,
                    aggression: 0.4, bluff: 0.06, rope: 0.1, cbet: 0.45, slowplay: 0.3, stickiness: 0.8, foldToBigBet: 0.2,
                    raiseValue: 0.35, raiseDraw: 0.05, sizingTell: 0.9, bigPotCaution: 0, donkValue: 0.55, thinValue: 0.5, heroCall: 0.1)
        case .tryingRec:
            Profile(type: t, vpip: 0.32, pfr: 0.15, threeBet: 0.04, limpPreference: 0.75, openSizeLow: 5, openSizeHigh: 7.5,
                    premiumOpenBump: 1.25, limpTrapPremiums: 0.15, straddleFreq: 0.05, coldCall: 0.24, positional: 0.5, foldTo3Bet: 0.55,
                    aggression: 0.3, bluff: 0.08, rope: 0.1, cbet: 0.3, slowplay: 0.15, stickiness: 0.2, foldToBigBet: 0.7,
                    raiseValue: 0.3, raiseDraw: 0.08, sizingTell: 0.75, bigPotCaution: 0.3, donkValue: 0.1, thinValue: 0.15, heroCall: 0)
        case .nit:
            Profile(type: t, vpip: 0.18, pfr: 0.09, threeBet: 0.025, limpPreference: 0.75, openSizeLow: 5, openSizeHigh: 7.5,
                    premiumOpenBump: 1.3, limpTrapPremiums: 0.2, straddleFreq: 0, coldCall: 0.12, positional: 0.5, foldTo3Bet: 0.6,
                    aggression: 0.25, bluff: 0.02, rope: 0.02, cbet: 0.25, slowplay: 0.2, stickiness: 0.1, foldToBigBet: 0.8,
                    raiseValue: 0.3, raiseDraw: 0.03, sizingTell: 0.6, bigPotCaution: 0.4, donkValue: 0.15, thinValue: 0.1, heroCall: 0)
        case .reg:
            Profile(type: t, vpip: 0.34, pfr: 0.30, threeBet: 0.08, limpPreference: 0.1, openSizeLow: 5, openSizeHigh: 6,
                    premiumOpenBump: 1.0, limpTrapPremiums: 0.03, straddleFreq: 0.1, coldCall: 0.24, positional: 0.8, foldTo3Bet: 0.45,
                    aggression: 0.65, bluff: 0.3, rope: 0.25, cbet: 0.75, slowplay: 0.15, stickiness: 0.35, foldToBigBet: 0.35,
                    raiseValue: 0.55, raiseDraw: 0.25, sizingTell: 0.15, bigPotCaution: 0.6, donkValue: 0.05, thinValue: 0.4, heroCall: 0.05)
        }
    }

    /// Base profile with ±15% jitter so no two bots of a type are identical.
    public static func random<R: RandomNumberGenerator>(_ t: PlayerType, rng: inout R) -> Profile {
        var p = base(t)
        func j(_ v: Double) -> Double { (v * Double.random(in: 0.85...1.15, using: &rng)).clamped(0, 1) }
        p.vpip = j(p.vpip); p.pfr = min(j(p.pfr), p.vpip * 0.9); p.threeBet = j(p.threeBet)
        p.limpPreference = j(p.limpPreference); p.coldCall = j(p.coldCall); p.foldTo3Bet = j(p.foldTo3Bet)
        p.aggression = j(p.aggression); p.bluff = j(p.bluff); p.rope = j(p.rope); p.cbet = j(p.cbet)
        p.slowplay = j(p.slowplay); p.stickiness = j(p.stickiness); p.foldToBigBet = j(p.foldToBigBet)
        p.raiseValue = j(p.raiseValue); p.raiseDraw = j(p.raiseDraw); p.sizingTell = j(p.sizingTell)
        p.donkValue = j(p.donkValue); p.thinValue = j(p.thinValue)
        // Quirks: these flip on/off per player, which is what you actually pick up on at a live table.
        let trapChance: Double = [.nit: 0.55, .tryingRec: 0.3, .fish: 0.3, .whale: 0.1, .reg: 0.08][t] ?? 0.2
        if Double.random(in: 0...1, using: &rng) < trapChance { p.limpTrapPremiums = min(1, p.limpTrapPremiums + 0.45) }
        if t != .reg && Double.random(in: 0...1, using: &rng) < 0.4 { p.premiumOpenBump = max(p.premiumOpenBump, 1.5) }
        if Double.random(in: 0...1, using: &rng) < 0.25 { p.straddleFreq = min(1, p.straddleFreq + 0.4) }
        return p
    }

    /// Human-readable quirks shown on the reveal screen.
    public var quirks: [String] {
        var q: [String] = []
        if limpTrapPremiums >= 0.3 { q.append("Limp-traps AA/KK (limp-raise = premium)") }
        if premiumOpenBump >= 1.35 { q.append("Opens bigger with premiums (preflop sizing tell)") }
        if straddleFreq >= 0.35 { q.append("Straddles often") }
        if donkValue >= 0.4 { q.append("Donk-leads value on the river") }
        if sizingTell >= 0.7 { q.append("Strong bet-sizing tells: big = strong, small = medium/draw") }
        if bluff >= 0.3 && rope >= 0.4 { q.append("Bluffs a lot when checked to (give rope)") }
        if stickiness >= 0.65 { q.append("Calling station: rarely folds a pair") }
        if foldToBigBet >= 0.6 { q.append("Folds to big bets") }
        if bigPotCaution >= 0.5 { q.append("Plays straightforward / underbluffs in big pots") }
        if bluff <= 0.05 { q.append("Almost never bluffs") }
        return q
    }

    /// Preference bonus applied on top of the Chen score when picking which hands to play.
    public var handBonus: @Sendable (HandClass) -> Double {
        switch type {
        case .fish:
            return { h in (h.suited ? 2 : 0) + (h.isAce ? 1.5 : 0) + (h.isPair ? 1 : 0) + (h.gap <= 1 && !h.isPair ? 1 : 0) }
        case .whale:
            return { h in (h.suited ? 1 : 0) + (h.isAce ? 1 : 0) + (h.high == 11 ? 0.5 : 0) }
        case .tryingRec:
            return { h in (h.isBroadway ? 1 : 0) + (h.suited ? 0.5 : 0) }
        case .nit:
            return { h in (h.isPair ? 1.5 : 0) + (h.isBroadway ? 1 : 0) - (h.isSuitedConnector && h.high < 9 ? 1 : 0) }
        case .reg:
            return { h in (h.suited ? 0.5 : 0) + (h.isPair ? 0.5 : 0) }
        }
    }
}

/// A bot sitting at the table.
public struct BotPlayer: Sendable, Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var profile: Profile
    public var appearance: String
    public var avatarHue: Double

    public var type: PlayerType { profile.type }
}

public enum TablePreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case typical, weekday, juicy, random

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .typical: "Typical 1/2 (weekend night)"
        case .weekday: "Weekday afternoon grind"
        case .juicy: "Juicy Saturday (2 whales)"
        case .random: "Random mix"
        }
    }

    public var detail: String {
        switch self {
        case .typical: "A whale (sometimes), 2–3 fish, a couple of trying recs, a reg or two, a nit."
        case .weekday: "Reg and nit heavy. Fewer gifts, tighter game: patience and steals."
        case .juicy: "Two whales and a pile of fish. Value-bet relentlessly, bluff rarely."
        case .random: "Any mix. Good for classification practice."
        }
    }

    /// Composition for `n` bots.
    public func composition<R: RandomNumberGenerator>(bots n: Int, rng: inout R) -> [PlayerType] {
        var types: [PlayerType]
        switch self {
        case .typical:
            types = [.fish, .fish, .tryingRec, .tryingRec, .reg, .nit]
            types.append(Bool.random(using: &rng) ? .whale : .fish)
            types.append([.reg, .fish, .nit, .tryingRec].randomElement(using: &rng)!)
        case .weekday:
            types = [.reg, .reg, .reg, .nit, .nit, .nit, .tryingRec, .fish]
        case .juicy:
            types = [.whale, .whale, .fish, .fish, .fish, .tryingRec, .reg, .nit]
        case .random:
            let weights: [(PlayerType, Double)] = [(.whale, 0.1), (.fish, 0.3), (.tryingRec, 0.22), (.nit, 0.18), (.reg, 0.2)]
            types = (0..<n).map { _ in Roster.weightedPick(weights, rng: &rng) }
        }
        while types.count < n { types.append(Roster.weightedPick([(.fish, 0.4), (.tryingRec, 0.3), (.nit, 0.15), (.reg, 0.15)], rng: &rng)) }
        return Array(types.shuffled(using: &rng).prefix(n))
    }
}

public enum Roster {
    static let firstNames = [
        "Mike", "Dave", "Tony", "Steve", "Linda", "Kevin", "Raj", "Hector", "Wei", "Jen", "Marcus", "Sal", "Patty", "Duc",
        "Gary", "Andre", "Bobby", "Nina", "Carlos", "Frank", "Yuki", "Omar", "Rick", "Tammy", "Jimmy", "Vinny", "Priya",
        "Alex", "Greg", "Sergei", "Kim", "Luis", "Benny", "Dmitri", "Rosa", "Ted", "Moe", "Hank", "Ivy", "Trent",
    ]

    /// Appearance correlates with type ~55% of the time — just like live, it's a hint, not a tell you can bank on.
    static let looks: [PlayerType: [String]] = [
        .whale: ["Loud, ordering another round", "Designer watch, tossing chips", "Celebrating every pot", "Bachelor party energy", "Rebuying from a thick wallet"],
        .fish: ["Tourist in a Vegas tee", "Chatty, on their phone", "First trip to the casino", "Asking how much to call", "Wearing a bachelorette sash"],
        .tryingRec: ["Poker-strategy book in bag", "Studies hands on phone between orbits", "Neat chip stacks, careful", "Quiet, watches every showdown"],
        .nit: ["Retiree with coffee and newspaper", "Visor and fanny pack", "Complains about the rake", "Folds, eats sandwich, folds"],
        .reg: ["Hoodie, headphones, poker face", "Two racks, knows the dealers by name", "Shuffles chips constantly", "Tracks results in an app"],
    ]

    static func weightedPick<R: RandomNumberGenerator>(_ items: [(PlayerType, Double)], rng: inout R) -> PlayerType {
        let total = items.reduce(0) { $0 + $1.1 }
        var x = Double.random(in: 0..<total, using: &rng)
        for (t, w) in items {
            if x < w { return t }
            x -= w
        }
        return items.last!.0
    }

    public static func makeBot<R: RandomNumberGenerator>(type: PlayerType, usedNames: Set<String>, rng: inout R) -> BotPlayer {
        let name = firstNames.filter { !usedNames.contains($0) }.randomElement(using: &rng) ?? "Player"
        let lookType: PlayerType = Double.random(in: 0...1, using: &rng) < 0.55 ? type : PlayerType.allCases.randomElement(using: &rng)!
        let look = looks[lookType]!.randomElement(using: &rng)!
        return BotPlayer(id: UUID(), name: name, profile: Profile.random(type, rng: &rng), appearance: look,
                         avatarHue: Double.random(in: 0...1, using: &rng))
    }

    /// Typical live buy-in for a type at a $100–$300 game.
    public static func buyIn<R: RandomNumberGenerator>(for type: PlayerType, config: TableConfig, rng: inout R) -> Int {
        let r = Double.random(in: 0...1, using: &rng)
        switch type {
        case .whale: return [config.maxBuyIn, config.maxBuyIn * 2, Int(Double(config.maxBuyIn) * 2.7)][Int(r * 3) % 3]
        case .reg: return r < 0.5 ? config.maxBuyIn : Int(Double(config.maxBuyIn) * (1.3 + r))
        case .nit: return config.maxBuyIn
        case .tryingRec: return r < 0.7 ? config.maxBuyIn : 200
        case .fish: return r < 0.3 ? config.minBuyIn : (r < 0.6 ? 200 : config.maxBuyIn)
        }
    }
}
