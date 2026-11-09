import PokerCore
import SwiftUI

struct WorkoutView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            if let w = app.workout {
                if w.finished {
                    WorkoutSummary(w: w).transition(.scale(scale: 0.96).combined(with: .opacity))
                } else if w.showingRoundSummary {
                    RoundSummary(w: w).transition(.scale(scale: 0.96).combined(with: .opacity))
                } else {
                    RepView(w: w).transition(.opacity)
                }
            } else {
                WorkoutStart().transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.28), value: app.workout?.finished)
        .animation(.snappy(duration: 0.28), value: app.workout?.showingRoundSummary)
        .animation(.snappy(duration: 0.28), value: app.workout == nil)
    }
}

/// Per-round color, Duolingo-style.
enum GymColor {
    static func round(_ i: Int) -> (Color, Color, String) {
        switch i {
        case 0: (Theme.duoBlue, Theme.duoBlueDark, "rectangle.stack.fill")
        case 1: (Theme.duoPurple, Theme.duoPurpleDark, "eye.fill")
        default: (Theme.duoGold, Theme.duoGoldDark, "dollarsign.circle.fill")
        }
    }
}

// MARK: - Start

private struct WorkoutStart: View {
    @Environment(AppModel.self) private var app

    var store: ProgressStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Daily Workout", subtitle: "3 rounds × 5 fresh spots. The skills you miss come back more often.") { EmptyView() }
                StreakHero(store: store)
                HStack(alignment: .top, spacing: 12) {
                    roundCard(0, "Preflop", "Iso-raises, facing opens, limp-raises, cold 4-bets, top-X% ranges")
                    roundCard(1, "Reads", "Spot the type from stats and showdowns, bluff-catching, sizing tells")
                    roundCard(2, "Value", "Inverse question, value sizing, thin value, barrels, bluffs")
                }
                HStack(spacing: 10) {
                    GymStat(icon: "bolt.fill", color: Theme.duoGold, value: "\(store.progress.xp)", label: "Total XP")
                    GymStat(icon: "shield.lefthalf.filled", color: Theme.duoPurple, value: "Lv \(store.level)", label: store.levelTitle)
                    GymStat(icon: "flame.fill", color: Theme.flame, value: "\(store.progress.bestCombo)", label: "Best combo")
                    GymStat(icon: "checkmark.seal.fill", color: Theme.duoGreen, value: "\(store.progress.workoutsCompleted)", label: "Workouts")
                }
                HStack(spacing: 14) {
                    Button { withAnimation(.snappy) { app.workout = WorkoutSession(store: store) } } label: { Text("START WORKOUT").frame(width: 260) }
                        .buttonStyle(ChunkyButtonStyle())
                        .keyboardShortcut(.return, modifiers: [])
                    Text("+10 XP a rep · 3 in a row ×2 · 6 in a row ×3 · +50 for finishing")
                        .font(Theme.ui(12.5)).foregroundStyle(Theme.textDim)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    func roundCard(_ i: Int, _ title: String, _ detail: String) -> some View {
        let (c, dark, icon) = GymColor.round(i)
        return VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 10).fill(c)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(.white))
                .background(RoundedRectangle(cornerRadius: 10).fill(dark).offset(y: 3))
            Text("ROUND \(i + 1)").font(Theme.mono(10.5, .semibold)).foregroundStyle(c)
            Text(title).font(Theme.ui(17, .bold))
            Text(detail).font(Theme.ui(12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.opacity(0.35), lineWidth: 1.5))
    }
}

/// Flame + streak count + this week's days.
struct StreakHero: View {
    let store: ProgressStore
    @State private var pulse = false

