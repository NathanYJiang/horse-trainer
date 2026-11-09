import Foundation

/// What you can actually know about a player: a read built from the hands you've watched.
/// The coach grades against this, not against the bot's hidden type and quirks.
public enum TypeEstimate {
    /// How common each type is in a typical live 1/2 game (the read before you've seen a hand).
    public static let population: [PlayerType: Double] = [.whale: 0.1, .fish: 0.3, .tryingRec: 0.22, .nit: 0.18, .reg: 0.2]

    /// Measured VPIP / PFR of each type in the calibrated pool.
    static let profile: [PlayerType: (vpip: Double, pfr: Double)] = [
        .whale: (0.71, 0.19), .fish: (0.51, 0.045), .tryingRec: (0.23, 0.08), .nit: (0.12, 0.05), .reg: (0.24, 0.18),
    ]

    /// Probability of each type given observed VPIP and PFR counts (binomial likelihoods, population prior).
    public static func posterior(_ s: PlayerStats) -> [PlayerType: Double] {
        var logp: [PlayerType: Double] = [:]
        for t in PlayerType.allCases {
            let (v, r) = profile[t]!
            let n = Double(s.hands)
            let ll = Double(s.vpip) * log(v) + (n - Double(s.vpip)) * log(1 - v)
                + Double(s.pfr) * log(r) + (n - Double(s.pfr)) * log(1 - r)
            logp[t] = log(population[t]!) + ll
        }
        let m = logp.values.max() ?? 0
        let unnorm = logp.mapValues { exp($0 - m) }
        let z = unnorm.values.reduce(0, +)
        return unnorm.mapValues { $0 / z }
    }

    public static func likely(_ s: PlayerStats) -> (type: PlayerType, confidence: Double) {
        let post = posterior(s)
        let best = PlayerType.allCases.max { post[$0]! < post[$1]! }!
        return (best, post[best]!)
    }

    /// The profile the coach should assume for a player: the likely type, with quirks only if you've seen them.
    public static func perceivedProfile(type: PlayerType, observed s: PlayerStats) -> Profile {
        var p = Profile.base(type)
        p.limpTrapPremiums = s.limpRaises > 0 ? 0.5 : 0
        return p
    }

    /// "likely Fish", "probably a Reg", or "no read yet" for the coach's wording.
    public static func label(_ s: PlayerStats) -> String {
        guard s.hands >= 8 else { return "no read yet" }
        let (t, c) = likely(s)
        return c >= 0.75 ? "likely \(t.name)" : "maybe \(t.name)"
    }
}
