import Foundation

public struct PlayerStats: Sendable, Codable, Equatable {
    public var hands = 0
    public var vpip = 0
    public var pfr = 0
    public var limps = 0
    public var threeBetOpp = 0
    public var threeBets = 0
    public var sawFlop = 0
    public var cbetOpp = 0
    public var cbets = 0
    public var foldToCbetOpp = 0
    public var foldToCbet = 0
    public var postflopAggressive = 0
    public var postflopCalls = 0
    public var wtsd = 0
    public var wonAtShowdown = 0
    public var straddles = 0
    /// Times this player was seen limping and then raising (the classic AA/KK trap).
    public var limpRaises = 0

    public init() {}

    static func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "–" : "\(Int((Double(a) / Double(b) * 100).rounded()))" }

    public var vpipText: String { Self.pct(vpip, hands) }
    public var pfrText: String { Self.pct(pfr, hands) }
    public var threeBetText: String { Self.pct(threeBets, threeBetOpp) }
    public var limpText: String { Self.pct(limps, hands) }
    public var cbetText: String { Self.pct(cbets, cbetOpp) }
    public var foldToCbetText: String { Self.pct(foldToCbet, foldToCbetOpp) }
    public var wtsdText: String { Self.pct(wtsd, sawFlop) }
    public var afText: String {
        postflopCalls == 0 ? (postflopAggressive > 0 ? "∞" : "–") : String(format: "%.1f", Double(postflopAggressive) / Double(postflopCalls))
    }
    public var vpipValue: Double { hands == 0 ? 0 : Double(vpip) / Double(hands) }
    public var pfrValue: Double { hands == 0 ? 0 : Double(pfr) / Double(hands) }
}

extension PlayerStats {
    /// Sums two stat lines (lifetime totals, per-type pools). Update this when adding a field.
    public func adding(_ o: PlayerStats) -> PlayerStats {
        var s = self
        s.hands += o.hands; s.vpip += o.vpip; s.pfr += o.pfr; s.limps += o.limps
        s.threeBetOpp += o.threeBetOpp; s.threeBets += o.threeBets; s.sawFlop += o.sawFlop
        s.cbetOpp += o.cbetOpp; s.cbets += o.cbets; s.foldToCbetOpp += o.foldToCbetOpp; s.foldToCbet += o.foldToCbet
        s.postflopAggressive += o.postflopAggressive; s.postflopCalls += o.postflopCalls
        s.wtsd += o.wtsd; s.wonAtShowdown += o.wonAtShowdown; s.straddles += o.straddles; s.limpRaises += o.limpRaises
        return s
    }
}

extension PlayerStats {
    /// Tolerant decoding: a field added later decodes as 0 instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        self.init()
        hands = v(.hands); vpip = v(.vpip); pfr = v(.pfr); limps = v(.limps)
        threeBetOpp = v(.threeBetOpp); threeBets = v(.threeBets); sawFlop = v(.sawFlop)
        cbetOpp = v(.cbetOpp); cbets = v(.cbets); foldToCbetOpp = v(.foldToCbetOpp); foldToCbet = v(.foldToCbet)
        postflopAggressive = v(.postflopAggressive); postflopCalls = v(.postflopCalls)
        wtsd = v(.wtsd); wonAtShowdown = v(.wonAtShowdown); straddles = v(.straddles); limpRaises = v(.limpRaises)
    }
}

public struct Evidence: Sendable, Codable, Identifiable, Equatable {
    public enum Kind: String, Sendable, Codable { case preflop, showdown, sizing }
    public let id: UUID
    public let handNumber: Int
    public let playerID: UUID
    public let seat: Int
    public let kind: Kind
    public let text: String
}

/// Collects what you'd actually observe at a live table: frequencies, sizes, and tabled hands.
public struct ReadTracker: Sendable, Codable {
    public private(set) var stats: [UUID: PlayerStats] = [:]
    public private(set) var evidence: [Evidence] = []

    public init() {}

    public func stats(for id: UUID) -> PlayerStats { stats[id] ?? PlayerStats() }
    public func evidence(for id: UUID) -> [Evidence] { evidence.filter { $0.playerID == id } }

    public mutating func reset() {
        stats = [:]
        evidence = []
    }