    var body: some View {
        let lit = store.streak > 0
        HStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.flame.opacity(lit ? 0.16 : 0.06)).frame(width: 84, height: 84)
                    .scaleEffect(pulse && lit ? 1.06 : 1)
                Image(systemName: "flame.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(lit ? Theme.flame : Theme.textFaint)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(store.streak)").font(Theme.mono(44, .semibold)).foregroundStyle(lit ? Theme.flame : Theme.text)
                    Text("day streak").font(Theme.ui(16, .semibold))
                }
                Text(store.activeToday ? "Streak safe today. Another set only makes it stronger."
                     : (lit ? "Do today's workout to keep it alive." : "Finish a workout to light your first flame."))
                    .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            WeekRow(days: Set(store.progress.activeDays))
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.flame.opacity(lit ? 0.35 : 0.12), lineWidth: 1.5))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// The last 7 days as circles; done days are filled orange with a check.
struct WeekRow: View {
    let days: Set<String>

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { i in
                let date = cal.date(byAdding: .day, value: i - 6, to: today)!
                let done = days.contains(ProgressStore.dayFormatter.string(from: date))
                let isToday = i == 6
                VStack(spacing: 6) {
                    Text(letters[cal.component(.weekday, from: date) - 1])
                        .font(Theme.mono(10.5, .semibold))
                        .foregroundStyle(isToday ? Theme.text : Theme.textFaint)
                    ZStack {
                        Circle().fill(done ? Theme.flame : Theme.surface3)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        }
                        if isToday && !done { Circle().strokeBorder(Theme.flame, lineWidth: 2) }
                    }
                    .frame(width: 30, height: 30)
                }
            }
        }
    }
}

struct GymStat: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(color).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Theme.mono(17, .semibold))
                Text(label).font(Theme.ui(11.5)).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1.5))
    }
}

// MARK: - Rep

private struct RepView: View {
    @Environment(AppModel.self) private var app
    let w: WorkoutSession
    @State private var comboToast: Int?

    var body: some View {
        let rep = w.rep
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let (c, _, _) = GymColor.round(w.roundIndex)
                    HStack(spacing: 8) {
                        Text("ROUND \(w.roundIndex + 1) · \(w.round.title.uppercased())").font(Theme.mono(11, .semibold)).foregroundStyle(c)
                        Text("·").foregroundStyle(Theme.textFaint)
                        Text(rep.skillTitle).font(Theme.ui(12.5, .medium)).foregroundStyle(Theme.textDim)
                        Spacer()
                        if let v = rep.villain { TypeBadge(type: v, small: true) }
                    }
                    scene(rep)
                    Text(rep.prompt).font(Theme.ui(20, .bold)).tracking(-0.2).fixedSize(horizontal: false, vertical: true)
                    answers(rep)
                }
                .padding(24)
                .frame(maxWidth: 980, alignment: .leading)
                .id(rep.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .animation(.snappy(duration: 0.3), value: rep.id)
            if let p = w.picked {
                feedback(rep, p)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: w.picked)
        .overlay(alignment: .top) {
            if let n = comboToast {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").foregroundStyle(.white)
                    Text("\(n) IN A ROW · ×\(min(3, 1 + n / 3)) XP").font(Theme.mono(13, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).frame(height: 38)
                .background(Capsule().fill(Theme.flame))
                .background(Capsule().fill(Theme.flameDark).offset(y: 3))
                .padding(.top, 70)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.45), value: comboToast)
        .onChange(of: w.combo) { _, n in
            guard n == 3 || n == 6 || (n > 6 && n % 3 == 0) else { return }
            comboToast = n
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                if comboToast == n { comboToast = nil }
            }
        }
    }

