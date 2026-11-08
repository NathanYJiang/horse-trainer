import PokerCore
import SwiftUI

struct PokerTableView: View {
    let game: GameController
    let settings: AppSettings

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let tableW = min(w * 0.76, h * 1.85)
            let tableH = min(h * 0.6, tableW * 0.5)
            ZStack {
                table(width: tableW, height: tableH).position(center)
                centerArea.position(center)

                ForEach(0..<game.session.seatCount, id: \.self) { seat in
                    let edge = seatPoint(seat, center: center, rx: tableW / 2, ry: tableH / 2)
                    SeatView(game: game, settings: settings, seat: seat)
                        .position(seatPoint(seat, center: center, rx: tableW / 2 + 30, ry: tableH / 2 + 34))
                    if let amount = betAmount(seat), amount > 0 {
                        ChipStack(amount: amount, compact: true)
                            .position(lerp(center, edge, 0.64))
                            .transition(.opacity)
                    }
                    if game.hand?.buttonSeat == seat {
                        DealerButton()
                            .position(lerp(center, edge, 0.80).applying(CGAffineTransform(translationX: seat == 0 ? 56 : 26, y: seat == 0 ? -6 : 0)))
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: game.hand?.actions.count)
        }
    }

    /// Minimal racetrack table: charcoal rail, near-black felt, one thin inner line.
    func table(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(Theme.rail)
                .frame(width: width + 24, height: height + 24)
            Capsule()
                .fill(Theme.felt)
                .frame(width: width, height: height)
            Capsule()
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                .frame(width: width - 40, height: height - 40)
            Text("HORSE TRAINER")
                .font(Theme.ui(11, .semibold))
                .tracking(5)
                .foregroundStyle(Color.white.opacity(0.08))
                .offset(y: height * 0.3)
        }
    }

    var centerArea: some View {
        VStack(spacing: 12) {
            if let h = game.hand {
                Text("Pot: $\(h.pot)")
                    .font(Theme.mono(14))
                    .foregroundStyle(.white)
                HStack(spacing: 7) {
                    ForEach(0..<5, id: \.self) { i in
                        CardView(card: i < h.board.count ? h.board[i] : nil, width: 54, fourColor: settings.fourColor)
                            .transition(.opacity)
                    }
                }
                .animation(.spring(duration: 0.4), value: h.board.count)
                if let r = h.result {
                    Text(resultText(h, r))
                        .font(Theme.ui(12.5, .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
                }
            } else {
                Text("Deal a hand to start").font(Theme.ui(13)).foregroundStyle(Theme.textDim)
            }
        }
    }

    func resultText(_ h: HandState, _ r: HandResult) -> String {
        r.pots.map { pot in
            let names = pot.winners.map { $0 == game.heroSeat ? "You" : (h.player(seat: $0)?.name ?? "?") }.joined(separator: " & ")
            return "\(names) win\(pot.winners.count == 1 && names != "You" ? "s" : "") $\(pot.amount)\(pot.winningHand.map { " · \($0)" } ?? "")"
        }.joined(separator: "\n")
    }

    func betAmount(_ seat: Int) -> Int? {
        guard let h = game.hand, !h.isComplete, let p = h.player(seat: seat) else { return nil }
        return p.committedStreet
    }

    func seatPoint(_ seat: Int, center: CGPoint, rx: CGFloat, ry: CGFloat) -> CGPoint {
        let angle = (90.0 + Double(seat) * 360.0 / Double(game.session.seatCount)) * .pi / 180
        return CGPoint(x: center.x + cos(angle) * rx, y: center.y + sin(angle) * ry)
    }

    func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

struct DealerButton: View {
    var body: some View {
        Text("D")
            .font(Theme.ui(11, .bold))
            .foregroundStyle(.black)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.white))
    }
}

struct SeatView: View {
    let game: GameController
    let settings: AppSettings
    let seat: Int

    var info: SeatInfo { game.seats[seat] }
    var handPlayer: SeatState? { game.hand?.player(seat: seat) }
    var isHero: Bool { info.occupant == .hero }
    var bot: BotPlayer? { info.occupant.bot }
    var toAct: Bool { game.hand.map { !$0.isComplete && $0.currentSeat == seat } ?? false }
    var folded: Bool { handPlayer?.folded ?? (game.hand != nil) }
    var showCards: Bool {
        guard let h = game.hand, handPlayer != nil else { return false }
        if isHero { return true }
        return h.result?.shown[seat] != nil
    }
    var won: Int? {
        guard let r = game.hand?.result, let net = r.net[seat], r.pots.contains(where: { $0.winners.contains(seat) }) else { return nil }
        return net
    }

