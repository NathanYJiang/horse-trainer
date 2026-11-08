import PokerCore
import SwiftUI

struct PlaybookView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Playbook", subtitle: "Classify, then exploit. Every bot, drill and coach grade in the app runs on this model.") { EmptyView() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
                    ForEach(PlayerType.allCases) { t in
                        let pb = TypePlaybook.of(t)
                        Panel {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Rectangle().fill(Theme.color(for: t)).frame(width: 4, height: 34)
                                    VStack(alignment: .leading) {
                                        Text(t.name).font(Theme.ui(16, .semibold))
                                        Text("VPIP \(Int(t.vpipBand.lowerBound * 100))–\(Int(t.vpipBand.upperBound * 100)) · PFR \(Int(t.pfrBand.lowerBound * 100))–\(Int(t.pfrBand.upperBound * 100))")
                                            .font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                                    }
                                }
                                Text(t.oneLiner).font(Theme.ui(12)).foregroundStyle(.white.opacity(0.85))
                                section("Tendencies", pb.tendencies, Theme.accent)
                                section("Tells", pb.tells, Theme.warn)
                                section("Exploits", pb.exploits, Theme.good)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Principles").font(Theme.ui(18, .bold)).padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 10)], spacing: 10) {
                    ForEach(Principle.allCases) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            PrincipleCard(principle: p)
                            Text(p.source).font(Theme.ui(9)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    func section(_ title: String, _ items: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(Theme.ui(10, .bold)).foregroundStyle(color)
            ForEach(items, id: \.self) { Text("• \($0)").font(Theme.ui(12)).foregroundStyle(.white.opacity(0.85)) }
        }
    }
}

