import PokerCore
import SwiftUI

/// Neutral, flat design system: near-black surfaces, 1px translucent borders, Geist + Geist Mono, white primary buttons.
enum Theme {
    // Surfaces
    static let bg = Color(hex: 0x0A0A0A)
    static let surface = Color(hex: 0x111111)
    static let card = Color(hex: 0x171717)
    static let surface2 = Color(hex: 0x1C1C1C)
    static let surface3 = Color(hex: 0x262626)
    static let panel = card
    static let panelHi = surface3
    static let border = Color.white.opacity(0.10)
    static let borderStrong = Color.white.opacity(0.20)
    static let stroke = border

    // Text
    static let text = Color(hex: 0xFAFAFA)
    static let textDim = Color(hex: 0xA1A1A1)
    static let textFaint = Color(hex: 0x737373)

    // Actions
    static let primary = Color(hex: 0xFAFAFA)
    static let onPrimary = Color(hex: 0x0A0A0A)

    // Signals (Tailwind-ish 500s)
    static let good = Color(hex: 0x00BB7F)
    static let warn = Color(hex: 0xF99C00)
    static let bad = Color(hex: 0xFB2C36)
    static let red = Color(hex: 0xFB2C36)
    static let redDark = Color(hex: 0x82181A)
    static let accent = Color(hex: 0x00A5EF)
    static let gold = Color(hex: 0xFCBB00)

    // Gym palette (Daily Workout, streaks, XP): bright and chunky on purpose.
    static let flame = Color(hex: 0xFF9600)
    static let flameDark = Color(hex: 0xCC7800)
    static let duoGreen = Color(hex: 0x58CC02)
    static let duoGreenDark = Color(hex: 0x46A302)
    static let duoRed = Color(hex: 0xFF4B4B)
    static let duoRedDark = Color(hex: 0xD33131)
    static let duoBlue = Color(hex: 0x1CB0F6)
    static let duoBlueDark = Color(hex: 0x1490CC)
    static let duoGold = Color(hex: 0xFFC800)
    static let duoGoldDark = Color(hex: 0xD9A800)
    static let duoPurple = Color(hex: 0xCE82FF)
    static let duoPurpleDark = Color(hex: 0xA65FD6)

    // Table
    static let felt = Color(hex: 0x111111)
    static let rail = Color(hex: 0x1C1C1C)

    static func color(for type: PlayerType) -> Color {
        switch type {
        case .whale: Color(hex: 0x3B82F6)
        case .fish: Color(hex: 0x00B7D7)
        case .tryingRec: Color(hex: 0xF99C00)
        case .nit: Color(hex: 0xA1A1A1)
        case .reg: Color(hex: 0xFB2C36)
        }
    }

    static func color(for grade: Grade) -> Color {
        switch grade {
        case .good: good
        case .okay: accent
        case .inaccuracy: warn
        case .mistake: bad
        }
    }

    // Type
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Geist-Medium"
        case .semibold: name = "Geist-SemiBold"
        case .bold, .heavy, .black: name = "Geist-Bold"
        default: name = "Geist-Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .regular, .light, .thin, .ultraLight: name = "GeistMono-Regular"
        case .medium: name = "GeistMono-Medium"
        default: name = "GeistMono-SemiBold"
        }
        return .custom(name, size: size)
    }

    static let label = mono(10, .medium)
    static let radius: CGFloat = 8
    static let radiusSm: CGFloat = 6
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct Backdrop: View {
    var body: some View { Theme.bg.ignoresSafeArea() }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Theme.label).tracking(0.8).foregroundStyle(Theme.textFaint)
    }
}

/// Keyboard hint, e.g. `Kbd("F")`.
struct Kbd: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(Theme.mono(10, .medium))
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.surface3))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

/// Classic white card with big indices; four-color deck optional.
struct CardView: View {
    let card: Card?
    var faceUp = true
    var width: CGFloat = 46
    var fourColor = true
    var dimmed = false

    var height: CGFloat { width * 1.4 }
    var radius: CGFloat { max(3, width * 0.09) }

    static func suitColor(_ s: Suit, fourColor: Bool) -> Color {
        switch s {
        case .spades: return Color(hex: 0x0A0A0A)
        case .hearts: return Color(hex: 0xE40014)
        case .diamonds: return fourColor ? Color(hex: 0x0084CC) : Color(hex: 0xE40014)
        case .clubs: return fourColor ? Color(hex: 0x00A544) : Color(hex: 0x0A0A0A)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let c = card, faceUp {
                RoundedRectangle(cornerRadius: radius).fill(Color(hex: 0xFAFAFA))
                let color = Self.suitColor(c.suit, fourColor: fourColor)
                VStack(alignment: .center, spacing: -width * 0.05) {
                    Text(c.rankText == "T" ? "10" : c.rankText)
                        .font(Theme.ui(width * (c.rankText == "T" ? 0.40 : 0.50), .semibold))
                        .tracking(c.rankText == "T" ? -1.5 : 0)
                    Text(c.suit.symbol).font(.system(size: width * 0.30))
                }
                .foregroundStyle(color)
                .padding(.leading, width * 0.07)
                .padding(.top, width * 0.03)
                Text(c.suit.symbol)
                    .font(.system(size: width * 0.6))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, width * 0.07)
            } else if card != nil || !faceUp {
                RoundedRectangle(cornerRadius: radius).fill(Theme.surface3)
                RoundedRectangle(cornerRadius: radius * 0.6)
                    .strokeBorder(Theme.border, lineWidth: 1)
                    .padding(width * 0.1)
                RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.borderStrong, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(width: width, height: height)
        .opacity(dimmed ? 0.35 : 1)
    }
}

struct ChipStack: View {
    let amount: Int
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.text).frame(width: 6, height: 6)
            Text("$\(amount)").font(Theme.mono(compact ? 11 : 12)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
    }
}

