import AppKit
import SwiftUI

extension ScribeAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum ScribeTheme {
    static let paper = adaptive(
        light: NSColor(red: 0.988, green: 0.979, blue: 0.955, alpha: 1),
        dark: NSColor(red: 0.090, green: 0.072, blue: 0.098, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(red: 0.976, green: 0.958, blue: 0.925, alpha: 1),
        dark: NSColor(red: 0.120, green: 0.095, blue: 0.120, alpha: 1)
    )
    static let surface = adaptive(
        light: .white,
        dark: NSColor(red: 0.155, green: 0.125, blue: 0.155, alpha: 1)
    )
    static let selection = adaptive(
        light: NSColor(red: 0.930, green: 0.904, blue: 0.855, alpha: 1),
        dark: NSColor(red: 0.245, green: 0.180, blue: 0.190, alpha: 1)
    )
    static let ink = adaptive(
        light: NSColor(red: 0.145, green: 0.095, blue: 0.170, alpha: 1),
        dark: NSColor(red: 0.950, green: 0.920, blue: 0.900, alpha: 1)
    )
    static let mutedInk = adaptive(
        light: NSColor(red: 0.365, green: 0.325, blue: 0.340, alpha: 1),
        dark: NSColor(red: 0.765, green: 0.710, blue: 0.720, alpha: 1)
    )
    static let faintInk = adaptive(
        light: NSColor(red: 0.535, green: 0.500, blue: 0.495, alpha: 1),
        dark: NSColor(red: 0.635, green: 0.585, blue: 0.600, alpha: 1)
    )
    static let coral = adaptive(
        light: NSColor(red: 1.000, green: 0.365, blue: 0.270, alpha: 1),
        dark: NSColor(red: 1.000, green: 0.445, blue: 0.355, alpha: 1)
    )
    static let divider = adaptive(
        light: NSColor(red: 0.805, green: 0.765, blue: 0.700, alpha: 0.58),
        dark: NSColor(red: 0.405, green: 0.340, blue: 0.365, alpha: 0.72)
    )
    static let button = adaptive(
        light: NSColor(red: 0.150, green: 0.095, blue: 0.170, alpha: 1),
        dark: NSColor(red: 0.355, green: 0.220, blue: 0.370, alpha: 1)
    )
    static let blue = adaptive(
        light: NSColor(red: 0.170, green: 0.520, blue: 0.690, alpha: 1),
        dark: NSColor(red: 0.330, green: 0.690, blue: 0.860, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
        return Color(nsColor: color)
    }

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
            .scribePointer()
    }
}

struct ScribeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScribeTheme.sans(13, weight: .medium))
            .foregroundStyle(ScribeTheme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(ScribeTheme.surface.opacity(configuration.isPressed ? 0.45 : 0.68))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ScribeTheme.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scribePointer()
    }
}

private struct ScribePointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard isEnabled else {
                    if isHovering { NSCursor.pop() }
                    isHovering = false
                    return
                }
                if hovering && !isHovering {
                    NSCursor.pointingHand.push()
                    isHovering = true
                } else if !hovering && isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
                isHovering = false
            }
    }
}

extension View {
    /// Gives custom clickable surfaces a familiar pointing-hand cursor.
    func scribePointer() -> some View {
        modifier(ScribePointerCursor())
    }
}
