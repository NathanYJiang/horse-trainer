import PokerCore
import SwiftUI

/// 13×13 hand matrix with click-and-drag painting.
struct RangeMatrix: View {
    @Binding var range: Set<HandClass>
    var editable = true
    var cellWidth: CGFloat = 46
    var cellHeight: CGFloat = 34
    var showRank = false
    /// When set, colors cells by correct / missed / extra against this target.
    var target: Set<HandClass>?

    @State private var paintAdd: Bool?
    @State private var lastCell: HandClass?

    let spacing: CGFloat = 2

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<13, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<13, id: \.self) { col in
                        cell(RangeGrid.hand(row: row, col: col))
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard let h = hand(at: v.location) else { return }
                    if paintAdd == nil { paintAdd = !range.contains(h) }
                    guard h != lastCell else { return }
                    lastCell = h
                    if paintAdd == true { range.insert(h) } else { range.remove(h) }
                }
                .onEnded { _ in
                    paintAdd = nil
                    lastCell = nil
                },
            including: editable ? .all : .none
        )
    }

    func hand(at p: CGPoint) -> HandClass? {
        let col = Int(p.x / (cellWidth + spacing))
        let row = Int(p.y / (cellHeight + spacing))
        guard (0..<13).contains(col), (0..<13).contains(row) else { return nil }
        return RangeGrid.hand(row: row, col: col)
    }

    func fill(_ h: HandClass) -> Color {
        let on = range.contains(h)
        if let t = target {
            switch (on, t.contains(h)) {
            case (true, true): return Theme.good
            case (false, true): return Theme.bad.opacity(0.75)
            case (true, false): return Theme.warn
            case (false, false): return Theme.surface2
            }
        }
        if on { return Theme.text }
        return h.isPair ? Theme.surface3 : Theme.surface2
    }

    func cell(_ h: HandClass) -> some View {
        VStack(spacing: 0) {
            Text(h.description).font(Theme.mono(cellWidth > 40 ? 11 : 9, .medium))
            if showRank {
                Text("\(max(1, Int((RangeModel.standard.percentile(of: h) * 100).rounded(.up))))%")
                    .font(Theme.mono(8.5, .regular))
                    .opacity(0.6)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .background(Rectangle().fill(fill(h)))
        .foregroundStyle(target != nil ? (range.contains(h) || target!.contains(h) ? Color.white : Theme.textFaint) : (range.contains(h) ? Theme.onPrimary : Theme.textDim))
    }
}

struct RangeBuilderView: View {
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeader(title: "Range Builder", subtitle: "Know what the top 10, 15 or 20% of hands looks like, and what each player type actually plays.") {
                    BlockTabs(selection: $mode, options: [(0, "Builder"), (1, "Quiz")])
                }
            }
            .padding(20)
            if mode == 0 { BuilderPane() } else { RangeQuizPane() }
        }
    }
}

private struct BuilderPane: View {
    @Environment(AppModel.self) private var app
    @State private var range: Set<HandClass> = RangeModel.standard.top(0.15)
    @State private var topPct: Double = 15
    @State private var notation = ""
    @State private var showRank = false
    @State private var simType: PlayerType = .reg
    @State private var simPos: Position = .co
    @State private var simAction = 0
    @State private var saveName = ""

