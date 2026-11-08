import Foundation

/// A player's holding in the equity calculator: exact cards, a range of hand classes, or any two cards.
public enum HoldingSpec: Sendable, Equatable {
    case cards([Card])
    case range(Set<HandClass>)
    case random

    /// All concrete 2-card combos for this spec, excluding dead cards.
    public func combos(excluding dead: UInt64) -> [[Card]] {
        switch self {
        case .cards(let c):
            return c.count == 2 && (mask(c) & dead) == 0 ? [c] : []
        case .random:
            var out: [[Card]] = []
            for i in 0..<52 {
                for j in (i + 1)..<52 {
                    let a = Card(id: UInt8(i)), b = Card(id: UInt8(j))
                    if (a.bit | b.bit) & dead == 0 { out.append([a, b]) }
                }
            }
            return out
        case .range(let set):
            var out: [[Card]] = []
            for h in set {
                for c in RangeParser.combos(of: h) where mask(c) & dead == 0 { out.append(c) }
            }
            return out
        }
    }
}

public struct EquityResult: Sendable, Equatable {
    public let equity: [Double]
    public let win: [Double]
    public let tie: [Double]
    public let samples: Int
    public let exact: Bool
}

public enum EquityCalculator {
    /// Exact enumeration when cheap, otherwise Monte Carlo.
    public static func run(players: [HoldingSpec], board: [Card], dead: [Card] = [], iterations: Int = 150_000, seed: UInt64 = 42) -> EquityResult? {
        guard players.count >= 2, board.count <= 5 else { return nil }
        let boardMask = mask(board)
        let deadMask = boardMask | mask(dead)
        let comboLists = players.map { $0.combos(excluding: deadMask) }
        guard comboLists.allSatisfy({ !$0.isEmpty }) else { return nil }
        let n = players.count
        var eq = [Double](repeating: 0, count: n)
        var win = [Double](repeating: 0, count: n)
        var tie = [Double](repeating: 0, count: n)
        var samples = 0

        func score(_ hands: [[Card]], _ fullBoard: UInt64) {
            var best = HandValue(raw: 0)
            var vals = [HandValue](repeating: HandValue(raw: 0), count: n)
            for k in 0..<n {
                vals[k] = HandEvaluator.evaluate(mask(hands[k]) | fullBoard)
                if vals[k] > best { best = vals[k] }
            }
            let winners = (0..<n).filter { vals[$0] == best }
            let share = 1.0 / Double(winners.count)
            for w in winners {
                eq[w] += share
                if winners.count == 1 { win[w] += 1 } else { tie[w] += 1 }
            }
            samples += 1
        }

        func finish(exact: Bool = true) -> EquityResult {
            let s = Double(samples)
            return EquityResult(equity: eq.map { $0 / s }, win: win.map { $0 / s }, tie: tie.map { $0 / s }, samples: samples, exact: exact)
        }

        // Exact: every player has exactly one combo and few runouts remain.
        let allFixed = comboLists.allSatisfy { $0.count == 1 }
        let need = 5 - board.count
        if allFixed {
            let used = comboLists.reduce(deadMask) { $0 | mask($1[0]) }
            let remaining = Card.all.filter { used & $0.bit == 0 }
            let hands = comboLists.map { $0[0] }
            let runouts = binomial(remaining.count, need)
            if runouts <= 200_000 {
                enumerate(remaining, need) { extra in score(hands, boardMask | extra) }
                return finish()
            }
        }

        var rng = SplitMix64(seed: seed)
        var attempts = 0
        while samples < iterations && attempts < iterations * 20 {
            attempts += 1
            var used = deadMask
            var hands: [[Card]] = []
            hands.reserveCapacity(n)
            var ok = true
            // Sample players in random order to avoid biasing the first player's range.
            for list in comboLists {
                let c = list[Int.random(in: 0..<list.count, using: &rng)]
                let m = mask(c)
                if m & used != 0 { ok = false; break }
                used |= m
                hands.append(c)
            }
            guard ok else { continue }
            var extra: UInt64 = 0
            var dealt = 0
            while dealt < need {
                let id = Int.random(in: 0..<52, using: &rng)
                let bit: UInt64 = 1 << UInt64(id)
                if (used | extra) & bit == 0 { extra |= bit; dealt += 1 }
            }
            score(hands, boardMask | extra)
        }
        guard samples > 0 else { return nil }
        return finish(exact: false)

    }

    static func binomial(_ n: Int, _ k: Int) -> Int {
        guard k >= 0 && k <= n else { return 0 }
        var r = 1
        for i in 0..<k { r = r * (n - i) / (i + 1) }
        return r
    }

    static func enumerate(_ cards: [Card], _ k: Int, _ body: (UInt64) -> Void) {
        if k == 0 { body(0); return }
        var idx = Array(0..<k)
        let n = cards.count
        while true {
            var m: UInt64 = 0
            for i in idx { m |= cards[i].bit }
            body(m)
            var i = k - 1
            while i >= 0 && idx[i] == n - k + i { i -= 1 }
            if i < 0 { return }
            idx[i] += 1
            for j in (i + 1)..<k { idx[j] = idx[j - 1] + 1 }
        }
    }
}

