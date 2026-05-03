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
