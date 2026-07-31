import SwiftUI

// MARK: - Tokens
//
// Ported from the design source `Lats Fleet Deck v6.html` and its linked
// `system.css` (claude.ai/design project e010d8da-5dd8-4f3f-bb3e-a24dd4c75532).
//
// The artifact is authored on a fixed 1376×1032 iPad-landscape canvas, so its
// CSS pixel values map 1:1 to SwiftUI points — every number below is the
// design's own. `oklch()` accents were converted to sRGB.

enum FleetV6 {

    // MARK: Text — now DeckTheme's ramp (the values were already identical)

    static let fg      = DeckTheme.text
    static let fg2     = DeckTheme.textSecondary
    static let fg3     = DeckTheme.textTertiary
    static let fg4     = DeckTheme.textDisabled

    // MARK: Accents
    //
    // Sixteen hues collapse to two. Green in particular is deliberate: running
    // is the default healthy state, and colouring it made the deck read as a
    // board where everything is lit and therefore nothing is. Anything that
    // used to be green/violet/blue now resolves to a text grey, so the only
    // saturation left on screen is something asking for you.

    static let green   = DeckTheme.textSecondary
    static let violet  = DeckTheme.textSecondary
    static let blue    = DeckTheme.textSecondary
    static let amber   = DeckTheme.accent
    static let red     = DeckTheme.error
    static let tileIcon = DeckTheme.textSecondary

    /// Identity no longer uses colour — a dot meant "which agent" in one place
    /// and "what state" thirty lines later, which is the actual incoherence.
    /// Identity is now icon + name + stable column position.
    static func agentHue(_ index: Int) -> Color { DeckTheme.textSecondary }

    // MARK: Hairlines

    static let brk     = DeckTheme.hairline
    static let brk2    = DeckTheme.hairline
    static let dotted  = DeckTheme.hairline
    static let seam    = Color.clear          // hard black seams: deleted

    // MARK: Surfaces
    //
    // Every gradient is now a flat fill. The machined enclosure — bezels,
    // keycaps, domes, black seams, top-gloss — was the technical vibe made
    // literal, and none of it survives at the sizes it was drawn: nobody's eye
    // resolves a three-stop keycap gradient on a 46pt key.

    static let wellBG  = DeckTheme.well
    static let cardBG  = DeckTheme.card
    static let cardBR  = DeckTheme.hairline
    static let heroBG  = DeckTheme.raised
    static let heroBR  = DeckTheme.hairlineStrong

    static let padBG       = DeckTheme.canvas
    static let deckPanelBG = DeckTheme.canvas
    static let bezel       = DeckTheme.raised
    static let keycap      = DeckTheme.control
    static let keycapHover = DeckTheme.raised
    static let tileFace    = DeckTheme.card
    static let dome        = DeckTheme.control
    static let tilesWrapBG = DeckTheme.well
    static let statusBG    = DeckTheme.canvas

    // MARK: Type
    //
    // The deck was authored entirely in tracked monospace. It now speaks in the
    // system face, because this app operates agents and dictation — not
    // terminals — and a remote control should look like the OS it lives on
    // rather than the thing it points at.
    //
    // `mono(_:_:)` keeps its name so 13 files of call sites stay put, but it is
    // SF Pro now. The serif survives, and only for utterances: an agent's
    // question, a transcript. It marks *someone is talking to you*.

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // MARK: Metrics — the design's own px values, as points

    enum M {
        static let padH: CGFloat = 16
        static let padTop: CGFloat = 12
        static let padBottom: CGFloat = 9
        static let stackGap: CGFloat = 9

        static let topBarHeight: CGFloat = 26
        static let channelsHeight: CGFloat = 158
        static let channelsRailHeight: CGFloat = 52     // .layout-focus
        static let voiceBarHeight: CGFloat = 58
        static let statusHeight: CGFloat = 26

        static let wellRadius: CGFloat = 10
        static let panelRadius: CGFloat = 12
        static let cardRadius: CGFloat = 5

