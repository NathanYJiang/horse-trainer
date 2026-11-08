import Foundation

/// The playbook. Every coach note and drill explanation links back to one of these.
public enum Principle: String, CaseIterable, Sendable, Codable, Identifiable {
    case overfoldToPassiveAggression
    case giveWhalesRope
    case fireWithFire
    case valueBetStations
    case noBigBluffsVsStations
    case sizeDownRiverVsRecs
    case bluffRecsBig
    case rangeBetHalfPot
    case aceHighOverbetOrCheck
    case isolateFishLimps
    case respectLimpTraps
    case limpRaiseIsNuts
    case cold4BetIsAces
    case dontOpenLimp
    case liveOpenSizing
    case respectNitRanges
    case threeBetWhalesWide
    case regsBigPots
    case sizingTells
    case inverseQuestion
    case thinValueVsFish
    case donkLeadIsValue
    case giveUpVsStations
    case barrelVsFolders
    case handVsRange

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overfoldToPassiveAggression: "Overfold to passive players' aggression"
        case .giveWhalesRope: "Give whales rope"
        case .fireWithFire: "When you show aggression, even whales under-bluff"
        case .valueBetStations: "Put the money in for them"
        case .noBigBluffsVsStations: "Don't big-bluff stations"
        case .sizeDownRiverVsRecs: "Size down river value vs trying recs"
        case .bluffRecsBig: "Bluff trying recs and nits, and bluff big"
        case .rangeBetHalfPot: "Range-bet ½ pot on non-A-high flops"
        case .aceHighOverbetOrCheck: "A-high flops: overbet or check"
        case .isolateFishLimps: "Isolate fish limpers wide"
        case .respectLimpTraps: "Tighten up vs limp-trappers"
        case .limpRaiseIsNuts: "Limp-raise = AA/KK"
        case .cold4BetIsAces: "Cold 4-bets are AA/KK"
        case .dontOpenLimp: "Don't open-limp"
        case .liveOpenSizing: "Live sizing: open bigger"
        case .respectNitRanges: "Respect nit ranges"
        case .threeBetWhalesWide: "3-bet whales wide for value"
        case .regsBigPots: "Regs are honest in big pots"
        case .sizingTells: "Read the bet size"
        case .inverseQuestion: "The inverse question"
        case .thinValueVsFish: "Thin value vs fish"
        case .donkLeadIsValue: "Fish river donk-leads are value"
        case .giveUpVsStations: "Give up your air vs stations"
        case .barrelVsFolders: "Barrel the players who fold"
        case .handVsRange: "What does my hand want to do?"
        }
    }

    public var summary: String {
        switch self {
        case .overfoldToPassiveAggression:
            "Fish, trying recs and nits bluff far too little. When they bet big or raise, they almost always have it. Fold your bluff catchers, even when it feels like a lot."
        case .giveWhalesRope:
            "Whales over-bluff when you check to them. Check your medium-strength hands and bluff-catch. Let them hang themselves."
        case .fireWithFire:
            "Even aggressive players under-bluff once *you* take aggressive action. When a whale raises your bet, that's mostly value, so overfold."
        case .valueBetStations:
            "Stations don't fold pairs. Bet bigger with value (75–100%+ pot) on every street. 'What does my hand want?' It wants their stack."
        case .noBigBluffsVsStations:
            "Big bluffs into players who can't fold just lose money. If you bluff a fish, use small sizes that fold out their total air."
        case .sizeDownRiverVsRecs:
            "Trying recs make big folds on the river. They rarely see big bluffs, so they've learned to fold in big pots. Size your river value down so they pay you off."
        case .bluffRecsBig:
            "Trying recs and nits fold too much. Bluff them more often and use bigger sizes, because big bets are what make them fold."
        case .rangeBetHalfPot:
            "As the in-position preflop raiser heads-up, bet about ½ pot with your whole range on non-Ace-high flops. Villains fast-play too often and cap themselves by the turn or river, which sets up profitable barrels."
        case .aceHighOverbetOrCheck:
            "On Ace-high (non-monotone) flops, overbet 1.5–2x with AQ+ and selected bluffs, and check everything else. Fish have tons of Ax and rarely fast-play, and flopped top pair is easy to fold later."
        case .isolateFishLimps:
            "Weak players limp weak hands. Raise to isolate wide in position (any pair, suited connectors, suited and offsuit broadways) and size up: $15–20 plus $5 per extra limper."
        case .respectLimpTraps:
            "Some players (often nits and older regulars) limp AA/KK to trap. Against them, iso-raise much tighter, and overlimp or fold marginal hands."
        case .limpRaiseIsNuts:
            "A limp-raise at 1/2 is almost always AA/KK. Fold nearly everything, including JJ and AQ."
        case .cold4BetIsAces:
            "When someone cold 4-bets at 1/2, fold almost everything except AA and maybe KK."
        case .dontOpenLimp:
            "Open-limping at a live table invites the whole table in while you're out of position with no initiative. Raise or fold when you're first in."
        case .liveOpenSizing:
            "Live 1/2 players don't fold to small raises. Open to about $10–15 (5–7bb) and add $5 per limper. Go bigger still in straddled pots."
        case .respectNitRanges:
            "A nit's open is roughly 6–10% of hands, and their 3-bet is QQ+/AK. Fold the hands that dominate you (AJ, KQ, small pairs for set value only)."
        case .threeBetWhalesWide:
            "Whales open and call with junk. 3-bet a wide value range (AJ+, KQ, TT+) and size it big, since they'll call anyway."
        case .regsBigPots:
            "Regs bluff correctly in small and medium pots but play very straightforwardly once the pot gets big. Overfold to them in big pots, and use big bluffs to put them in uncomfortable spots."
        case .sizingTells:
            "About 75% of the live pool sizes by hand strength: big bet = strong, small or medium bet = medium hand or draw. Read the size before you look at your cards."
        case .inverseQuestion:
            "Value sizing, backwards: 'If they have top pair top kicker here, how much would I have to bet to make them fold it?' Then bet just under that. Against stations that line is huge, against trying recs and nits it's small, and it shrinks on the river. Reading their bets works the same way: ask how this player would bet the nuts, a medium hand and air, then compare that to what they actually did."
        case .thinValueVsFish:
            "Fish call rivers with worse pairs and ace-high. When they check to you, bet your second pair or weak top pair for value. A small-to-medium size works well."
        case .donkLeadIsValue:
            "A fish who suddenly leads into the preflop raiser on the river almost always has value. Fold your bluff catchers and put all your money in with strong hands."
        case .giveUpVsStations:
            "Barreling air into a station that already called just burns money. Give up and take the free card or showdown."
        case .barrelVsFolders:
            "Players who fold too much (trying recs, nits, regs in big pots) are the ones to keep barreling. Keep the pressure on with your equity."
        case .handVsRange:
            "Against fish and whales, don't think range vs range. Ask what your specific hand wants to do against their wide, sticky range."
        }
    }

    public var source: String {
        switch self {
        case .rangeBetHalfPot, .aceHighOverbetOrCheck, .overfoldToPassiveAggression, .giveWhalesRope, .fireWithFire,
             .valueBetStations, .sizeDownRiverVsRecs, .bluffRecsBig, .regsBigPots, .handVsRange, .noBigBluffsVsStations:
            "Hungry Horse–style player-type exploits"
        case .limpRaiseIsNuts, .cold4BetIsAces, .respectLimpTraps, .isolateFishLimps, .sizingTells, .donkLeadIsValue:
            "Live preflop/postflop exploit framework"
        default:
            "Live 1/2 fundamentals"
        }
    }
}

