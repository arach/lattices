import AppKit
import SwiftUI

/// One colour, stated once for each appearance.
///
/// Every colour in Action's palette was already a light/dark pair — the old
/// `StageHUDTheme` opened with a `dynamic(light:dark:)` helper and then called
/// it ninety times. Making the pair the *type* rather than a helper is what
/// lets a theme be data: a duo round-trips through JSON, can be lightened or
/// mixed as a unit, and can be checked for contrast in both appearances at once.
///
/// A colour that is meant to stay put across appearances — the capture HUD's
/// coral, which reports that this Mac is being driven right now — is written as
/// a duo with two identical sides rather than as a special case.
struct ActionThemeColor: Equatable, Sendable {
    var light: ActionRGBA
    var dark: ActionRGBA

    init(light: ActionRGBA, dark: ActionRGBA) {
        self.light = light
        self.dark = dark
    }

    /// The same value in both appearances.
    init(_ both: ActionRGBA) {
        self.init(light: both, dark: both)
    }

    func resolved(for appearance: ActionAppearanceSide) -> ActionRGBA {
        appearance == .dark ? dark : light
    }

    /// A SwiftUI colour that follows the effective appearance of whatever view
    /// resolves it, including a window that has been pinned to one appearance.
    var color: Color {
        Color(nsColor: nsColor)
    }

    var nsColor: NSColor {
        let light = light
        let dark = dark
        return NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
            case .darkAqua: return dark.nsColor
            default: return light.nsColor
            }
        }
    }

    // MARK: Composition

    func mapped(_ transform: (ActionRGBA) -> ActionRGBA) -> ActionThemeColor {
        ActionThemeColor(light: transform(light), dark: transform(dark))
    }

    /// Per-appearance transform. Most derivations differ between the two sides —
    /// "one step lighter than the page" is a different move on paper than it is
    /// on graphite — so this is the common case, not the exception.
    func mapped(
        light lightTransform: (ActionRGBA) -> ActionRGBA,
        dark darkTransform: (ActionRGBA) -> ActionRGBA
    ) -> ActionThemeColor {
        ActionThemeColor(light: lightTransform(light), dark: darkTransform(dark))
    }

    func withAlpha(_ alpha: Double) -> ActionThemeColor {
        mapped { $0.withAlpha(alpha) }
    }

    func mixed(with other: ActionThemeColor, _ amount: Double) -> ActionThemeColor {
        ActionThemeColor(
            light: light.mixed(with: other.light, amount),
            dark: dark.mixed(with: other.dark, amount)
        )
    }
}

enum ActionAppearanceSide: String, Sendable, CaseIterable {
    case light
    case dark
}

// MARK: - RGBA

