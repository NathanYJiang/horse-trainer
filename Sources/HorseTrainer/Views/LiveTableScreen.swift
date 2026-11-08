import PokerCore
import SwiftUI

struct LiveTableScreen: View {
    @Environment(AppModel.self) private var app
    let game: GameController
    @State private var tab: SideTab = .coach
    @State private var showNewTable = false

    static let sessionQuestion = """
    Analyze this live 1/2 session like a coach would after a session, using the live-exploit frameworks (Hungry Horse–style player types, \
    sizing tells, overfolding to passive aggression, value-betting stations) and standard 'how to beat 1/2' fundamentals (tight-aggressive \
    preflop, iso-raising limpers, big value bets, few bluffs into stations, table selection, bankroll and tilt). Give me:
    1. A short verdict on the session (results vs. quality of decisions; separate luck from skill).
    2. My biggest leaks, ranked, each with the concrete evidence from these hands and the fix.
    3. How well I adjusted to each player type at the table, and who I should have been targeting.
    4. My stats vs. a winning live 1/2 profile, and what's off.
    5. The top 3 things to drill next (name the app's drills: Exploit Drills concepts, Sizing Lab, Range Builder, Read the Table).
    """

    enum SideTab: String, CaseIterable {
        case coach = "Coach", reads = "Reads", history = "History"
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                if game.mode == .reads { readsBanner }
                PokerTableView(game: game, settings: app.settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ActionBar(game: game)
            }
            Rectangle().fill(Theme.border).frame(width: 1)
            sidePanel.frame(width: 340)
        }
        .background(Theme.bg)
        .sheet(isPresented: $showNewTable) { NewTableSheet(game: game) }
        .sheet(isPresented: Binding(get: { game.quiz != nil }, set: { if !$0 { game.dismissQuiz() } })) {
            if let q = game.quiz { QuizResultView(result: q) { game.dismissQuiz() } }
        }
        .onAppear {
            if game.mode == .reads {
                tab = .reads
                if game.hand == nil { game.dealNext() }
            }
            if GameController.autopilot && game.hand == nil && game.mode == .play { game.dealNext() }
        }
    }

    var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.mode == .reads ? "Read the Table" : "Live Table").font(.system(size: 15, weight: .semibold))
                Text("NL Hold'em $1/$2 · \(game.session.seatCount)-max · \(game.preset.name)").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 90, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 8)
            if game.mode == .play {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        StatBox(label: "Stack", value: "$\(game.stack(of: game.heroSeat))")
                        netBox
                        StatBox(label: "bb/100", value: String(format: "%.1f", game.bbPer100))
                        StatBox(label: "Hands", value: "\(game.stats.hands)")
                    }
                    HStack(spacing: 8) {
                        netBox
                        StatBox(label: "Hands", value: "\(game.stats.hands)")
                    }
                    EmptyView()
                }
            } else {
                StatBox(label: "Observed", value: "\(game.session.handNumber) hands")
                StatBox(label: "Tagged", value: "\(game.seats.filter { s in s.occupant.bot.map { game.tags[$0.id] != nil } ?? false }.count)/\(game.seats.filter { $0.occupant.bot != nil }.count)")
            }
            Rectangle().fill(Theme.border).frame(width: 1, height: 28).padding(.horizontal, 4)
            if game.mode == .play {
                Button("Review session") {
                    app.openChat(title: "Session review", context: game.sessionReport(), question: Self.sessionQuestion)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .fixedSize()
                .disabled(game.stats.hands < 10)
                .help(game.stats.hands < 10 ? "Play at least 10 hands first" : "Claude reviews your whole session")
            }
            Button(game.showHUD ? "Hide types" : "Show types") { game.showHUD.toggle() }
                .buttonStyle(PillButtonStyle(color: Theme.accent, prominent: game.showHUD))
                .disabled(game.mode == .reads && game.quiz == nil && !game.showHUD)
                .help(game.mode == .reads ? "Submit your reads to unlock the reveal" : "Reveal true player types (for learning)")
                .fixedSize()
            Button(game.heroSittingOut ? "Sit in" : "Sit out") { game.toggleSitOut() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .fixedSize()
            Button("New table") { showNewTable = true }
                .buttonStyle(PillButtonStyle(prominent: false))
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    var netBox: some View {
        StatBox(label: "Net", value: (game.stats.net >= 0 ? "+$" : "-$") + "\(abs(game.stats.net))", color: game.stats.net >= 0 ? Theme.good : Theme.bad)
    }

    var readsBanner: some View {
        HStack(spacing: 8) {
            Text("Watch the table, tag every seat in the Reads tab, then submit. Showdowns and bet sizes are your evidence.")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.8))
            Spacer()
            Button("Simulate 10") { game.simulate(10) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(game.handInProgress)
            Button("Simulate 50") { game.simulate(50) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(game.handInProgress)
            Button("Submit reads") { game.submitReads() }.buttonStyle(PillButtonStyle(color: Theme.red))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    var sidePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SideTab.allCases, id: \.self) { t in
                    Button { tab = t } label: {
                        Text(t.rawValue)
                            .font(.system(size: 12, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? .white : Theme.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(tab == t ? Theme.red : .clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
            ScrollView {
                switch tab {
                case .coach: CoachPanel(game: game)
                case .reads: ReadsPanel(game: game)
                case .history: HistoryPanel(game: game)
                }
            }
            .padding(.top, 10)
        }
        .background(Theme.bg)
    }
}

struct CoachPanel: View {
    @Environment(AppModel.self) private var app
    let game: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if game.stats.hands > 0 {
                HStack(spacing: 12) {
                    gradeCount("Good", game.stats.good, Theme.good)
                    gradeCount("Inaccuracies", game.stats.inaccuracies, Theme.warn)
                    gradeCount("Mistakes", game.stats.mistakes, Theme.bad)
                    Spacer()
                }
                .padding(.bottom, 2)
            }
            if app.settings.instantFeedback && game.handInProgress && !game.notesThisHand.isEmpty {
                Text("THIS HAND").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textDim)
                ForEach(game.notesThisHand) { NoteCard(note: $0) }
            }
            if let rec = game.history.first(where: { $0.heroInHand }) {
                HStack {
                    Text("HAND #\(rec.id)").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textDim)
                    Spacer()
                    if let net = rec.heroNet {
                        Text(net >= 0 ? "+$\(net)" : "-$\(abs(net))")
                            .font(Theme.mono(12))
                            .foregroundStyle(net >= 0 ? Theme.good : Theme.bad)
                    }
                }
                if game.handInProgress && !app.settings.instantFeedback {
                    Text("Grades for the current hand appear when it ends. Turn on instant feedback in Settings to see them as you act.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                if rec.notes.isEmpty {
                    Panel {
                        Text("No flagged decisions. Either standard play, or spots the rule coach doesn't grade. Ask Claude for a full review.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    ForEach(rec.notes) { NoteCard(note: $0) }
                }
                Button {
                    app.openChat(title: "Hand #\(rec.id) review", context: "Live 1/2 hand history (villain types shown in brackets, which hero may not have known):\n\n" + rec.coachText,
                                 question: "Review my play in this hand street by street against these specific player types. What was the best exploitative line, and was the rule-coach's grading right?")
                } label: {
                    Text("Ask Claude to review this hand").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                DisclosureGroup("Hand history") {
                    Text(rec.publicText)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 12))
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coach").font(.system(size: 14, weight: .bold))
                        Text("Play hands and your key decisions get graded against each opponent's type: overfolding to passive aggression, sizing up value vs stations, isolating fish, and more. Each grade cites the principle behind it.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}

extension CoachPanel {
    func gradeCount(_ label: String, _ n: Int, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(c).frame(width: 3, height: 12)
            Text("\(n)").font(Theme.mono(13))
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
    }
}

struct NoteCard: View {
    let note: CoachNote

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Theme.color(for: note.grade)).frame(width: 3)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.grade.label.uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.color(for: note.grade))
                    Text("\(note.street.name) · \(note.heroAction)").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    Spacer()
                }
                Text(note.headline).font(.system(size: 13, weight: .semibold))
                Text(note.detail).font(.system(size: 12)).foregroundStyle(Color(white: 0.8)).fixedSize(horizontal: false, vertical: true)
                if let p = note.principle {
                    Text(p.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.gold).help(p.summary)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.border))
    }
}

struct ReadsPanel: View {
    let game: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(game.seats.filter { $0.occupant.bot != nil }) { s in
                ReadRow(game: game, seat: s.seat, bot: s.occupant.bot!)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}

struct ReadRow: View {
    let game: GameController
    let seat: Int
    let bot: BotPlayer
    @State private var expanded = false

    var stats: PlayerStats { game.tracker.stats(for: bot.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Avatar(name: bot.name, hue: bot.avatarHue, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(bot.name) · seat \(seat + 1)").font(.system(size: 12, weight: .semibold))
                    Text(bot.appearance).font(.system(size: 10)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(PlayerType.allCases) { t in
                        Button(t.name) { game.tags[bot.id] = t }
                    }
                    Divider()
                    Button("Clear") { game.tags[bot.id] = nil }
                } label: {
                    if let t = game.tags[bot.id] { Text(t.name) } else { Text("Tag…") }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            HStack(spacing: 10) {
                statCell("H", "\(stats.hands)")
                statCell("VPIP", stats.vpipText)
                statCell("PFR", stats.pfrText)
                statCell("3B", stats.threeBetText)
                statCell("Limp", stats.limpText)
                statCell("AF", stats.afText)
                statCell("WTSD", stats.wtsdText)
            }
            if game.showHUD {
                HStack { TypeBadge(type: bot.type, small: true); Spacer() }
                ForEach(bot.profile.quirks, id: \.self) { q in
                    Text("• \(q)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                }
            }
            let ev = game.tracker.evidence(for: bot.id)
            if !ev.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ev.suffix(8).reversed()) { e in
                            Text("#\(e.handNumber) \(e.text)")
                                .font(.system(size: 10))
                                .foregroundStyle(e.kind == .showdown ? Theme.gold.opacity(0.9) : .white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } label: {
                    Text("Evidence (\(ev.count))").font(.system(size: 11, weight: .medium))
                }
            }
            TextField("Notes…", text: Binding(get: { game.playerNotes[bot.id] ?? "" }, set: { game.playerNotes[bot.id] = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(game.showHUD ? Theme.color(for: bot.type).opacity(0.5) : Theme.stroke))
    }

    func statCell(_ l: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Text(l).font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textDim)
            Text(v).font(Theme.mono(11))
        }
    }
}

struct HistoryPanel: View {
    @Environment(AppModel.self) private var app
    let game: GameController

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            if game.history.isEmpty {
                Text("No hands yet.").foregroundStyle(Theme.textDim).padding()
            }
            ForEach(game.history) { rec in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rec.publicText)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(rec.notes) { NoteCard(note: $0) }
                        if rec.heroInHand {
                            Button("Ask Claude about this hand") {
                                app.openChat(title: "Hand #\(rec.id) review", context: rec.coachText,
                                             question: "Review my play in this hand against these player types.")
                            }
                            .font(.system(size: 11))
                        }
                    }
                } label: {
                    HStack {
                        Text("#\(rec.id)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text(summary(rec)).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                        Spacer()
                        if let n = rec.heroNet, rec.heroInHand {
                            Text(n >= 0 ? "+$\(n)" : "-$\(abs(n))").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(n > 0 ? Theme.good : (n < 0 ? Theme.bad : Theme.textDim))
                        }
                        ForEach(rec.notes.filter { $0.grade == .mistake || $0.grade == .inaccuracy }) { Circle().fill(Theme.color(for: $0.grade)).frame(width: 6, height: 6) }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    func summary(_ rec: HandRecord) -> String {
        guard let r = rec.state.result else { return "" }
        let pot = r.pots.reduce(0) { $0 + $1.amount }
        let winners = Set(r.pots.flatMap(\.winners)).map { $0 == game.heroSeat && rec.heroInHand ? "You" : (rec.state.player(seat: $0)?.name ?? "?") }
        return "$\(pot) pot → \(winners.joined(separator: ", "))\(r.wentToShowdown ? " (SD)" : "")"
    }
}

struct NewTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    let game: GameController
    @State private var preset: TablePreset = .typical
    @State private var seats: Double = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New table").font(.title2.bold())
            ForEach(TablePreset.allCases) { p in
                Button {
                    preset = p
                } label: {
                    HStack {
                        Image(systemName: preset == p ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(p.name).font(.system(size: 13, weight: .semibold))
                            Text(p.detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Players").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(seats))-handed\(Int(seats) == 2 ? " (heads-up)" : (Int(seats) <= 6 ? " (short-handed)" : ""))")
                        .font(Theme.mono(13, .bold))
                }
                Slider(value: $seats, in: 2...9, step: 1)
                Text("Live 1/2 is usually 9-handed. Short-handed tables mean more pots, wider ranges and more decisions per hour.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Text("Starting a new table ends this session (saved to Progress).").font(.system(size: 11)).foregroundStyle(Theme.textDim)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Sit down") {
                    game.newTable(preset: preset, seats: Int(seats))
                    if game.mode == .play {
                        app.settings.defaultPreset = preset
                        app.settings.defaultSeats = Int(seats)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            preset = game.preset
            seats = Double(game.session.seatCount)
        }
    }
}

struct QuizResultView: View {
    let result: QuizResult
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Reads: \(result.score)/\(result.rows.count)").font(.title.bold())
                    Text("after \(result.handsObserved) hands observed").foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(result.rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Rectangle().fill(row.correct ? Theme.good : (row.guess == nil ? Theme.textFaint : Theme.bad)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.bot.name).font(.system(size: 13, weight: .semibold))
                                    TypeBadge(type: row.bot.type, small: true)
                                    if let g = row.guess, !row.correct {
                                        Text("you said \(g.name)").font(.system(size: 11)).foregroundStyle(Theme.bad)
                                    }
                                    if row.seat == nil { Text("(left the table)").font(.system(size: 10)).foregroundStyle(Theme.textDim) }
                                }
                                Text("VPIP \(row.stats.vpipText) · PFR \(row.stats.pfrText) · 3B \(row.stats.threeBetText) · Limp \(row.stats.limpText) · AF \(row.stats.afText) · WTSD \(row.stats.wtsdText) over \(row.stats.hands) hands")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                                Text("Typical \(row.bot.type.name): VPIP \(Int(row.bot.type.vpipBand.lowerBound * 100))–\(Int(row.bot.type.vpipBand.upperBound * 100)), PFR \(Int(row.bot.type.pfrBand.lowerBound * 100))–\(Int(row.bot.type.pfrBand.upperBound * 100)). \(row.bot.type.oneLiner)")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                                ForEach(row.bot.profile.quirks, id: \.self) { Text("• \($0)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)) }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 600)
    }
}
