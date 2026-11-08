import PokerCore
import SwiftUI

struct EqPlayer: Identifiable, Equatable {
    enum Mode: String, CaseIterable { case cards = "Cards", range = "Range", random = "Random" }
    let id = UUID()
    var mode: Mode = .cards
    var cards: [Card?] = [nil, nil]
    var rangeText = ""
    var range: Set<HandClass> = []

    var spec: HoldingSpec? {
        switch mode {
        case .cards:
            let c = cards.compactMap { $0 }
            return c.count == 2 ? .cards(c) : nil
        case .range: return range.isEmpty ? nil : .range(range)
        case .random: return .random
        }
    }
}

struct EquityView: View {
    @Environment(AppModel.self) private var app
    @State private var players: [EqPlayer] = [EqPlayer(), EqPlayer()]
    @State private var board: [Card?] = Array(repeating: nil, count: 5)
    @State private var result: EquityResult?
    @State private var resultFor: [UUID] = []
    @State private var running = false
    @State private var error: String?

    var usedCards: Set<Card> {
        Set(players.flatMap { $0.mode == .cards ? $0.cards.compactMap { $0 } : [] } + board.compactMap { $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Equity Calculator", subtitle: "Hand vs hand, hand vs range, range vs range. Exact when possible, Monte Carlo otherwise.") {
                    Menu("Presets") {
                        Button("AA vs KK") { preset([.cards([Card("As"), Card("Ah")]), .cards([Card("Ks"), Card("Kd")])]) }
                        Button("AKs vs QQ (coin flip)") { preset([.cards([Card("Ah"), Card("Kh")]), .cards([Card("Qs"), Card("Qd")])]) }
                        Button("Any two vs any two") { preset([.random, .random]) }
                        Button("JJ vs nit 3-bet (QQ+, AK)") { preset([.cards([Card("Js"), Card("Jd")]), .range("QQ+, AK")]) }
                        Button("AQo vs limp-raise (KK+)") { preset([.cards([Card("Ac"), Card("Qd")]), .range("KK+")]) }
                        Button("Whale open (60%) vs AJo") { preset([.range("60%"), .cards([Card("Ah"), Card("Jc")])]) }
                    }
                    .frame(width: 120)
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($players) { $p in
                            let idx = players.firstIndex(where: { $0.id == p.id }) ?? 0
                            EqPlayerRow(player: $p, index: idx, used: usedCards, equity: equity(for: p.id), canRemove: players.count > 2) {
                                players.removeAll { $0.id == p.id }
                            }
                        }
                        HStack {
                            Button { players.append(EqPlayer()) } label: { Label("Add player", systemImage: "plus") }
                                .disabled(players.count >= 9)
                            Spacer()
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BOARD").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textDim)
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { i in
                                CardSlot(card: $board[i], used: usedCards, width: 52)
                                if i == 2 || i == 3 { Spacer().frame(width: 6) }
                            }
                            Spacer()
                            Button("Clear board") { board = Array(repeating: nil, count: 5) }
                        }
                    }
                }

                HStack {
                    Button {
                        calculate()
                    } label: {
                        Text(running ? "Calculating…" : "Calculate").frame(minWidth: 140)
                    }
                    .buttonStyle(PillButtonStyle(color: Theme.red))
                    .disabled(running)
                    .keyboardShortcut(.return, modifiers: [.command])
                    if running { ProgressView().controlSize(.small) }
                    if let r = result {
                        Text(r.exact ? "Exact · \(r.samples.formatted()) runouts" : "Monte Carlo · \(r.samples.formatted()) samples")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    if let e = error { Text(e).foregroundStyle(Theme.bad).font(.system(size: 12)) }
                    Spacer()
                }
            }
            .padding(20)
        }
    }

    func equity(for id: UUID) -> (Double, Double, Double)? {
        guard let r = result, let i = resultFor.firstIndex(of: id) else { return nil }
        return (r.equity[i], r.win[i], r.tie[i])
    }

    enum PresetSpec {
        case cards([Card?])
        case range(String)
        case random
    }

    func preset(_ specs: [PresetSpec]) {
        board = Array(repeating: nil, count: 5)
        players = specs.map { s in
            var p = EqPlayer()
            switch s {
            case .cards(let c): p.mode = .cards; p.cards = c
            case .range(let t): p.mode = .range; p.rangeText = t; p.range = RangeParser.parse(t) ?? []
            case .random: p.mode = .random
            }
            return p
        }
        calculate()
    }

    func calculate() {
        let specs = players.map(\.spec)
        guard specs.allSatisfy({ $0 != nil }) else {
            error = "Every player needs two cards, a range, or Random."
            return
        }
        let b = board.compactMap { $0 }
        guard [0, 3, 4, 5].contains(b.count) else {
            error = "Board must have 0, 3, 4 or 5 cards."
            return
        }
        error = nil
        running = true
        let ids = players.map(\.id)
        let s = specs.compactMap { $0 }
        Task {
            let r = await Task.detached(priority: .userInitiated) {
                EquityCalculator.run(players: s, board: b, iterations: 120_000, seed: UInt64.random(in: 0...UInt64.max))
            }.value
            running = false
            if let r {
                result = r
                resultFor = ids
            } else {
                error = "Couldn't deal those holdings (card conflicts?)."
            }
        }
    }
}