    var header: some View {
        HStack(spacing: 16) {
            Button { app.workout = nil } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.textDim)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quit workout")
            GeometryReader { g in
                let frac = CGFloat(w.answeredCount) / CGFloat(max(1, w.totalReps))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3)
                    Capsule().fill(Theme.duoGreen)
                        .frame(width: max(16, g.size.width * frac))
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.28)).frame(height: 4).padding(.horizontal, 8).padding(.top, 3)
                        }
                        .opacity(frac > 0 ? 1 : 0)
                }
                .animation(.spring(duration: 0.5, bounce: 0.3), value: w.answeredCount)
            }
            .frame(height: 16)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 15, weight: .bold))
                Text("\(w.combo)").font(Theme.mono(15, .semibold))
            }
            .foregroundStyle(w.combo >= 3 ? Theme.flame : (w.combo > 0 ? Theme.flame.opacity(0.7) : Theme.textFaint))
            .help("Combo: 3 in a row for ×2, 6 for ×3")
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 14, weight: .bold))
                Text("\(w.xpEarned)").font(Theme.mono(15, .semibold)).contentTransition(.numericText())
            }
            .foregroundStyle(Theme.duoGold)
            .animation(.snappy, value: w.xpEarned)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    func answers(_ rep: Rep) -> some View {
        let columns = rep.options.count > 3 ? [GridItem(.adaptive(minimum: 150), spacing: 10)] : Array(repeating: GridItem(.flexible(), spacing: 10), count: rep.options.count)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(rep.options.indices, id: \.self) { i in
                Button { w.answer(i) } label: {
                    Text(rep.options[i]).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .buttonStyle(AnswerTileStyle(state: tileState(i, rep)))
                .disabled(w.picked != nil)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    func tileState(_ i: Int, _ rep: Rep) -> AnswerTileStyle.State {
        guard let p = w.picked else { return .idle }
        if rep.correct.contains(i) { return .correct }
        if i == p { return .wrong }
        return .faded
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
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.duoPurple.opacity(0.3), lineWidth: 1.5))
        case .hand(_, let cards):
            HStack(spacing: 8) {
                ForEach(cards, id: \.self) { CardView(card: $0, width: 84, fourColor: app.settings.fourColor) }
            }
            .padding(.vertical, 8)
        }
    }

    static let praise = ["Nice!", "Great read!", "Exactly.", "That's the exploit.", "Money.", "Correct!"]

    func feedback(_ rep: Rep, _ p: Int) -> some View {
        let ok = rep.correct.contains(p)
        let c = ok ? Theme.duoGreen : Theme.duoRed
        let dark = ok ? Theme.duoGreenDark : Theme.duoRedDark
        let title = ok ? Self.praise[w.answeredCount % Self.praise.count] : "Not quite"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Circle().fill(c).frame(width: 34, height: 34)
                    .overlay(Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 15, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.ui(19, .bold)).foregroundStyle(c)
                    if !ok {
                        Text("Best: \(rep.correct.sorted().map { rep.options[$0] }.joined(separator: " / "))").font(Theme.ui(13, .semibold)).foregroundStyle(c.opacity(0.9))
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                    Text(ok ? "+\(10 * w.multiplier) XP" : "+2 XP").font(Theme.mono(13, .semibold))
                }
                .foregroundStyle(Theme.duoGold)
                Button { withAnimation(.snappy(duration: 0.3)) { w.next() } } label: { Text("CONTINUE").frame(width: 170) }
                    .buttonStyle(ChunkyButtonStyle(color: c, ledge: dark))
                    .keyboardShortcut(.return, modifiers: [])
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(rep.explanation).font(Theme.ui(13.5)).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    if let pr = rep.principle { PrincipleCard(principle: pr) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(c.opacity(0.10))
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(c.opacity(0.5)).frame(height: 2) }
    }
}

// MARK: - Summaries

private struct RoundSummary: View {
    let w: WorkoutSession
    @State private var shown = false

