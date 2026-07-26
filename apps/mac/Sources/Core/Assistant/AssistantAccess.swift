import Foundation

/// Opens the Workspace Assistant tab in the main Lattices window.
enum AssistantAccess {
    static func show() {
        MenuBarController.shared.dismissPopover()
        ScreenMapWindowController.shared.showAssistant()
    }
}
