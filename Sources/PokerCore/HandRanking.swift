import Foundation

/// 169 starting hands ranked strongest-first by a blend of all-in equity vs 1 and vs 3 random hands
/// (live pots are often multiway). Precomputed offline with 40k/25k Monte Carlo runouts per hand.
public enum HandRanking {
    static let rows: [String] = [
        "AA KK QQ JJ TT 99 AKs AQs 88 AJs AKo ATs KQs",
        "AQo 77 KJs AJo A9s KTs KQo QJs ATo A8s 66 KJo QTs",
        "A7s K9s KTo QJo JTs A9o A6s Q9s K8s A4s A5s A8o 55",
        "QTo K7s A3s K9o A7o JTo K6s J9s A2s Q8s A5o A6o T9s",
        "K5s Q9o A4o K8o J8s K4s 44 Q7s T8s A3o J9o K3s 98s",
        "K7o Q6s T9o Q5s Q8o J7s A2o K6o K2s T7s K5o Q4s 33",
        "J8o 97s J6s Q7o Q3s T8o K4o 87s T6s J5s Q2s Q6o K3o",
        "98o J4s 96s 86s J3s J7o K2o T7o Q5o 22 T5s 76s 97o",
        "J2s Q4o 87o 65s T4s J6o 75s 95s 85s T3s Q3o T2s T6o",
        "J5o Q2o 54s J4o 74s 96o 94s 84s 64s 86o 76o 93s J3o",
        "T5o 53s 92s T4o J2o 85o 65o 63s 75o 95o 83s 43s 82s",
        "T3o 73s T2o 54o 94o 52s 72s 42s 84o 64o 93o 62s 74o",
        "92o 32s 53o 63o 73o 83o 43o 82o 52o 62o 72o 42o 32o",
    ]

    public static let order: [HandClass] = rows.flatMap { $0.split(separator: " ").compactMap { HandClass(String($0)) } }
}
