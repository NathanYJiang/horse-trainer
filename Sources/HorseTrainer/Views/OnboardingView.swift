import PokerCore
import SwiftUI

/// First-run walkthrough. Re-open any time from the sidebar's Guide button.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step = 0
    @State private var key = ""

    let steps = 6

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("\(String(format: "%02d", step + 1)) / \(String(format: "%02d", steps))").font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
                    Spacer()
                    Button("Skip") { app.finishOnboarding() }
                        .buttonStyle(.plain)
                        .font(Theme.ui(12.5))
                        .foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: types
                    case 2: table
                    case 3: tools
                    case 4: claude
                    default: start
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(step)
                .transition(.opacity)
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(i <= step ? Theme.text : Theme.surface3).frame(width: 28, height: 4)
                    }
                    Spacer()
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(PillButtonStyle(prominent: false))
                            .keyboardShortcut(.leftArrow, modifiers: [])
                    }
                    if step < steps - 1 {
                        Button { withAnimation { step += 1 } } label: { HStack(spacing: 8) { Text("Next"); Kbd("→") } }
                            .buttonStyle(PillButtonStyle())
                            .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 22)
            }
            .frame(width: 880, height: 600)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.borderStrong))
        }
        .onAppear { key = app.settings.apiKey }
    }

    func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t).font(Theme.ui(30, .semibold)).tracking(-0.6)
            Text(sub).font(Theme.ui(15)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Steps

    var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            title("Beat live 1/2 by reading people.",
                  "Horse Trainer is a gym for live low-stakes poker. You won't learn solver strategy here. You'll learn to spot who you're up against, then make the play that beats that specific player.")
            HStack(spacing: 12) {
                loopCard("01", "Classify", "Whale, fish, trying rec, nit or reg? Read it from limps, sizes and showdowns.")
                loopCard("02", "Exploit", "Each type has its own leak. Value-bet stations, fold to passive aggression, bluff the folders.")
                loopCard("03", "Review", "Every decision is graded. Each session ends with feedback and an optional Claude review.")
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("A day in the gym")
                HStack(spacing: 8) {
                    dayChip("Workout", "8 min · 15 reps")
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                    dayChip("Play", "30+ hands at a 1/2 table")
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                    dayChip("Review", "Session feedback + Claude")
                }
                Text("Play chips only. You can get thousands of reps in before you ever sit down in a real game.")
                    .font(Theme.ui(12.5)).foregroundStyle(Theme.textFaint)
            }
        }
    }

    func dayChip(_ t: String, _ d: String) -> some View {
        HStack(spacing: 8) {
            Text(t).font(Theme.ui(13, .semibold))
            Text(d).font(Theme.mono(11)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
    }

    func loopCard(_ n: String, _ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(n).font(Theme.mono(11)).foregroundStyle(Theme.textFaint)
            Text(t).font(Theme.ui(17, .semibold))
            Text(d).font(Theme.ui(13)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }

    var types: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Five player types run every 1/2 game.", "Every bot, drill and grade in the app uses this model. Learn it once and use it everywhere.")
            VStack(spacing: 6) {
                ForEach(PlayerType.allCases) { t in
                    HStack(alignment: .top, spacing: 14) {
                        TypeBadge(type: t).frame(width: 120, alignment: .leading)
                        Text(t.oneLiner).font(Theme.ui(13)).foregroundStyle(Theme.textDim).frame(maxWidth: .infinity, alignment: .leading)
                        Text(TypePlaybook.of(t).exploits.first ?? "").font(Theme.ui(13, .medium)).frame(width: 260, alignment: .leading)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                }
            }
        }
    }

    var table: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Playing a session", "Types are hidden at the table, just like live. Here's the flow.")
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    bullet("Sit down", "Live Table deals 2–9 handed 1/2 with a realistic mix. Pick the table size and mix under New table.")
                    bullet("Tag players", "Open the Reads tab and tag each seat as you figure them out. Showdowns and bet sizes are your evidence.")
                    bullet("Get graded", "The Coach tab grades your key decisions against each villain's type and names the principle behind each grade.")
                    bullet("End session", "You get a report on leaks, your stats vs a winning 1/2 profile, and the drills to do next.")
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("At the table")
                    shortcut("F", "Fold")
                    shortcut("C", "Check / call")
                    shortcut("R", "Bet / raise")
                    shortcut("Space", "Deal next hand")
                    SectionLabel("Anywhere").padding(.top, 8)
                    shortcut("⌘1–9", "Jump between screens")
                    shortcut("1–5", "Answer drill options")
                    shortcut("⏎", "Next spot")
                }
                .padding(16)
                .frame(width: 250, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            }
        }
    }

    func bullet(_ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(Theme.ui(14, .semibold))
            Text(d).font(Theme.ui(13)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
        }
    }

    func shortcut(_ k: String, _ d: String) -> some View {
        HStack(spacing: 10) {
            Kbd(k)
            Text(d).font(Theme.ui(12.5)).foregroundStyle(Theme.textDim)
        }
    }

    var tools: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("The gym", "Short, repeatable training. The daily workout mixes all of it.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tool(.workout, "Do this daily. 15 fresh reps, XP, combos and a streak.")
                tool(.drills, "Same spot vs every type. Learn why the answer changes.")
                tool(.sizing, "The inverse question: what bet folds their TPTK? Bet just under it.")
                tool(.ranges, "Paint and quiz the top 10/15/20% and see the bots' real ranges.")
                tool(.reads, "Sit out, watch hands, classify every seat, then get scored.")
                tool(.equity, "Hand vs hand, hand vs range, any two cards.")
            }
        }
    }

    func tool(_ s: Screen, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: s.icon).font(.system(size: 14)).frame(width: 22).foregroundStyle(Theme.textDim)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(Theme.ui(14, .semibold))
                Text(d).font(Theme.ui(12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }

    var claude: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Optional: Claude coach", "The built-in coach grades every decision on its own. Add an Anthropic API key for deep dives: a breakdown of any hand, drill or full session, plus follow-up questions.")
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Anthropic API key")
                SecureField("sk-ant-…", text: $key)
                    .textFieldStyle(BlockFieldStyle())
                    .frame(width: 460)
                Text(app.settings.hasKey ? "Key saved. You're connected." : "It's stored only on this Mac, in a file only your user can read. You can change it later in Settings.")
                    .font(Theme.ui(12)).foregroundStyle(app.settings.hasKey ? Theme.good : Theme.textDim)
                Button("Save key") { app.settings.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .disabled(key.isEmpty || key == app.settings.apiKey)
            }
        }
    }

    var start: some View {
        VStack(alignment: .leading, spacing: 20) {
            title("Where do you want to start?", "You can always come back to this guide from the sidebar.")
            HStack(spacing: 12) {
                startCard("Learn the types", "Read the playbook. Two minutes.", .playbook)
                startCard("First workout", "15 reps to see where you're at.", .workout)
                startCard("Sit at a table", "Jump into a 9-handed 1/2 game.", .live)
            }
        }
    }

    func startCard(_ t: String, _ d: String, _ s: Screen) -> some View {
        Button {
            if s == .workout && app.workout == nil { app.workout = WorkoutSession(store: app.store) }
            app.screen = s
            app.finishOnboarding()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: s.icon).font(.system(size: 18)).foregroundStyle(Theme.textDim)
                Spacer()
                Text(t).font(Theme.ui(17, .semibold))
                Text(d).font(Theme.ui(13)).foregroundStyle(Theme.textDim)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.borderStrong))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
