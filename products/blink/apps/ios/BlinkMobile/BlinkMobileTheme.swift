import HudsonUI
import SwiftUI
import UIKit

enum BlinkAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "blink.mobile.appearance"
    static let `default`: BlinkAppearance = .system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static var stored: BlinkAppearance {
        BlinkAppearance(
            rawValue: UserDefaults.standard.string(forKey: storageKey) ?? ""
        ) ?? .default
    }
}

enum BlinkThemeChoice: String, CaseIterable, Identifiable {
    case indexTape
    case field
    case deck
    case scope
    case focus
    case console

    static let storageKey = "blink.mobile.theme"
    static let `default`: BlinkThemeChoice = .indexTape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indexTape: "Index Tape"
        case .field: "Field"
        case .deck: "Deck"
        case .scope: "Scope"
        case .focus: "Focus"
        case .console: "Console"
        }
    }

    var detail: String {
        switch self {
        case .indexTape: "Paper · cobalt"
        case .field: "Warm paper · emerald"
        case .deck: "Graphite · amber"
        case .scope: "Cream · brass"
        case .focus: "Umber · signal yellow"
        case .console: "Neutral · blue"
        }
    }

    static var stored: BlinkThemeChoice {
        BlinkThemeChoice(
            rawValue: UserDefaults.standard.string(forKey: storageKey) ?? ""
        ) ?? .default
    }

    fileprivate var palette: BlinkThemePalette {
        switch self {
        case .indexTape:
            BlinkThemePalette(
                signal: .init(light: 0x2D5DAF, dark: 0x83B4FF),
                canvas: .init(light: 0xF2F0EC, dark: 0x0A0B0C),
                surface: .init(light: 0xFCFAF6, dark: 0x121416),
                raisedSurface: .init(light: 0xFFFFFF, dark: 0x17191C),
                rail: .init(light: 0xEBE7DF, dark: 0x0E1012),
                hairline: .init(light: 0xDAD5CB, dark: 0x2A2E31),
                ink: .init(light: 0x17130F, dark: 0xFBEEE8),
                secondaryInk: .init(light: 0x5C554F, dark: 0xB8BEC0),
                faintInk: .init(light: 0x6F695F, dark: 0x9AA0A2),
                amber: .init(light: 0x7E6029, dark: 0xD6B96C)
            )
        case .field:
            BlinkThemePalette(
                signal: .init(light: 0x07785B, dark: 0x10B981),
                canvas: .init(light: 0xF6F3ED, dark: 0x0A0A0A),
                surface: .init(light: 0xFFFDF9, dark: 0x171717),
                raisedSurface: .init(light: 0xFFFFFC, dark: 0x211C18),
                rail: .init(light: 0xF2EEE6, dark: 0x111113),
                hairline: .init(light: 0xCDC5B8, dark: 0x262626),
                ink: .init(light: 0x23211D, dark: 0xE5E5E5),
                secondaryInk: .init(light: 0x58534B, dark: 0xB8B8B8),
                faintInk: .init(light: 0x69635A, dark: 0x969696),
                amber: .init(light: 0xA15B00, dark: 0xF59E0B)
            )
        case .deck:
            BlinkThemePalette(
                signal: .init(light: 0x9A690E, dark: 0xE4B65C),
                canvas: .init(light: 0xF4F1E8, dark: 0x0D0F12),
                surface: .init(light: 0xFFFCF5, dark: 0x131518),
                raisedSurface: .init(light: 0xFFFFFF, dark: 0x181B1F),
                rail: .init(light: 0xEAE4D6, dark: 0x0A0B0D),
                hairline: .init(light: 0xD8CFBD, dark: 0x303237),
                ink: .init(light: 0x211F1A, dark: 0xE2E2DF),
                secondaryInk: .init(light: 0x605B50, dark: 0xA0A09B),
                faintInk: .init(light: 0x756E61, dark: 0x85857F),
                amber: .init(light: 0x9A690E, dark: 0xE4B65C)
            )
        case .scope:
            BlinkThemePalette(
                signal: .init(light: 0x9A6828, dark: 0xE89A3C),
                canvas: .init(light: 0xFBFAF7, dark: 0x0A0907),
                surface: .init(light: 0xF8F6F1, dark: 0x13110E),
                raisedSurface: .init(light: 0xFFFFFD, dark: 0x1A1714),
                rail: .init(light: 0xF2F0EA, dark: 0x151310),
                hairline: .init(light: 0xE4DFD6, dark: 0x322D27),
                ink: .init(light: 0x1A1612, dark: 0xF5F3EE),
                secondaryInk: .init(light: 0x5A5045, dark: 0xA8A096),
                faintInk: .init(light: 0x766A5A, dark: 0x968876),
                amber: .init(light: 0x7E6029, dark: 0xD6B96C)
            )
        case .focus:
            BlinkThemePalette(
                signal: .init(light: 0x706B00, dark: 0xEAE434),
                canvas: .init(light: 0xFAF7F1, dark: 0x17120F),
                surface: .init(light: 0xFFFCF7, dark: 0x251D17),
                raisedSurface: .init(light: 0xFFFFFF, dark: 0x30261E),
                rail: .init(light: 0xF0E8DD, dark: 0x201913),
                hairline: .init(light: 0xD9CCBD, dark: 0x42382F),
                ink: .init(light: 0x2A2019, dark: 0xF4EEE6),
                secondaryInk: .init(light: 0x6B5C4E, dark: 0xBCAE9E),
                faintInk: .init(light: 0x766A5E, dark: 0x96897D),
                amber: .init(light: 0xA65513, dark: 0xF2A65A)
            )
        case .console:
            BlinkThemePalette(
                signal: .init(light: 0x235DAD, dark: 0x3B82F6),
                canvas: .init(light: 0xFAFAFA, dark: 0x0A0A0A),
                surface: .init(light: 0xF5F5F5, dark: 0x171717),
                raisedSurface: .init(light: 0xFFFFFF, dark: 0x1D1D1D),
                rail: .init(light: 0xEFEFEF, dark: 0x060606),
                hairline: .init(light: 0xDBDBDB, dark: 0x272727),
                ink: .init(light: 0x171717, dark: 0xE5E5E5),
                secondaryInk: .init(light: 0x525252, dark: 0xA3A3A3),
                faintInk: .init(light: 0x737373, dark: 0x8F8F8F),
                amber: .init(light: 0xA15B00, dark: 0xF59E0B)
            )
        }
    }
}