    var body: some View {
        VStack(spacing: -14) {
            cards.zIndex(0)
            plate
                .overlay(alignment: .bottom) { bubble.offset(y: 14) }
                .zIndex(1)
        }
        .opacity(folded && !isHero ? 0.45 : 1)
    }

    @ViewBuilder var cards: some View {
        if let p = handPlayer, !(p.folded && !isHero) {
            HStack(spacing: isHero ? 3 : -18) {
                CardView(card: p.hole[0], faceUp: showCards, width: isHero ? 52 : 40, fourColor: settings.fourColor, dimmed: p.folded)
                CardView(card: p.hole[1], faceUp: showCards, width: isHero ? 52 : 40, fourColor: settings.fourColor, dimmed: p.folded)
            }
        } else {
            Color.clear.frame(width: 60, height: isHero ? 72 : 56)
        }
    }

    var borderColor: Color {
        if won != nil { return Theme.good }
        if toAct { return .white }
        return Theme.border
    }

    var plate: some View {
        HStack(spacing: 0) {
            if game.showHUD, let b = bot {
                Rectangle().fill(Theme.color(for: b.type)).frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(isHero ? "You" : info.name)
                        .font(Theme.ui(12, .medium))
                        .foregroundStyle(Color(white: 0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let h = game.hand, handPlayer != nil {
                        Text(h.position(of: seat).short)
                            .font(Theme.ui(9, .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Text("$\(game.stack(of: seat))")
                    .font(Theme.mono(13.5))
                    .foregroundStyle(.white)
                subline
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
        }
        .frame(width: 126, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(borderColor, lineWidth: toAct || won != nil ? 1.5 : 1))
        .overlay(alignment: .bottom) {
            if toAct { Rectangle().fill(Theme.text).frame(height: 2).padding(.horizontal, 1) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(bot.map { "\($0.name): \($0.appearance)" } ?? "")
    }

    @ViewBuilder var subline: some View {
        if let b = bot {
            if game.showHUD {
                Text(b.type.name).font(Theme.ui(9.5, .medium)).foregroundStyle(Theme.color(for: b.type))
            } else if let tag = game.tags[b.id] {
                Text("Tag: \(tag.name)").font(Theme.ui(9.5)).foregroundStyle(Theme.textDim)
            }
        } else if isHero, let p = handPlayer, let h = game.hand, h.board.count >= 3 {
            Text(HandRead.describe(hole: p.hole, board: h.board, value: HandEvaluator.evaluate(p.hole + h.board)))
                .font(Theme.ui(9.5))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
        }
    }

    @ViewBuilder var bubble: some View {
        if let w = won, w > 0 {
            label("+$\(w)", Theme.good)
        } else if let a = game.lastAction[seat], !a.isEmpty {
            label(a, bubbleColor(a))
        }
    }

    func label(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.ui(10.5, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }

    func bubbleColor(_ a: String) -> Color {
        if a.hasPrefix("Fold") { return Theme.surface3 }
        if a.hasPrefix("Raise") || a.hasPrefix("Bet") || a.hasPrefix("All-in") { return Theme.text }
        if a.hasPrefix("Straddle") { return Color(white: 0.3) }
        return Color(white: 0.3)
    }
}

struct ActionBar: View {
    let game: GameController
    @State private var amount: Double = 0
    @State private var amountText = ""

    var body: some View {
        HStack(spacing: 12) {
            if let legal = game.legal, let h = game.hand {
                controls(legal, h)
            } else if game.hand?.isComplete ?? true {
                if game.heroSittingOut {
                    Text("Sitting out. Hands deal automatically.").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                    Spacer()
                } else {
                    Spacer()
                    Button { game.dealNext() } label: { Text("Deal Next Hand").frame(minWidth: 180) }
                        .buttonStyle(PillButtonStyle(large: true))
                        .keyboardShortcut(.space, modifiers: [])
                }
            } else {
                Text(game.heroInCurrentHand ? "Waiting for other players…" : "Hand in progress…").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 92)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder
    func controls(_ legal: LegalActions, _ h: HandState) -> some View {
        let presets = presetAmounts(legal, h)
        Spacer()
        VStack(alignment: .trailing, spacing: 8) {
            if legal.canRaise {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.label) { p in
                        Button(p.label) { setAmount(Double(p.to), legal) }
                            .buttonStyle(PillButtonStyle(color: Theme.surface3, prominent: Int(amount) == p.to, small: true))
                    }
                    BlockSlider(value: Binding(get: { amount }, set: { setAmount($0.rounded(), legal) }),
                                range: Double(legal.minRaiseTo)...Double(max(legal.minRaiseTo + 1, legal.maxRaiseTo)))
                        .frame(width: 180)
                    TextField("", text: $amountText)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 6)
                        .frame(width: 64, height: 24)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bg))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.borderStrong))
                        .onSubmit { if let v = Double(amountText) { setAmount(v, legal) } }
                }
                .fixedSize()
            }
            HStack(spacing: 8) {
                if legal.toCall > 0 {
                    actionButton("Fold", nil, key: "f", primary: false) { game.heroAct(.fold) }
                }
                actionButton(legal.canCheck ? "Check" : "Call", legal.canCheck ? nil : "$\(legal.callAmount)", key: "c", primary: !legal.canRaise) {
                    game.heroAct(legal.canCheck ? .check : .call)
                }
                if legal.canRaise {
                    let to = Int(amount)
                    actionButton(to >= legal.maxRaiseTo ? "All-in" : (legal.isBet ? "Bet" : "Raise to"), "$\(to)", key: "r", primary: true) {
                        game.heroAct(.raise(to: to))
                    }
                }
            }
        }
        .onAppear { setAmount(Double(defaultAmount(legal, h)), legal) }
        .onChange(of: h.actions.count) { setAmount(Double(defaultAmount(legal, h)), legal) }
    }

    func actionButton(_ title: String, _ sub: String?, key: KeyEquivalent, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.ui(13, .medium))
                    if let sub { Text(sub).font(Theme.mono(12.5, .semibold)) }
                }
                Spacer(minLength: 0)
                Text(String(key.character).uppercased())
                    .font(Theme.mono(10))
                    .foregroundStyle(primary ? Theme.onPrimary.opacity(0.5) : Theme.textFaint)
            }
            .padding(.horizontal, 12)
            .frame(width: 128, height: 44)
            .foregroundStyle(primary ? Theme.onPrimary : Theme.text)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(primary ? Theme.primary : Theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(primary ? .clear : Theme.borderStrong))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
    }

    func setAmount(_ v: Double, _ legal: LegalActions) {
        let clamped = min(max(v, Double(legal.minRaiseTo)), Double(legal.maxRaiseTo))
        amount = clamped
        amountText = "\(Int(clamped))"
    }

    func defaultAmount(_ legal: LegalActions, _ h: HandState) -> Int {
        presetAmounts(legal, h).first(where: { $0.isDefault })?.to ?? legal.minRaiseTo
    }

    struct Preset {
        let label: String
        let to: Int
        var isDefault = false
    }

    func presetAmounts(_ legal: LegalActions, _ h: HandState) -> [Preset] {
        let clamp = { (x: Int) in min(max(x, legal.minRaiseTo), legal.maxRaiseTo) }
        var out: [Preset] = []
        if h.street == .preflop {
            let sit = PreflopSituation(state: h, seat: game.heroSeat)
            if sit.raises == 0 {
                let base = h.straddleSeat != nil ? 20 : 12
                let rec = base + 5 * sit.limpers.count
                out.append(Preset(label: "$\(h.straddleSeat != nil ? 15 : 10)", to: clamp(h.straddleSeat != nil ? 15 : 10)))
                out.append(Preset(label: "$\(rec)", to: clamp(rec), isDefault: true))
                out.append(Preset(label: "$\(rec + 5)", to: clamp(rec + 5)))
            } else {
                let facing = h.currentBet
                out.append(Preset(label: "3x", to: clamp(facing * 3), isDefault: true))
                out.append(Preset(label: "4x", to: clamp(facing * 4)))
                out.append(Preset(label: "5x", to: clamp(facing * 5)))
            }
        } else {
            let pot = h.pot
            for (label, f, def) in [("⅓", 0.33, false), ("½", 0.5, true), ("¾", 0.75, false), ("Pot", 1.0, false)] {
                let to = legal.isBet ? legal.committed + Int((Double(pot) * f).rounded())
                    : h.currentBet + Int((Double(pot + legal.toCall) * f).rounded())
                out.append(Preset(label: label, to: clamp(to), isDefault: def))
            }
        }
        out.append(Preset(label: "Max", to: legal.maxRaiseTo))
        return out
    }
}
