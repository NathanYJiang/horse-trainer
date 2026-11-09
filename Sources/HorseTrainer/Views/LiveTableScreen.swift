import PokerCore
import SwiftUI

struct LiveTableScreen: View {
    @Environment(AppModel.self) private var app
    let game: GameController
    @State private var tab: SideTab = .coach

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
                if game.mode == .reads { readsBanner } else { practiceBar }
                PokerTableView(game: game, settings: app.settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ActionBar(game: game)
            }
            Rectangle().fill(Theme.border).frame(width: 1)
            sidePanel.frame(width: 340)
        }
        .background(Theme.bg)
        .onAppear {
            if game.mode == .reads {
                tab = .reads
                if game.hand == nil { game.dealNext() }
            }
            if GameController.autopilot && game.hand == nil && game.mode.isPlaying { game.dealNext() }
        }
    }

    var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(game.mode == .reads ? "Read the Table" : (game.mode == .cash ? "Cash Game" : "Training Table")).font(Theme.ui(15, .semibold))
                Text("NL Hold'em $1/$2 · \(game.session.seatCount)-max · \(game.preset.name)").font(Theme.ui(11)).foregroundStyle(Theme.textDim)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 90, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 8)
            if game.mode.isPlaying {
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
            if game.revealsTypes {
                Button(game.showHUD ? "Hide types" : "Show types") { game.showHUD.toggle() }
                    .buttonStyle(PillButtonStyle(color: Theme.surface3, prominent: game.showHUD))
                    .disabled(game.mode == .reads && game.quiz == nil && !game.showHUD)
                    .help(game.mode == .reads ? "Submit your reads to unlock the reveal" : "Reveal true player types (for learning)")
                    .fixedSize()
            }
            Button(game.heroSittingOut ? "Sit in" : "Sit out") { game.toggleSitOut() }
                .buttonStyle(PillButtonStyle(prominent: false))
                .fixedSize()
            Menu {
                if game.mode.isPlaying {
                    Button("End session and get feedback") { app.modal = .sessionReport(game, startNewAfter: true) }
                        .disabled(game.stats.hands == 0)
                    if game.revealsTypes {
                        Button("Review session with Claude") {
                            app.openChat(title: "Session review", context: game.sessionReport(), question: Self.sessionQuestion)
                        }
                        .disabled(game.stats.hands < 10)
                    }
                    Divider()
                }
                Button("New table…") { app.modal = .newTable(game) }
            } label: {
                HStack(spacing: 6) {
                    Text("Session").font(Theme.ui(13, .medium))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface2))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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

    /// Full sessions or spot practice, plus quick table size.
    var practiceBar: some View {
        HStack(spacing: 10) {
            if game.mode == .cash {
                HStack(spacing: 8) {
                    Circle().fill(Theme.good).frame(width: 7, height: 7)
                    Text("Tracked").font(Theme.ui(12, .medium))
                    Text("Real conditions: player types stay hidden and the coach's grades are revealed when you end the session.")
                        .font(Theme.ui(12)).foregroundStyle(Theme.textDim).lineLimit(1).truncationMode(.tail)
                }
                .layoutPriority(-1)
            } else {
            BlockMenu(label: "PRACTICE", selection: Binding(get: { game.spotKind }, set: { game.setSpot($0, villain: game.spotVillain) }),
                      options: SpotKind.allCases.map { ($0, $0.title) })
            if game.spotMode {
                BlockMenu(label: "VS", selection: Binding(get: { game.spotVillain }, set: { game.setSpot(game.spotKind, villain: $0) }),
                          options: [(PlayerType?.none, "Anyone")] + PlayerType.allCases.map { (PlayerType?.some($0), $0.name) })
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(spotLine).font(Theme.ui(12)).foregroundStyle(Theme.textDim).lineLimit(1)
                if game.currentHandIsSpot, game.handInProgress, let m = game.spotMessage {
                    Text(m).font(Theme.ui(11)).foregroundStyle(Theme.textFaint).lineLimit(1)
                }
            }
            .truncationMode(.tail)
            .layoutPriority(-1)
            }
            Spacer(minLength: 8)
            if game.spotMode && game.spotScore.spots > 0 {
                Text("\(game.spotScore.spots) spots · \(game.spotScore.good) good · \(game.spotScore.bad) flagged")
                    .font(Theme.mono(11)).foregroundStyle(Theme.textDim).fixedSize()
            }
            BlockTabs(selection: Binding(get: { game.session.seatCount }, set: { n in
                guard n != game.session.seatCount else { return }
                game.newTable(preset: game.preset, seats: n)
                app.settings.defaultSeats = n
            }), options: [(6, "6-max"), (9, "9-handed")])
            .help("Live 1/2 is almost always 9-handed. 6-max gives you more decisions per hour. Changing it starts a new table.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    var spotLine: String {
        guard game.spotMode else { return "Every hand, folds and all. Pick a spot to drill one situation on repeat." }
        if game.currentHandIsSpot, game.handInProgress, !game.spotVillains.isEmpty {
            let names = game.spotVillains.compactMap { game.session.bot(at: $0)?.name }
            return "\(game.spotKind.title) · vs \(names.prefix(3).joined(separator: ", "))"
        }
        return game.spotKind.detail
    }

    var readsBanner: some View {
        HStack(spacing: 8) {
            Text("Watch the table, tag every seat in the Reads tab, then submit. Showdowns and bet sizes are your evidence.")
                .font(Theme.ui(12))
                .foregroundStyle(Color(white: 0.8))
            Spacer()
            Button("Simulate 10") { game.simulate(10) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(game.handInProgress)
            Button("Simulate 50") { game.simulate(50) }.buttonStyle(PillButtonStyle(prominent: false)).disabled(game.handInProgress)
            Button("Submit reads") {
                game.submitReads()
                app.modal = .quiz(game)
            }.buttonStyle(PillButtonStyle())
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
                            .font(Theme.ui(12.5, tab == t ? .medium : .regular))
                            .foregroundStyle(tab == t ? .white : Theme.textDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(tab == t ? Theme.text : .clear).frame(height: 2) }
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
        if game.revealsTypes { open } else { sealed }
    }

    /// Cash tables: grades exist but stay sealed until the session ends, like finding out in review.
    var sealed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        Text("Grades are sealed").font(Theme.ui(14, .semibold))
                    }
                    Text("At Cash Game tables you play like it's real: no types, no live coaching. The coach is still grading every key decision. End the session to see the grades, your leaks and how you did against each type.")
                        .font(Theme.ui(12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                    Button("End session and reveal") { app.modal = .sessionReport(game, startNewAfter: true) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(game.stats.hands == 0)
                    Text("Want hints while you play? Use the Training Table.").font(Theme.ui(11.5)).foregroundStyle(Theme.textFaint)
                }
            }
            if let rec = game.history.first(where: { $0.heroInHand }) {
                Text("LAST HAND #\(rec.id)").font(Theme.ui(10, .bold)).foregroundStyle(Theme.textDim)
                Text(rec.publicText).font(Theme.mono(11, .regular)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }

    var open: some View {
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
                Text("THIS HAND").font(Theme.ui(10, .bold)).foregroundStyle(Theme.textDim)
                ForEach(game.notesThisHand) { NoteCard(note: $0) }
            }
            if let rec = game.history.first(where: { $0.heroInHand }) {
                HStack {
                    Text("HAND #\(rec.id)").font(Theme.ui(10, .bold)).foregroundStyle(Theme.textDim)
                    Spacer()
                    if let net = rec.heroNet {
                        Text(net >= 0 ? "+$\(net)" : "-$\(abs(net))")
                            .font(Theme.mono(12))
                            .foregroundStyle(net >= 0 ? Theme.good : Theme.bad)
                    }
                }
                if game.handInProgress && !app.settings.instantFeedback {
                    Text("Grades for the current hand appear when it ends. Turn on instant feedback in Settings to see them as you act.")
                        .font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                }
                if rec.notes.isEmpty {
                    Panel {
                        Text("No flagged decisions. Either standard play, or spots the rule coach doesn't grade. Ask Claude for a full review.")
                            .font(Theme.ui(12)).foregroundStyle(.white.opacity(0.8))
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
                        .font(Theme.mono(11, .regular))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.ui(12))
            } else {
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Coach").font(Theme.ui(14, .bold))
                        Text("Play hands and your key decisions get graded against each opponent's type: overfolding to passive aggression, sizing up value vs stations, isolating fish, and more. Each grade cites the principle behind it.")
                            .font(Theme.ui(12)).foregroundStyle(.white.opacity(0.8))
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
            Text(label).font(Theme.ui(11)).foregroundStyle(Theme.textDim)
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
                        .font(Theme.ui(9.5, .bold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.color(for: note.grade))
                    Text("\(note.street.name) · \(note.heroAction)").font(Theme.ui(11)).foregroundStyle(Theme.textDim)
                    Spacer()
                }
                Text(note.headline).font(Theme.ui(13, .semibold))
                Text(note.detail).font(Theme.ui(12)).foregroundStyle(Color(white: 0.8)).fixedSize(horizontal: false, vertical: true)
                if let p = note.principle {
                    Text(p.title).font(Theme.ui(11, .medium)).foregroundStyle(Theme.gold).help(p.summary)
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
                    Text("\(bot.name) · seat \(seat + 1)").font(Theme.ui(12, .semibold))
                    Text(bot.appearance).font(Theme.ui(10)).foregroundStyle(Theme.textDim).lineLimit(1)
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
                    Text("• \(q)").font(Theme.ui(10)).foregroundStyle(.white.opacity(0.75))
                }
            }
            let ev = game.tracker.evidence(for: bot.id)
            if !ev.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ev.suffix(8).reversed()) { e in
                            Text("#\(e.handNumber) \(e.text)")
                                .font(Theme.ui(10))
                                .foregroundStyle(e.kind == .showdown ? Theme.gold.opacity(0.9) : .white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } label: {
                    Text("Evidence (\(ev.count))").font(Theme.ui(11, .medium))
                }
            }
            TextField("Notes…", text: Binding(get: { game.playerNotes[bot.id] ?? "" }, set: { game.playerNotes[bot.id] = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(Theme.ui(11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(game.showHUD ? Theme.color(for: bot.type).opacity(0.5) : Theme.stroke))
    }

    func statCell(_ l: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            Text(l).font(Theme.ui(8, .bold)).foregroundStyle(Theme.textDim)
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
                            .font(Theme.mono(10.5, .regular))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if game.revealsTypes { ForEach(rec.notes) { NoteCard(note: $0) } }
                        if rec.heroInHand {
                            Button("Ask Claude about this hand") {
                                if game.revealsTypes {
                                    app.openChat(title: "Hand #\(rec.id) review", context: rec.coachText,
                                                 question: "Review my play in this hand against these player types.")
                                } else {
                                    app.openChat(title: "Hand #\(rec.id) review", context: "Live 1/2 hand history. Hero does not know opponent types; judge from the actions only.\n\n" + rec.publicText,
                                                 question: "Review my play in this hand using only what I could see at the table. What reads does the action give, and what was the best exploitative line?")
                                }
                            }
                            .font(Theme.ui(11))
                        }
                    }
                } label: {
                    HStack {
                        Text("#\(rec.id)").font(Theme.mono(12, .semibold))
                        Text(summary(rec)).font(Theme.ui(11)).foregroundStyle(Theme.textDim).lineLimit(1)
                        Spacer()
                        if let n = rec.heroNet, rec.heroInHand {
                            Text(n >= 0 ? "+$\(n)" : "-$\(abs(n))").font(Theme.ui(11, .bold))
                                .foregroundStyle(n > 0 ? Theme.good : (n < 0 ? Theme.bad : Theme.textDim))
                        }
                        ForEach(game.revealsTypes ? rec.notes.filter { $0.grade == .mistake || $0.grade == .inaccuracy } : []) { Circle().fill(Theme.color(for: $0.grade)).frame(width: 6, height: 6) }
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
    @Environment(AppModel.self) private var app
    let game: GameController
    @State private var preset: TablePreset = .typical
    @State private var seats: Double = 9

    var body: some View {
        ModalCard(title: "New table", width: 520, onClose: { app.modal = nil }) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Table mix")
                VStack(spacing: 6) {
                    ForEach(TablePreset.allCases) { p in
                        Button { preset = p } label: {
                            HStack(alignment: .top, spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(preset == p ? Theme.text : Theme.borderStrong, lineWidth: 1.5)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(preset == p ? Theme.text : .clear).padding(3))
                                    .frame(width: 14, height: 14)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(Theme.ui(13.5, .medium))
                                    Text(p.detail).font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(preset == p ? Theme.surface2 : .clear))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(preset == p ? Theme.borderStrong : Theme.border))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    SectionLabel("Players")
                    Spacer()
                    Text("\(Int(seats))-handed\(Int(seats) <= 6 ? " · short-handed" : "")").font(Theme.mono(12))
                }
                BlockSlider(value: $seats, range: 3...9, step: 1)
                Text("Live 1/2 is usually 9-handed. Short-handed means more pots and more decisions per hour.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                HStack {
                    Text("Ends the current session and saves it to Progress.").font(Theme.ui(11.5)).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Button("Sit down") {
                        game.newTable(preset: preset, seats: Int(seats))
                        if game.mode.isPlaying {
                            app.settings.defaultPreset = preset
                            app.settings.defaultSeats = Int(seats)
                        }
                        app.modal = nil
                    }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .padding(18)
        }
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
        ModalCard(title: "Your reads: \(result.score)/\(result.rows.count) after \(result.handsObserved) hands", width: 700, onClose: onClose) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(result.rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 1).fill(row.correct ? Theme.good : (row.guess == nil ? Theme.textFaint : Theme.bad)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(row.bot.name).font(Theme.ui(13.5, .semibold))
                                    TypeBadge(type: row.bot.type, small: true)
                                    if let g = row.guess, !row.correct {
                                        Text("you said \(g.name)").font(Theme.mono(11)).foregroundStyle(Theme.bad)
                                    }
                                    if row.seat == nil { Text("left the table").font(Theme.mono(10.5)).foregroundStyle(Theme.textFaint) }
                                }
                                Text("VPIP \(row.stats.vpipText) · PFR \(row.stats.pfrText) · 3B \(row.stats.threeBetText) · Limp \(row.stats.limpText) · AF \(row.stats.afText) · WTSD \(row.stats.wtsdText) · \(row.stats.hands) hands")
                                    .font(Theme.mono(11)).foregroundStyle(Theme.textDim)
                                Text("Typical \(row.bot.type.name): VPIP \(Int(row.bot.type.vpipBand.lowerBound * 100))–\(Int(row.bot.type.vpipBand.upperBound * 100)), PFR \(Int(row.bot.type.pfrBand.lowerBound * 100))–\(Int(row.bot.type.pfrBand.upperBound * 100)). \(row.bot.type.oneLiner)")
                                    .font(Theme.ui(12)).foregroundStyle(Theme.textFaint)
                                ForEach(row.bot.profile.quirks, id: \.self) { Text("– \($0)").font(Theme.ui(11.5)).foregroundStyle(Theme.textDim) }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: 600)
        }
    }
}
