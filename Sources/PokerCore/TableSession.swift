import Foundation

public enum Occupant: Sendable, Codable, Equatable {
    case hero
    case bot(BotPlayer)

    public var bot: BotPlayer? {
        if case .bot(let b) = self { return b }
        return nil
    }
}

public struct SeatInfo: Sendable, Codable, Identifiable, Equatable {
    public var id: Int { seat }
    public let seat: Int
    public var occupant: Occupant
    public var stack: Int

    public var name: String {
        switch occupant {
        case .hero: "You"
        case .bot(let b): b.name
        }
    }
}

public struct SessionStats: Sendable, Codable, Equatable {
    public var hands = 0
    public var handsPlayed = 0
    public var net = 0
    public var buyIns = 0
    public var good = 0
    public var inaccuracies = 0
    public var mistakes = 0
    public init() {}
}

/// A table of bots (and optionally the hero). Owns seats, stacks, button, reads and rebuys.
/// UI-free so it can be simulated in tests and fast-forwarded.
public struct TableSession: Sendable {
    public static let maxSeats = 9
    /// Number of seats at this table (2–9). The hero is always seat 0.
    public let seatCount: Int
    public static let heroSeat = 0

    public var config: TableConfig
    public private(set) var seats: [SeatInfo]
    public private(set) var button: Int
    public private(set) var handNumber = 0
    public var tracker = ReadTracker()
    public var stats = SessionStats()
    public var heroStraddles = false
    public var autoRebuyHero = true
    /// Players leave and new ones sit down over time, so stacks and line-ups stay realistic.
    public var tableTurnover = true
    public var rng: SplitMix64
    public let preset: TablePreset
    /// Bots that left the table this session (so the reads quiz can still reference them).
    public private(set) var departed: [BotPlayer] = []

    public init(preset: TablePreset, seats seatCount: Int = 9, config: TableConfig = TableConfig(), heroBuyIn: Int? = nil, includeHero: Bool = true,
                seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.seatCount = min(Self.maxSeats, max(2, seatCount))
        self.config = config
        self.preset = preset
        var rng = SplitMix64(seed: seed)
        let botCount = includeHero ? self.seatCount - 1 : self.seatCount
        let types = preset.composition(bots: botCount, rng: &rng)
        var seats: [SeatInfo] = []
        var used = Set<String>()
        var t = 0
        for s in 0..<self.seatCount {
            if includeHero && s == Self.heroSeat {
                seats.append(SeatInfo(seat: s, occupant: .hero, stack: heroBuyIn ?? config.maxBuyIn))
            } else {
                let bot = Roster.makeBot(type: types[t], usedNames: used, rng: &rng)
                used.insert(bot.name)
                t += 1
                seats.append(SeatInfo(seat: s, occupant: .bot(bot), stack: Roster.buyIn(for: bot.type, config: config, rng: &rng)))
            }
        }
        self.seats = seats
        button = Int.random(in: 0..<self.seatCount, using: &rng)
        self.rng = rng
        if includeHero { stats.buyIns = heroBuyIn ?? config.maxBuyIn }
    }

    public var hasHero: Bool { seats.contains { $0.occupant == .hero } }
    public var heroStack: Int { seats.first { $0.occupant == .hero }?.stack ?? 0 }
    public var bots: [BotPlayer] { seats.compactMap(\.occupant.bot) }

    public func bot(at seat: Int) -> BotPlayer? { seats[seat].occupant.bot }

    public var profilesBySeat: [Int: Profile] {
        var m: [Int: Profile] = [:]
        for s in seats { if let b = s.occupant.bot { m[s.seat] = b.profile } }
        return m
    }

    /// Stable id used to track the hero's own stats in the read tracker.
    public static let heroID = UUID(uuidString: "00000000-0000-0000-0000-00000000BEEF")!

    public var idsBySeat: [Int: UUID] {
        var m: [Int: UUID] = [:]
        for s in seats {
            switch s.occupant {
            case .bot(let b): m[s.seat] = b.id
            case .hero: m[s.seat] = Self.heroID
            }
        }
        return m
    }

    /// Deals a new hand. `heroSittingOut` removes the hero from this hand.
    public mutating func startHand(heroSittingOut: Bool = false) -> HandState {
        // Rebuys, busted players and people going home happen between hands, so the last hand's
        // seats (names, stacks, shown cards) stay intact until the next deal.
        handleBusts()
        handNumber += 1
        let dealt = seats.filter { s in
            s.stack > 0 && !(s.occupant == .hero && heroSittingOut)
        }
        // Advance the button to the next dealt seat.
        let dealtSeats = dealt.map(\.seat).sorted()
        button = dealtSeats.first { $0 > button } ?? dealtSeats[0]

        // UTG decides on the straddle.
        var straddle = false
        if dealtSeats.count >= 4 {
            let startIdx = dealtSeats.firstIndex { $0 > button } ?? 0
            let ordered = Array(dealtSeats[startIdx...] + dealtSeats[..<startIdx])
            let utg = seats[ordered[2]]
            if utg.stack > config.straddleAmount * 10 {
                switch utg.occupant {
                case .hero: straddle = heroStraddles
                case .bot(let b): straddle = BotBrain.wantsStraddle(b.profile, rng: &rng)
                }
            }
        }
        return HandState(config: config, handNumber: handNumber, seats: dealt.map { ($0.seat, $0.name, $0.stack) },
                         buttonSeat: button, straddle: straddle, rng: &rng)
    }

