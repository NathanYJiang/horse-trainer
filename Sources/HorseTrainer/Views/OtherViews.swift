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
                                        Text(t.name).font(.system(size: 16, weight: .semibold))
                                        Text("VPIP \(Int(t.vpipBand.lowerBound * 100))–\(Int(t.vpipBand.upperBound * 100)) · PFR \(Int(t.pfrBand.lowerBound * 100))–\(Int(t.pfrBand.upperBound * 100))")
                                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                                    }
                                }
                                Text(t.oneLiner).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                                section("Tendencies", pb.tendencies, Theme.accent)
                                section("Tells", pb.tells, Theme.warn)
                                section("Exploits", pb.exploits, Theme.good)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Principles").font(.system(size: 18, weight: .bold)).padding(.top, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 10)], spacing: 10) {
                    ForEach(Principle.allCases) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            PrincipleCard(principle: p)
                            Text(p.source).font(.system(size: 9)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    func section(_ title: String, _ items: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            ForEach(items, id: \.self) { Text("• \($0)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)) }
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
                        Text("Live sessions").font(.system(size: 14, weight: .bold))
                        if p.sessions.isEmpty { Text("No sessions yet. Sessions are saved when you start a new table or quit.").font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                        ForEach(p.sessions.reversed()) { s in
                            HStack {
                                Text(s.date.formatted(date: .abbreviated, time: .shortened)).frame(width: 170, alignment: .leading)
                                Text(s.preset).frame(width: 220, alignment: .leading).foregroundStyle(Theme.textDim)
                                Text("\(s.hands) hands").frame(width: 90, alignment: .leading)
                                Text(s.net >= 0 ? "+$\(s.net)" : "-$\(abs(s.net))").foregroundStyle(s.net >= 0 ? Theme.good : Theme.bad).frame(width: 80, alignment: .leading)
                                Text("\(s.good) good · \(s.inaccuracies) inacc · \(s.mistakes) mistakes")
                                Spacer()
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Read-the-table quizzes").font(.system(size: 14, weight: .bold))
                        if p.quizzes.isEmpty { Text("No quizzes yet.").font(.system(size: 12)).foregroundStyle(Theme.textDim) }
                        ForEach(p.quizzes.reversed()) { q in
                            Text("\(q.date.formatted(date: .abbreviated, time: .shortened)) · \(q.correct)/\(q.total) after \(q.handsObserved) hands")
                                .font(.system(size: 12))
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
                Text(title).font(.system(size: 14, weight: .bold))
                ForEach(rows, id: \.0) { row in
                    HStack(spacing: 8) {
                        Text(row.0).font(.system(size: 11)).frame(width: 140, alignment: .leading).lineLimit(1)
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
                            .font(.system(size: 11, design: .monospaced)).frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var s = app.settings
        Form {
            Section("Table") {
                Picker("Default table", selection: $s.defaultPreset) {
                    ForEach(TablePreset.allCases) { Text($0.name).tag($0) }
                }
                HStack {
                    Text("Bot speed")
                    Slider(value: $s.botSpeed, in: 0.15...1.5)
                    Text(String(format: "%.1fs", s.botSpeed)).monospacedDigit().frame(width: 40)
                }
                Toggle("Auto-deal next hand", isOn: $s.autoDeal)
                Toggle("Straddle when I'm UTG", isOn: $s.heroStraddles)
                Toggle("Four-color deck", isOn: $s.fourColor)
                Toggle("Instant coach feedback (grade each decision as you make it)", isOn: $s.instantFeedback)
            }
            Section {
                SecureField("Anthropic API key", text: $s.apiKey)
                Picker("Model", selection: $s.model) {
                    ForEach(ClaudeClient.models, id: \.self) { Text($0).tag($0) }
                }
                Picker("Effort", selection: $s.effort) {
                    ForEach(["low", "medium", "high"], id: \.self) { Text($0).tag($0) }
                }
                Text(app.settings.hasKey ? "Claude coaching is enabled." : "Add a key (saved only on this Mac, readable only by your user) or launch with ANTHROPIC_API_KEY set.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            } header: {
                Text("Claude coach")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

struct ClaudeChatSheet: View {
    @Environment(AppModel.self) private var app
    let chat: CoachChat
    @State private var followUp = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(chat.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(app.settings.model).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                Button("Close") {
                    chat.cancel()
                    app.chat = nil
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(chat.turns.enumerated()), id: \.offset) { _, turn in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(turn.question)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.18)))
                            if turn.answer.isEmpty && chat.isStreaming {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Claude is thinking…").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                                }
                            } else {
                                MarkdownText(text: turn.answer)
                            }
                        }
                    }
                    if let e = chat.error {
                        Text(e).foregroundStyle(Theme.bad).font(.system(size: 12))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                TextField("Ask a follow-up…", text: $followUp)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Send", action: send).disabled(followUp.isEmpty || chat.isStreaming)
            }
            .padding(12)
        }
        .frame(width: 640, height: 640)
    }

    func send() {
        guard !followUp.isEmpty, !chat.isStreaming else { return }
        chat.ask(followUp, settings: app.settings)
        followUp = ""
    }
}
