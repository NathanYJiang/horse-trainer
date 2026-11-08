import PokerCore
import SwiftUI

struct SizingLabView: View {
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Sizing Lab", subtitle: "Bet the most they'll call. Read what their bet means.") {
                BlockTabs(selection: $mode, options: [(0, "Inverse Question"), (1, "Read Their Bet"), (2, "Size It")])
            }
            .padding(20)
            switch mode {
            case 0: ValueQuestionView()
            case 1: InverseQuestionView()
            default: SizeItView()
            }
        }
    }
}

struct InverseQuestionView: View {
    @Environment(AppModel.self) private var app
    @State private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    @State private var drill: InverseDrill?
    @State private var step = 0
    @State private var answers: [Int: Int] = [:]
    @State private var type: PlayerType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BlockMenu(label: "VILLAIN", selection: $type, options: [(PlayerType?.none, "Any")] + PlayerType.allCases.map { (PlayerType?.some($0), $0.name) })
                    Spacer()
                }
                .onChange(of: type) { next() }
                if let d = drill {
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: nil, history: d.history,
                                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: d.bet)
                            ForEach(0..<min(step + 1, d.questions.count), id: \.self) { qi in
                                questionView(d.questions[qi], index: qi)
                            }
                            if step >= d.questions.count {
                                HStack {
                                    let score = d.questions.indices.filter { qi in answers[qi].map { d.questions[qi].correct.contains($0) } ?? false }.count
                                    Text("Score: \(score)/\(d.questions.count)").font(Theme.ui(15, .bold))
                                    Spacer()
                                    Button {
                                        app.openChat(title: "Inverse question", context: d.asText,
                                                     question: "Walk me through the inverse question for this spot: how this player type bets each part of their range here, what their actual size means, and my best response.")
                                    } label: { Text("Ask Claude") }
                                        .buttonStyle(PillButtonStyle(prominent: false))
                                    Button { next() } label: { Text("Next spot  →") }
                                        .buttonStyle(PillButtonStyle())
                                        .keyboardShortcut(.return, modifiers: [])
                                }
                                PrincipleCard(principle: .inverseQuestion)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { if drill == nil { next() } }
    }

    @ViewBuilder
    func questionView(_ q: LabQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1). \(q.prompt)").font(Theme.ui(14, .semibold))
            HStack(spacing: 8) {
                ForEach(q.options.indices, id: \.self) { i in
                    Button(q.options[i]) { pick(i, index, q) }
                        .buttonStyle(PillButtonStyle(color: color(i, index, q), prominent: answers[index] != nil))
                        .disabled(answers[index] != nil)
                }
            }
            if let a = answers[index] {
                HStack(alignment: .top, spacing: 6) {
                    Text(q.correct.contains(a) ? "Correct." : "Wrong.").font(Theme.ui(12, .semibold)).foregroundStyle(q.correct.contains(a) ? Theme.good : Theme.bad)
                    Text(q.explanation).font(Theme.ui(12)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface2))
    }

    func color(_ i: Int, _ qi: Int, _ q: LabQuestion) -> Color {
        guard let a = answers[qi] else { return Theme.accent }
        if q.correct.contains(i) { return Theme.good }
        if i == a { return Theme.bad }
        return Theme.panelHi
    }

    func pick(_ i: Int, _ qi: Int, _ q: LabQuestion) {
        answers[qi] = i
        app.store.recordInverse(drill!.villainType, correct: q.correct.contains(i))
        step = qi + 1
    }

    func next() {
        drill = SizingLab.inverse(type: type, rng: &rng)
        step = 0
        answers = [:]
    }
}

struct SizeItView: View {
    @Environment(AppModel.self) private var app
    @State private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    @State private var drill: SizeItDrill?
    @State private var fraction: Double = 0.5
    @State private var result: (correct: Bool, message: String)?
    @State private var type: PlayerType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BlockMenu(label: "VILLAIN", selection: $type, options: [(PlayerType?.none, "Any")] + PlayerType.allCases.map { (PlayerType?.some($0), $0.name) })
                    Spacer()
                }
                .onChange(of: type) { next() }
                if let d = drill {
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: nil, history: d.history,
                                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: nil)
                            Text("You have \(d.handText). Pick your size.").font(Theme.ui(15, .semibold))
                            HStack(spacing: 14) {
                                Text(fraction <= 0 ? "Check" : "\(Int(fraction * 100))% pot · $\(Int(Double(d.pot) * fraction))")
                                    .font(Theme.mono(17))
                                    .frame(width: 200, alignment: .leading)
                                BlockSlider(value: $fraction, range: 0...2, step: 0.05).disabled(result != nil)
                            }
                            HStack(spacing: 8) {
                                ForEach([("Check", 0.0), ("33%", 0.33), ("50%", 0.5), ("66%", 0.66), ("75%", 0.75), ("Pot", 1.0), ("150%", 1.5), ("2x", 2.0)], id: \.0) { item in
                                    Button(item.0) { fraction = item.1 }
                                        .buttonStyle(PillButtonStyle(prominent: false))
                                        .disabled(result != nil)
                                }
                                Spacer()
                                if result == nil {
                                    Button("Submit") {
                                        let r = d.grade(fraction: fraction)
                                        result = r
                                        app.store.recordSizeIt(d.villainType, correct: r.correct)
                                    }
                                    .buttonStyle(PillButtonStyle(color: Theme.good))
                                    .keyboardShortcut(.return, modifiers: [])
                                }
                            }
                            if let r = result {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(r.correct ? "Correct. \(r.message)" : "Not quite. \(r.message)")
                                        .font(Theme.ui(15, .bold))
                                        .foregroundStyle(r.correct ? Theme.good : Theme.bad)
                                    Text(d.explanation).font(Theme.ui(13))
                                    PrincipleCard(principle: d.principle)
                                    HStack {
                                        Spacer()
                                        Button { next() } label: { Text("Next  →") }
                                            .buttonStyle(PillButtonStyle())
                                            .keyboardShortcut(.return, modifiers: [])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { if drill == nil { next() } }
    }

    func next() {
        drill = SizingLab.sizeIt(type: type, rng: &rng)
        result = nil
        fraction = 0.5
    }
}


