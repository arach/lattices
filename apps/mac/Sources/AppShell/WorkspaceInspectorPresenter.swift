import AppKit

enum WorkspaceInspectorPresenter {
    static func show() {
        guard let entry = DesktopModel.shared.frontmostWindow(),
              entry.app != "Lattices" else {
            ScreenMapWindowController.shared.showPage(.screenMap)
            return
        }

        ScreenMapWindowController.shared.showWindow(wid: entry.wid)
    }
}
