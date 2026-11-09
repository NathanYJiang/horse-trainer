import Foundation
import PokerCore

/// One Cash Game hand, kept small so years of hands fit in one JSON file.
struct TrackedHand: Codable {
    var session: UUID
    var date: Date
    var net: Int
    var position: String
    var showdown: Bool
    /// Types of opponents who voluntarily played the pot with the hero (shown only after the session).
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

    var bb100: Double { hands == 0 ? 0 : Double(net) / TrackerStore.bigBlind / Double(hands) * 100 }
}

/// Simulated decision quality for one session (dollars).
struct SimTotals: Codable {
    var decisions = 0
    var evLost = 0.0
    var readCost = 0.0
}

struct TrackerData: Codable {
    var sessions: [TrackedSession] = []
    var hands: [TrackedHand] = []
    /// Optional so older tracker files still decode.
    var sim: [UUID: SimTotals]?
}

/// Long-run results for label-free Cash Game tables, like an online tracker (HM / PT) for the simulated 1/2 pool.
/// The Cash session in progress is sealed: it's recorded hand by hand but stays out of every number until it ends,
/// so nothing here leaks opponent types or coach grades mid-session.
@MainActor
@Observable
final class TrackerStore {
    private(set) var data = TrackerData()
    private(set) var sealed: UUID?

    nonisolated static let bigBlind = 2.0
    /// Typical live 1/2 pace, used to translate hands into "live hours".
    static let liveHandsPerHour = 30.0

    /// Snapshots/tests/autoplay: keep data in memory only.
    var persist = true
    private var unsaved = 0

    // Cached aggregates over unsealed data (recomputed when data changes, not on every render).
    private(set) var sessions: [TrackedSession] = []
    private(set) var totalHands = 0
    private(set) var totalNet = 0
    private(set) var bb100 = 0.0
    private(set) var bb100Interval: Double?
    private(set) var sdPerHand: Double?
    private(set) var lifetimeHero = PlayerStats()
    private(set) var lifetimeSessionStats = SessionStats()
    private(set) var byPosition: [Row] = []
    private(set) var byOpponentType: [(PlayerType, Row)] = []
    private(set) var graph: [GraphPoint] = []
    private(set) var simTotals = SimTotals()
    /// Hands in the sessions that have simulated decisions (the denominator for per-100 rates).
    private(set) var simHands = 0

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HorseTrainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tracker.json")
    }

    init() {
        if let d = try? Data(contentsOf: url) {
            if let t = try? JSONDecoder().decode(TrackerData.self, from: d) {
                data = t
            } else {
                // Never overwrite history we can't read: set it aside and start fresh.
                let stamp = Int(Date().timeIntervalSince1970)
                try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("tracker-unreadable-\(stamp).json"))
            }
        }
        refresh()
    }

    func save() {
        unsaved = 0
        guard persist else { return }
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }

    /// Hide this session from every aggregate until `unseal()`.
    func seal(_ session: UUID) {
        sealed = session
        refresh()
    }

    func unseal() {
        sealed = nil
        refresh()
        save()
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
        if sessionID != sealed { refresh() }
        unsaved += 1
        if unsaved >= 10 { save() }
    }

    func addSim(_ e: SimEval, sessionID: UUID) {
        var t = data.sim?[sessionID] ?? SimTotals()
        t.decisions += 1
        t.evLost += e.loss(e.read)
        t.readCost += e.readCost()
        data.sim = (data.sim ?? [:]).merging([sessionID: t]) { $1 }
        if sessionID != sealed { refresh() }
        unsaved += 1
        if unsaved >= 10 { save() }
    }

    func sim(for session: UUID) -> SimTotals? { data.sim?[session] }

    /// bb per 100 hands, from a dollar total.
    func per100(_ dollars: Double, hands: Int) -> Double? {
        hands == 0 ? nil : dollars / Self.bigBlind / Double(hands) * 100
    }

    // MARK: - Aggregates

    struct Row: Identifiable {
        var id: String { label }
        let label: String
        let hands: Int
        let net: Int
        var bb100: Double { hands == 0 ? 0 : Double(net) / TrackerStore.bigBlind / Double(hands) * 100 }
    }

    struct GraphPoint: Identifiable {
        var id: String { "\(series)-\(hand)" }
        let hand: Int
        let value: Double
        let series: String
    }

    /// Hands needed for the 95% interval to shrink to ±`target` bb/100.
    func handsNeeded(for target: Double) -> Int? {
        sdPerHand.map { WinRate.handsNeeded(sdPerHand: $0, target: target) }
    }

    private func refresh() {
        let hands = data.hands.filter { $0.session != sealed }
        sessions = data.sessions.filter { $0.id != sealed }
        totalHands = hands.count
        totalNet = hands.reduce(0) { $0 + $1.net }
        let wr = WinRate.bb100(nets: hands.map(\.net), bigBlind: Int(Self.bigBlind))
        bb100 = wr.rate
        bb100Interval = wr.interval
        sdPerHand = wr.sdPerHand
        lifetimeHero = sessions.reduce(PlayerStats()) { $0.adding($1.hero) }
        var s = SessionStats()
        s.hands = totalHands
        s.net = totalNet
        s.good = sessions.reduce(0) { $0 + $1.good }
        s.inaccuracies = sessions.reduce(0) { $0 + $1.inaccuracies }
        s.mistakes = sessions.reduce(0) { $0 + $1.mistakes }
        lifetimeSessionStats = s
        let simmed = sessions.filter { data.sim?[$0.id] != nil }
        simHands = simmed.reduce(0) { $0 + $1.hands }
        simTotals = simmed.compactMap { data.sim?[$0.id] }.reduce(into: SimTotals()) {
            $0.decisions += $1.decisions; $0.evLost += $1.evLost; $0.readCost += $1.readCost
        }

        let groups = Dictionary(grouping: hands, by: \.position)
        byPosition = Position.allCases.map(\.short).compactMap { p in
            groups[p].map { Row(label: p, hands: $0.count, net: $0.reduce(0) { $0 + $1.net }) }
        }
        byOpponentType = PlayerType.allCases.compactMap { t in
            let hs = hands.filter { $0.vs.contains(t.rawValue) }
            return hs.isEmpty ? nil : (t, Row(label: t.name, hands: hs.count, net: hs.reduce(0) { $0 + $1.net }))
        }

        // Cumulative won (total, showdown, non-showdown) in dollars, thinned to ~600 points per series.
        var pts: [GraphPoint] = []
        if !hands.isEmpty {
            let step = max(1, hands.count / 600)
            var total = 0, sd = 0, nsd = 0
            pts = ["Total", "Showdown", "Non-showdown"].map { GraphPoint(hand: 0, value: 0, series: $0) }
            for (i, h) in hands.enumerated() {
                total += h.net
                if h.showdown { sd += h.net } else { nsd += h.net }
                if (i + 1) % step == 0 || i == hands.count - 1 {
                    pts.append(GraphPoint(hand: i + 1, value: Double(total), series: "Total"))
                    pts.append(GraphPoint(hand: i + 1, value: Double(sd), series: "Showdown"))
                    pts.append(GraphPoint(hand: i + 1, value: Double(nsd), series: "Non-showdown"))
                }
            }
        }
        graph = pts
    }
}
