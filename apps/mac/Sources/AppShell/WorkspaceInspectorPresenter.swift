import AppKit

enum WorkspaceInspectorPresenter {
    static func show() {
        guard let entry = DesktopModel.shared.frontmostWindow(),
              entry.app != "Lattices" else {
            ScreenMapWindowController.shared.showPage(.overview)
            return
        }

        ScreenMapWindowController.shared.showWindow(wid: entry.wid)
    }
}
