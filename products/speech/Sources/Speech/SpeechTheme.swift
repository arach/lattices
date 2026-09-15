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

    /// Reading font for message *content* (assistant/user prose) — SF Mono, the
    /// system monospace: crisp and fine, with native hinting, and still clearly
    /// monospaced/terminal-grade vs. the rounded SF used for UI chrome. (Was
    /// JetBrains Mono, which read heavier and wider for body copy.)
    static func reading(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

