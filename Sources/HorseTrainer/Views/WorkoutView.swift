import PokerCore
import SwiftUI

struct WorkoutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let w = app.workout {
                if w.finished {
                    WorkoutSummary(w: w)
                } else if w.showingRoundSummary {
                    RoundSummary(w: w)
                } else {
                    RepView(w: w)
                }
            } else {
                WorkoutStart()
            }
        }
    }
}

private struct WorkoutStart: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Daily Workout", subtitle: "3 rounds × 5 reps of fresh spots. The skills you miss come back more often.") { EmptyView() }
                HStack(spacing: 10) {
                    StatBox(label: "Streak", value: "\(app.store.streak) day\(app.store.streak == 1 ? "" : "s")")
                    StatBox(label: "Level", value: "\(app.store.level) · \(app.store.levelTitle)")
                    StatBox(label: "XP", value: "\(app.store.progress.xp)")
                    StatBox(label: "Workouts", value: "\(app.store.progress.workoutsCompleted)")
                    StatBox(label: "Best combo", value: "\(app.store.progress.bestCombo)")
                }
                HStack(alignment: .top, spacing: 12) {
                    roundCard(1, "Preflop", "Iso-raises, facing opens, limp-raises, cold 4-bets, top-X% ranges")
                    roundCard(2, "Reads", "Spot the type from stats and showdowns, bluff-catching by type, sizing tells, flop raises")
                    roundCard(3, "Value", "Inverse question, value sizing, thin value, barrels, bluffs, c-bets")
                }
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Scoring")
                        Text("+10 XP per correct rep. Get 3 in a row for ×2, 6 in a row for ×3. Finishing the workout is +50 XP and counts today toward your streak.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                    }
                }
                Button { app.workout = WorkoutSession(store: app.store) } label: { Text("Start workout").frame(minWidth: 160) }
                    .buttonStyle(PillButtonStyle(large: true))
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    func roundCard(_ n: Int, _ title: String, _ detail: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Round \(n)")
                Text(title).font(Theme.ui(16, .semibold))
                Text(detail).font(Theme.ui(12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RepView: View {
    @Environment(AppModel.self) private var app
    let w: WorkoutSession

    var body: some View {
        let rep = w.rep
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionLabel(rep.skillTitle)
                        Spacer()
                        if let v = rep.villain { TypeBadge(type: v, small: true) }
                    }
                    scene(rep)
                    Text(rep.prompt).font(Theme.ui(16, .semibold))
                    HStack(spacing: 8) {
                        ForEach(rep.options.indices, id: \.self) { i in
                            Button { w.answer(i) } label: {
                                HStack(spacing: 8) {
                                    Kbd("\(i + 1)")
                                    Text(rep.options[i])
                                }
                                .frame(minWidth: 84)
                            }
                            .buttonStyle(PillButtonStyle(color: color(i, rep), prominent: w.picked != nil && (rep.correct.contains(i) || w.picked == i), large: true))
                            .disabled(w.picked != nil)
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                        }
                    }
                    if let p = w.picked { feedback(rep, p) }
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
            }
        }
    }

    var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Round \(w.roundIndex + 1) of \(w.rounds.count) · \(w.round.title)").font(Theme.ui(14, .semibold))
                Text(w.round.subtitle).font(Theme.ui(12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(w.round.reps.indices, id: \.self) { i in
                    let r = w.round.reps[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(blockColor(r, current: i == w.repIndex))
                        .frame(width: 26, height: 8)
                }
            }
            StatBox(label: "Combo", value: w.combo > 0 ? "\(w.combo) · ×\(w.multiplier)" : "–", color: w.multiplier > 1 ? Theme.gold : Theme.text)
            StatBox(label: "XP", value: "+\(w.xpEarned)")
            Button("Quit") { app.workout = nil }.buttonStyle(PillButtonStyle(prominent: false, small: true))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    func blockColor(_ r: Rep, current: Bool) -> Color {
        if let a = w.answers[r.id] { return r.correct.contains(a) ? Theme.good : Theme.bad }
        return current ? Theme.text : Theme.surface3
    }

    @ViewBuilder
    func scene(_ rep: Rep) -> some View {
        switch rep.scene {
        case .spot(let d):
            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: d.villainAppearance, history: d.history,
                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: d.villainBet)
        case .value(let d):
            SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: nil, history: d.history,
                      board: d.board, heroCards: d.heroCards, pot: d.pot, bet: nil)
        case .profile(let bot, let st, let ev):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Avatar(name: bot.name, hue: bot.avatarHue, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bot.name).font(Theme.ui(15, .semibold))
                        Text(bot.appearance).font(Theme.ui(12.5)).foregroundStyle(Theme.textDim)
                    }
                }
                HStack(spacing: 6) {
                    StatBox(label: "VPIP", value: st.vpipText)
                    StatBox(label: "PFR", value: st.pfrText)
                    StatBox(label: "3-bet", value: st.threeBetText)
                    StatBox(label: "Limp", value: st.limpText)
                    StatBox(label: "AF", value: st.afText)
                    StatBox(label: "WTSD", value: st.wtsdText)
                }
                if !ev.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel("What you saw")
                        ForEach(ev, id: \.self) { Text($0).font(Theme.mono(11.5, .regular)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
        case .hand(_, let cards):
            HStack(spacing: 8) {
                ForEach(cards, id: \.self) { CardView(card: $0, width: 84, fourColor: app.settings.fourColor) }
            }
            .padding(.vertical, 8)
        }
    }

    func color(_ i: Int, _ rep: Rep) -> Color {
        guard let p = w.picked else { return Theme.primary }
        if rep.correct.contains(i) { return Theme.good }
        if i == p { return Theme.bad }
        return Theme.surface3
    }

    func feedback(_ rep: Rep, _ p: Int) -> some View {
        let ok = rep.correct.contains(p)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(ok ? "Correct" : "Miss").font(Theme.ui(15, .semibold)).foregroundStyle(ok ? Theme.good : Theme.bad)
                Text(ok ? "+\(10 * w.multiplier) XP" : "+2 XP").font(Theme.mono(12)).foregroundStyle(Theme.textDim)
                if !ok { Text("Best: \(rep.correct.sorted().map { rep.options[$0] }.joined(separator: " / "))").font(Theme.ui(13)).foregroundStyle(Theme.textDim) }
            }
            Text(rep.explanation).font(Theme.ui(13.5)).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            if let pr = rep.principle { PrincipleCard(principle: pr) }
            HStack {
                Spacer()
                Button { w.next() } label: { HStack(spacing: 8) { Text("Next"); Kbd("⏎") } }
                    .buttonStyle(PillButtonStyle(large: true))
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }
}

