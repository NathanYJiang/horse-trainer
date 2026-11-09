import Charts
import PokerCore
import SwiftUI

/// Long-run Cash Game results, like an online tracker for the simulated 1/2 pool.
struct TrackerView: View {
    @Environment(AppModel.self) private var app
    @State private var hoverHand: Int?
    var scrolls = true

    var t: TrackerStore { app.tracker }

    static let series: [(String, Color)] = [
        ("Total", Color(hex: 0x3987E5)),
        ("Showdown", Color(hex: 0x199E70)),
        ("Non-showdown", Color(hex: 0xD95926)),
    ]

    var body: some View {
        if scrolls { ScrollView { content } } else { content }
    }

    var content: some View {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Tracker", subtitle: "Every Cash Game hand against the same statistically modeled 1/2 pool. Training tables and spot practice don't count.") {
                    Button("Play Cash Game") { app.screen = .live }.buttonStyle(PillButtonStyle())
                }
                if t.totalHands == 0 {
                    Panel(padding: 20) {
                        Text("No tracked hands yet. Sit at the Cash Game table: no labels, no live coaching, results recorded here hand by hand. Your graph, win rate, stats and leaks build up over time.")
                            .font(Theme.ui(13)).foregroundStyle(Theme.textDim)
                    }
                } else {
                    headline
                    graphCard
                    HStack(alignment: .top, spacing: 16) {
                        varianceCard
                        statsCard
                    }
                    HStack(alignment: .top, spacing: 16) {
                        table("By position", rows: t.byPosition.map { ($0.label, nil, $0) })
                        table("Pots you played vs each type (revealed after the fact)", rows: t.byOpponentType.map { ($0.1.label, $0.0, $0.1) })
                    }
                    sessions
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
    }

    var headline: some View {
        let ci = t.bb100Interval
        let hours = Double(t.totalHands) / TrackerStore.liveHandsPerHour
        return HStack(spacing: 8) {
            StatBox(label: "Hands", value: "\(t.totalHands)")
            StatBox(label: "Net", value: money(t.totalNet), color: t.totalNet >= 0 ? Theme.good : Theme.bad)
            StatBox(label: "bb/100", value: String(format: "%.1f", t.bb100) + (ci.map { String(format: " ± %.0f", $0) } ?? ""))
            StatBox(label: "Live hours", value: String(format: "%.0f", hours))
            StatBox(label: "$/hr at live pace", value: hours > 0 ? String(format: "%.0f", Double(t.totalNet) / hours) : "–")
            StatBox(label: "Sessions", value: "\(t.data.sessions.count)")
        }
    }

