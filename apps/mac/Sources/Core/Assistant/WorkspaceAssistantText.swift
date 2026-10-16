import AppKit
import SwiftUI
import HudsonUI

// Assistant message text: Hudson's `HudSelectableText` (one AppKit text view per
// turn, so a drag selects across every block) fed by `HudAttributedMarkdown`,
// with the assistant's faces and inks.

// MARK: - Fonts

enum WorkspaceAssistantFonts {
    /// Prose and labels: the system sans. Regular and Medium only below 14pt;
    /// Light thins to broken stems at 1x.
    static func prose(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Code and numbers: JetBrains Mono (the Ghostty face), falling back to SF
    /// Mono. Regular by default; Light only at 14pt and up.
    static func code(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let weight: NSFont.Weight = size < 14 && weight < .regular ? .regular : weight
        let name = weight >= .medium ? "JetBrainsMono-Medium"
            : weight >= .regular ? "JetBrainsMono-Regular"
            : "JetBrainsMono-Light"
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func codeFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> Font {
        Font(code(size, weight: weight) as CTFont)
    }
}

// MARK: - Inks

/// The assistant page's ground. Dark is the app's `Palette.bg`; light is a
/// near-white paper, there to compare how the faces rasterize. Read from
/// defaults so non-view code (the markdown builder) sees the same value; the
/// view rebuilds the page when it changes.
enum AssistantAppearance: String {
    case dark
    case light

    static let defaultsKey = "assistant.appearance"

    static var current: AssistantAppearance {
        AssistantAppearance(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .dark
    }
}

/// Opaque inks over the page. Two text inks carry the page: `prose` for what
/// you read, `dim` for what describes it. `strong` is for emphasis only and
/// `muted` for list markers and disabled glyphs.
enum AssistantInk {
    /// `Palette.bg` (#141416) as AppKit.
    private static let darkPage = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
    private static let lightPage = NSColor(srgbRed: 0.985, green: 0.985, blue: 0.98, alpha: 1)

    private static let darkSet: HudOpaqueInk = {
        var ink = HudOpaqueInk(ground: darkPage)
        ink.prose = ink.over(0.90)
        ink.strong = ink.over(0.96)
        ink.dim = ink.over(0.74)
        ink.muted = ink.over(0.42)
        ink.code = ink.over(0.96)
        return ink
    }()

    private static let lightSet: HudOpaqueInk = {
        var ink = HudOpaqueInk(ground: lightPage, base: .black)
        ink.prose = ink.over(0.88)
        ink.strong = ink.over(0.96)
        ink.dim = ink.over(0.62)
        ink.muted = ink.over(0.38)
        ink.code = ink.over(0.92)
        ink.codeGround = ink.over(0.04)
        ink.selection = ink.over(0.14)
        return ink
    }()

    /// The ground every text view draws on.
    static var page: NSColor { Self.set.ground }

    static var set: HudOpaqueInk {
        AssistantAppearance.current == .light ? lightSet : darkSet
    }

    static var prose: Color { Color(nsColor: Self.set.prose) }
    static var strong: Color { Color(nsColor: Self.set.strong) }
    static var dim: Color { Color(nsColor: Self.set.dim) }
    static var muted: Color { Color(nsColor: Self.set.muted) }
}

// MARK: - Markdown

struct WorkspaceAssistantMarkdown {
    var size: CGFloat

    private var builder: HudAttributedMarkdown {
        HudAttributedMarkdown(style: HudAttributedMarkdownStyle(
            size: size,
            ink: AssistantInk.set,
            prose: { WorkspaceAssistantFonts.prose($0, weight: $1) },
            code: { WorkspaceAssistantFonts.code($0, weight: $1) },
            inlineCodeGround: false
        ))
    }

    func plain(_ text: String) -> NSAttributedString {
        builder.plain(text, color: AssistantInk.set.prose)
    }

    func render(_ text: String) -> NSAttributedString {
        builder.render(text)
    }
}
