import PokerCore
import SwiftUI

/// End-of-session feedback: result, stats vs a winning 1/2 profile, ranked leaks with drills, and a Claude review.
struct SessionReportView: View {
    @Environment(AppModel.self) private var app
    let game: GameController
    let startNewAfter: Bool

    var feedback: SessionFeedback {
        SessionFeedback.make(stats: game.stats, hero: game.heroStats, notes: game.history.flatMap(\.notes), bigBlind: 2)
    }

    var body: some View {
        let f = feedback
        ModalCard(title: "Session report", width: 760, onClose: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(f.headline).font(Theme.ui(19, .semibold)).tracking(-0.2)
                        HStack(spacing: 8) {
                            StatBox(label: "Hands", value: "\(game.stats.hands)")
                            StatBox(label: "Net", value: (game.stats.net >= 0 ? "+$" : "-$") + "\(abs(game.stats.net))",
                                    color: game.stats.net >= 0 ? Theme.good : Theme.bad)
                            StatBox(label: "bb/100", value: String(format: "%.1f", game.bbPer100))
                            StatBox(label: "Good / Inacc / Mist", value: "\(game.stats.good) / \(game.stats.inaccuracies) / \(game.stats.mistakes)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Your stats vs a winning live 1/2 player")
                        HStack(spacing: 6) {
                            ForEach(f.benchmarks) { b in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.name).font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                                    Text(b.value == nil ? "–" : b.display).font(Theme.mono(15, .semibold))
                                        .foregroundStyle(b.value == nil ? Theme.textFaint : color(b.status))
                                    Text(target(b)).font(Theme.mono(9.5)).foregroundStyle(Theme.textFaint)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Feedback")
                        ForEach(f.findings) { item in
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 1).fill(color(item.level)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(Theme.ui(14, .semibold))
                                    Text(item.detail).font(Theme.ui(13)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if let d = item.drill {
                                    Button("Drill: \(d.title)") {
                                        app.modal = nil
                                        app.openDrill(d)
                                    }
                                    .buttonStyle(PillButtonStyle(prominent: false, small: true))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            app.openChat(title: "Session review", context: game.sessionReport(), question: LiveTableScreen.sessionQuestion)
                        } label: { Text("Full review with Claude") }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .disabled(!app.settings.hasKey)
                            .help(app.settings.hasKey ? "" : "Add an Anthropic API key in Settings")
                        Spacer()
                        if startNewAfter {
                            Button("Start fresh session") { close() }
                                .buttonStyle(PillButtonStyle())
                                .keyboardShortcut(.return, modifiers: [])
                        } else {
                            Button("Keep playing") { close() }
                                .buttonStyle(PillButtonStyle())
                                .keyboardShortcut(.return, modifiers: [])
                        }
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: 640)
        }
    }

    func close() {
        if startNewAfter { game.newTable(preset: game.preset, seats: game.session.seatCount) }
        app.modal = nil
    }

    func target(_ b: SessionFeedback.Benchmark) -> String {
        let lo = b.target.lowerBound, hi = b.target.upperBound
        return b.name == "AF" ? String(format: "%.0f–%.1f", lo, hi) : "\(Int(lo))–\(Int(hi))%"
    }

    func color(_ l: SessionFeedback.Level) -> Color {
        switch l {
        case .good: Theme.good
        case .watch: Theme.warn
        case .leak: Theme.bad
        }
    }
}

/// Claude conversation as a right-side drawer inside the window.
struct ChatDrawer: View {
    @Environment(AppModel.self) private var app
    let chat: CoachChat
    @State private var followUp = ""

    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.title).font(Theme.ui(15, .semibold))
                        Text("Claude · \(app.settings.model)").font(Theme.mono(10.5)).foregroundStyle(Theme.textFaint)
                    }
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface2))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 14)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(chat.turns.enumerated()), id: \.offset) { _, turn in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("YOU").font(Theme.mono(10)).foregroundStyle(Theme.textFaint).padding(.top, 2)
                                    Text(turn.question).font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                                }
                                .padding(.bottom, 4)
                                if turn.answer.isEmpty && chat.isStreaming {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Thinking…").font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
                                    }
                                } else {
                                    MarkdownText(text: turn.answer)
                                }
                            }
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1).offset(y: 10) }
                        }
                        if let e = chat.error {
                            Text(e).foregroundStyle(Theme.bad).font(Theme.ui(12.5))
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 8) {
                    TextField("Ask a follow-up…", text: $followUp)
                        .textFieldStyle(BlockFieldStyle())
                        .onSubmit(send)
                    Button("Send", action: send)
                        .buttonStyle(PillButtonStyle())
                        .disabled(followUp.isEmpty || chat.isStreaming)
                }
                .padding(14)
            }
            .frame(width: 520)
            .frame(maxHeight: .infinity)
            .background(Theme.card)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.borderStrong).frame(width: 1) }
            .transition(.move(edge: .trailing))
        }
        .ignoresSafeArea()
    }

    func close() {
        chat.cancel()
        app.chat = nil
    }

    func send() {
        guard !followUp.isEmpty, !chat.isStreaming else { return }
        chat.ask(followUp, settings: app.settings)
        followUp = ""
    }
}