struct ProgressScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let p = app.store.progress
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Progress", subtitle: "Accuracy by concept and villain type, reads quizzes and live sessions.") {
                    Button("Reset all progress", role: .destructive) { app.store.reset() }
                        .buttonStyle(PillButtonStyle(color: Theme.bad, prominent: false))
                }
                HStack(alignment: .top, spacing: 14) {
                    tallyPanel("Drills by concept", DrillConcept.allCases.map { ($0.title, p.drillByConcept[$0.rawValue] ?? Tally()) })
                    tallyPanel("Drills by villain type", PlayerType.allCases.map { ($0.name, p.drillByType[$0.rawValue] ?? Tally()) })
                }
                HStack(alignment: .top, spacing: 14) {
                    tallyPanel("Inverse question (value)", PlayerType.allCases.map { ($0.name, p.valueByType[$0.rawValue] ?? Tally()) })
                    tallyPanel("Read their bet", PlayerType.allCases.map { ($0.name, p.inverseByType[$0.rawValue] ?? Tally()) })
                    tallyPanel("Size It", PlayerType.allCases.map { ($0.name, p.sizeItByType[$0.rawValue] ?? Tally()) })
                }
                HStack(alignment: .top, spacing: 14) {
                    tallyPanel("Classification accuracy", PlayerType.allCases.map { ($0.name, p.classifyByType[$0.rawValue] ?? Tally()) })
                    tallyPanel("Range quizzes", [("Paint top X%", p.rangeQuiz["paint"] ?? Tally()), ("In or out", p.rangeQuiz["inout"] ?? Tally()), ("Name the %", p.rangeQuiz["name"] ?? Tally())])
                }
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live sessions").font(Theme.ui(14, .bold))
                        if p.sessions.isEmpty { Text("No sessions yet. Sessions are saved when you start a new table or quit.").font(Theme.ui(12)).foregroundStyle(Theme.textDim) }
                        ForEach(p.sessions.reversed()) { s in
                            HStack {
                                Text(s.date.formatted(date: .abbreviated, time: .shortened)).frame(width: 170, alignment: .leading)
                                Text(s.preset).frame(width: 220, alignment: .leading).foregroundStyle(Theme.textDim)
                                Text("\(s.hands) hands").frame(width: 90, alignment: .leading)
                                Text(s.net >= 0 ? "+$\(s.net)" : "-$\(abs(s.net))").foregroundStyle(s.net >= 0 ? Theme.good : Theme.bad).frame(width: 80, alignment: .leading)
                                Text("\(s.good) good · \(s.inaccuracies) inacc · \(s.mistakes) mistakes")
                                Spacer()
                            }
                            .font(Theme.ui(12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Read-the-table quizzes").font(Theme.ui(14, .bold))
                        if p.quizzes.isEmpty { Text("No quizzes yet.").font(Theme.ui(12)).foregroundStyle(Theme.textDim) }
                        ForEach(p.quizzes.reversed()) { q in
                            Text("\(q.date.formatted(date: .abbreviated, time: .shortened)) · \(q.correct)/\(q.total) after \(q.handsObserved) hands")
                                .font(Theme.ui(12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    func tallyPanel(_ title: String, _ rows: [(String, Tally)]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.ui(14, .bold))
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 8) {
                        Text(row.0).font(Theme.ui(11)).frame(width: 140, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.panelHi)
                                Capsule().fill(row.1.rate >= 0.7 ? Theme.good : (row.1.rate >= 0.5 ? Theme.warn : Theme.bad))
                                    .frame(width: g.size.width * row.1.rate)
                                    .opacity(row.1.attempts == 0 ? 0 : 1)
                            }
                        }
                        .frame(height: 6)
                        Text(row.1.attempts == 0 ? "–" : "\(row.1.correct)/\(row.1.attempts)")
                            .font(Theme.mono(11, .regular)).frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var keyDraft = ""

    var body: some View {
        @Bindable var s = app.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Settings", subtitle: "Table feel, deck, and the Claude coach.") { EmptyView() }
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        row("Default table", "Mix used when the app starts") {
                            BlockMenu(label: "MIX", selection: $s.defaultPreset, options: TablePreset.allCases.map { ($0, $0.name) })
                        }
                        row("Bot speed", "Seconds per bot action") {
                            HStack(spacing: 10) {
                                BlockSlider(value: $s.botSpeed, range: 0.15...1.5, step: 0.05).frame(width: 180)
                                Text(String(format: "%.2fs", s.botSpeed)).font(Theme.mono(12)).frame(width: 46, alignment: .trailing)
                            }
                        }
                        row("Auto-deal", "Deal the next hand automatically") { toggle($s.autoDeal) }
                        row("Straddle when UTG", "Post a $5 straddle from under the gun") { toggle($s.heroStraddles) }
                        row("Four-color deck", "♠ black, ♥ red, ♦ blue, ♣ green") { toggle($s.fourColor) }
                        row("Instant feedback", "Grade each decision as you make it, not after the hand", last: true) { toggle($s.instantFeedback) }
                    }
                }
                SectionLabel("Claude coach")
                Panel(padding: 0) {
                    VStack(spacing: 0) {
                        row("API key", app.settings.hasKey ? "Connected. Stored only on this Mac." : "Needed for Claude reviews. Stored only on this Mac.") {
                            HStack(spacing: 8) {
                                SecureField(app.settings.apiKey.isEmpty ? "sk-ant-…" : "••••••••••••", text: $keyDraft)
                                    .textFieldStyle(BlockFieldStyle())
                                    .frame(width: 240)
                                Button("Save") {
                                    s.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                    keyDraft = ""
                                }
                                .buttonStyle(PillButtonStyle(prominent: false))
                                .disabled(keyDraft.isEmpty)
                            }
                        }
                        row("Model", "Which Claude model reviews your play") {
                            BlockMenu(label: "MODEL", selection: $s.model, options: ClaudeClient.models.map { ($0, $0) })
                        }
                        row("Effort", "Higher means deeper reviews, but they're slower", last: true) {
                            BlockTabs(selection: $s.effort, options: [("low", "Low"), ("medium", "Medium"), ("high", "High")])
                        }
                    }
                }
                HStack {
                    Button("Show the guide again") { app.showOnboarding = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    func row<C: View>(_ title: String, _ detail: String, last: Bool = false, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.ui(13.5, .medium))
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.border).frame(height: 1) } }
    }

    func toggle(_ b: Binding<Bool>) -> some View {
        Button { b.wrappedValue.toggle() } label: {
            ZStack(alignment: b.wrappedValue ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 5).fill(b.wrappedValue ? Theme.text : Theme.surface3).frame(width: 36, height: 20)
                RoundedRectangle(cornerRadius: 4).fill(b.wrappedValue ? Theme.bg : Theme.textDim).frame(width: 14, height: 14).padding(3)
            }
            .animation(.easeOut(duration: 0.12), value: b.wrappedValue)
        }
        .buttonStyle(.plain)
    }
}
