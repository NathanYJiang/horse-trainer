import Foundation
import PokerCore

/// One Cash Game hand, kept small so years of hands fit in one JSON file.
struct TrackedHand: Codable {
    var session: UUID
    var date: Date
    var net: Int
    var position: String
    var showdown: Bool
    /// Types of opponents who voluntarily played the pot (revealed only after the fact, in the tracker).
    var vs: [String]
    var good: Int
    var inaccuracies: Int
    var mistakes: Int
}

struct TrackedSession: Codable, Identifiable {
    var id: UUID
    var start: Date
    var end: Date
    var seats: Int
    var preset: String
    var hands = 0
    var net = 0
    var good = 0
    var inaccuracies = 0
    var mistakes = 0
    var hero = PlayerStats()

    var bb100: Double { hands == 0 ? 0 : Double(net) / 2 / Double(hands) * 100 }
}

struct TrackerData: Codable {
    var sessions: [TrackedSession] = []
    var hands: [TrackedHand] = []
}

/// Long-run results for label-free Cash Game tables, like an online tracker (HM / PT) for the simulated 1/2 pool.
@MainActor
@Observable
final class TrackerStore {
    private(set) var data = TrackerData()

    nonisolated static let bigBlind = 2.0
    /// Typical live 1/2 pace, used to translate hands into "live hours".
    static let liveHandsPerHour = 30.0

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HorseTrainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tracker.json")
    }

    init() {
        if let d = try? Data(contentsOf: url), let t = try? JSONDecoder().decode(TrackerData.self, from: d) { data = t }
    }

    /// Snapshots/tests: keep data in memory only.
    var persist = true

    func save() {
        guard persist else { return }
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    func record(hand h: HandState, heroSeat: Int, notes: [CoachNote], sessionID: UUID, seats: Int, preset: String,
                heroStats: PlayerStats, profiles: [Int: Profile]) {
        guard let result = h.result, let hero = h.player(seat: heroSeat) else { return }
        let net = result.net[heroSeat] ?? 0
        let played = h.actions.contains { $0.seat == heroSeat && ($0.type == .call || $0.type.isAggressive) }
        let vs = !played ? [] : Set(h.actions.filter { $0.seat != heroSeat && ($0.type == .call || $0.type.isAggressive) }.map(\.seat))
            .compactMap { profiles[$0]?.type.rawValue }.sorted()
        let g = notes.filter { $0.grade == .good }.count
        let i = notes.filter { $0.grade == .inaccuracy }.count
        let m = notes.filter { $0.grade == .mistake }.count
        data.hands.append(TrackedHand(session: sessionID, date: Date(), net: net, position: h.position(of: heroSeat).short,
                                      showdown: result.wentToShowdown && !hero.folded, vs: vs, good: g, inaccuracies: i, mistakes: m))
        if let k = data.sessions.firstIndex(where: { $0.id == sessionID }) {
            data.sessions[k].end = Date()
            data.sessions[k].hands += 1
            data.sessions[k].net += net
            data.sessions[k].good += g
            data.sessions[k].inaccuracies += i
            data.sessions[k].mistakes += m
            data.sessions[k].hero = heroStats
        } else {
            var s = TrackedSession(id: sessionID, start: Date(), end: Date(), seats: seats, preset: preset)
            s.hands = 1
            s.net = net
            s.good = g
            s.inaccuracies = i
            s.mistakes = m
            s.hero = heroStats
            data.sessions.append(s)
        }
        save()
    }

    // MARK: - Aggregates

    var totalHands: Int { data.hands.count }
    var totalNet: Int { data.hands.reduce(0) { $0 + $1.net } }
    var bb100: Double { totalHands == 0 ? 0 : Double(totalNet) / Self.bigBlind / Double(totalHands) * 100 }

    /// 95% confidence half-width on bb/100, from the per-hand standard deviation.
    var bb100Interval: Double? {
        let n = Double(totalHands)
        guard n >= 30 else { return nil }
        let xs = data.hands.map { Double($0.net) / Self.bigBlind }
        let mean = xs.reduce(0, +) / n
        let sd = sqrt(xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1))
        return 1.96 * sd / sqrt(n) * 100
    }

    /// Hands needed for the 95% interval to shrink to ±`target` bb/100.
    func handsNeeded(for target: Double) -> Int? {
        let n = Double(totalHands)
        guard n >= 30 else { return nil }
        let xs = data.hands.map { Double($0.net) / Self.bigBlind }
        let mean = xs.reduce(0, +) / n
        let sd = sqrt(xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1))
        return Int(pow(1.96 * sd * 100 / target, 2))
    }

    var lifetimeHero: PlayerStats {
        data.sessions.reduce(PlayerStats()) { $0.adding($1.hero) }
    }

    var lifetimeSessionStats: SessionStats {
        var s = SessionStats()
        s.hands = totalHands
        s.net = totalNet
        s.good = data.sessions.reduce(0) { $0 + $1.good }
        s.inaccuracies = data.sessions.reduce(0) { $0 + $1.inaccuracies }
        s.mistakes = data.sessions.reduce(0) { $0 + $1.mistakes }
        return s
    }

    struct Row: Identifiable {
        var id: String { label }
        let label: String
        let hands: Int
        let net: Int
        var bb100: Double { hands == 0 ? 0 : Double(net) / TrackerStore.bigBlind / Double(hands) * 100 }
    }

    var byPosition: [Row] {
        let order = Position.allCases.map(\.short)
        let groups = Dictionary(grouping: data.hands, by: \.position)
        return order.compactMap { p in groups[p].map { Row(label: p, hands: $0.count, net: $0.reduce(0) { $0 + $1.net }) } }
    }

    var byOpponentType: [(PlayerType, Row)] {
        PlayerType.allCases.compactMap { t in
            let hs = data.hands.filter { $0.vs.contains(t.rawValue) }
            return hs.isEmpty ? nil : (t, Row(label: t.name, hands: hs.count, net: hs.reduce(0) { $0 + $1.net }))
        }
    }

    struct GraphPoint: Identifiable {
        var id: String { "\(series)-\(hand)" }
        let hand: Int
        let value: Double
        let series: String
    }

    /// Cumulative won (total, showdown, non-showdown) in dollars, thinned to ~600 points per series.
    var graph: [GraphPoint] {
        guard !data.hands.isEmpty else { return [] }
        let step = max(1, data.hands.count / 600)
        var total = 0, sd = 0, nsd = 0
        var out: [GraphPoint] = [GraphPoint(hand: 0, value: 0, series: "Total"), GraphPoint(hand: 0, value: 0, series: "Showdown"),
                                 GraphPoint(hand: 0, value: 0, series: "Non-showdown")]
        for (i, h) in data.hands.enumerated() {
            total += h.net
            if h.showdown { sd += h.net } else { nsd += h.net }
            if (i + 1) % step == 0 || i == data.hands.count - 1 {
                out.append(GraphPoint(hand: i + 1, value: Double(total), series: "Total"))
                out.append(GraphPoint(hand: i + 1, value: Double(sd), series: "Showdown"))
                out.append(GraphPoint(hand: i + 1, value: Double(nsd), series: "Non-showdown"))
            }
        }
        return out
    }
}
