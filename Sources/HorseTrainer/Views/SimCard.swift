import PokerCore
import SwiftUI

/// One simulated decision: every option's EV under no read, your read, and the real types.
struct SimCard: View {
    let eval: SimEval
    /// Off while a hand with hidden types is still being played, so the real-types row can't tip you off.
    var showTruth = true

    var grade: Grade { eval.grade() }
    var loss: Double { eval.loss(eval.read) }

    var verdict: String {
        switch grade {
        case .good: "BEST"
        case .okay: "CLOSE"
        case .inaccuracy: "INACCURACY"
        case .mistake: "MISTAKE"
        }
    }

    var summary: String {
        let e = eval
        var parts: [String] = []
        switch grade {
        case .good: parts.append("Best option against your read.")
        case .okay: parts.append("Within noise of the best option (\(e.options[e.read.best])).")
        default: parts.append("\(e.options[e.read.best]) was worth about $\(Int(loss.rounded())) more against your read.")
        }
        if e.exploitDiffers {
            parts.append("With no read the default is \(e.options[e.baseline.best]); against this read it's \(e.options[e.read.best]). That's the exploit.")
        }
        let rc = e.readCost()
        if rc > 0 && showTruth { parts.append("Knowing their real types, \(e.options[e.truth.best]) was best (+$\(Int(rc.rounded())) over what your read suggested).") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Theme.color(for: grade)).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verdict).font(Theme.ui(9.5, .bold)).tracking(0.5).foregroundStyle(Theme.color(for: grade))
                    Text("\(eval.street.name) · \(eval.heroAction)").font(Theme.ui(11)).foregroundStyle(Theme.textDim).lineLimit(1)
                    Spacer()
                    if loss > 0 {
                        Text("-$\(Int(loss.rounded()))").font(Theme.mono(11, .semibold)).foregroundStyle(Theme.color(for: grade))
                    }
                }
                Text(summary).font(Theme.ui(12)).foregroundStyle(Color(white: 0.82)).fixedSize(horizontal: false, vertical: true)
                grid
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.border))
    }

    /// EVs relative to the first option (fold, or check when there's nothing to call).
    var grid: some View {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("EV $").gridColumnAlignment(.leading)
                ForEach(eval.options.indices, id: \.self) { i in
                    Text(short(eval.options[i]))
                        .foregroundStyle(i == eval.chosen ? Theme.text : Theme.textFaint)
                        .underline(i == eval.chosen)
                }
            }
            .font(Theme.mono(9.5))
            .foregroundStyle(Theme.textFaint)
            ForEach(Array(eval.lenses.prefix(showTruth ? 3 : 2).enumerated()), id: \.offset) { _, lens in
                GridRow {
                    Text(lens.name).font(Theme.mono(10)).foregroundStyle(Theme.textDim)
                    ForEach(eval.options.indices, id: \.self) { i in
                        let v = lens.evs[i] - lens.evs[0]
                        Text(i == 0 ? "0" : String(format: "%+.0f", v))
                            .font(Theme.mono(10.5, i == lens.best ? .bold : .regular))
                            .foregroundStyle(i == lens.best ? Theme.good : Theme.textDim)
                    }
                }
            }
        }
        .padding(.top, 2)
        .help("Each option played out hundreds of times against the hands their actions point to. You play the rest of the hand like a solid reg. Bold = best in that row.")
    }

    func short(_ label: String) -> String {
        label.replacingOccurrences(of: "Raise to ", with: "R ").replacingOccurrences(of: "Call ", with: "C ")
            .replacingOccurrences(of: "Bet ", with: "B ").components(separatedBy: " (").first ?? label
    }
}

/// Session-level summary of the simulated decisions.
struct SimSummary: View {
    let game: GameController
    var replay: ((Int) -> Void)?

    var body: some View {
        let sims = game.sims
        let lost = sims.reduce(0) { $0 + $1.loss($1.read) }
        let readCost = sims.reduce(0) { $0 + $1.readCost() }
        let hands = max(1, game.stats.hands)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Decision quality (simulated)")
            HStack(spacing: 8) {
                StatBox(label: "Decisions", value: "\(sims.count)")
                StatBox(label: "EV lost", value: "$\(Int(lost.rounded()))", color: lost > 0 ? Theme.bad : Theme.good)
                StatBox(label: "EV lost bb/100", value: String(format: "%.1f", lost / 2 / Double(hands) * 100))
                StatBox(label: "Read cost", value: "$\(Int(readCost.rounded()))", color: Theme.warn)
            }
            if game.pendingSims > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Simulating \(game.pendingSims) more decision\(game.pendingSims == 1 ? "" : "s")…").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                }
            }
            Text("Every decision was played out against the hands each opponent's actions point to: as a random 1/2 player (no read), as your read from what you'd seen, and as who they really were. EV lost is graded on your read, so it's fair. Read cost is what perfect reads would have added.")
                .font(Theme.ui(12)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
            let costly = sims.filter { $0.loss($0.read) > 0 || $0.readCost() > 0 }
                .sorted { $0.loss($0.read) + $0.readCost() > $1.loss($1.read) + $1.readCost() }
                .prefix(6)
            if !costly.isEmpty {
                Text("COSTLIEST DECISIONS").font(Theme.ui(10, .bold)).foregroundStyle(Theme.textDim).padding(.top, 4)
                ForEach(Array(costly)) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Hand #\(e.handNumber)").font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                            Spacer()
                            if let replay {
                                Button { replay(e.handNumber) } label: { Label("Replay", systemImage: "play.fill") }
                                    .buttonStyle(PillButtonStyle(prominent: false, small: true))
                            }
                        }
                        SimCard(eval: e)
                    }
                }
            }
        }
    }
}
