import SwiftUI

// MARK: - Colors

enum Palette {
    // Base surfaces
    static let bg         = Color(red: 0.08, green: 0.08, blue: 0.09)   // #141416
    static let bgSidebar  = Color(red: 0.08, green: 0.08, blue: 0.09)   // same as bg
    static let surface    = Color(white: 0.10)                           // Raised cards
    static let surfaceHov = Color(white: 0.14)                           // Hovered cards
    static let border     = Color.white.opacity(0.08)
    static let borderLit  = Color.white.opacity(0.14)

    // Text
    static let text       = Color.white.opacity(0.92)
    static let textDim    = Color.white.opacity(0.58)
    static let textMuted  = Color.white.opacity(0.40)

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

struct LiquidGlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base: translucent dark fill
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.04))

                    // Subtle gradient: brighter at top edge for "glass reflection"
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.06), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    // Border: top-bright, bottom-dark for depth
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
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

    func liquidGlass() -> some View {
        modifier(LiquidGlassCard())
    }

    func angularButton(_ color: Color, filled: Bool = true) -> some View {
        modifier(AngularButton(color: color, filled: filled))
    }
}
