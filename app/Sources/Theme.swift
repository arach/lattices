import SwiftUI

// MARK: - Colors

enum Palette {
    // Base surfaces — warm dark
    static let bg         = Color(red: 0.11, green: 0.11, blue: 0.12)   // #1C1C1E
    static let surface    = Color(red: 0.15, green: 0.15, blue: 0.16)   // Raised cards
    static let surfaceHov = Color(red: 0.18, green: 0.18, blue: 0.19)   // Hovered cards
    static let border     = Color.white.opacity(0.05)
    static let borderLit  = Color.white.opacity(0.10)

    // Text
    static let text       = Color.white.opacity(0.92)
    static let textDim    = Color.white.opacity(0.50)
    static let textMuted  = Color.white.opacity(0.30)

    // Functional accents
    static let running  = Color(red: 0.20, green: 0.78, blue: 0.45)   // Green
    static let detach   = Color(red: 0.96, green: 0.65, blue: 0.14)   // Amber
    static let kill     = Color(red: 0.94, green: 0.30, blue: 0.35)   // Red
    static let launch   = Color.white                                   // Clean white
}

// MARK: - Typography

enum Typo {
    private static let jetbrains = "JetBrains Mono"
    private static let geist     = "GeistMono Nerd Font"
    private static let gohu      = "GohuFontuni14 Nerd Font"

    static func title(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func heading(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func body(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func caption(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func mono(_ size: CGFloat = 11) -> Font {
        .custom(jetbrains, size: size)
    }

    static func monoBold(_ size: CGFloat = 11) -> Font {
        Font.custom(jetbrains, size: size).weight(.semibold)
    }

    static func geistMono(_ size: CGFloat = 11) -> Font {
        .custom(geist, size: size)
    }

    static func geistMonoBold(_ size: CGFloat = 11) -> Font {
        Font.custom(geist, size: size).weight(.medium)
    }

    static func pixel(_ size: CGFloat = 14) -> Font {
        .custom(gohu, size: size)
    }
}

// MARK: - Background

struct PanelBackground: View {
    var body: some View {
        Palette.bg
    }
}

// MARK: - Reusable modifiers

struct GlassCard: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Palette.surfaceHov : Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isHovered ? Palette.borderLit : Palette.border, lineWidth: 0.5)
                    )
            )
    }
}

struct AngularButton: ViewModifier {
    let color: Color
    var filled: Bool = true

    func body(content: Content) -> some View {
        content
            .font(Typo.monoBold(10))
            .foregroundColor(filled ? Palette.bg : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(filled ? color : color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(filled ? Color.clear : color.opacity(0.25), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(hovered: Bool = false) -> some View {
        modifier(GlassCard(isHovered: hovered))
    }

    func angularButton(_ color: Color, filled: Bool = true) -> some View {
        modifier(AngularButton(color: color, filled: filled))
    }
}