    var combos: Int { RangeParser.comboCount(range) }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    RangeMatrix(range: $range, showRank: showRank)
                    HStack(spacing: 14) {
                        legend(Theme.text, "In range")
                        legend(Theme.surface3, "Pairs")
                        Text("Upper right = suited, lower left = offsuit. Click or drag to paint.")
                            .font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                        Spacer()
                        Button(showRank ? "Hide rank %" : "Show rank %") { showRank.toggle() }
                            .buttonStyle(PillButtonStyle(color: Theme.surface3, prominent: showRank, small: true))
                    }
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: 14) {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(String(format: "%.1f%%", Double(combos) / 13.26)).font(Theme.mono(26))
                                Text("of hands · \(combos) combos").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                            }
                            let pairs = range.filter(\.isPair).reduce(0) { $0 + $1.combos }
                            let suited = range.filter(\.suited).reduce(0) { $0 + $1.combos }
                            Text("Pairs \(pairs) · Suited \(suited) · Offsuit \(combos - pairs - suited)")
                                .font(Theme.mono(11, .regular)).foregroundStyle(Theme.textDim)
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Top X% of hands")
                            HStack {
                                BlockSlider(value: $topPct, range: 1...100, step: 1) { range = RangeModel.standard.top(topPct / 100) }
                                Text("\(Int(topPct))%").font(Theme.mono(13)).frame(width: 40, alignment: .trailing)
                            }
                            HStack(spacing: 5) {
                                ForEach([5, 10, 15, 20, 25, 30, 40, 50], id: \.self) { p in
                                    Button("\(p)") {
                                        topPct = Double(p)
                                        range = RangeModel.standard.top(Double(p) / 100)
                                    }
                                    .buttonStyle(PillButtonStyle(color: Theme.surface3, prominent: Int(topPct) == p, small: true))
                                }
                            }
                            Text("Ranked by all-in equity vs 1 and 3 random hands, since live pots are often multiway.")
                                .font(Theme.ui(10.5)).foregroundStyle(Theme.textDim)
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Notation")
                            TextEditor(text: $notation)
                                .font(Theme.mono(12, .regular))
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(height: 64)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bg))
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                            HStack {
                                Button("Apply") { if let r = RangeParser.parse(notation) { range = r } }
                                    .buttonStyle(PillButtonStyle(prominent: false, small: true))
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(notation, forType: .string)
                                }
                                .buttonStyle(PillButtonStyle(prominent: false, small: true))
                                Button("Clear") { range = [] }
                                    .buttonStyle(PillButtonStyle(prominent: false, small: true))
                            }
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("How the table plays (first in)")
                            HStack {
                                BlockMenu(label: "TYPE", selection: $simType, options: PlayerType.allCases.map { ($0, $0.name) })
                                BlockMenu(label: "SEAT", selection: $simPos, options: [Position.utg, .utg1, .mp, .lj, .hj, .co, .btn, .sb].map { ($0, $0.short) })
                            }
                            BlockTabs(selection: $simAction, options: [(0, "Open-raise"), (1, "Limp"), (2, "All VPIP")])
                            let r = BotBrain.unopenedRanges(profile: Profile.base(simType), position: simPos)
                            Text("\(simType.name) from \(simPos.short): raises \(pct(r.raise)), limps \(pct(r.limp)).")
                                .font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                            Button("Load range") { range = simAction == 0 ? r.raise : (simAction == 1 ? r.limp : r.raise.union(r.limp)) }
                                .buttonStyle(PillButtonStyle(small: true))
                        }
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Saved ranges")
                            HStack {
                                TextField("Name, e.g. Nit 3-bet", text: $saveName).textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    guard !saveName.isEmpty else { return }
                                    app.store.saveRange(saveName, RangeParser.compact(range))
                                    saveName = ""
                                }
                                .buttonStyle(PillButtonStyle(prominent: false, small: true))
                                .disabled(saveName.isEmpty || range.isEmpty)
                            }
                            ForEach(app.store.progress.savedRanges.keys.sorted(), id: \.self) { name in
                                HStack {
                                    Button(name) { if let r = RangeParser.parse(app.store.progress.savedRanges[name] ?? "") { range = r } }
                                        .buttonStyle(.plain)
                                        .font(Theme.ui(12))
                                    Spacer()
                                    Button { app.store.deleteRange(name) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Theme.textDim)
                                }
                            }
                            if app.store.progress.savedRanges.isEmpty {
                                Text("None yet.").font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                }
                .frame(width: 330)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onChange(of: range) { notation = RangeParser.compact(range) }
        .onAppear { notation = RangeParser.compact(range) }
    }

    func pct(_ r: Set<HandClass>) -> String {
        String(format: "%.0f%%", Double(RangeParser.comboCount(r)) / 13.26)
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(c).frame(width: 10, height: 10)
            Text(t).font(Theme.ui(11)).foregroundStyle(Theme.textDim)
        }
    }
}

