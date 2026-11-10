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
        }.joined(separator: "\n") + (r.rake > 0 ? "\nRake $\(r.rake)" : "")
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
            .foregroundStyle(color == Theme.text ? Theme.onPrimary : .white)
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

/// Fixed layout: three action slots and the sizing row never move, so a fast click can't land on the wrong button.
/// Slot 1 = fold, slot 2 = check / call, slot 3 = bet / raise (or deal next when the hand is over).
struct ActionBar: View {
    let game: GameController
    @Environment(AppModel.self) private var app
    @State private var amount: Double = 0
    @State private var amountText = ""
    /// Clicks are ignored for a moment after the buttons change meaning (e.g. Deal → Raise).
    @State private var armedAt = Date.distantPast

    static let slotWidth: CGFloat = 138

    enum Phase: Equatable { case act, premove, idle, busy }

    var phase: Phase {
        if game.legal != nil && game.hand != nil { return .act }
        if game.findingSpot { return .busy }
        if game.hand?.isComplete ?? true { return game.heroSittingOut ? .busy : .idle }
        if game.heroInCurrentHand { return .premove }
        return game.heroSittingOut ? .busy : .idle
    }

    var body: some View {
        HStack(spacing: 14) {
            status
                .frame(maxWidth: .infinity, alignment: .leading)
            autoDealToggle
            VStack(alignment: .trailing, spacing: 8) {
                sizingRow
                HStack(spacing: 8) { slot1; slot2; slot3 }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 104)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .onChange(of: phase) { armedAt = Date() }
        .onChange(of: game.hand?.handNumber) { armedAt = Date() }
        .onAppear { if let l = game.legal, let h = game.hand { setAmount(Double(defaultAmount(l, h)), l) } }
        .onChange(of: game.hand?.actions.count) {
            if let l = game.legal, let h = game.hand { setAmount(Double(defaultAmount(l, h)), l) }
        }
    }

    func guarded(_ f: @escaping () -> Void) -> () -> Void {
        { if app.modal == nil && Date().timeIntervalSince(armedAt) > 0.35 { f() } }
    }

    // MARK: Left side

    @ViewBuilder var status: some View {
        switch phase {
        case .busy where game.findingSpot:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Dealing until: \(game.spotKind.title)…").font(Theme.ui(12.5)).foregroundStyle(Theme.textDim)
            }
        case .busy:
            Text("Sitting out. Hands deal automatically.").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
        case .premove:
            Text("Waiting for other players… pre-select below.").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
        case .idle:
            if game.hand.map({ !$0.isComplete }) ?? false {
                Text("You're out of this hand.").font(Theme.ui(12)).foregroundStyle(Theme.textDim)
            } else if let m = game.spotMessage, game.hand == nil || !game.currentHandIsSpot {
                Text(m).font(Theme.ui(12)).foregroundStyle(Theme.warn)
            }
        case .act:
            if let l = game.legal, l.toCall > 0, let h = game.hand {
                Text("$\(l.callAmount) to call · pot $\(h.pot)").font(Theme.mono(12)).foregroundStyle(Theme.textDim)
            }
        }
    }

    var autoDealToggle: some View {
        PreToggle(title: "Auto-deal", on: app.settings.autoDeal) { app.settings.autoDeal.toggle() }
            .help("Deal the next hand automatically a moment after each hand ends")
    }

    // MARK: Slots

    var toCallWhileWaiting: Int {
        game.hand.flatMap { h in h.player(seat: game.heroSeat).map { max(0, h.currentBet - $0.committedStreet) } } ?? 0
    }

    @ViewBuilder var slot1: some View {
        switch phase {
        case .act:
            let l = game.legal!
            ActionSlot(title: "Fold", enabled: l.toCall > 0, action: guarded { game.heroAct(.fold) })
                .keyboardShortcut("f", modifiers: [])
        case .premove:
            PreSlot(title: toCallWhileWaiting > 0 ? "Fold" : "Check/Fold", on: game.premove == .checkFold) { toggle(.checkFold) }
                .keyboardShortcut("f", modifiers: [])
        default:
            ActionSlot.placeholder
        }
    }

    @ViewBuilder var slot2: some View {
        switch phase {
        case .act:
            let l = game.legal!
            ActionSlot(title: l.canCheck ? "Check" : "Call", sub: l.canCheck ? nil : "$\(l.callAmount)",
                       action: guarded { game.heroAct(l.canCheck ? .check : .call) })
                .keyboardShortcut("c", modifiers: [])
        case .premove:
            if toCallWhileWaiting == 0 {
                PreSlot(title: "Check", on: game.premove == .check) { toggle(.check) }
                    .keyboardShortcut("k", modifiers: [])
            } else {
                ActionSlot.placeholder
            }
        default:
            ActionSlot.placeholder
        }
    }