public struct TypePlaybook: Sendable {
    public let type: PlayerType
    public let tendencies: [String]
    public let tells: [String]
    public let exploits: [String]

    public static func of(_ t: PlayerType) -> TypePlaybook {
        switch t {
        case .whale:
            TypePlaybook(type: t,
                         tendencies: ["VPIP 60–75%, opens big and random ($20–40)", "Straddles", "Calls too much, folds too little", "Bluffs too much when given rope"],
                         tells: ["Chatty, splashy, rebuys", "Random huge opens", "Barrels when checked to", "Showed down air after betting"],
                         exploits: ["Hand vs range: what does your hand want?", "Value bet huge sizes", "Bluff much less, and small when you do", "Give rope: check medium hands and bluff-catch", "Overfold when they raise *your* bet (fire with fire)", "3-bet wide for value"])
        case .fish:
            TypePlaybook(type: t,
                         tendencies: ["VPIP 40–55%, PFR under 10%", "Limps and limp-calls", "Calls down with any pair or draw", "Almost never bluffs"],
                         tells: ["Small bet = medium hand or draw", "Big bet or raise = nuts", "River donk-lead = value", "Opens bigger with premiums"],
                         exploits: ["Isolate their limps wide in position", "Put the money in: big value sizes early", "Thin value bet rivers", "Bluff rarely, and only with small sizes", "OVERFOLD MASSIVELY to their aggression"])
        case .tryingRec:
            TypePlaybook(type: t,
                         tendencies: ["Tight-passive, 'by the book'", "Opens $10–15, c-bets value, checks air", "Folds to big bets", "Rarely bluffs, especially rivers"],
                         tells: ["Sizing tells: big = strong", "Checks medium hands, then calls once", "Folds a lot to turn and river pressure"],
                         exploits: ["Bigger value sizes early in the hand", "Size DOWN value on the river", "Bluff more often with larger sizes", "Overfold to their aggression"])
        case .nit:
            TypePlaybook(type: t,
                         tendencies: ["VPIP 10–15%", "Pairs and big cards only", "Often limp-traps AA/KK", "Raises = nutted. Never bluffs rivers"],
                         tells: ["Folds forever, then suddenly raises", "Limp-raise = AA/KK", "Open size jumps with premiums"],
                         exploits: ["Steal their blinds and attack their checks", "Fold to their 3-bets and limp-raises", "Barrel more: they fold one pair to pressure", "Don't pay off big postflop aggression"])
        case .reg:
            TypePlaybook(type: t,
                         tendencies: ["TAG, ~25/20", "Iso-raises fish, ranges small c-bets", "Bluffs in small and medium pots", "Straightforward in big pots"],
                         tells: ["Balanced sizes: size tells you little", "Positionally aware", "Raises draws on wet flops"],
                         exploits: ["Put yourself in their shoes", "Play your value like they play bluffs, and your bluffs like they play value", "Overfold in big pots", "Bluff big pots with big sizes to make them uncomfortable", "Avoid marginal spots. Go find the fish"])
        }
    }
}