struct EqPlayerRow: View {
    @Binding var player: EqPlayer
    let index: Int
    let used: Set<Card>
    let equity: (Double, Double, Double)?
    let canRemove: Bool
    let onRemove: () -> Void
    @State private var showGrid = false

    var body: some View {
        HStack(spacing: 14) {
            Text("P\(index + 1)").font(Theme.mono(13)).foregroundStyle(Theme.textDim).frame(width: 28)
            Picker("", selection: $player.mode) {
                ForEach(EqPlayer.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Group {
                switch player.mode {
                case .cards:
                    HStack(spacing: 6) {
                        CardSlot(card: $player.cards[0], used: used, width: 40)
                        CardSlot(card: $player.cards[1], used: used, width: 40)
                    }
                case .range:
                    HStack(spacing: 6) {
                        TextField("e.g. QQ+, AKs, ATs+, 76s-54s, 15%", text: $player.rangeText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                            .onSubmit { player.range = RangeParser.parse(player.rangeText) ?? [] }
                            .onChange(of: player.rangeText) { player.range = RangeParser.parse(player.rangeText) ?? player.range }
                        Button { showGrid = true } label: { Image(systemName: "square.grid.3x3.fill") }
                            .popover(isPresented: $showGrid) {
                                RangeGrid(range: $player.range) { player.rangeText = RangeParser.format(player.range) }
                            }
                        Text("\(RangeParser.comboCount(player.range)) combos · \(String(format: "%.1f", Double(RangeParser.comboCount(player.range)) / 13.26))%")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                case .random:
                    Text("Any two cards").foregroundStyle(Theme.textDim)
                }
            }
            .frame(minHeight: 56)
            Spacer()
            if let (eq, win, tie) = equity {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.1f%%", eq * 100)).font(Theme.mono(20))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.panelHi)
                            Capsule().fill(Theme.red).frame(width: g.size.width * eq)
                        }
                    }
                    .frame(width: 160, height: 6)
                    Text(String(format: "win %.1f%% · tie %.1f%%", win * 100, tie * 100)).font(.system(size: 10)).foregroundStyle(Theme.textDim)
                }
            }
            if canRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct CardSlot: View {
    @Environment(AppModel.self) private var app
    @Binding var card: Card?
    let used: Set<Card>
    var width: CGFloat = 44
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            CardView(card: card, width: width, fourColor: app.settings.fourColor)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $picking) {
            CardPicker(used: used.subtracting(card.map { [$0] } ?? [])) { c in
                card = c
                picking = false
            }
        }
    }
}

struct CardPicker: View {
    @Environment(AppModel.self) private var app
    let used: Set<Card>
    let onPick: (Card?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Suit.allCases.reversed(), id: \.self) { suit in
                HStack(spacing: 4) {
                    ForEach((0..<13).reversed(), id: \.self) { r in
                        let c = Card(rankIndex: r, suit: suit)
                        Button { onPick(c) } label: { CardView(card: c, width: 30, fourColor: app.settings.fourColor, dimmed: used.contains(c)) }
                            .buttonStyle(.plain)
                            .disabled(used.contains(c))
                    }
                }
            }
            Button("Clear") { onPick(nil) }
        }
        .padding(12)
    }
}

struct RangeGrid: View {
    @Binding var range: Set<HandClass>
    let onChange: () -> Void
    @State private var topPct: Double = 15

    static func hand(row: Int, col: Int) -> HandClass {
        let r = 12 - row, c = 12 - col
        if r == c { return HandClass(high: r, low: r, suited: false) }
        return col > row ? HandClass(high: r, low: c, suited: true) : HandClass(high: c, low: r, suited: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<13, id: \.self) { row in
                    GridRow {
                        ForEach(0..<13, id: \.self) { col in
                            let h = Self.hand(row: row, col: col)
                            let on = range.contains(h)
                            Button {
                                if on { range.remove(h) } else { range.insert(h) }
                                onChange()
                            } label: {
                                Text(h.description)
                                    .font(.system(size: 9, weight: .medium))
                                    .frame(width: 32, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(on ? Theme.red : (h.isPair ? Theme.panelHi : (h.suited ? Theme.panel : Color(white: 0.09)))))
                                    .foregroundStyle(on ? .white : .white.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack {
                Text("Top \(Int(topPct))%").font(.system(size: 11)).frame(width: 60)
                Slider(value: $topPct, in: 1...100, step: 1)
                Button("Fill") {
                    range = Set(HandClass.all.filter { RangeModel.standard.inTop(topPct / 100, $0) })
                    onChange()
                }
                Button("Clear") { range = []; onChange() }
            }
        }
        .padding(12)
    }
}