    @ViewBuilder var slot3: some View {
        switch phase {
        case .act:
            let l = game.legal!
            let to = Int(amount)
            ActionSlot(title: !l.canRaise ? "Raise" : (to >= l.maxRaiseTo ? "All-in" : (l.isBet ? "Bet" : "Raise to")),
                       sub: l.canRaise ? "$\(to)" : nil, primary: l.canRaise, enabled: l.canRaise,
                       action: guarded { game.heroAct(.raise(to: to)) })
                .keyboardShortcut("r", modifiers: [])
        case .premove:
            PreSlot(title: toCallWhileWaiting > 0 ? "Call any" : "Check/Call any", on: game.premove == .callAny) { toggle(.callAny) }
                .keyboardShortcut("c", modifiers: [])
        case .idle:
            let inHand = game.hand.map { !$0.isComplete } ?? false
            ActionSlot(title: game.spotMode ? (inHand ? "Skip to next spot" : "Next spot") : (inHand ? "Skip hand" : "Deal next"),
                       sub: nil, primary: true, action: guarded { inHand ? game.skipToNextHand() : game.dealNext() })
                .keyboardShortcut(.space, modifiers: [])
        case .busy:
            ActionSlot.placeholder
        }
    }

    func toggle(_ p: Premove) {
        game.premove = game.premove == p ? nil : p
    }

    /// Presets, slider and amount box. Always laid out so nothing below it shifts; hidden unless you can bet.
    @ViewBuilder var sizingRow: some View {
        let active = phase == .act && (game.legal?.canRaise ?? false)
        HStack(spacing: 6) {
            if active, let legal = game.legal, let h = game.hand {
                ForEach(presetAmounts(legal, h), id: \.label) { p in
                    Button(p.label) { setAmount(Double(p.to), legal) }
                        .buttonStyle(PillButtonStyle(color: Color.white.opacity(0.16), prominent: Int(amount) == p.to, small: true))
                }
                BlockSlider(value: Binding(get: { amount }, set: { setAmount($0.rounded(), legal) }),
                            range: Double(legal.minRaiseTo)...Double(max(legal.minRaiseTo + 1, legal.maxRaiseTo)))
                    .frame(width: 170)
                TextField("", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(13))
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 10)
                    .frame(width: 72, height: 26)
                    .background(Capsule().fill(Theme.bg))
                    .overlay(Capsule().strokeBorder(Theme.borderStrong, lineWidth: 0.75))
                    .onSubmit { if let v = Double(amountText) { setAmount(v, legal) } }
            }
        }
        .frame(height: 26)
        .fixedSize()
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

/// One fixed-size action slot. Placeholders keep the geometry when a slot has nothing to offer.
struct ActionSlot: View {
    let title: String
    var sub: String?
    var primary = false
    var enabled = true
    let action: () -> Void
    @State private var hover = false

    static var placeholder: some View {
        Capsule().strokeBorder(Color.white.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(width: ActionBar.slotWidth, height: 46)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(Theme.ui(13.5, .semibold))
                if let sub { Text(sub).font(Theme.mono(12, .medium)).opacity(0.75) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: ActionBar.slotWidth, height: 46)
            .foregroundStyle(primary ? Theme.onPrimary : Theme.text)
            .glassCapsule(fill: primary ? Theme.primary.opacity(0.92) : Color.white.opacity(0.07), hover: hover && enabled, pressed: false, dark: primary)
        }
        .buttonStyle(PressScale())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .onHover { hover = $0 }
    }
}

/// Pre-action checkbox drawn in an action slot, so the click target stays where the real action will appear.
struct PreSlot: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(on ? Theme.text : Theme.borderStrong, lineWidth: 1.5)
                    .background(Circle().fill(on ? Theme.text : .clear).padding(3.5))
                    .frame(width: 14, height: 14)
                Text(title).font(Theme.ui(12.5, .medium)).foregroundStyle(on ? Theme.text : Theme.textDim)
            }
            .lineLimit(1)
            .frame(width: ActionBar.slotWidth, height: 46)
            .glassCapsule(fill: Color.white.opacity(on ? 0.12 : 0.04), hover: hover, pressed: false)
        }
        .buttonStyle(PressScale())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// Checkbox-style chip used for pre-actions.
struct PreToggle: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Capsule().fill(on ? Theme.good : Color.white.opacity(0.14))
                    .frame(width: 22, height: 13)
                    .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 9, height: 9).padding(2) }
                Text(title).font(Theme.ui(12.5, .medium)).foregroundStyle(on ? Theme.text : Theme.textDim)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassCapsule(fill: Color.white.opacity(0.05), hover: false, pressed: false)
            .animation(.easeOut(duration: 0.15), value: on)
        }
        .buttonStyle(PressScale())
        .fixedSize()
    }
}