/// The inverse question for value: "If they have TPTK, what bet folds it? Bet just under that."
struct ValueQuestionView: View {
    @Environment(AppModel.self) private var app
    @State private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))
    @State private var drill: ValueDrill?
    @State private var answers: [Int: Int] = [:]
    @State private var type: PlayerType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BlockMenu(label: "VILLAIN", selection: $type, options: [(PlayerType?.none, "Any")] + PlayerType.allCases.map { (PlayerType?.some($0), $0.name) })
                    Spacer()
                }
                .onChange(of: type) { next() }
                if let d = drill {
                    Panel {
                        VStack(alignment: .leading, spacing: 14) {
                            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: nil, history: d.history,
                                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: nil)
                            Text("You have \(d.heroHandText) and can play for stacks (effective $\(d.effectiveStack)).")
                                .font(Theme.ui(13)).foregroundStyle(Color(white: 0.8))
                            ForEach(0..<min(answers.count + 1, d.questions.count), id: \.self) { qi in
                                question(d.questions[qi], index: qi, drill: d)
                            }
                            if answers.count >= d.questions.count { summary(d) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear { if drill == nil { next() } }
    }

    func question(_ q: LabQuestion, index: Int, drill d: ValueDrill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index + 1). \(q.prompt)").font(Theme.ui(13.5, .semibold))
            if index == 0 {
                HStack(spacing: 6) {
                    SectionLabel("Their hand")
                    ForEach(d.villainExample, id: \.self) { CardView(card: $0, width: 30, fourColor: app.settings.fourColor) }
                }
            }
            FlowButtons(options: q.options, picked: answers[index], correct: q.correct) { i in
                guard answers[index] == nil else { return }
                answers[index] = i
                app.store.recordValue(d.villainType, correct: q.correct.contains(i))
            }
            if let a = answers[index] {
                Text((q.correct.contains(a) ? "Correct. " : "Not quite. ") + q.explanation)
                    .font(Theme.ui(12))
                    .foregroundStyle(q.correct.contains(a) ? Theme.good : Color(white: 0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface2))
    }

    func summary(_ d: ValueDrill) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("What \(d.villainType.name.lowercased())s call here (\(d.street.name.lowercased()))")
            VStack(spacing: 0) {
                ForEach(d.callTable, id: \.holding) { row in
                    HStack {
                        Text(row.holding.label).font(Theme.ui(12))
                        Spacer()
                        Text("up to \(row.maxCall)").font(Theme.mono(12))
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(row.holding == d.villainHolding ? Theme.surface3 : .clear)
                }
            }
            .overlay(Rectangle().strokeBorder(Theme.border))
            Text(d.plan).font(Theme.ui(12)).foregroundStyle(Color(white: 0.85)).fixedSize(horizontal: false, vertical: true)
            PrincipleCard(principle: .inverseQuestion)
            HStack {
                Button("Ask Claude") {
                    app.openChat(title: "Inverse question", context: d.asText,
                                 question: "Walk me through the inverse question for value here: what's the most this player type calls with that hand, how should I size each street to get stacks or max value, and what changes vs other types?")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                Spacer()
                Button("Next spot  →") { next() }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    func next() {
        drill = SizingLab.valueDrill(type: type, rng: &rng)
        answers = [:]
    }
}

/// Wrapping row of answer buttons.
struct FlowButtons: View {
    let options: [String]
    let picked: Int?
    let correct: Set<Int>
    let onPick: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i]) { onPick(i) }
                    .buttonStyle(PillButtonStyle(color: color(i), prominent: picked != nil && (correct.contains(i) || picked == i)))
                    .disabled(picked != nil)
            }
        }
    }

    func color(_ i: Int) -> Color {
        guard let p = picked else { return Theme.surface3 }
        if correct.contains(i) { return Theme.good }
        if i == p { return Theme.bad }
        return Theme.surface3
    }
}