private struct RangeQuizPane: View {
    @Environment(AppModel.self) private var app
    @State private var kind = 0
    @State private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))

    // Paint
    @State private var target: Double = 15
    @State private var painted: Set<HandClass> = []
    @State private var submitted = false

    // In or out
    @State private var probeHand = HandClass("K9s")!
    @State private var probeCards: [Card] = []
    @State private var probePct = 20
    @State private var probeAnswer: Bool?
    @State private var streak = 0

    // Name the %
    @State private var namePct = 15
    @State private var namePick: Int?

    let pctChoices = [5, 10, 15, 20, 25, 30, 40, 50]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BlockTabs(selection: $kind, options: [(0, "Paint the top X%"), (1, "In or out?"), (2, "Name the %")])
                switch kind {
                case 0: paintQuiz
                case 1: inOutQuiz
                default: nameQuiz
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { newPaint(); newProbe(); newName() }
    }

    // MARK: Paint the top X%

    var paintScore: Double {
        let t = RangeModel.standard.top(target / 100)
        let inter = RangeParser.comboCount(t.intersection(painted))
        let union = RangeParser.comboCount(t.union(painted))
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    var paintQuiz: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paint the top \(Int(target))% of hands").font(Theme.ui(16, .semibold))
                RangeMatrix(range: $painted, editable: !submitted, target: submitted ? RangeModel.standard.top(target / 100) : nil)
                if submitted {
                    HStack(spacing: 14) {
                        legendBox(Theme.good, "Correct")
                        legendBox(Theme.bad.opacity(0.75), "Missed")
                        legendBox(Theme.warn, "Extra")
                    }
                }
            }
            .fixedSize()
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Your range")
                    Text(String(format: "%.1f%% painted", Double(RangeParser.comboCount(painted)) / 13.26)).font(Theme.mono(18))
                    if submitted {
                        let score = paintScore
                        Text(String(format: "Overlap %.0f%%", score * 100)).font(Theme.mono(22)).foregroundStyle(score >= 0.85 ? Theme.good : Theme.warn)
                        Text(score >= 0.85 ? "Nice. That's close enough to use at the table." : "Compare the missed and extra cells. Small pairs and offsuit broadways are the usual misses.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                        Text("Answer: \(RangeParser.compact(RangeModel.standard.top(target / 100)))")
                            .font(Theme.mono(11, .regular)).foregroundStyle(Color(white: 0.8)).textSelection(.enabled)
                        Button("Next  →") { newPaint() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.return, modifiers: [])
                    } else {
                        Button("Submit") {
                            submitted = true
                            app.store.recordRangeQuiz("paint", correct: paintScore >= 0.85)
                        }
                        .buttonStyle(PillButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                        Button("Clear") { painted = [] }.buttonStyle(PillButtonStyle(prominent: false))
                    }
                }
            }
            .frame(width: 300)
        }
    }

    func newPaint() {
        target = Double([5, 10, 15, 20, 25, 30].randomElement(using: &rng)!)
        painted = []
        submitted = false
    }

    // MARK: In or out

    var inOutQuiz: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Is this hand in the top \(probePct)%?").font(Theme.ui(16, .semibold))
                HStack(spacing: 6) {
                    ForEach(probeCards, id: \.self) { CardView(card: $0, width: 64, fourColor: app.settings.fourColor) }
                    Text(probeHand.description).font(Theme.mono(22)).padding(.leading, 10)
                }
                HStack(spacing: 8) {
                    Button("In") { answerProbe(true) }.buttonStyle(PillButtonStyle(large: true)).keyboardShortcut("y", modifiers: [])
                        .disabled(probeAnswer != nil)
                    Button("Out") { answerProbe(false) }.buttonStyle(PillButtonStyle(prominent: false, large: true)).keyboardShortcut("n", modifiers: [])
                        .disabled(probeAnswer != nil)
                    Spacer()
                    StatBox(label: "Streak", value: "\(streak)")
                }
                if let a = probeAnswer {
                    let p = RangeModel.standard.percentile(of: probeHand)
                    let isIn = p <= Double(probePct) / 100
                    let rank = (RangeModel.standard.order.firstIndex(of: probeHand) ?? 0) + 1
                    Text(a == isIn ? "Correct." : "Wrong.").font(Theme.ui(14, .semibold)).foregroundStyle(a == isIn ? Theme.good : Theme.bad)
                    Text("\(probeHand) is hand #\(rank) of 169. The top \(String(format: "%.1f", p * 100))% of hands includes it, so it's \(isIn ? "in" : "out") at \(probePct)%.")
                        .font(Theme.ui(12)).foregroundStyle(Color(white: 0.8))
                    Button("Next  →") { newProbe() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .frame(maxWidth: 560)
    }

    func answerProbe(_ saidIn: Bool) {
        guard probeAnswer == nil else { return }
        probeAnswer = saidIn
        let isIn = RangeModel.standard.percentile(of: probeHand) <= Double(probePct) / 100
        streak = saidIn == isIn ? streak + 1 : 0
        app.store.recordRangeQuiz("inout", correct: saidIn == isIn)
    }

    func newProbe() {
        probePct = pctChoices.randomElement(using: &rng)!
        // Pick hands near the boundary so it's actually a test.
        let near = HandClass.all.filter { abs(RangeModel.standard.percentile(of: $0) - Double(probePct) / 100) < 0.07 }
        probeHand = (near.isEmpty ? HandClass.all : near).randomElement(using: &rng)!
        probeCards = DrillFactory.cards(for: probeHand, rng: &rng)
        probeAnswer = nil
    }

    // MARK: Name the %

    var nameQuiz: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What percentage of hands is this?").font(Theme.ui(16, .semibold))
                RangeMatrix(range: .constant(RangeModel.standard.top(Double(namePct) / 100)), editable: false, cellWidth: 38, cellHeight: 28)
            }
            .fixedSize()
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Pick one")
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(60)), count: 4), spacing: 8) {
                        ForEach(pctChoices, id: \.self) { p in
                            Button("\(p)%") {
                                guard namePick == nil else { return }
                                namePick = p
                                app.store.recordRangeQuiz("name", correct: p == namePct)
                            }
                            .buttonStyle(PillButtonStyle(color: namePick == nil ? Theme.surface3 : (p == namePct ? Theme.good : (p == namePick ? Theme.bad : Theme.surface3)),
                                                         prominent: true))
                        }
                    }
                    if let p = namePick {
                        Text(p == namePct ? "Correct." : "It's the top \(namePct)%.").font(Theme.ui(13, .semibold))
                            .foregroundStyle(p == namePct ? Theme.good : Theme.bad)
                        Button("Next  →") { newName() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .frame(width: 300)
        }
    }

    func newName() {
        namePct = pctChoices.randomElement(using: &rng)!
        namePick = nil
    }

    func legendBox(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(c).frame(width: 10, height: 10)
            Text(t).font(Theme.ui(11)).foregroundStyle(Theme.textDim)
        }
    }
}
