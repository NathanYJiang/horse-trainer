import Foundation
import PokerCore

enum TableMode {
    case play, reads
}

struct HandRecord: Identifiable {
    var id: Int { state.handNumber }
    let state: HandState
    let notes: [CoachNote]
    let heroNet: Int?
    let heroInHand: Bool
    let publicText: String
    let coachText: String
}

enum Premove: Equatable {
    case checkFold, check, callAny
}

struct SpotScore {
    var spots = 0
    var good = 0
    var bad = 0
}

struct QuizRow: Identifiable {
    var id: UUID { bot.id }
    let bot: BotPlayer
    let seat: Int?
    let guess: PlayerType?
    let stats: PlayerStats
    var correct: Bool { guess == bot.type }
}

struct QuizResult {
    let rows: [QuizRow]
    let handsObserved: Int
    var score: Int { rows.filter(\.correct).count }
}

@MainActor
@Observable
final class GameController {
    let mode: TableMode
    let settings: AppSettings
    let store: ProgressStore
    private(set) var session: TableSession
    private(set) var hand: HandState?
    private(set) var notesThisHand: [CoachNote] = []
    private(set) var history: [HandRecord] = []
    private(set) var lastAction: [Int: String] = [:]
    private(set) var quiz: QuizResult?
    var showHUD = false
    var heroSittingOut: Bool
    var tags: [UUID: PlayerType] = [:]
    var playerNotes: [UUID: String] = [:]
    private var loopTask: Task<Void, Never>?
    private var dealTask: Task<Void, Never>?

    /// Pre-selected action that fires as soon as it's the hero's turn.
    var premove: Premove?

    /// Spot practice: `.any` plays full hands; anything else fast-forwards to that situation.
    var spotKind: SpotKind = .any
    var spotVillain: PlayerType?
    private(set) var findingSpot = false
    private(set) var spotMessage: String?
    private(set) var spotVillains: [Int] = []
    private(set) var spotScore = SpotScore()
    private(set) var currentHandIsSpot = false
    var spotMode: Bool { spotKind != .any }

    let heroSeat = TableSession.heroSeat

    init(mode: TableMode, preset: TablePreset, seats: Int = 9, settings: AppSettings, store: ProgressStore) {
        self.mode = mode
        self.settings = settings
        self.store = store
        session = TableSession(preset: preset, seats: seats)
        heroSittingOut = mode == .reads
    }

    // MARK: - Derived state

    var isHeroTurn: Bool { hand.map { !$0.isComplete && $0.currentSeat == heroSeat } ?? false }
    var legal: LegalActions? { isHeroTurn ? hand?.legalActions() : nil }
    var handInProgress: Bool { hand.map { !$0.isComplete } ?? false }
    var lastRecord: HandRecord? { history.first }
    var preset: TablePreset { session.preset }
    var stats: SessionStats { session.stats }
    var seats: [SeatInfo] { session.seats }
    var tracker: ReadTracker { session.tracker }
    var bbPer100: Double {
        guard session.stats.hands > 0 else { return 0 }
        return Double(session.stats.net) / Double(session.config.bigBlind) / Double(session.stats.hands) * 100
    }
    var heroInCurrentHand: Bool {
        guard let h = hand, let p = h.player(seat: heroSeat) else { return false }
        return !p.folded
    }

    func stack(of seat: Int) -> Int {
        if let h = hand, let p = h.player(seat: seat) { return p.stack }
        return session.seats[seat].stack
    }

    // MARK: - Flow

    func newTable(preset: TablePreset, seats: Int) {
        endSession()
        loopTask?.cancel()
        dealTask?.cancel()
        session = TableSession(preset: preset, seats: seats)
        hand = nil
        history = []
        notesThisHand = []
        lastAction = [:]
        tags = [:]
        playerNotes = [:]
        quiz = nil
        showHUD = false
        premove = nil
        spotScore = SpotScore()
        spotMessage = nil
        spotVillains = []
    }

    func dealNext() {
        guard !handInProgress, !findingSpot else { return }
        dealTask?.cancel()
        premove = nil
        session.heroStraddles = settings.heroStraddles
        if spotMode && !heroSittingOut {
            dealSpot()
            return
        }
        currentHandIsSpot = false
        spotVillains = []
        let h = session.startHand(heroSittingOut: heroSittingOut)
        hand = h
        notesThisHand = []
        lastAction = [:]
        for a in h.actions where a.type == .postStraddle { lastAction[a.seat] = "Straddle $\(a.added)" }
        runLoop()
    }

