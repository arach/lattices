import AppKit
import Foundation

enum ActionAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "Action.AppearanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }

    static func load() -> ActionAppearanceMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let mode = ActionAppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.storageKey)
    }
}
