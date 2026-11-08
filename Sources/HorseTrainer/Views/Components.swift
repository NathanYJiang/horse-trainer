import PokerCore
import SwiftUI

/// Flat, minimalist palette in the style of a classic desktop poker client: black, charcoal, white, one red accent.
enum Theme {
    static let bg = Color(white: 0.045)
    static let surface = Color(white: 0.085)
    static let surface2 = Color(white: 0.12)
    static let surface3 = Color(white: 0.16)
    static let border = Color(white: 0.2)
    static let stroke = Color(white: 0.2)
    static let panel = Color(white: 0.085)
    static let panelHi = Color(white: 0.14)
    static let textDim = Color(white: 0.58)
    static let textFaint = Color(white: 0.4)

    static let red = Color(red: 0.78, green: 0.11, blue: 0.13)
    static let redDark = Color(red: 0.52, green: 0.07, blue: 0.09)
    static let accent = Color(red: 0.25, green: 0.52, blue: 0.95)
    static let gold = Color(red: 0.95, green: 0.78, blue: 0.35)
    static let good = Color(red: 0.27, green: 0.68, blue: 0.42)
    static let bad = Color(red: 0.86, green: 0.26, blue: 0.24)
    static let warn = Color(red: 0.90, green: 0.62, blue: 0.20)

    static let felt = Color(white: 0.11)
    static let rail = Color(white: 0.17)

    static func color(for type: PlayerType) -> Color {
        switch type {
        case .whale: Color(red: 0.36, green: 0.55, blue: 0.95)
        case .fish: Color(red: 0.28, green: 0.72, blue: 0.75)
        case .tryingRec: Color(red: 0.88, green: 0.70, blue: 0.28)
        case .nit: Color(white: 0.62)
        case .reg: Color(red: 0.86, green: 0.34, blue: 0.36)
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

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    static let label = Font.system(size: 10, weight: .semibold)
}

/// Solid app background.
struct Backdrop: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Theme.label).tracking(0.6).foregroundStyle(Theme.textDim)
    }
}

/// Classic client card: white face, big index top-left, large pip bottom-right. Four-color deck optional.
struct CardView: View {
    let card: Card?
    var faceUp = true
    var width: CGFloat = 46
    var fourColor = true
    var dimmed = false

    var height: CGFloat { width * 1.4 }
    var radius: CGFloat { width * 0.09 }

    static func suitColor(_ s: Suit, fourColor: Bool) -> Color {
        switch s {
        case .spades: return .black
        case .hearts: return Color(red: 0.82, green: 0.07, blue: 0.10)
        case .diamonds: return fourColor ? Color(red: 0.05, green: 0.30, blue: 0.80) : Color(red: 0.82, green: 0.07, blue: 0.10)
        case .clubs: return fourColor ? Color(red: 0.05, green: 0.52, blue: 0.18) : .black
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let c = card, faceUp {
                RoundedRectangle(cornerRadius: radius).fill(Color.white)
                RoundedRectangle(cornerRadius: radius).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5)
                let color = Self.suitColor(c.suit, fourColor: fourColor)
                VStack(alignment: .center, spacing: -width * 0.06) {
                    Text(c.rankText == "T" ? "10" : c.rankText)
                        .font(.system(size: width * (c.rankText == "T" ? 0.40 : 0.48), weight: .bold))
                        .tracking(c.rankText == "T" ? -1.2 : 0)
                    Text(c.suit.symbol).font(.system(size: width * 0.30))
                }
                .foregroundStyle(color)
                .padding(.leading, width * 0.06)
                .padding(.top, width * 0.02)
                Text(c.suit.symbol)
                    .font(.system(size: width * 0.62))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, width * 0.06)
            } else if card != nil || !faceUp {
                RoundedRectangle(cornerRadius: radius).fill(Theme.redDark)
                RoundedRectangle(cornerRadius: radius * 0.6)
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    .padding(width * 0.07)
                RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .frame(width: width, height: height)
        .opacity(dimmed ? 0.35 : 1)
    }
}

struct ChipStack: View {
    let amount: Int
    var compact = false

    var chipColor: Color {
        switch amount {
        case ..<5: Color(white: 0.9)
        case ..<25: Theme.red
        case ..<100: Theme.good
        case ..<500: Color(white: 0.15)
        default: Color(red: 0.45, green: 0.3, blue: 0.7)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(chipColor)
                .overlay(Circle().strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [2.2, 2.2])).padding(1))
                .frame(width: 14, height: 14)
            Text("$\(amount)")
                .font(Theme.mono(compact ? 11 : 12))
                .foregroundStyle(.white)
        }
    }
}

struct TypeBadge: View {
    let type: PlayerType
    var small = false

    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Theme.color(for: type)).frame(width: 3, height: small ? 10 : 12)
            Text(type.name)
        }
        .font(.system(size: small ? 10 : 12, weight: .medium))
        .padding(.horizontal, small ? 5 : 7)
        .padding(.vertical, small ? 2 : 3)
        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.surface3))
        .foregroundStyle(.white)
    }
}

/// Flat bordered container.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint?.opacity(0.6) ?? Theme.border, lineWidth: 1))
    }
}

struct PrincipleCard: View {
    let principle: Principle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Theme.gold).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(principle.title).font(.system(size: 13, weight: .semibold))
                Text(principle.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Flat rectangular button. `prominent` fills with `color`; otherwise a bordered dark button.
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.red
    var prominent = true
    var large = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        FlatButton(configuration: configuration, color: color, prominent: prominent, large: large, small: small)
    }

    private struct FlatButton: View {
        let configuration: Configuration
        let color: Color
        let prominent: Bool
        let large: Bool
        let small: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: large ? 14 : (small ? 11.5 : 12.5), weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, large ? 18 : (small ? 9 : 12))
                .padding(.vertical, large ? 10 : (small ? 4 : 6))
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(prominent ? color.opacity(configuration.isPressed ? 0.75 : 1) : Theme.surface2.opacity(configuration.isPressed ? 0.6 : 1))
                )
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(prominent ? Color.clear : Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

struct Avatar: View {
    let name: String
    let hue: Double
    var size: CGFloat = 44

    var body: some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.35, brightness: 0.45))
            .overlay(Text(String(name.prefix(1))).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
    }
}

/// Markdown text that renders headings/bullets reasonably for Claude output.
struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 4)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(Theme.textDim)
                Text(inline(String(line.dropFirst(2))))
            }
            .font(.system(size: 13))
        } else if line.isEmpty {
            Spacer().frame(height: 2)
        } else {
            Text(inline(line)).font(.system(size: 13))
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            trailing
        }
    }
}

/// Small flat stat box used in headers.
struct StatBox: View {
    let label: String
    let value: String
    var color: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.textDim)
            Text(value).font(Theme.mono(14)).foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 64, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
        .fixedSize()
    }
}