/// A colour value in extended-sRGB components, kept as `Double` rather than as
/// a hex string so the built-in themes can carry the exact decimals the app
/// shipped with. Hex is the *encoding* for themes on disk, not the storage.
struct ActionRGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(white: Double, alpha: Double = 1) {
        self.init(white, white, white, alpha)
    }

    /// `0xRRGGBB`, optionally with a separate alpha.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255.0,
            Double((hex >> 8) & 0xFF) / 255.0,
            Double(hex & 0xFF) / 255.0,
            alpha
        )
    }

    /// `#RGB`, `#RRGGBB`, or `#RRGGBBAA`. Returns nil rather than a fallback
    /// colour: a theme file with a typo in it should be reported, not quietly
    /// rendered in some other colour.
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy(\.isHexDigit),
              let value = UInt32(text, radix: 16) else { return nil }
        if text.count == 6 {
            self.init(hex: value)
        } else {
            self.init(
                Double((value >> 24) & 0xFF) / 255.0,
                Double((value >> 16) & 0xFF) / 255.0,
                Double((value >> 8) & 0xFF) / 255.0,
                Double(value & 0xFF) / 255.0
            )
        }
    }

    var hexString: String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        guard alpha < 1 else { return base }
        return base + String(format: "%02X", byte(alpha))
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: Math

    func withAlpha(_ newAlpha: Double) -> ActionRGBA {
        ActionRGBA(red, green, blue, min(max(newAlpha, 0), 1))
    }

    func mixed(with other: ActionRGBA, _ amount: Double) -> ActionRGBA {
        let t = min(max(amount, 0), 1)
        return ActionRGBA(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t,
            alpha + (other.alpha - alpha) * t
        )
    }

    /// Toward white. Used for the "one step up from the page" moves — a raised
    /// panel, a hover fill — in both appearances, because a raised surface is
    /// lighter than its ground on paper *and* on graphite.
    func lightened(_ amount: Double) -> ActionRGBA {
        mixed(with: ActionRGBA(white: 1, alpha: alpha), amount)
    }

    /// Toward black. The recessed direction.
    func darkened(_ amount: Double) -> ActionRGBA {
        mixed(with: ActionRGBA(0, 0, 0, alpha), amount)
    }

    /// WCAG relative luminance, used by the contrast checks a generated theme
    /// has to pass before it is allowed to paint anything.
    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            let v = min(max(value, 0), 1)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// CIE L*, 0…100.
    ///
    /// The separation checks use this rather than relative luminance because
    /// luminance is linear-light: two near-blacks that are plainly a step apart
    /// on screen — Home's page and its panels, at #14191A and #1C2223 — differ
    /// by three thousandths of a luminance, and a threshold that catches a real
    /// collapse in light mode would condemn every dark surface in the app.
    var perceptualLightness: Double {
        let y = relativeLuminance
        let f = y > 0.008856 ? pow(y, 1.0 / 3.0) : (7.787 * y) + (16.0 / 116.0)
        return (116 * f) - 16
    }

    /// The same colour, moved a fixed number of L\* steps lighter or darker.
    ///
    /// This is the move every derived ground is built from, and it has to be in
    /// L\* rather than in "mix 4.5% toward white". Action's own light page and
    /// its panels are #F3EBDD and #FAF5EB — a 58% step toward white on the red
    /// channel — while its dark page and panels are #14191A and #1C2223, a 3%
    /// step. As a *mix* those two have nothing in common. As lightness they are
    /// the same move: three points of L\*. A constant-mix derivation reproduces
    /// one of them and flattens the other, which is exactly what a seeded theme
    /// must not do.
    ///
    /// Solved by bisection on the mix amount because there is no closed form
    /// that both hits a target L\* and keeps the hue: twenty iterations lands
    /// well inside a 24-bit channel step.
    func lightnessAdjusted(by delta: Double) -> ActionRGBA {
        guard delta != 0 else { return self }
        let target = min(max(perceptualLightness + delta, 0), 100)
        let anchor = delta > 0 ? ActionRGBA(white: 1, alpha: alpha) : ActionRGBA(0, 0, 0, alpha)
        guard (delta > 0) == (anchor.perceptualLightness > perceptualLightness) else { return self }

        // Lightness is monotonic in the mix amount, but it *rises* toward white
        // and *falls* toward black, so the half to keep flips with the sign of
        // the step.
        var low = 0.0
        var high = 1.0
        var result = self
        for _ in 0..<20 {
            let mid = (low + high) / 2
            result = mixed(with: anchor, mid)
            let overshot = delta > 0
                ? result.perceptualLightness >= target
                : result.perceptualLightness <= target
            if overshot {
                high = mid
            } else {
                low = mid
            }
        }
        return result
    }

    /// CIELAB coordinates, for the one question contrast cannot answer: are
    /// these two colours *the same colour*?
    ///
    /// Two hues at the same lightness score a contrast ratio near 1:1 against
    /// each other and pass every legibility check ever written, because
    /// legibility is about light and dark. Telling an accent apart from an alarm
    /// is about hue, and needs a perceptual space to ask in.
    var lab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), bl = linear(blue)
        let x = (r * 0.4124 + g * 0.3576 + bl * 0.1805) / 0.95047
        let y = r * 0.2126 + g * 0.7152 + bl * 0.0722
        let z = (r * 0.0193 + g * 0.1192 + bl * 0.9505) / 1.08883
        func f(_ t: Double) -> Double {
            t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t) + (16.0 / 116.0)
        }
        let fx = f(x), fy = f(y), fz = f(z)
        return ((116 * fy) - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// CIE76 colour difference. Rough by modern standards and entirely good
    /// enough for "could a person mistake one of these for the other".
    func difference(from other: ActionRGBA) -> Double {
        let a = lab, b = other.lab
        return ((a.l - b.l) * (a.l - b.l) + (a.a - b.a) * (a.a - b.a) + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    /// WCAG contrast ratio, 1…21.
    ///
    /// Alpha is composited onto `background` first. A muted ink written as
    /// "ink at 55%" is only legible because of what is behind it, and checking
    /// it without compositing would score a colour nobody ever sees.
    func contrastRatio(against background: ActionRGBA) -> Double {
        let foreground = alpha < 1 ? background.mixed(with: withAlpha(1), alpha) : self
        let a = foreground.relativeLuminance
        let b = background.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Codable

extension ActionRGBA: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = ActionRGBA(hexString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(text)\" is not a hex colour (#RGB, #RRGGBB or #RRGGBBAA)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

extension ActionThemeColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case light
        case dark
    }

    /// Two spellings, because a theme author reaches for both: `"#EF6A47"` when
    /// the colour is the same in either appearance, and `{"light":…,"dark":…}`
    /// when it is not. Anything else is an error rather than a default.
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(ActionRGBA.self) {
            self.init(value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            light: try container.decode(ActionRGBA.self, forKey: .light),
            dark: try container.decode(ActionRGBA.self, forKey: .dark)
        )
    }

    func encode(to encoder: Encoder) throws {
        if light == dark {
            var container = encoder.singleValueContainer()
            try container.encode(light)
            return
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(light, forKey: .light)
        try container.encode(dark, forKey: .dark)
    }
}
