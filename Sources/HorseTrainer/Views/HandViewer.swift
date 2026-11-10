import PokerCore
import SwiftUI

/// Step-through replayer for the session's hands: table picture, action log and the grades for each decision.
struct HandViewer: View {
    static let width: CGFloat = 1180
    /// ImageRenderer can't draw scroll views; snapshots flip this to lay everything out flat.
    nonisolated(unsafe) static var flat = false

    @Environment(AppModel.self) private var app
    let game: GameController
    /// Grades, true types and every hole card. Off while a Cash Game session is still running.
    let reveal: Bool
    var start: Int?

    @State private var selected: Int?
    @State private var frames: [HandState] = []
    @State private var step = 0
    @State private var onlyMine = true
    @State private var showAll = false

    var hands: [HandRecord] { game.history.filter { !onlyMine || $0.heroInHand }.sorted { $0.id < $1.id } }
    var record: HandRecord? { game.history.first { $0.id == selected } }
    var heroSeat: Int { game.heroSeat }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 230)
            Rectangle().fill(Theme.border).frame(width: 1)
            if let rec = record, !frames.isEmpty {
                detail(rec)
            } else {
                Text(game.history.isEmpty ? "No hands played yet." : "Pick a hand on the left.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 680)
        .background(keys)
        .onAppear {
            if let s = start, let r = game.history.first(where: { $0.id == s }), !r.heroInHand { onlyMine = false }
            select(start ?? hands.first?.id)
        }
    }

    func select(_ id: Int?) {
        selected = id
        frames = record.map { HandReplay.frames($0.state) } ?? []
        step = 0
    }

    func moveHand(_ d: Int) {
        let ids = hands.map(\.id)
        guard let cur = selected, let i = ids.firstIndex(of: cur) else { select(ids.first); return }
        let j = i + d
        if ids.indices.contains(j) { select(ids[j]) }
    }

    func go(_ k: Int) { step = min(max(0, k), max(0, frames.count - 1)) }

    /// ← → step through the hand, ↑ ↓ change hands.
    var keys: some View {
        ZStack {
            Button("") { go(step - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { go(step + 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { moveHand(-1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { moveHand(1) }.keyboardShortcut(.downArrow, modifiers: [])
        }
        .buttonStyle(.plain)
        .opacity(0)
        .allowsHitTesting(false)
    }

    // MARK: Hand list

    var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(hands.count) hands").font(Theme.ui(12, .medium)).foregroundStyle(Theme.textDim)
                Spacer()
                PreToggle(title: "Mine", on: onlyMine) {
                    onlyMine.toggle()
                    if let s = selected, !hands.contains(where: { $0.id == s }) { select(hands.first?.id) }
                }
                .help("Only hands you were dealt into")
            }
            .padding(10)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollViewReader { proxy in
                Scroller {
                    VStack(spacing: 2) {
                        ForEach(hands) { rec in
                            row(rec).id(rec.id)
                        }
                    }
                    .padding(6)
                }
                .onAppear { if let s = selected { proxy.scrollTo(s, anchor: .center) } }
                .onChange(of: selected) { if let s = selected { withAnimation { proxy.scrollTo(s) } } }
            }
        }
        .background(Theme.surface)
    }

    func row(_ rec: HandRecord) -> some View {
        let on = rec.id == selected
        let hero = rec.heroInHand ? rec.state.player(seat: heroSeat) : nil
        return Button { select(rec.id) } label: {
            HStack(spacing: 8) {
                Text("#\(rec.id)").font(Theme.mono(11.5, .semibold)).foregroundStyle(on ? Theme.text : Theme.textDim)
                    .frame(width: 38, alignment: .leading)
                if let p = hero {
                    MiniCards(cards: p.hole)
                    Text(rec.state.position(of: heroSeat).short).font(Theme.ui(10.5, .medium)).foregroundStyle(Theme.textFaint)
                } else {
                    Text(potLine(rec)).font(Theme.ui(11)).foregroundStyle(Theme.textFaint).lineLimit(1)
                }
                Spacer(minLength: 0)
                if reveal, let g = worstGrade(rec.id), g == .mistake || g == .inaccuracy {
                    Circle().fill(Theme.color(for: g)).frame(width: 6, height: 6)
                }
                if let n = rec.heroNet, rec.heroInHand, n != 0 {
                    Text(n > 0 ? "+$\(n)" : "-$\(abs(n))").font(Theme.mono(11, .semibold))
                        .foregroundStyle(n > 0 ? Theme.good : Theme.bad)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(on ? Color.white.opacity(0.10) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func potLine(_ rec: HandRecord) -> String {
        guard let r = rec.state.result else { return "" }
        return "$\(r.pots.reduce(0) { $0 + $1.amount }) pot"
    }

    func worstGrade(_ hand: Int) -> Grade? {
        let rank: [Grade: Int] = [.good: 0, .okay: 1, .inaccuracy: 2, .mistake: 3]
        let grades = (game.history.first { $0.id == hand }?.notes.map(\.grade) ?? []) + game.sims(for: hand).map { $0.grade() }
        return grades.max { rank[$0]! < rank[$1]! }
    }

    // MARK: Detail

    var voluntary: [PlayerAction] { record?.state.actions.filter(\.type.isVoluntary) ?? [] }

    /// The action that produced frame `k` (nil for the blinds frame).
    func action(at k: Int) -> PlayerAction? { k > 0 && k - 1 < voluntary.count ? voluntary[k - 1] : nil }

    func name(_ seat: Int, _ rec: HandRecord) -> String {
        seat == heroSeat && rec.heroInHand ? "You" : (rec.state.player(seat: seat)?.name ?? "?")
    }

    func detail(_ rec: HandRecord) -> some View {
        let frame = frames[min(step, frames.count - 1)]
        return VStack(spacing: 0) {
            header(rec)
            ReplayTable(hand: frame, final: rec.state, seatCount: game.session.seatCount, heroSeat: rec.heroInHand ? heroSeat : nil,
                        types: reveal ? rec.profiles.mapValues(\.type) : [:], showAll: reveal && showAll,
                        lastAction: action(at: step), fourColor: app.settings.fourColor)
                .frame(height: 320)
            controls(rec)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                log(rec).frame(maxWidth: .infinity)
                Rectangle().fill(Theme.border).frame(width: 1)
                grades(rec).frame(width: 400)
            }
        }
    }

    func header(_ rec: HandRecord) -> some View {
        HStack(spacing: 10) {
            Text("Hand #\(rec.id)").font(Theme.ui(15, .semibold))
            if rec.heroInHand, let p = rec.state.player(seat: heroSeat) {
                Text("You: \(rec.state.position(of: heroSeat).short)").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                MiniCards(cards: p.hole)
                Text("$\(p.startingStack) deep").font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
            } else {
                Text("You weren't dealt in").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            if reveal {
                PreToggle(title: "Show all cards", on: showAll) { showAll.toggle() }
            }
            if let n = rec.heroNet, rec.heroInHand {
                Text(n == 0 ? "$0" : (n > 0 ? "+$\(n)" : "-$\(abs(n))")).font(Theme.mono(14, .semibold))
                    .foregroundStyle(n > 0 ? Theme.good : (n < 0 ? Theme.bad : Theme.textDim))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func controls(_ rec: HandRecord) -> some View {
        let last = frames.count - 1
        return HStack(spacing: 8) {
            Group {
                Button { go(0) } label: { Image(systemName: "backward.end.fill") }
                Button { go(step - 1) } label: { Image(systemName: "chevron.left") }
                Button { go(step + 1) } label: { Image(systemName: "chevron.right") }
                Button { go(last) } label: { Image(systemName: "forward.end.fill") }
            }
            .buttonStyle(PillButtonStyle(prominent: false, small: true))
            Text(caption(rec)).font(Theme.ui(12.5, .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
            ForEach([Street.preflop, .flop, .turn, .river], id: \.self) { st in
                if let k = firstFrame(on: st) {
                    Button(st.name) { go(k) }
                        .buttonStyle(PillButtonStyle(color: Color.white.opacity(0.16), prominent: streetOf(step) == st, small: true))
                }
            }
            Text("\(step)/\(last)").font(Theme.mono(11)).foregroundStyle(Theme.textFaint).frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func caption(_ rec: HandRecord) -> String {
        guard let a = action(at: step) else { return "Blinds posted. Press → to step through." }
        var s = "\(a.street.name): \(name(a.seat, rec)) \(ReadTracker.describe(a))"
        if step == frames.count - 1, let r = frames[step].result {
            let winners = Set(r.pots.flatMap(\.winners)).map { name($0, rec) }.joined(separator: " & ")
            s += " · \(winners) win\(winners == "You" || winners.contains("&") ? "" : "s") $\(r.pots.reduce(0) { $0 + $1.amount })"
        }
        return s
    }

    func streetOf(_ k: Int) -> Street { action(at: k)?.street ?? .preflop }

    func firstFrame(on st: Street) -> Int? {
        guard let i = voluntary.firstIndex(where: { $0.street == st }), i + 1 < frames.count else { return nil }
        return i + 1
    }

    // MARK: Log

    func log(_ rec: HandRecord) -> some View {
        let byStreet = Dictionary(grouping: voluntary.enumerated().map { ($0.offset + 1, $0.element) }, by: { $0.1.street })
        return ScrollViewReader { proxy in
            Scroller {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach([Street.preflop, .flop, .turn, .river], id: \.self) { st in
                        if let rows = byStreet[st] {
                            streetHeader(st, rec)
                            ForEach(rows, id: \.0) { k, a in
                                logRow(k, a, rec).id(k)
                            }
                        }
                    }
                    if let r = rec.state.result {
                        resultBlock(r, rec)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: step) { withAnimation { proxy.scrollTo(step, anchor: .center) } }
        }
    }

    func streetHeader(_ st: Street, _ rec: HandRecord) -> some View {
        let n = st == .flop ? 3 : (st == .turn ? 4 : (st == .river ? 5 : 0))
        return HStack(spacing: 8) {
            Text(st.name.uppercased()).font(Theme.ui(10, .bold)).tracking(0.6).foregroundStyle(Theme.textFaint)
            if n > 0 && rec.state.board.count >= n { MiniCards(cards: Array(rec.state.board.prefix(n))) }
            Spacer()
        }
        .padding(.top, st == .preflop ? 0 : 8)
        .padding(.bottom, 2)
    }

    func logRow(_ k: Int, _ a: PlayerAction, _ rec: HandRecord) -> some View {
        let isHero = a.seat == heroSeat && rec.heroInHand
        let graded = reveal ? gradeFor(a.index, rec) : nil
        return Button { go(k) } label: {
            HStack(spacing: 8) {
                Text(name(a.seat, rec)).font(Theme.ui(12, isHero ? .semibold : .regular)).frame(width: 84, alignment: .leading).lineLimit(1)
                Text(rec.state.position(of: a.seat).short).font(Theme.ui(10)).foregroundStyle(Theme.textFaint).frame(width: 34, alignment: .leading)
                Text(ReadTracker.describe(a)).font(Theme.mono(11.5)).foregroundStyle(a.type.isAggressive ? Theme.text : Theme.textDim)
                Spacer(minLength: 0)
                if let g = graded {
                    Text(g.label.uppercased()).font(Theme.ui(9, .bold)).foregroundStyle(Theme.color(for: g))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(k == step ? Color.white.opacity(0.12) : (isHero ? Color.white.opacity(0.03) : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func resultBlock(_ r: HandResult, _ rec: HandRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("RESULT").font(Theme.ui(10, .bold)).tracking(0.6).foregroundStyle(Theme.textFaint).padding(.top, 8)
            ForEach(Array(r.pots.enumerated()), id: \.offset) { _, pot in
                Text("\(pot.winners.map { name($0, rec) }.joined(separator: " & ")) won $\(pot.amount)\(pot.winningHand.map { " with \($0)" } ?? "")")
                    .font(Theme.ui(12))
            }
            ForEach(r.shown.keys.sorted(), id: \.self) { seat in
                if let p = rec.state.player(seat: seat) {
                    HStack(spacing: 6) {
                        Text(name(seat, rec)).font(Theme.ui(11.5)).foregroundStyle(Theme.textDim)
                        MiniCards(cards: p.hole)
                        Text(r.shown[seat] ?? "").font(Theme.ui(11)).foregroundStyle(Theme.textFaint)
                    }
                }
            }
            if r.rake > 0 { Text("Rake $\(r.rake)").font(Theme.mono(10.5)).foregroundStyle(Theme.textFaint) }
        }
    }

    // MARK: Grades

    func gradeFor(_ index: Int, _ rec: HandRecord) -> Grade? {
        if let s = game.sims(for: rec.id).first(where: { $0.actionIndex == index }) { return s.grade() }
        return rec.notes.first { $0.actionIndex == index }?.grade
    }

    @ViewBuilder func grades(_ rec: HandRecord) -> some View {
        Scroller {
            VStack(alignment: .leading, spacing: 8) {
                if !reveal {
                    Panel {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Grades are sealed", systemImage: "lock.fill").font(Theme.ui(13, .semibold))
                            Text("End the session to see how each decision was graded and who everyone really was.")
                                .font(Theme.ui(12)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if !rec.heroInHand {
                    Text("You weren't in this hand.").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                } else {
                    let sims = game.sims(for: rec.id)
                    let indices = Set(sims.map(\.actionIndex) + rec.notes.map(\.actionIndex)).sorted()
                    let current = action(at: step)?.index
                    if indices.isEmpty {
                        Text(game.pendingSims > 0 ? "Simulating…" : "Nothing graded: junk preflop folds aren't simulated.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                    }
                    ForEach(indices, id: \.self) { i in
                        let k = voluntary.firstIndex { $0.index == i }.map { $0 + 1 }
                        Button { if let k { go(k) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(sims.filter { $0.actionIndex == i }) { SimCard(eval: $0) }
                                ForEach(rec.notes.filter { $0.actionIndex == i }) { NoteCard(note: $0) }
                            }
                            .overlay(Rectangle().strokeBorder(i == current ? Theme.text : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct Scroller<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if HandViewer.flat { VStack { content; Spacer(minLength: 0) } } else { ScrollView { content } }
    }
}

/// Two-to-five tiny cards for lists and logs.
struct MiniCards: View {
    let cards: [Card]
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                Text(c.pretty)
                    .font(Theme.mono(10.5, .semibold))
                    .foregroundStyle(CardView.suitColor(c.suit, fourColor: app.settings.fourColor))
                    .padding(.horizontal, 3)
                    .frame(height: 17)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xFAFAFA)))
            }
        }
        .fixedSize()
    }
}

/// The table at one moment of a replay.
struct ReplayTable: View {
    let hand: HandState
    let final: HandState
    let seatCount: Int
    let heroSeat: Int?
    let types: [Int: PlayerType]
    let showAll: Bool
    let lastAction: PlayerAction?
    let fourColor: Bool

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let rx = min(geo.size.width * 0.34, 300.0), ry = geo.size.height * 0.27
            ZStack {
                Capsule().fill(Theme.rail).frame(width: rx * 2 + 18, height: ry * 2 + 18).position(c)
                Capsule().fill(Theme.felt).frame(width: rx * 2, height: ry * 2).position(c)
                VStack(spacing: 6) {
                    Text("Pot $\(hand.pot)").font(Theme.mono(12)).foregroundStyle(.white)
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            CardView(card: i < hand.board.count ? hand.board[i] : nil, width: 36, fourColor: fourColor)
                        }
                    }
                }
                .position(c)
                ForEach(hand.players) { p in
                    let edge = point(p.seat, c, rx, ry)
                    seat(p).position(point(p.seat, c, rx + 46, ry + 34))
                    if p.committedStreet > 0 && !hand.isComplete {
                        ChipStack(amount: p.committedStreet, compact: true).position(lerp(c, edge, 0.62))
                    }
                    if p.seat == hand.buttonSeat {
                        DealerButton().scaleEffect(0.85).position(lerp(c, edge, 0.84).applying(CGAffineTransform(translationX: 22, y: 0)))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hand.actions.count)
    }

    func showCards(_ seat: Int) -> Bool {
        seat == heroSeat || showAll || final.result?.shown[seat] != nil
    }

    func seat(_ p: SeatState) -> some View {
        let acted = lastAction?.seat == p.seat
        let won = hand.result?.pots.contains { $0.winners.contains(p.seat) } ?? false
        return VStack(spacing: 3) {
            HStack(spacing: -10) {
                CardView(card: p.hole[0], faceUp: showCards(p.seat), width: 28, fourColor: fourColor, dimmed: p.folded)
                CardView(card: p.hole[1], faceUp: showCards(p.seat), width: 28, fourColor: fourColor, dimmed: p.folded)
            }
            .opacity(p.folded && !showCards(p.seat) ? 0 : 1)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    if let t = types[p.seat] { Circle().fill(Theme.color(for: t)).frame(width: 6, height: 6).help(t.name) }
                    Text(p.seat == heroSeat ? "You" : p.name).font(Theme.ui(11, .medium)).lineLimit(1)
                    Text(hand.position(of: p.seat).short).font(Theme.ui(9, .semibold)).foregroundStyle(Theme.textFaint)
                }
                Text("$\(p.stack)").font(Theme.mono(11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(minWidth: 92)
            .background(Capsule().fill(Theme.surface2))
            .overlay(Capsule().strokeBorder(won ? Theme.good : (acted ? Theme.text : Theme.border), lineWidth: acted || won ? 1.5 : 1))
            .overlay(alignment: .bottom) {
                if acted, let a = lastAction {
                    Text(ReadTracker.describe(a).components(separatedBy: " (").first ?? "")
                        .font(Theme.ui(10, .semibold))
                        .foregroundStyle(a.type.isAggressive ? Theme.onPrimary : .white)
                        .padding(.horizontal, 7).padding(.vertical, 1.5)
                        .background(Capsule().fill(a.type.isAggressive ? Theme.text : Color(white: 0.3)))
                        .offset(y: 12)
                        .fixedSize()
                }
            }
        }
        .opacity(p.folded && !acted ? 0.4 : 1)
    }

    func point(_ seat: Int, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPoint {
        let n = max(seatCount, (hand.players.map(\.seat).max() ?? 0) + 1)
        let angle = (90.0 + Double(seat) * 360.0 / Double(n)) * .pi / 180
        return CGPoint(x: c.x + cos(angle) * rx, y: c.y + sin(angle) * ry)
    }

    func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