/// Parses standard range notation: "QQ+, AKs, ATs+, KJo+, 76s-54s, 22-66, 15%, random".
public enum RangeParser {
    public static func combos(of h: HandClass) -> [[Card]] {
        var out: [[Card]] = []
        let suits = Suit.allCases
        if h.isPair {
            for i in 0..<4 { for j in (i + 1)..<4 { out.append([Card(rankIndex: h.high, suit: suits[i]), Card(rankIndex: h.low, suit: suits[j])]) } }
        } else if h.suited {
            for s in suits { out.append([Card(rankIndex: h.high, suit: s), Card(rankIndex: h.low, suit: s)]) }
        } else {
            for s1 in suits { for s2 in suits where s1 != s2 { out.append([Card(rankIndex: h.high, suit: s1), Card(rankIndex: h.low, suit: s2)]) } }
        }
        return out
    }

    public static func parse(_ text: String) -> Set<HandClass>? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return nil }
        if trimmed == "random" || trimmed == "any" || trimmed == "100%" { return Set(HandClass.all) }
        var out = Set<HandClass>()
        for raw in trimmed.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let tok = String(raw).uppercased()
            if tok.hasSuffix("%"), let v = Double(tok.dropLast()) {
                let model = RangeModel.standard
                out.formUnion(HandClass.all.filter { model.inTop(v / 100, $0) })
                continue
            }
            if tok.contains("-") {
                let parts = tok.split(separator: "-").map(String.init)
                guard parts.count == 2, let a = HandClass(parts[0]), let b = HandClass(parts[1]) else { return nil }
                if a.isPair && b.isPair {
                    for r in min(a.high, b.high)...max(a.high, b.high) { out.insert(HandClass(high: r, low: r, suited: false)) }
                } else if a.high == b.high {
                    // K9s-K6s
                    for l in min(a.low, b.low)...max(a.low, b.low) { out.formUnion(variants(a.high, l, parts[0])) }
                } else if a.high - a.low == b.high - b.low {
                    // 76s-54s (same gap)
                    let gap = a.high - a.low
                    for h in min(a.high, b.high)...max(a.high, b.high) { out.formUnion(variants(h, h - gap, parts[0])) }
                } else {
                    return nil
                }
                continue
            }
            let plus = tok.hasSuffix("+")
            let body = plus ? String(tok.dropLast()) : tok
            guard let h = HandClass(body) else { return nil }
            if h.isPair {
                for r in h.high...(plus ? 12 : h.high) { out.insert(HandClass(high: r, low: r, suited: false)) }
            } else {
                for l in h.low...(plus ? h.high - 1 : h.low) { out.formUnion(variants(h.high, l, body)) }
            }
        }
        return out.isEmpty ? nil : out
    }

    /// "AK" → both suited and offsuit, "AKs" → suited, "AKo" → offsuit.
    static func variants(_ high: Int, _ low: Int, _ token: String) -> Set<HandClass> {
        let t = token.uppercased()
        if t.hasSuffix("S") { return [HandClass(high: high, low: low, suited: true)] }
        if t.hasSuffix("O") { return [HandClass(high: high, low: low, suited: false)] }
        return [HandClass(high: high, low: low, suited: true), HandClass(high: high, low: low, suited: false)]
    }

    public static func format(_ set: Set<HandClass>) -> String {
        RangeModel.standard.order.filter { set.contains($0) }.map(\.description).joined(separator: ", ")
    }

    public static func comboCount(_ set: Set<HandClass>) -> Int { set.reduce(0) { $0 + $1.combos } }

    /// Compact standard notation, e.g. "TT+, 66-44, ATs+, KJs+, AQo+, 76s".
    public static func compact(_ set: Set<HandClass>) -> String {
        var parts: [String] = []
        func runs(_ values: [Int]) -> [[Int]] {
            var out: [[Int]] = []
            for v in values.sorted(by: >) {
                if let last = out.last?.last, last == v + 1 { out[out.count - 1].append(v) } else { out.append([v]) }
            }
            return out
        }
        let pairs = set.filter(\.isPair).map(\.high)
        for r in runs(pairs) {
            let hi = Card.rankChar(r.first!), lo = Card.rankChar(r.last!)
            if r.count == 1 { parts.append(hi + hi) } else if r.first! == 12 { parts.append(lo + lo + "+") } else { parts.append("\(hi)\(hi)-\(lo)\(lo)") }
        }
        for suited in [true, false] {
            let suffix = suited ? "s" : "o"
            for high in stride(from: 12, through: 1, by: -1) {
                let kickers = set.filter { !$0.isPair && $0.suited == suited && $0.high == high }.map(\.low)
                let h = Card.rankChar(high)
                for r in runs(kickers) {
                    let top = Card.rankChar(r.first!), bottom = Card.rankChar(r.last!)
                    if r.count == 1 { parts.append(h + top + suffix) } else if r.first! == high - 1 { parts.append(h + bottom + suffix + "+") } else {
                        parts.append(h + top + suffix + "-" + h + bottom + suffix)
                    }
                }
            }
        }
        return parts.joined(separator: ", ")
    }
}
