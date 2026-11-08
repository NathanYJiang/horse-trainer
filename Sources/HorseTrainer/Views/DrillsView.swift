import PokerCore
import SwiftUI

struct SpotScene: View {
    @Environment(AppModel.self) private var app
    let villainName: String
    let villainType: PlayerType
    let villainAppearance: String?
    let history: [String]
    let board: [Card]
    let heroCards: [Card]
    let pot: Int
    let bet: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: villainName, hue: Double(villainName.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 100) / 100, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(villainName).font(Theme.ui(15, .semibold))
                        TypeBadge(type: villainType)
                    }
                    if let a = villainAppearance { Text(a).font(Theme.ui(12)).foregroundStyle(Theme.textDim) }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    SectionLabel("Pot")
                    Text("$\(pot)").font(Theme.mono(18))
                    if let b = bet {
                        Text("Facing $\(b)").font(Theme.mono(12)).foregroundStyle(Theme.red)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(history, id: \.self) { line in
                    Text(line).font(Theme.ui(13)).foregroundStyle(Color(white: 0.85))
                }
            }
            HStack(alignment: .bottom, spacing: 28) {
                if !board.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Board")
                        HStack(spacing: 6) {
                            ForEach(board, id: \.self) { CardView(card: $0, width: 54, fourColor: app.settings.fourColor) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("You")
                    HStack(spacing: 6) {
                        ForEach(heroCards, id: \.self) { CardView(card: $0, width: 58, fourColor: app.settings.fourColor) }
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.felt))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.rail, lineWidth: 6))
        }
    }
}

struct DrillsView: View {
    @Environment(AppModel.self) private var app
    @State private var concept: DrillConcept?
    @State private var type: PlayerType?
    @State private var drill: SpotDrill?
    @State private var picked: Int?
    @State private var streak = 0
    @State private var sessionCorrect = 0
    @State private var sessionTotal = 0
    @State private var rng = SplitMix64(seed: UInt64.random(in: 0...UInt64.max))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let d = drill {
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                SectionLabel(d.concept.title)
                                Spacer()
                                Text("\(d.heroPosition.short) vs \(d.villainPosition.short) · eff. $\(d.effectiveStack)").font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                            }
                            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: d.villainAppearance, history: d.history,
                                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: d.villainBet)
                            Text(d.prompt).font(Theme.ui(15, .semibold))
                            HStack(spacing: 10) {
                                ForEach(d.options.indices, id: \.self) { i in
                                    Button { answer(i, d) } label: { Text(d.options[i]).frame(minWidth: 90) }
                                        .buttonStyle(PillButtonStyle(color: color(i, d), prominent: picked != nil))
                                        .disabled(picked != nil)
                                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                                }
                            }
                            if picked != nil { feedback(d) }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let c = app.drillConcept {
                concept = c
                app.drillConcept = nil
            }
            if drill == nil { next() }
        }
    }

    var header: some View {
        PageHeader(title: "Exploit Drills", subtitle: "Same spot, different villain, different answer. Learn what each type's action means.") {
            BlockMenu(label: "CONCEPT", selection: $concept,
                      options: [(DrillConcept?.none, "All")] + DrillConcept.allCases.map { (DrillConcept?.some($0), $0.title) })
            BlockMenu(label: "VILLAIN", selection: $type, options: [(PlayerType?.none, "Any")] + PlayerType.allCases.map { (PlayerType?.some($0), $0.name) })
            StatBox(label: "Session", value: "\(sessionCorrect)/\(sessionTotal) · streak \(streak)")
        }
        .onChange(of: concept) { next() }
        .onChange(of: type) { next() }
    }

    func color(_ i: Int, _ d: SpotDrill) -> Color {
        guard let p = picked else { return Theme.accent }
        if d.correct.contains(i) { return Theme.good }
        if i == p { return Theme.bad }
        return Theme.panelHi
    }

    func answer(_ i: Int, _ d: SpotDrill) {
        picked = i
        let ok = d.correct.contains(i)
        sessionTotal += 1
        if ok { sessionCorrect += 1; streak += 1 } else { streak = 0 }
        app.store.recordDrill(d.concept, d.villainType, correct: ok)
    }

    func next() {
        picked = nil
        drill = DrillFactory.make(concept: concept, type: type, rng: &rng)
    }

    @ViewBuilder
    func feedback(_ d: SpotDrill) -> some View {
        let ok = d.correct.contains(picked!)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(ok ? "Correct" : "Not quite").font(Theme.ui(15, .semibold)).foregroundStyle(ok ? Theme.good : Theme.bad)
                Text("Best: \(d.correct.sorted().map { d.options[$0] }.joined(separator: " or "))").foregroundStyle(Theme.textDim)
            }
            Text(d.explanation).font(Theme.ui(13)).fixedSize(horizontal: false, vertical: true)
            PrincipleCard(principle: d.principle)
            VStack(alignment: .leading, spacing: 6) {
                Text("SAME SPOT VS EACH TYPE").font(Theme.ui(10, .bold)).foregroundStyle(Theme.textDim)
                ForEach(d.perType, id: \.type) { row in
                    HStack(alignment: .top, spacing: 10) {
                        TypeBadge(type: row.type, small: true).frame(width: 110, alignment: .leading)
                        Text(row.answer).font(Theme.ui(12, .semibold)).frame(width: 130, alignment: .leading)
                        Text(row.why).font(Theme.ui(11)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(row.type == d.villainType ? 1 : 0.7)
                }
            }
            HStack {
                Button {
                    app.openChat(title: d.concept.title, context: d.asText + "\nHero picked: \(d.options[picked!])",
                                 question: "Explain this spot more deeply vs this player type. Use the inverse question, and explain why the answer changes vs other types.")
                } label: { Text("Ask Claude") }
                    .buttonStyle(PillButtonStyle(prominent: false))
                Spacer()
                Button { next() } label: { Label("Next spot", systemImage: "arrow.right") }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}