    var graphCard: some View {
        let pts = t.graph
        let last = Dictionary(grouping: pts, by: \.series).compactMapValues { $0.last }
        let hovered = hoverHand.map { h in pts.filter { $0.hand == nearest(h, in: pts) } } ?? []
        return Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    SectionLabel("Winnings ($)")
                    Spacer()
                    ForEach(Self.series, id: \.0) { name, c in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 14, height: 2)
                            Text(name).font(Theme.ui(11.5)).foregroundStyle(Theme.textDim)
                        }
                    }
                }
                Chart {
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.borderStrong).lineStyle(StrokeStyle(lineWidth: 1))
                    ForEach(pts) { p in
                        LineMark(x: .value("Hand", p.hand), y: .value("Won", p.value), series: .value("Series", p.series))
                            .foregroundStyle(by: .value("Series", p.series))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                    ForEach(Self.series, id: \.0) { name, _ in
                        if let p = last[name] {
                            PointMark(x: .value("Hand", p.hand), y: .value("Won", p.value))
                                .foregroundStyle(by: .value("Series", name))
                                .symbolSize(30)
                                .annotation(position: .trailing, spacing: 6) {
                                    Text(money(Int(p.value))).font(Theme.mono(10.5)).foregroundStyle(Theme.textDim)
                                }
                        }
                    }
                    if let h = hovered.first {
                        RuleMark(x: .value("Hand", h.hand))
                            .foregroundStyle(Theme.textFaint)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Hand \(h.hand)").font(Theme.mono(10.5, .semibold))
                                    ForEach(hovered) { p in
                                        HStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 1).fill(color(p.series)).frame(width: 10, height: 2)
                                            Text("\(p.series) \(money(Int(p.value)))").font(Theme.mono(10.5))
                                        }
                                    }
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface2))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.borderStrong))
                            }
                    }
                }
                .chartForegroundStyleScale(domain: Self.series.map(\.0), range: Self.series.map(\.1))
                .chartLegend(.hidden)
                .chartXSelection(value: $hoverHand)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.border)
                        AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.border)
                        AxisValueLabel().font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(.trailing, 50)
                .frame(height: 280)
                Text("Showdown winnings are what you win when hands go to showdown; non-showdown is what you win (or lose) by betting people off hands or folding. Live 1/2 winners usually make most of their money at showdown by value-betting stations.")
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var varianceCard: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Is it real or is it luck?")
                if let ci = t.bb100Interval, let need = t.handsNeeded(for: 10) {
                    Text(String(format: "Your true win rate is likely between %.1f and %.1f bb/100.", t.bb100 - ci, t.bb100 + ci))
                        .font(Theme.ui(14, .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("That's a 95% range from your per-hand swings. To pin it down to ±10 bb/100 takes about \(need.formatted()) hands (≈\(Int(Double(need) / TrackerStore.liveHandsPerHour).formatted()) live hours). Judge yourself on decision quality until then.")
                        .font(Theme.ui(12.5)).foregroundStyle(Theme.textDim).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Play at least 30 hands for a confidence range.").font(Theme.ui(12.5)).foregroundStyle(Theme.textDim)
                }
                let s = t.lifetimeSessionStats
                let per100 = s.hands > 0 ? Double(s.mistakes) / Double(s.hands) * 100 : 0
                HStack(spacing: 8) {
                    StatBox(label: "Graded good", value: "\(s.good)", color: Theme.good)
                    StatBox(label: "Inaccuracies", value: "\(s.inaccuracies)", color: Theme.warn)
                    StatBox(label: "Mistakes / 100", value: String(format: "%.1f", per100), color: Theme.bad)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var statsCard: some View {
        let f = SessionFeedback.make(stats: t.lifetimeSessionStats, hero: t.lifetimeHero, notes: [], bigBlind: 2)
        return Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Lifetime stats vs a winning 1/2 player")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(f.benchmarks) { b in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.name).font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                            HStack(spacing: 5) {
                                Circle().fill(statusColor(b)).frame(width: 6, height: 6)
                                Text(b.value == nil ? "–" : b.display).font(Theme.mono(14, .semibold))
                            }
                            Text(b.name == "AF" ? String(format: "%.0f–%.1f", b.target.lowerBound, b.target.upperBound) : "\(Int(b.target.lowerBound))–\(Int(b.target.upperBound))%")
                                .font(Theme.mono(9.5)).foregroundStyle(Theme.textFaint)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    func table(_ title: String, rows: [(String, PlayerType?, TrackerStore.Row)]) -> some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title)
                HStack {
                    Text("").frame(width: 110, alignment: .leading)
                    Text("HANDS").frame(width: 60, alignment: .trailing)
                    Text("NET").frame(width: 70, alignment: .trailing)
                    Text("BB/100").frame(width: 70, alignment: .trailing)
                }
                .font(Theme.mono(9.5)).foregroundStyle(Theme.textFaint)
                ForEach(rows, id: \.0) { label, type, r in
                    HStack {
                        Group {
                            if let type { TypeBadge(type: type, small: true) } else { Text(label).font(Theme.mono(12)) }
                        }
                        .frame(width: 110, alignment: .leading)
                        Text("\(r.hands)").frame(width: 60, alignment: .trailing).foregroundStyle(Theme.textDim)
                        Text(money(r.net)).frame(width: 70, alignment: .trailing)
                        Text(r.hands < 20 ? "–" : String(format: "%.1f", r.bb100)).frame(width: 70, alignment: .trailing)
                            .foregroundStyle(r.hands < 20 ? Theme.textFaint : (r.bb100 >= 0 ? Theme.good : Theme.bad))
                    }
                    .font(Theme.mono(12))
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var sessions: some View {
        Panel(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Sessions")
                HStack {
                    Text("DATE").frame(width: 160, alignment: .leading)
                    Text("TABLE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("HANDS").frame(width: 60, alignment: .trailing)
                    Text("NET").frame(width: 70, alignment: .trailing)
                    Text("BB/100").frame(width: 70, alignment: .trailing)
                    Text("GOOD/INACC/MIST").frame(width: 130, alignment: .trailing)
                }
                .font(Theme.mono(9.5)).foregroundStyle(Theme.textFaint)
                ForEach(t.data.sessions.reversed()) { s in
                    HStack {
                        Text(s.start.formatted(date: .abbreviated, time: .shortened)).frame(width: 160, alignment: .leading).foregroundStyle(Theme.textDim)
                        Text("\(s.seats)-handed · \(s.preset)").frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).foregroundStyle(Theme.textDim)
                        Text("\(s.hands)").frame(width: 60, alignment: .trailing)
                        Text(money(s.net)).frame(width: 70, alignment: .trailing).foregroundStyle(s.net >= 0 ? Theme.good : Theme.bad)
                        Text(String(format: "%.1f", s.bb100)).frame(width: 70, alignment: .trailing)
                        Text("\(s.good)/\(s.inaccuracies)/\(s.mistakes)").frame(width: 130, alignment: .trailing).foregroundStyle(Theme.textDim)
                    }
                    .font(Theme.mono(12))
                    .padding(.vertical, 2)
                }
            }
        }
    }

    func money(_ n: Int) -> String { (n >= 0 ? "+$" : "-$") + "\(abs(n))" }

    func color(_ series: String) -> Color { Self.series.first { $0.0 == series }?.1 ?? Theme.text }

    func statusColor(_ b: SessionFeedback.Benchmark) -> Color {
        guard b.value != nil else { return Theme.textFaint }
        switch b.status {
        case .good: return Theme.good
        case .watch: return Theme.warn
        case .leak: return Theme.bad
        }
    }

    func nearest(_ h: Int, in pts: [TrackerStore.GraphPoint]) -> Int {
        pts.min { abs($0.hand - h) < abs($1.hand - h) }?.hand ?? h
    }
}
