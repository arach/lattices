import AppKit
import HudsonUI
import SwiftUI

/// Blink's brand as a Hudson theme, so stock `HudSettings*` primitives take it
/// without forking them. Surfaces are the Lattices site's neutrals (`#fafaf9`
/// / `#111113` pages, white / `#1c1c1e` cards); ink is the family ink, and
/// coral — the family's one accent — marks only the live thing: the mark's
/// front note, the page you're on, focus.
enum BlinkBrand {
    struct Surfaces {
        let chrome: Color
        let page: Color
        let card: Color
        let ink: Color
        let inkSoft: Color
        let label: Color
        let rule: Color
        let ruleStrong: Color
    }

    /// The family coral, the same in both themes.
    static let coral = color(0xEF6A47)

    static func surfaces(dark: Bool) -> Surfaces {
        dark
            ? Surfaces(
                chrome: color(0x0B0B0D), page: color(0x111113), card: color(0x1C1C1E),
                ink: color(0xF2F2F2), inkSoft: color(0xA1A1AA), label: color(0x7A7A84),
                rule: color(0xF2F2F2, 0.08), ruleStrong: color(0xF2F2F2, 0.16)
            )
            : Surfaces(
                chrome: color(0xF1F1EF), page: color(0xFAFAF9), card: color(0xFFFFFF),
                ink: color(0x101518), inkSoft: color(0x4A5155), label: color(0x6E7478),
                rule: color(0x101518, 0.09), ruleStrong: color(0x101518, 0.18)
            )
    }

    static func hudTheme(dark: Bool) -> HudTheme {
        let s = surfaces(dark: dark)
        return HudTheme(
            palette: HudThemePalette(
                bg: s.page, surface: s.card, chrome: s.chrome,
                ink: s.ink, muted: s.inkSoft, dim: s.label,
                border: s.ruleStrong,
                accent: coral, accentSoft: coral.opacity(0.12),
                statusOk: s.ink, statusWarn: coral, statusError: coral, statusInfo: s.inkSoft
            ),
            hairline: HudThemeHairline(subtle: s.rule, standard: s.ruleStrong),
            radius: HudThemeRadius(tight: 6, standard: 8, card: 12),
            focus: HudThemeFocus(ring: coral, ringWidth: 2)
        )
    }

    /// Page entrance: rise 4pt, expo out.
    static let rise = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.28)

    private static func color(_ value: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(nsColor: Woven.hex(value, alpha: alpha))
    }
}

/// The Blink mark on the family grid: a panel frame with two notes stepping
/// across it; the front note, the one in hand, is coral. Mirrors the site's
/// `BlinkMark` (20-unit box, frame as thick as the grid's 1.2 gap).
struct BlinkMark: View {
    var ink: Color
    var accent: Color? = BlinkBrand.coral

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 20
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            var frame = Path(roundedRect: r(2, 2, 16, 16), cornerRadius: 4.1 * s, style: .circular)
            frame.addPath(Path(roundedRect: r(3.2, 3.2, 13.6, 13.6), cornerRadius: 2.9 * s, style: .circular))
            context.fill(frame, with: .color(ink), style: FillStyle(eoFill: true))
            context.fill(Path(r(6.3, 6.3, 3.7, 3.7)), with: .color(ink))
            context.fill(Path(r(10, 10, 3.7, 3.7)), with: .color(accent ?? ink))
        }
        .accessibilityHidden(true)
    }
}

/// 26pt, tight corners, a strong rule on the page; ink on hover.
struct BrandButtonStyle: ButtonStyle {
    var quiet = false

    func makeBody(configuration: Configuration) -> some View {
        BrandButton(configuration: configuration, quiet: quiet)
    }
}

private struct BrandButton: View {
    let configuration: ButtonStyleConfiguration
    let quiet: Bool

    @Environment(\.hudTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(quiet && !hovering ? theme.palette.muted : theme.palette.ink)
            .padding(.horizontal, quiet ? HudSpacing.sm : HudSpacing.lg)
            .frame(height: 26)
            .background {
                if !quiet {
                    RoundedRectangle(cornerRadius: theme.radius.tight, style: .continuous)
                        .fill(theme.palette.surface)
                    RoundedRectangle(cornerRadius: theme.radius.tight, style: .continuous)
                        .strokeBorder(hovering ? theme.palette.ink.opacity(0.5) : theme.hairline.standard, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A 34×20 switch: an ink track when on, a ruled well when off. The label is
/// left to the row; name the toggle with `accessibilityLabel`.
struct BrandToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        BrandToggle(configuration: configuration)
    }
}

private struct BrandToggle: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.hudTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private var on: Bool { configuration.isOn }

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule()
                    .fill(on ? theme.palette.ink : theme.palette.chrome)
                    .overlay(Capsule().strokeBorder(on ? .clear : theme.hairline.standard, lineWidth: 1))
                Circle()
                    .fill(on ? theme.palette.bg : theme.palette.surface)
                    .overlay(Circle().strokeBorder(on ? .clear : theme.hairline.standard, lineWidth: 1))
                    .shadow(color: .black.opacity(on ? 0 : 0.08), radius: 1, y: 0.5)
                    .padding(3)
            }
            .frame(width: 34, height: 20)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Woven.reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.18), value: on)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// `HudSettingsSection` with a 16pt row gutter and the label in the dim ink.
struct BrandSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.hudTheme) private var theme

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HudSettingsSection(title, labelTint: theme.palette.dim) {
            VStack(spacing: 0) { content() }
                .padding(.horizontal, HudSpacing.md)
        }
    }
}

/// Segments in a ruled well; the chosen one is an ink pill, like the switch's
/// track, so selection never borrows the system blue.
struct BrandSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(label: String, value: Value)]

    @Environment(\.hudTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let chosen = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(chosen ? theme.palette.bg : theme.palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background {
                            RoundedRectangle(cornerRadius: theme.radius.tight - 2, style: .continuous)
                                .fill(chosen ? theme.palette.ink : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: theme.radius.tight, style: .continuous)
                .fill(theme.palette.chrome)
            RoundedRectangle(cornerRadius: theme.radius.tight, style: .continuous)
                .strokeBorder(theme.hairline.standard, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(Woven.reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.18), value: selection)
        .accessibilityElement(children: .contain)
    }
}
