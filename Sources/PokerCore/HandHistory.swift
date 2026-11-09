import Foundation

public enum HandHistoryFormatter {
    /// Plain-text hand history. Villain types are included only when `revealTypes` is set (for the coach).
    public static func format(_ h: HandState, heroSeat: Int?, profiles: [Int: Profile], revealTypes: Bool, notes: [CoachNote] = []) -> String {
        var lines: [String] = []
        lines.append("Hand #\(h.handNumber) — NLHE $\(h.config.smallBlind)/$\(h.config.bigBlind) live\(h.straddleSeat != nil ? " (straddled $\(h.config.straddleAmount))" : "")")
        for p in h.players {
            var who = p.name
            if p.seat == heroSeat { who = "Hero" }
            var extra = ""
            if revealTypes, let t = profiles[p.seat]?.type { extra = " [\(t.name)]" }
            let cards = p.seat == heroSeat ? " — \(p.hole.map(\.pretty).joined())" : ""
            lines.append("  \(h.position(of: p.seat).short): \(who)\(extra) ($\(p.startingStack))\(cards)")
        }
        for street in [Street.preflop, .flop, .turn, .river] {
            let acts = h.actions(on: street)
            guard !acts.isEmpty || (street != .preflop && boardFor(street, h.board) != nil) else { continue }
            var header = street.name
            if let b = boardFor(street, h.board) { header += " [\(b.map(\.pretty).joined(separator: " "))]" }
            if let first = acts.first { header += " (pot $\(first.potBefore))" }
            lines.append(header)
            for a in acts {
                let who = a.seat == heroSeat ? "Hero" : (h.player(seat: a.seat)?.name ?? "?")
                lines.append("  \(who): \(ReadTracker.describe(a))")
                if let n = notes.first(where: { $0.actionIndex == a.index }) {
                    lines.append("    ↳ coach: \(n.grade.label) — \(n.headline)")
                }
            }
        }
        if let r = h.result {
            if r.wentToShowdown {
                lines.append("Showdown")
                for (seat, desc) in r.shown.sorted(by: { $0.key < $1.key }) {
                    let p = h.player(seat: seat)!
                    lines.append("  \(seat == heroSeat ? "Hero" : p.name) shows \(p.hole.map(\.pretty).joined()) — \(desc)")
                }
            }
            for pot in r.pots {
                let names = pot.winners.map { $0 == heroSeat ? "Hero" : (h.player(seat: $0)?.name ?? "?") }
                lines.append("  \(names.joined(separator: " & ")) win\(names.count == 1 ? "s" : "") $\(pot.amount)\(pot.winningHand.map { " with \($0)" } ?? "")")
            }
            if r.rake > 0 { lines.append("  Rake $\(r.rake)") }
            if let hs = heroSeat, let net = r.net[hs] { lines.append("Hero net: \(net >= 0 ? "+" : "")$\(net)") }
        }
        return lines.joined(separator: "\n")
    }

    static func boardFor(_ s: Street, _ board: [Card]) -> [Card]? {
        switch s {
        case .flop: board.count >= 3 ? Array(board.prefix(3)) : nil
        case .turn: board.count >= 4 ? Array(board.prefix(4)) : nil
        case .river: board.count >= 5 ? board : nil
        default: nil
        }
    }
}