    /// Spot practice: puts the button on a random seat so the hero sees every position.
    public mutating func moveButtonRandomly() {
        button = Int.random(in: 0..<seatCount, using: &rng)
    }

    public mutating func botDecision(_ state: HandState) -> Decision? {
        guard let seat = state.currentSeat, let bot = bot(at: seat) else { return nil }
        return BotBrain.decide(state: state, seat: seat, profile: bot.profile, rng: &rng)
    }

    /// Applies the finished hand: stacks, reads, hero stats, and bot rebuys / table changes.
    /// `trackHero: false` keeps the hand out of the hero's own stats (spot practice, where an autopilot played the early streets).
    public mutating func finishHand(_ state: HandState, trackHero: Bool = true) {
        guard let result = state.result else { return }
        for p in state.players {
            seats[p.seat].stack = p.stack
        }
        var ids = idsBySeat
        if !trackHero { ids = ids.filter { $0.value != Self.heroID } }
        tracker.record(state, ids: ids)
        if let hero = state.players.first(where: { seats[$0.seat].occupant == .hero }) {
            stats.hands += 1
            stats.net += result.net[hero.seat] ?? 0
            if state.actions.contains(where: { $0.seat == hero.seat && ($0.type == .call || $0.type == .raise || $0.type == .bet) }) {
                stats.handsPlayed += 1
            }
        }
    }

    public mutating func rebuyHero(_ amount: Int) {
        guard let i = seats.firstIndex(where: { $0.occupant == .hero }) else { return }
        seats[i].stack += amount
        stats.buyIns += amount
    }

    private mutating func handleBusts() {
        for i in seats.indices {
            switch seats[i].occupant {
            case .hero:
                if seats[i].stack == 0 && autoRebuyHero {
                    seats[i].stack = config.maxBuyIn
                    stats.buyIns += config.maxBuyIn
                }
            case .bot(let b):
                if seats[i].stack < config.bigBlind * 2 {
                    let rebuyChance: Double = [.whale: 0.9, .fish: 0.7, .tryingRec: 0.5, .reg: 0.8, .nit: 0.4][b.type] ?? 0.5
                    if Double.random(in: 0..<1, using: &rng) < rebuyChance {
                        seats[i].stack += Roster.buyIn(for: b.type, config: config, rng: &rng)
                    } else {
                        replaceBot(at: i)
                    }
                } else if tableTurnover {
                    // People go home: ~6 live hours on average, sooner once they've racked up a big win.
                    let leave = seats[i].stack >= config.maxBuyIn * 3 ? 1.0 / 45 : 1.0 / 180
                    if Double.random(in: 0..<1, using: &rng) < leave { replaceBot(at: i) }
                }
            }
        }
    }

    /// A new player from the same kind of game takes the seat, like live.
    private mutating func replaceBot(at i: Int) {
        guard let b = seats[i].occupant.bot else { return }
        departed.append(b)
        let used = Set(seats.compactMap { $0.occupant.bot?.name })
        // Keep the table's character: usually the same kind of player sits down.
        let t = Double.random(in: 0..<1, using: &rng) < 0.7 ? b.type : preset.composition(bots: 1, rng: &rng)[0]
        let nb = Roster.makeBot(type: t, usedNames: used, rng: &rng)
        seats[i] = SeatInfo(seat: i, occupant: .bot(nb), stack: Roster.buyIn(for: nb.type, config: config, rng: &rng))
    }

    /// Plays a full hand with bots only (hero sits out). Returns the finished hand.
    @discardableResult
    public mutating func simulateHand() -> HandState {
        playHand(heroProfile: nil)
    }

    /// Plays and finishes a whole hand. With `heroProfile`, a bot with that profile plays the hero seat; otherwise the hero sits out.
    @discardableResult
    public mutating func playHand(heroProfile: Profile?) -> HandState {
        var state = startHand(heroSittingOut: heroProfile == nil)
        var guardCount = 0
        while !state.isComplete, let seat = state.currentSeat, guardCount < 500 {
            if seat == Self.heroSeat, let hp = heroProfile {
                state.apply(BotBrain.decide(state: state, seat: seat, profile: hp, rng: &rng))
            } else if let d = botDecision(state) {
                state.apply(d)
            } else {
                break
            }
            guardCount += 1
        }
        finishHand(state)
        return state
    }

    /// Replaces a bot by id-free seat index (used by tests / custom tables).
    public mutating func setBot(_ bot: BotPlayer, at seat: Int, stack: Int) {
        seats[seat] = SeatInfo(seat: seat, occupant: .bot(bot), stack: stack)
    }

    public var totalChips: Int { seats.reduce(0) { $0 + $1.stack } }
}
