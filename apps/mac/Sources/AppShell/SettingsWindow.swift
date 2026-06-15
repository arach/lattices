import AppKit

/// Thin redirect — Settings is now a page inside the unified app window.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var isVisible: Bool { ScreenMapWindowController.shared.isVisible }

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        ScreenMapWindowController.shared.showPage(.settings)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .latticesShowGeneralSettings, object: nil)
        }
    }

    func showCompanion() {
        ScreenMapWindowController.shared.showPage(.companionSettings)
    }

    /// Open Settings and jump to a specific sidebar section by its raw value
    /// (general, shortcuts, mouse, ai, voice, search, companion).
    func show(section rawValue: String) {
        ScreenMapWindowController.shared.showPage(.settings)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .latticesShowSettingsSection,
                object: nil,
                userInfo: ["section": rawValue]
            )
        }
    }

    func showAssistant() {
        ScreenMapWindowController.shared.showPage(.settings)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .latticesShowAssistantSettings, object: nil)
        }
    }

    func close() {
        ScreenMapWindowController.shared.close()
    }
}