    func setSpot(_ kind: SpotKind, villain: PlayerType?) {
        spotKind = kind
        spotVillain = villain
        spotMessage = nil
        if !handInProgress && kind != .any && !heroSittingOut { dealNext() }
    }

    /// Fast-forwards (off the main thread) to a hand where the hero faces the chosen spot.
    private func dealSpot() {
        findingSpot = true
        spotMessage = nil
        let base = session, kind = spotKind, villain = spotVillain
        Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { SpotFinder.find(kind, against: villain, from: base) }.value
            guard let self else { return }
            self.findingSpot = false
            if self.spotKind != kind || self.spotVillain != villain {
                self.dealNext()
                return
            }
            guard let found, !self.handInProgress else {
                if found == nil { self.spotMessage = "Couldn't find that spot\(villain.map { " vs a \($0.name)" } ?? "") at this table. Try another filter or a new table." }
                return
            }
            self.session = found.session
            self.currentHandIsSpot = true
            self.spotVillains = found.villains
            self.notesThisHand = []
            var bubbles: [Int: String] = [:]
            for a in found.hand.actions where a.type.isVoluntary || a.type == .postStraddle {
                if a.type == .fold || a.street == found.hand.street { bubbles[a.seat] = Self.bubble(a) }
            }
            self.lastAction = bubbles
            self.hand = found.hand
            let autoActs = found.hand.actions.filter { $0.seat == self.heroSeat && $0.type.isVoluntary }
            self.spotMessage = autoActs.isEmpty ? nil
                : "Autopilot played your earlier streets: " + autoActs.map { "\($0.street.name) \(Self.bubble($0).lowercased())" }.joined(separator: ", ") + "."
            self.runLoop()
        }
    }

    private func runLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in await self?.advance() }
    }

    /// Debug/demo: `HT_AUTOPLAY=1` lets a reg-profile bot play the hero seat and auto-deals.
    static let autopilot = ProcessInfo.processInfo.environment["HT_AUTOPLAY"] != nil

    private func advance() async {
        while let h = hand, !h.isComplete {
            if h.currentSeat == heroSeat {
                if let pm = premove, let legal = h.legalActions() {
                    premove = nil
                    let d: Decision? = switch pm {
                    case .checkFold: legal.canCheck ? .check : .fold
                    case .check: legal.canCheck ? .check : nil
                    case .callAny: legal.canCheck ? .check : .call
                    }
                    if let d {
                        try? await Task.sleep(for: .seconds(0.25))
                        if Task.isCancelled { return }
                        heroAct(d)
                    }
                    return
                }
                guard Self.autopilot else { return }
                try? await Task.sleep(for: .seconds(settings.botSpeed * 2))
                if Task.isCancelled { return }
                var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
                heroAct(BotBrain.decide(state: h, seat: heroSeat, profile: Profile.base(.reg), rng: &rng))
                return
            }
            let fast = !heroInCurrentHand
            let delay = settings.botSpeed * (fast ? 0.45 : 1) * Double.random(in: 0.7...1.3)
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            guard var s = hand, !s.isComplete, let seat = s.currentSeat, let d = session.botDecision(s) else { return }
            let street = s.street
            s.apply(d)
            record(s, seat: seat, streetBefore: street)
            hand = s
        }
        completeHandIfNeeded()
    }

    private func record(_ s: HandState, seat: Int, streetBefore: Street) {
        if let a = s.actions.last { lastAction[seat] = Self.bubble(a) }
        if s.street != streetBefore {
            // New street: clear bubbles except folds.
            lastAction = lastAction.filter { $0.value == "Fold" }
            premove = nil
        }
    }

    func heroAct(_ d: Decision) {
        guard isHeroTurn, var s = hand else { return }
        if let note = Coach.grade(state: s, heroSeat: heroSeat, decision: d, profiles: session.profilesBySeat) {
            notesThisHand.append(note)
        }
        let street = s.street
        s.apply(d)
        record(s, seat: heroSeat, streetBefore: street)
        hand = s
        if s.isComplete { completeHandIfNeeded() } else { runLoop() }
    }

    private func completeHandIfNeeded() {
        guard let h = hand, h.isComplete, history.first?.id != h.handNumber else { return }
        premove = nil
        session.finishHand(h, trackHero: !currentHandIsSpot)
        if currentHandIsSpot {
            spotScore.spots += 1
            spotScore.good += notesThisHand.filter { $0.grade == .good || $0.grade == .okay }.count
            spotScore.bad += notesThisHand.filter { $0.grade == .mistake || $0.grade == .inaccuracy }.count
            for n in notesThisHand where n.grade != .okay {
                store.rep("spot.\(spotKind.rawValue)", correct: n.grade == .good, xp: n.grade == .good ? 10 : 2)
            }
            store.save()
        }
        for n in notesThisHand {
            switch n.grade {
            case .good: session.stats.good += 1
            case .inaccuracy: session.stats.inaccuracies += 1
            case .mistake: session.stats.mistakes += 1
            case .okay: break
            }
        }
        appendRecord(h, notes: notesThisHand)
        if settings.autoDeal || heroSittingOut || Self.autopilot {
            let wait = heroSittingOut ? max(1.2, settings.botSpeed * 2.5) : 2.5
            dealTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                if Task.isCancelled { return }
                self?.dealNext()
            }
        }
    }

    private func appendRecord(_ h: HandState, notes: [CoachNote]) {
        let profiles = session.profilesBySeat
        let heroIn = h.player(seat: heroSeat) != nil
        let rec = HandRecord(
            state: h, notes: notes, heroNet: heroIn ? h.result?.net[heroSeat] : nil, heroInHand: heroIn,
            publicText: HandHistoryFormatter.format(h, heroSeat: heroIn ? heroSeat : nil, profiles: profiles, revealTypes: false),
            coachText: HandHistoryFormatter.format(h, heroSeat: heroIn ? heroSeat : nil, profiles: profiles, revealTypes: true, notes: notes))
        history.insert(rec, at: 0)
        if history.count > 300 { history.removeLast() }
    }

    /// Deals and plays bots synchronously until it's the hero's turn (snapshots / tests).
    func debugAdvanceToHero(maxHands: Int = 30) {
        for _ in 0..<maxHands {
            var h = session.startHand()
            while !h.isComplete && h.currentSeat != heroSeat, let d = session.botDecision(h) {
                let seat = h.currentSeat!
                h.apply(d)
                if let a = h.actions.last { lastAction[seat] = Self.bubble(a) }
            }
            hand = h
            if !h.isComplete { return }
            session.finishHand(h)
            appendRecord(h, notes: [])
            lastAction = [:]
        }
    }

    /// Hero is out of the hand: play the rest instantly and deal the next one.
    func skipToNextHand() {
        guard var h = hand, !h.isComplete, !heroInCurrentHand else { return }
        loopTask?.cancel()
        var guardCount = 0
        while !h.isComplete, h.currentSeat != heroSeat, let d = session.botDecision(h), guardCount < 500 {
            h.apply(d)
            guardCount += 1
        }
        hand = h
        completeHandIfNeeded()
        dealTask?.cancel()
        dealNext()
    }

    func stopAutoDeal() {
        dealTask?.cancel()
    }

    /// Fast-forward `n` hands with the hero sitting out (reads mode).
    func simulate(_ n: Int) {
        guard !handInProgress else { return }
        dealTask?.cancel()
        for _ in 0..<n {
            let h = session.simulateHand()
            appendRecord(h, notes: [])
            hand = h
        }
        lastAction = [:]
    }

    func toggleSitOut() {
        heroSittingOut.toggle()
        if heroSittingOut && !handInProgress { dealNext() }
        if !heroSittingOut { dealTask?.cancel() }
    }

    // MARK: - Reads quiz

    func submitReads() {
        let current = session.seats.compactMap { s -> (BotPlayer, Int)? in s.occupant.bot.map { ($0, s.seat) } }
        var rows = current.map { QuizRow(bot: $0.0, seat: $0.1, guess: tags[$0.0.id], stats: session.tracker.stats(for: $0.0.id)) }
        for b in session.departed where tags[b.id] != nil {
            rows.append(QuizRow(bot: b, seat: nil, guess: tags[b.id], stats: session.tracker.stats(for: b.id)))
        }
        let result = QuizResult(rows: rows, handsObserved: session.handNumber)
        quiz = result
        showHUD = true
        store.recordQuiz(QuizRecord(handsObserved: result.handsObserved, correct: result.score, total: rows.count),
                         perType: rows.map { ($0.bot.type, $0.correct) })
    }

    func dismissQuiz() { quiz = nil }

    func endSession() {
        let s = session.stats
        store.recordSession(SessionRecord(preset: session.preset.name, hands: s.hands, net: s.net, good: s.good,
                                          inaccuracies: s.inaccuracies, mistakes: s.mistakes))
    }

    // MARK: - Helpers

    static func bubble(_ a: PlayerAction) -> String {
        switch a.type {
        case .fold: "Fold"
        case .check: "Check"
        case .call: a.isAllIn ? "Call $\(a.added) (all-in)" : "Call $\(a.added)"
        case .bet: a.isAllIn ? "All-in $\(a.toAmount)" : "Bet $\(a.added)"
        case .raise: a.isAllIn ? "All-in $\(a.toAmount)" : "Raise $\(a.toAmount)"
        case .postStraddle: "Straddle $\(a.added)"
        default: ""
        }
    }

    func profile(at seat: Int) -> Profile? { session.bot(at: seat)?.profile }

    var heroStats: PlayerStats { session.tracker.stats(for: TableSession.heroID) }

    /// Everything Claude needs to review the whole session.
    func sessionReport() -> String {
        let s = session.stats
        let h = heroStats
        var out = "LIVE $1/$2 SESSION REVIEW\n"
        out += "Table: \(session.preset.name), \(session.seatCount)-handed. Hands dealt to hero: \(s.hands), played: \(s.handsPlayed).\n"
        out += "Result: \(s.net >= 0 ? "+" : "")$\(s.net) (\(String(format: "%.1f", bbPer100)) bb/100). Bought in for $\(s.buyIns).\n"
        out += "Hero stats: VPIP \(h.vpipText)%, PFR \(h.pfrText)%, 3-bet \(h.threeBetText)%, limp \(h.limpText)%, c-bet \(h.cbetText)%, fold to c-bet \(h.foldToCbetText)%, AF \(h.afText), WTSD \(h.wtsdText)%.\n"
        out += "Coach grades: \(s.good) good, \(s.inaccuracies) inaccuracies, \(s.mistakes) mistakes.\n\n"
        out += "OPPONENTS (true types; hero's tag in brackets):\n"
        for seat in session.seats {
            guard let b = seat.occupant.bot else { continue }
            let st = session.tracker.stats(for: b.id)
            let tag = tags[b.id].map { " [hero tagged: \($0.name)]" } ?? ""
            out += "- \(b.name): \(b.type.name)\(tag). \(st.hands) hands, VPIP \(st.vpipText), PFR \(st.pfrText), AF \(st.afText). Quirks: \(b.profile.quirks.joined(separator: "; "))\n"
        }
        let notes = history.flatMap(\.notes)
        var byPrinciple: [String: (Int, Int)] = [:]
        for n in notes where n.grade == .mistake || n.grade == .inaccuracy {
            let k = n.principle?.title ?? n.headline
            let cur = byPrinciple[k] ?? (0, 0)
            byPrinciple[k] = n.grade == .mistake ? (cur.0 + 1, cur.1) : (cur.0, cur.1 + 1)
        }
        if !byPrinciple.isEmpty {
            out += "\nFLAGGED LEAKS (mistakes / inaccuracies):\n"
            for (k, v) in byPrinciple.sorted(by: { ($0.value.0 * 2 + $0.value.1) > ($1.value.0 * 2 + $1.value.1) }) {
                out += "- \(k): \(v.0) / \(v.1)\n"
            }
        }
        let flagged = notes.filter { $0.grade == .mistake || $0.grade == .inaccuracy }.suffix(15)
        if !flagged.isEmpty {
            out += "\nFLAGGED DECISIONS:\n"
            for n in flagged { out += "- Hand #\(n.handNumber) \(n.street.name), \(n.heroAction): \(n.headline). \(n.detail)\n" }
        }
        let key = history.filter { $0.heroInHand && ($0.heroNet ?? 0) != 0 }
            .sorted { abs($0.heroNet ?? 0) > abs($1.heroNet ?? 0) }
            .prefix(6)
        if !key.isEmpty {
            out += "\nBIGGEST POTS (full histories, villain types in brackets):\n"
            for r in key { out += "\n" + r.coachText + "\n" }
        }
        return out
    }
}
