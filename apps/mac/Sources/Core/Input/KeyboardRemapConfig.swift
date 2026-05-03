import CoreGraphics
import Foundation

enum KeyboardRemapKey: String, Codable, Equatable {
    case capsLock = "caps_lock"

    var keyCode: Int64 {
        switch self {
        case .capsLock: return 57
        }
    }

    var displayLabel: String {
        switch self {
        case .capsLock: return "Caps Lock"
        }
    }
}

enum KeyboardRemapAction: String, Codable, Equatable {
    case escape
    case hyper

    var displayLabel: String {
        switch self {
        case .escape: return "Escape"
        case .hyper: return "Hyper"
        }
    }
}

struct KeyboardRemapRule: Codable, Equatable, Identifiable {
    var id: String
    var enabled: Bool
    var from: KeyboardRemapKey
    var toIfHeld: KeyboardRemapAction
    var toIfAlone: KeyboardRemapAction?

    var summaryLine: String {
        let held = "hold \(from.displayLabel) -> \(toIfHeld.displayLabel)"
        guard let alone = toIfAlone else { return held }
        return "\(held), tap -> \(alone.displayLabel)"
    }
}

struct KeyboardRemapConfig: Codable, Equatable {
    var rules: [KeyboardRemapRule]

    static let defaults = KeyboardRemapConfig(
        rules: [
            KeyboardRemapRule(
                id: "caps_lock_hyper_escape",
                enabled: true,
                from: .capsLock,
                toIfHeld: .hyper,
                toIfAlone: .escape
            )
        ]
    )
}

extension CGEventFlags {
    static let latticesHyper: CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift,
    ]
}