        static let panelBodyPadH: CGFloat = 15
        static let panelBodyPadV: CGFloat = 12
        static let bodyGap: CGFloat = 14
        static let consoleWidth: CGFloat = 390          // #bodyOps  390px 1fr
        static let focusConsoleWidth: CGFloat = 340     // #bodyFocus 1fr 340px

        static let tilesHeight: CGFloat = 128
        static let tileGap: CGFloat = 8
        static let trackpadHeight: CGFloat = 84
        static let keyRowHeight: CGFloat = 46
    }

    // MARK: Helper

    static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Surfaces

/// `--well-bg` + `--well-sh` + `--well-lip`: a recessed well. The browser draws
/// this with an inset box-shadow; natively it is a dark fill, a hairline inner
/// stroke, and a lit bottom lip that reads as the far wall of the recess.
struct FleetWell<Content: View>: View {
    var radius: CGFloat = FleetV6.M.wellRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(FleetV6.wellBG)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 14)
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.035))
                            .frame(height: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
    }
}

/// `.mcard` — the flat card. `hero` promotes it to `.mcard.console` (raised,
/// gradient face, top gloss); `recent` draws the eight corner ticks the design
/// uses to mark the card that just changed.
struct FleetCard<Content: View>: View {
    var hero: Bool = false
    var recent: Bool = false
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder var content: () -> Content

    private let radius = FleetV6.M.cardRadius

    var body: some View {
        content()
            .padding(padding)
            .background {
                ZStack {
                    if hero {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(FleetV6.heroBG)
                            .shadow(color: .black.opacity(0.9), radius: 22, y: 20)
                        // ::before — a 46%-tall gloss down from the top edge
                        LinearGradient(
                            colors: [Color.white.opacity(0.035), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(FleetV6.cardBG)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        recent ? Color.white.opacity(0.18) : (hero ? FleetV6.heroBR : FleetV6.cardBR),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay { if recent { FleetCornerTicks() } }
    }
}

/// `.mcard.recent::after` — 12×1.5pt ticks at each corner.
private struct FleetCornerTicks: View {
    private let length: CGFloat = 12
    private let weight: CGFloat = 1.5

    private let corners: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]

    var body: some View {
        ZStack {
            ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
                Color.clear.overlay(alignment: corner) {
                    ZStack(alignment: corner) {
                        Rectangle().fill(.white).frame(width: length, height: weight)
                        Rectangle().fill(.white).frame(width: weight, height: length)
                    }
                }
            }
        }
        .opacity(0.7)
        .padding(-2)
        .allowsHitTesting(false)
    }
}

/// `.key` / `.abtn` / `.ask-opt` — one keycap face, reused everywhere the
/// design presses a physical-feeling control into the enclosure.
struct FleetKeycapBackground: View {
    var radius: CGFloat = 7
    var pressed: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(pressed ? FleetV6.keycapHover : FleetV6.keycap)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .shadow(color: .black.opacity(0.6), radius: 2, y: 2)
    }
}

/// The 30pt engineering grid printed on `.deck-panel`.
/// Retired alongside `LatsGridBackground` — see the note there. Kept as an empty
/// view so its call sites can stay put.
struct FleetPanelGrid: View {
    var spacing: CGFloat = 30
    var line: Color = .clear

    var body: some View {
        EmptyView()
    }
}

// MARK: - Small primitives

/// `.lbl` — the 10pt tracked micro-cap that labels a region.
struct FleetLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = FleetV6.fg3

    var body: some View {
        Text(text.uppercased())
            .font(FleetV6.mono(size, .medium))
            .tracking(size * 0.18)
            .foregroundStyle(color)
    }
}

/// The status dot used in channel heads, the panel head, and the feed.
struct FleetDot: View {
    var color: Color = FleetV6.fg3
    var size: CGFloat = 6
    var glow: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.8) : .clear, radius: glow ? 5 : 0)
    }
}

/// A dotted rule. The design uses `1px dotted` under every card head; SwiftUI
/// needs the dash pattern spelled out.
struct FleetDottedRule: View {
    var color: Color = FleetV6.dotted

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                }
            }
    }
}