    public mutating func record(_ hand: HandState, ids: [Int: UUID]) {
        let bb = hand.config.bigBlind
        let pre = hand.actions(on: .preflop)
        let flop = hand.actions(on: .flop)

        for p in hand.players {
            guard let id = ids[p.seat] else { continue }
            var s = stats[id] ?? PlayerStats()
            s.hands += 1
            var raisesBefore = 0
            var limpedFirst = false
            var firstVoluntary = true
            for a in pre {
                if a.seat == p.seat {
                    if a.type == .postStraddle { s.straddles += 1 }
                    if a.type.isVoluntary {
                        if raisesBefore == 1 {
                            s.threeBetOpp += 1
                            if a.type == .raise { s.threeBets += 1 }
                        }
                        if firstVoluntary && a.type == .call && raisesBefore == 0 {
                            s.limps += 1
                            limpedFirst = true
                        }
                        if a.type == .raise && raisesBefore == 0 {
                            let unit = hand.straddleSeat != nil ? hand.config.straddleAmount : bb
                            if a.toAmount >= unit * 8 {
                                add(hand, id, p.seat, .preflop, "Opened big to $\(a.toAmount)\(hand.straddleSeat != nil ? " (straddled pot)" : "") from \(hand.position(of: p.seat).short)")
                            } else if a.toAmount <= unit * 3 {
                                add(hand, id, p.seat, .preflop, "Min/small open to $\(a.toAmount) from \(hand.position(of: p.seat).short)")
                            }
                        }
                        if a.type == .raise && limpedFirst && raisesBefore >= 1 {
                            s.limpRaises += 1
                            add(hand, id, p.seat, .preflop, "Limp-raised to $\(a.toAmount)!")
                        }
                        if a.type == .raise && raisesBefore >= 2 {
                            add(hand, id, p.seat, .preflop, "\(raisesBefore + 1)-bet to $\(a.toAmount)")
                        }
                        firstVoluntary = false
                    }
                }
                if a.type == .raise || a.type == .bet { raisesBefore += 1 }
            }
            if pre.contains(where: { $0.seat == p.seat && ($0.type == .call || $0.type == .raise) }) { s.vpip += 1 }
            if pre.contains(where: { $0.seat == p.seat && $0.type == .raise }) { s.pfr += 1 }

            let sawFlop = hand.board.count >= 3 && !pre.contains { $0.seat == p.seat && $0.type == .fold }
            if sawFlop {
                s.sawFlop += 1
                if hand.preflopRaiser == p.seat {
                    if let firstBetIdx = flop.firstIndex(where: { $0.type == .bet }) {
                        if flop[firstBetIdx].seat == p.seat { s.cbetOpp += 1; s.cbets += 1 } else if flop.prefix(firstBetIdx).contains(where: { $0.seat == p.seat }) { s.cbetOpp += 1 }
                    } else if flop.contains(where: { $0.seat == p.seat }) {
                        s.cbetOpp += 1
                    }
                }
                if let pfr = hand.preflopRaiser, pfr != p.seat,
                   let cb = flop.first(where: { $0.type == .bet }), cb.seat == pfr,
                   let resp = flop.first(where: { $0.seat == p.seat && $0.index > cb.index }) {
                    s.foldToCbetOpp += 1
                    if resp.type == .fold { s.foldToCbet += 1 }
                }
            }
            for a in hand.actions where a.street > .preflop && a.seat == p.seat {
                if a.type.isAggressive { s.postflopAggressive += 1 }
                if a.type == .call { s.postflopCalls += 1 }
            }
            if let result = hand.result, result.wentToShowdown, result.shown[p.seat] != nil {
                s.wtsd += 1
                if result.pots.contains(where: { $0.winners.contains(p.seat) }) { s.wonAtShowdown += 1 }
                add(hand, id, p.seat, .showdown, showdownNarrative(hand, seat: p.seat))
            }
            stats[id] = s
        }
        if evidence.count > 600 { evidence.removeFirst(evidence.count - 600) }
    }

    private mutating func add(_ hand: HandState, _ id: UUID, _ seat: Int, _ kind: Evidence.Kind, _ text: String) {
        evidence.append(Evidence(id: UUID(), handNumber: hand.handNumber, playerID: id, seat: seat, kind: kind, text: text))
    }

    /// "Showed 9♠8♠ (Middle pair): Flop called $10 (50%) · Turn called $25 (60%) · River bet $90 (110%)"
    public static func line(_ hand: HandState, seat: Int) -> String {
        var parts: [String] = []
        for street in [Street.flop, .turn, .river] {
            let acts = hand.actions(on: street).filter { $0.seat == seat }
            guard !acts.isEmpty else { continue }
            let desc = acts.map { describe($0) }.joined(separator: ", ")
            parts.append("\(street.name) \(desc)")
        }
        return parts.joined(separator: " · ")
    }

    public static func describe(_ a: PlayerAction) -> String {
        switch a.type {
        case .check: return "check"
        case .fold: return "fold"
        case .call:
            let pct = a.potBefore > 0 ? Int(Double(a.toCallBefore) / Double(max(1, a.potBefore - a.toCallBefore)) * 100) : 0
            return "call $\(a.added)\(a.street == .preflop ? "" : " (\(pct)% bet)")"
        case .bet:
            let pct = a.potBefore > 0 ? Int(Double(a.added) / Double(a.potBefore) * 100) : 0
            return "bet $\(a.added) (\(pct)% pot)\(a.isAllIn ? " all-in" : "")"
        case .raise:
            return "raise to $\(a.toAmount)\(a.isAllIn ? " all-in" : "")"
        case .postSB: return "post SB $\(a.added)"
        case .postBB: return "post BB $\(a.added)"
        case .postStraddle: return "straddle $\(a.added)"
        }
    }

    func showdownNarrative(_ hand: HandState, seat: Int) -> String {
        guard let p = hand.player(seat: seat) else { return "" }
        let cards = p.hole.map(\.pretty).joined()
        let made = hand.board.count >= 3 ? HandRead.describe(hole: p.hole, board: hand.board, value: HandEvaluator.evaluate(p.hole + hand.board)) : ""
        let preLine = hand.actions(on: .preflop).filter { $0.seat == seat && $0.type.isVoluntary }.map { Self.describe($0) }.joined(separator: ", ")
        let post = Self.line(hand, seat: seat)
        var text = "Showed \(cards) — \(made). Pre: \(preLine.isEmpty ? "–" : preLine)"
        if !post.isEmpty { text += " · " + post }
        return text
    }
}