struct TypeBadge: View {
    let type: PlayerType
    var small = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.color(for: type)).frame(width: 6, height: 6)
            Text(type.name)
        }
        .font(Theme.mono(small ? 10 : 11, .medium))
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
        .foregroundStyle(Theme.text)
    }
}

/// Bordered card container.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(tint?.opacity(0.5) ?? Theme.border, lineWidth: 1))
    }
}

struct PrincipleCard: View {
    let principle: Principle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                SectionLabel("Principle")
                Text(principle.title).font(Theme.ui(13, .semibold))
            }
            Text(principle.summary)
                .font(Theme.ui(12.5))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

/// Capsule button in the Aside style: glassy fill, hairline edge, soft hover layer.
/// Prominent white = primary; prominent with `color` = selected chip; otherwise a quiet glass button.
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.primary
    var prominent = true
    var large = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(configuration: configuration, color: color, prominent: prominent, large: large, small: small)
    }

    private struct CapsuleButton: View {
        let configuration: Configuration
        let color: Color
        let prominent: Bool
        let large: Bool
        let small: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var isPrimary: Bool { prominent && color == Theme.primary }

        var body: some View {
            configuration.label
                .font(Theme.ui(large ? 14 : (small ? 12 : 13), .medium))
                .lineLimit(1)
                .padding(.horizontal, large ? 20 : (small ? 11 : 14))
                .frame(minHeight: large ? 40 : (small ? 26 : 32))
                .foregroundStyle(isPrimary ? Theme.onPrimary : Theme.text)
                .glassCapsule(fill: isPrimary ? Theme.primary.opacity(0.92) : (prominent ? color : Color.white.opacity(0.06)),
                              hover: hover && enabled, pressed: configuration.isPressed, dark: isPrimary)
                .opacity(enabled ? 1 : 0.45)
                .onHover { hover = $0 }
        }
    }
}

extension View {
    /// Capsule fill + hairline edge + hover/press state layer, shared by every button-like control.
    func glassCapsule(fill: Color, hover: Bool, pressed: Bool, dark: Bool = false) -> some View {
        self
            .background(Capsule().fill(fill))
            .background(Capsule().fill(Color.black.opacity(dark ? 0.0 : 0.15)).shadow(color: .black.opacity(0.35), radius: 6, y: 2))
            .overlay(Capsule().fill(dark ? Color.black.opacity(pressed ? 0.14 : (hover ? 0.06 : 0)) : Color.white.opacity(pressed ? 0.04 : (hover ? 0.09 : 0))))
            .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0 : 0.12), lineWidth: 0.75))
            .overlay(Capsule().strokeBorder(Color.black.opacity(pressed ? 0.25 : 0), lineWidth: 2).blur(radius: 1.5).clipShape(Capsule()))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: hover)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// Chunky, colorful button with a solid bottom ledge that presses down. Used in the gym.
struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.duoGreen
    var ledge: Color = Theme.duoGreenDark
    var textColor: Color = .white
    var height: CGFloat = 46
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        Chunky(configuration: configuration, style: self)
    }

    private struct Chunky: View {
        let configuration: Configuration
        let style: ChunkyButtonStyle
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false

        var body: some View {
            let pressed = configuration.isPressed
            let depth: CGFloat = 4
            configuration.label
                .font(Theme.ui(15, .bold))
                .tracking(0.3)
                .foregroundStyle(enabled ? style.textColor : Theme.textFaint)
                .padding(.horizontal, 22)
                .frame(maxWidth: style.fill ? .infinity : nil, minHeight: style.height)
                .background(RoundedRectangle(cornerRadius: 12).fill(enabled ? style.color : Theme.surface3).brightness(hover && !pressed ? 0.04 : 0))
                .background(RoundedRectangle(cornerRadius: 12).fill(enabled ? style.ledge : Theme.surface2).offset(y: pressed ? 0 : depth))
                .offset(y: pressed ? depth : 0)
                .padding(.bottom, depth)
                .contentShape(Rectangle())
                .animation(.snappy(duration: 0.08), value: pressed)
                .onHover { hover = $0 }
        }
    }
}

