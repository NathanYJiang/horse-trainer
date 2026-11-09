import PokerCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var store: ProgressStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Home", subtitle: "Classify the table. Exploit each type. Review. Repeat.") {
                    Button("How this works") { app.showOnboarding = true }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                HStack(alignment: .top, spacing: 16) {
                    workoutCard
                    streakCard.frame(width: 360)
                }
                loop
                HStack(alignment: .top, spacing: 16) {
                    weakSpots
                    lastSession
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    var workoutCard: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel("Today's workout")
                    Spacer()
                    Text(store.activeToday ? "DONE" : "\(store.repsToday) / 20 REPS")
                        .font(Theme.mono(10.5, .semibold))
                        .foregroundStyle(store.activeToday ? Theme.good : Theme.textDim)
                }
                Text(store.activeToday ? "You trained today. Run another set or go play." : "3 rounds × 5 fresh spots: preflop, reads, value.")
                    .font(Theme.ui(20, .semibold))
                    .tracking(-0.2)
                Text("About 8 minutes. Spots you miss come back more often until you stop missing them.")
                    .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface3)
                        Capsule().fill(Theme.duoGreen)
                            .frame(width: g.size.width * min(1, CGFloat(store.repsToday) / 20))
                            .opacity(store.repsToday > 0 ? 1 : 0)
                    }
                }
                .frame(height: 12)
                HStack(spacing: 8) {
                    Button {
                        if app.workout == nil || app.workout?.finished == true { app.workout = WorkoutSession(store: store) }
                        app.screen = .workout
                    } label: {
                        Text(app.workout != nil && app.workout?.finished == false ? "RESUME WORKOUT" : "START WORKOUT").frame(minWidth: 200)
                    }
                    .buttonStyle(ChunkyButtonStyle())
                    .keyboardShortcut(.return, modifiers: [])
                    Button("SIT AT A TABLE") { app.screen = .live }
                        .buttonStyle(ChunkyButtonStyle(color: Theme.surface3, ledge: Theme.surface2, textColor: Theme.text))
                }
            }
        }
    }

    var streakCard: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "flame.fill").font(.system(size: 30, weight: .bold))
                        .foregroundStyle(store.streak > 0 ? Theme.flame : Theme.textFaint)
                    Text("\(store.streak)").font(Theme.mono(40, .semibold)).foregroundStyle(store.streak > 0 ? Theme.flame : Theme.text)
                    Text("day streak").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.textDim)
                    Spacer()
                }
                WeekRow(days: Set(store.progress.activeDays))
                LevelBar(store: store)
            }
        }
    }

    var loop: some View {
        HStack(spacing: 12) {
            step("01", "Learn the types", "Five player types and how to beat each one.", .playbook)
            step("02", "Daily workout", "15 reps: preflop, reads, value.", .workout)
            step("03", "Play & read", "Live table with hidden types. Tag every seat.", .live)
            step("04", "Review", "End the session for feedback and a Claude review.", .progress)
        }
    }

    func step(_ n: String, _ title: String, _ detail: String, _ screen: Screen) -> some View {
        Button { app.screen = screen } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(n).font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
                Text(title).font(Theme.ui(14, .semibold))
                Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("Open").font(Theme.ui(12, .medium))
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.textDim)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var weakSpots: some View {
        let rated = DrillConcept.allCases.compactMap { c in store.skillRate(c.rawValue).map { (c, $0) } }.sorted { $0.1 < $1.1 }
        return Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Weakest skills")
                if rated.isEmpty {
                    Text("Do a workout or a few drills and your weakest skills will show up here.")
                        .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                } else {
                    ForEach(rated.prefix(5), id: \.0) { c, rate in
                        HStack(spacing: 10) {
                            Text(c.title).font(Theme.ui(13)).frame(width: 170, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Theme.surface3)
                                    RoundedRectangle(cornerRadius: 2).fill(rate >= 0.75 ? Theme.good : (rate >= 0.5 ? Theme.warn : Theme.bad)).frame(width: g.size.width * rate)
                                }
                            }
                            .frame(height: 6)
                            Text("\(Int(rate * 100))%").font(Theme.mono(11)).frame(width: 36, alignment: .trailing)
                            Button("Drill") { app.openDrill(c) }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                        }
                    }
                }
            }
        }
    }

    var lastSession: some View {
        Panel(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Last live session")
                if let s = store.progress.sessions.last {
                    HStack(spacing: 10) {
                        StatBox(label: "Hands", value: "\(s.hands)")
                        StatBox(label: "Net", value: (s.net >= 0 ? "+$" : "-$") + "\(abs(s.net))", color: s.net >= 0 ? Theme.good : Theme.bad)
                        StatBox(label: "Graded", value: "\(s.good)/\(s.inaccuracies)/\(s.mistakes)")
                    }
                    Text(s.date.formatted(date: .abbreviated, time: .shortened) + " · " + s.preset).font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
                } else {
                    Text("No sessions yet. Sit at a table, play 30+ hands, then hit End session for feedback.")
                        .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                }
                Button(app.live.stats.hands > 0 ? "Resume table (\(app.live.stats.hands) hands)" : "Open the live table") { app.screen = .live }
                    .buttonStyle(PillButtonStyle(prominent: false))
            }
        }
    }
}