private struct AdaptiveHex {
    let light: UInt32
    let dark: UInt32

    var color: Color {
        Color(uiColor: UIColor { traits in
            UIColor(blinkRGB: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private struct BlinkThemePalette {
    let signal: AdaptiveHex
    let canvas: AdaptiveHex
    let surface: AdaptiveHex
    let raisedSurface: AdaptiveHex
    let rail: AdaptiveHex
    let hairline: AdaptiveHex
    let ink: AdaptiveHex
    let secondaryInk: AdaptiveHex
    let faintInk: AdaptiveHex
    let amber: AdaptiveHex
}

enum BlinkMobileTheme {
    private static var palette: BlinkThemePalette { BlinkThemeChoice.stored.palette }

    static var signal: Color { palette.signal.color }
    static var canvas: Color { palette.canvas.color }
    static var surface: Color { palette.surface.color }
    static var raisedSurface: Color { palette.raisedSurface.color }
    static var rail: Color { palette.rail.color }
    static var hairline: Color { palette.hairline.color }
    static var ink: Color { palette.ink.color }
    static var secondaryInk: Color { palette.secondaryInk.color }
    static var faintInk: Color { palette.faintInk.color }
    static var amber: Color { palette.amber.color }

    static var hudTheme: HudTheme {
        HudTheme(
            palette: HudThemePalette(
                bg: canvas,
                surface: surface,
                chrome: rail,
                ink: ink,
                muted: secondaryInk,
                dim: faintInk,
                border: hairline,
                accent: signal,
                accentSoft: signal.opacity(0.10),
                statusOk: signal,
                statusWarn: amber,
                statusError: Color(red: 0.78, green: 0.20, blue: 0.18),
                statusInfo: signal
            ),
            hairline: HudThemeHairline(subtle: hairline, standard: hairline),
            radius: .default,
            focus: HudThemeFocus(ring: signal.opacity(0.85), ringWidth: 1.5)
        )
    }
}

extension BlinkThemeChoice {
    var previewColors: [Color] {
        [palette.canvas.color, palette.surface.color, palette.signal.color]
    }
}

private extension UIColor {
    convenience init(blinkRGB: UInt32) {
        self.init(
            red: CGFloat((blinkRGB >> 16) & 0xFF) / 255,
            green: CGFloat((blinkRGB >> 8) & 0xFF) / 255,
            blue: CGFloat(blinkRGB & 0xFF) / 255,
            alpha: 1
        )
    }
}