/// Answer tile for workout reps: neutral until answered, then green / red.
struct AnswerTileStyle: ButtonStyle {
    enum State { case idle, correct, wrong, faded }
    var state: State = .idle

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let (fill, edge, stroke): (Color, Color, Color) = switch state {
        case .idle: (Theme.card, Color(hex: 0x2E2E2E), Theme.borderStrong)
        case .correct: (Theme.duoGreen.opacity(0.18), Theme.duoGreenDark, Theme.duoGreen)
        case .wrong: (Theme.duoRed.opacity(0.18), Theme.duoRedDark, Theme.duoRed)
        case .faded: (Theme.surface, Theme.surface2, Theme.border)
        }
        return configuration.label
            .font(Theme.ui(14.5, .semibold))
            .foregroundStyle(state == .faded ? Theme.textFaint : (state == .correct ? Theme.duoGreen : (state == .wrong ? Theme.duoRed : Theme.text)))
            .padding(.horizontal, 16)
            .frame(minWidth: 96, minHeight: 50)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(edge).offset(y: pressed ? 0 : 4)
                    RoundedRectangle(cornerRadius: 12).fill(Theme.card)
                    RoundedRectangle(cornerRadius: 12).fill(fill)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stroke, lineWidth: 2))
            .offset(y: pressed ? 4 : 0)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.08), value: pressed)
            .animation(.easeOut(duration: 0.2), value: state)
    }
}

/// Segmented control replacement.
struct BlockTabs<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title) = options[i]
                Button { selection = value } label: {
                    Text(title)
                        .font(Theme.ui(12.5, .medium))
                        .foregroundStyle(selection == value ? Theme.text : Theme.textDim)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(Capsule().fill(selection == value ? Color.white.opacity(0.12) : .clear))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(selection == value ? 0.12 : 0), lineWidth: 0.75))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.75))
        .animation(.easeOut(duration: 0.15), value: selection)
        .fixedSize()
    }
}

/// Dropdown with a block-styled label.
struct BlockMenu<T: Hashable>: View {
    let label: String
    @Binding var selection: T
    let options: [(T, String)]

    var current: String { options.first { $0.0 == selection }?.1 ?? "" }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].1) { selection = options[i].0 }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label).font(Theme.mono(10.5)).foregroundStyle(Theme.textFaint)
                Text(current).font(Theme.ui(12.5, .medium)).foregroundStyle(Theme.text)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textDim)
            }
            .padding(.horizontal, 13)
            .frame(height: 32)
            .glassCapsule(fill: Color.white.opacity(0.06), hover: false, pressed: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Flat slider: thin track, round thumb.
struct BlockSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var onCommit: (() -> Void)?

    var body: some View {
        GeometryReader { g in
            let span = max(0.0001, range.upperBound - range.lowerBound)
            let t = CGFloat((value - range.lowerBound) / span).clamped01
            let thumb: CGFloat = 14
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.surface3).frame(height: 4)
                RoundedRectangle(cornerRadius: 2).fill(Theme.text).frame(width: max(0, (g.size.width - thumb) * t + thumb / 2), height: 4)
                Circle()
                    .fill(Theme.text)
                    .frame(width: thumb, height: thumb)
                    .offset(x: (g.size.width - thumb) * t)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let frac = Double(((v.location.x - thumb / 2) / max(1, g.size.width - thumb)).clamped01)
                        var nv = range.lowerBound + frac * span
                        nv = (nv / step).rounded() * step
                        value = min(range.upperBound, max(range.lowerBound, nv))
                    }
                    .onEnded { _ in onCommit?() }
            )
        }
        .frame(height: 20)
    }
}

extension CGFloat {
    var clamped01: CGFloat { Swift.min(1, Swift.max(0, self)) }
}

/// Block text field style.
struct BlockFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.ui(13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
    }
}

struct Avatar: View {
    let name: String
    let hue: Double
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(Color(hue: hue, saturation: 0.25, brightness: 0.28))
            .overlay(Text(String(name.prefix(1))).font(Theme.ui(size * 0.42, .semibold)).foregroundStyle(Theme.text))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(Theme.border))
            .frame(width: size, height: size)
    }
}

/// Markdown text that renders headings/bullets reasonably for Claude output.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            Text(inline(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                .font(Theme.ui(14.5, .semibold))
                .padding(.top, 6)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("–").foregroundStyle(Theme.textFaint)
                Text(inline(String(line.dropFirst(2))))
            }
            .font(Theme.ui(13.5))
        } else if line.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(line)).font(Theme.ui(13.5))
        }
    }

    func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.ui(22, .semibold)).tracking(-0.3)
                Text(subtitle).font(Theme.ui(13)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            trailing
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.mono(9.5)).tracking(0.6).foregroundStyle(Theme.textFaint)
            Text(value).font(Theme.mono(13.5, .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 62, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSm).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.border))
        .fixedSize()
    }
}

/// Centered modal card drawn inside the window (instead of a system sheet).
struct ModalCard<Content: View>: View {
    let title: String
    var width: CGFloat = 520
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Theme.ui(15, .semibold))
                Spacer()
                CloseButton(action: onClose)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Rectangle().fill(Theme.border).frame(height: 1)
            content
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.borderStrong))
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textDim)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hover ? 0.14 : 0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hover = $0 }
    }
}