private struct RoundSummary: View {
    let w: WorkoutSession

    var body: some View {
        let r = w.round
        let score = w.roundScore(r)
        VStack(spacing: 18) {
            SectionLabel("Round \(w.roundIndex + 1) complete")
            Text("\(score) / \(r.reps.count)").font(Theme.mono(56, .semibold))
            Text(score == r.reps.count ? "Perfect round." : (score >= 3 ? "Solid. Keep going." : "Rough round. The misses will come back in later workouts."))
                .font(Theme.ui(14)).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(r.reps) { rep in
                    let ok = w.answers[rep.id].map { rep.correct.contains($0) } ?? false
                    HStack(spacing: 8) {
                        Circle().fill(ok ? Theme.good : Theme.bad).frame(width: 7, height: 7)
                        Text(rep.skillTitle).font(Theme.ui(13))
                        if let v = rep.villain { Text("vs \(v.name)").font(Theme.mono(11)).foregroundStyle(Theme.textFaint) }
                    }
                }
            }
            .padding(14)
            .frame(width: 360, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            Button { w.next() } label: {
                HStack(spacing: 8) { Text(w.roundIndex + 1 < w.rounds.count ? "Next round: \(w.rounds[w.roundIndex + 1].title)" : "Finish workout"); Kbd("⏎") }
            }
            .buttonStyle(PillButtonStyle(large: true))
            .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WorkoutSummary: View {
    @Environment(AppModel.self) private var app
    let w: WorkoutSession

    var body: some View {
        VStack(spacing: 20) {
            SectionLabel("Workout complete")
            Text("\(w.correctCount) / \(w.totalReps)").font(Theme.mono(64, .semibold))
            HStack(spacing: 10) {
                StatBox(label: "XP earned", value: "+\(w.xpEarned)", color: Theme.gold)
                StatBox(label: "Best combo", value: "\(w.bestCombo)")
                StatBox(label: "Streak", value: "\(app.store.streak) day\(app.store.streak == 1 ? "" : "s")")
                StatBox(label: "Level", value: "\(app.store.level) · \(app.store.levelTitle)")
            }
            LevelBar(store: app.store).frame(width: 420)
            HStack(spacing: 10) {
                Button("Back to Home") {
                    app.workout = nil
                    app.screen = .home
                }
                .buttonStyle(PillButtonStyle(prominent: false, large: true))
                Button("Another set") { app.workout = WorkoutSession(store: app.store) }
                    .buttonStyle(PillButtonStyle(large: true))
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LevelBar: View {
    let store: ProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Level \(store.level) · \(store.levelTitle)").font(Theme.ui(12.5, .medium))
                Spacer()
                Text("\(store.progress.xp) / \(store.xpFor(level: store.level + 1)) XP").font(Theme.mono(11)).foregroundStyle(Theme.textDim)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.surface3)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.text).frame(width: g.size.width * min(1, max(0, store.levelProgress)))
                }
            }
            .frame(height: 6)
        }
    }
}

/// GitHub-style activity grid of the last N weeks.
struct ActivityGrid: View {
    let days: Set<String>
    var weeks = 16

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - 1
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        HStack(spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                        let key = ProgressStore.dayFormatter.string(from: date)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(date > today ? Color.clear : (days.contains(key) ? Theme.good : Theme.surface3))
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }
}
