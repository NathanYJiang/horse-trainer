import AppKit
import PokerCore
import SwiftUI

/// `HorseTrainer --snapshot <dir>` renders key screens to PNGs offscreen and exits (no window). Used for UI checks.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        let app = AppModel()
        app.live.debugAdvanceToHero()
        let size = CGSize(width: 1240, height: 900)
        render(OnboardingView().environment(app), size: CGSize(width: 1000, height: 700), to: dir.appendingPathComponent("onboarding.png"))
        render(HStack(spacing: 0) { Sidebar().frame(width: 224); Rectangle().fill(Theme.border).frame(width: 1); Spacer() }.environment(app),
               size: CGSize(width: 400, height: 900), to: dir.appendingPathComponent("sidebar.png"))
        render(LiveTableScreen(game: app.live).environment(app), size: size, to: dir.appendingPathComponent("live.png"))
        app.live.showHUD = true
        render(PokerTableView(game: app.live, settings: app.settings).environment(app), size: CGSize(width: 860, height: 640), to: dir.appendingPathComponent("table-hud.png"))
        var rng = SplitMix64(seed: 3)
        let d = DrillFactory.make(concept: .riverBluffCatch, type: .fish, rng: &rng)
        render(Panel {
            VStack(alignment: .leading, spacing: 14) {
                SpotScene(villainName: d.villainName, villainType: d.villainType, villainAppearance: d.villainAppearance, history: d.history,
                          board: d.board, heroCards: d.heroCards, pot: d.pot, bet: d.villainBet)
                PrincipleCard(principle: d.principle)
                NoteCard(note: CoachNote(handNumber: 1, street: .river, grade: .mistake, principle: .overfoldToPassiveAggression,
                                         headline: "Overfold vs Fish aggression", detail: d.explanation, heroAction: "Call $60", actionIndex: 0))
                HStack { ForEach(PlayerType.allCases) { TypeBadge(type: $0) } }
            }
        }.padding(20).environment(app), size: size, to: dir.appendingPathComponent("drill-parts.png"))
        render(HStack(alignment: .top, spacing: 20) {
            RangeMatrix(range: .constant(RangeModel.standard.top(0.2)), showRank: true)
            RangeMatrix(range: .constant(RangeModel.standard.top(0.15)), target: RangeModel.standard.top(0.2))
        }.padding(20).environment(app), size: CGSize(width: 1300, height: 560), to: dir.appendingPathComponent("ranges.png"))
        render(VStack { ReadsPanel(game: app.live) ; Spacer() }.padding(.top, 20).environment(app), size: CGSize(width: 380, height: 1400), to: dir.appendingPathComponent("reads.png"))
        render(VStack(alignment: .leading, spacing: 18) {
            StreakHero(store: app.store)
            HStack(spacing: 10) {
                GymStat(icon: "bolt.fill", color: Theme.duoGold, value: "1240", label: "Total XP")
                GymStat(icon: "shield.lefthalf.filled", color: Theme.duoPurple, value: "Lv 4", label: "Grinder")
                GymStat(icon: "flame.fill", color: Theme.flame, value: "7", label: "Best combo")
            }
            HStack(spacing: 10) {
                Button("Fold") {}.buttonStyle(AnswerTileStyle(state: .idle))
                Button("Call") {}.buttonStyle(AnswerTileStyle(state: .correct))
                Button("Raise") {}.buttonStyle(AnswerTileStyle(state: .wrong))
                Button("Jam") {}.buttonStyle(AnswerTileStyle(state: .faded))
            }
            HStack(spacing: 12) {
                Button("START WORKOUT") {}.buttonStyle(ChunkyButtonStyle())
                Button("CONTINUE") {}.buttonStyle(ChunkyButtonStyle(color: Theme.duoRed, ledge: Theme.duoRedDark))
                Button("BACK") {}.buttonStyle(ChunkyButtonStyle(color: Theme.surface3, ledge: Theme.surface2, textColor: Theme.text))
            }
            LevelBar(store: app.store).frame(width: 440)
            ActionBar(game: app.live)
        }.padding(24).environment(app), size: CGSize(width: 1100, height: 700), to: dir.appendingPathComponent("gym.png"))
        exit(0)
    }

    static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(Backdrop())
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
        let r = ImageRenderer(content: content)
        r.scale = 1
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