    var body: some View {
        let r = w.round
        let score = w.roundScore(r)
        let (c, dark, icon) = GymColor.round(w.roundIndex)
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.surface3, lineWidth: 12)
                Circle().trim(from: 0, to: shown ? CGFloat(score) / CGFloat(max(1, r.reps.count)) : 0)
                    .stroke(c, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(c)
                    Text("\(score)/\(r.reps.count)").font(Theme.mono(32, .semibold))
                }
            }
            .frame(width: 150, height: 150)
            Text("ROUND \(w.roundIndex + 1) COMPLETE").font(Theme.mono(12, .semibold)).foregroundStyle(c)
            Text(score == r.reps.count ? "Perfect round!" : (score >= 3 ? "Solid. Keep going." : "Rough round. The misses come back later."))
                .font(Theme.ui(20, .bold))
            HStack(spacing: 8) {
                ForEach(r.reps) { rep in
                    let ok = w.answers[rep.id].map { rep.correct.contains($0) } ?? false
                    VStack(spacing: 6) {
                        Circle().fill(ok ? Theme.duoGreen : Theme.duoRed).frame(width: 28, height: 28)
                            .overlay(Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                        Text(rep.skillTitle).font(Theme.ui(10.5)).foregroundStyle(Theme.textDim).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(width: 92)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border, lineWidth: 1.5))
            Button { withAnimation(.snappy(duration: 0.3)) { w.next() } } label: {
                Text(w.roundIndex + 1 < w.rounds.count ? "NEXT: \(w.rounds[w.roundIndex + 1].title.uppercased())" : "FINISH WORKOUT").frame(width: 280)
            }
            .buttonStyle(ChunkyButtonStyle(color: c, ledge: dark))
            .keyboardShortcut(.return, modifiers: [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.easeOut(duration: 0.8).delay(0.15)) { shown = true } }
    }
}

private struct WorkoutSummary: View {
    @Environment(AppModel.self) private var app
    let w: WorkoutSession
    @State private var pop = false

    var body: some View {
        let acc = Int((Double(w.correctCount) / Double(max(1, w.totalReps)) * 100).rounded())
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.flame.opacity(0.15)).frame(width: 130, height: 130).scaleEffect(pop ? 1 : 0.4)
                Image(systemName: "flame.fill").font(.system(size: 64, weight: .bold)).foregroundStyle(Theme.flame)
                    .scaleEffect(pop ? 1 : 0.2)
                    .rotationEffect(.degrees(pop ? 0 : -20))
            }
            VStack(spacing: 6) {
                Text("Workout complete!").font(Theme.ui(28, .bold))
                Text("\(app.store.streak) day streak").font(Theme.mono(15, .semibold)).foregroundStyle(Theme.flame)
            }
            HStack(spacing: 12) {
                tile("TOTAL XP", "+\(w.xpEarned)", "bolt.fill", Theme.duoGold)
                tile("ACCURACY", "\(acc)%", "scope", Theme.duoGreen)
                tile("BEST COMBO", "\(w.bestCombo)", "flame.fill", Theme.flame)
            }
            .opacity(pop ? 1 : 0)
            .offset(y: pop ? 0 : 16)
            LevelBar(store: app.store).frame(width: 440)
            HStack(spacing: 12) {
                Button("BACK TO HOME") {
                    app.workout = nil
                    app.screen = .home
                }
                .buttonStyle(ChunkyButtonStyle(color: Theme.surface3, ledge: Theme.surface2, textColor: Theme.text))
                Button { app.workout = WorkoutSession(store: app.store) } label: { Text("ANOTHER SET").frame(width: 200) }
                    .buttonStyle(ChunkyButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.5).delay(0.1)) { pop = true } }
    }

    func tile(_ label: String, _ value: String, _ icon: String, _ c: Color) -> some View {
        VStack(spacing: 0) {
            Text(label).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(c)
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(c)
                Text(value).font(Theme.mono(22, .semibold)).foregroundStyle(c)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.bg)
        }
        .frame(width: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c, lineWidth: 2))
    }
}

struct LevelBar: View {
    let store: ProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.duoPurple)
                Text("Level \(store.level) · \(store.levelTitle)").font(Theme.ui(12.5, .semibold))
                Spacer()
                Text("\(store.progress.xp) / \(store.xpFor(level: store.level + 1)) XP").font(Theme.mono(11)).foregroundStyle(Theme.textDim)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface3)
                    Capsule().fill(Theme.duoPurple).frame(width: max(10, g.size.width * min(1, max(0, store.levelProgress))))
                }
            }
            .frame(height: 10)
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
                        RoundedRectangle(cornerRadius: 3)
                            .fill(date > today ? Color.clear : (days.contains(key) ? Theme.flame : Theme.surface3))
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }
}
