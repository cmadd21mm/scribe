import SwiftUI

enum ScribeTheme {
    static let paper = Color(red: 0.988, green: 0.979, blue: 0.955)
    static let sidebar = Color(red: 0.976, green: 0.958, blue: 0.925)
    static let selection = Color(red: 0.930, green: 0.904, blue: 0.855)
    static let ink = Color(red: 0.145, green: 0.095, blue: 0.170)
    static let mutedInk = Color(red: 0.365, green: 0.325, blue: 0.340)
    static let faintInk = Color(red: 0.535, green: 0.500, blue: 0.495)
    static let coral = Color(red: 1.000, green: 0.365, blue: 0.270)
    static let divider = Color(red: 0.805, green: 0.765, blue: 0.700).opacity(0.58)
    static let button = Color(red: 0.150, green: 0.095, blue: 0.170)
    static let blue = Color(red: 0.170, green: 0.520, blue: 0.690)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct ScribeBrand: View {
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : 14) {
            Image(systemName: "quote.bubble")
                .font(.system(size: compact ? 20 : 30, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(ScribeTheme.coral, ScribeTheme.ink)
                .frame(width: compact ? 30 : 42, height: compact ? 30 : 42)

            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCRIBE")
                        .font(ScribeTheme.serif(27, weight: .medium))
                        .tracking(3.2)
                        .foregroundStyle(ScribeTheme.ink)
                    Text("Stay in the conversation.")
                        .font(ScribeTheme.serif(13).italic())
                        .foregroundStyle(ScribeTheme.coral)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scribe — Stay in the conversation")
    }
}

struct ScribeSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ScribeTheme.divider)
            .frame(height: 1)
    }
}

struct ScribePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScribeTheme.sans(14, weight: .medium))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(ScribeTheme.button.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ScribeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScribeTheme.sans(13, weight: .medium))
            .foregroundStyle(ScribeTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.white.opacity(configuration.isPressed ? 0.35 : 0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ScribeTheme.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
