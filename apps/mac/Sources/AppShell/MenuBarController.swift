import AppKit
import SwiftUI

final class MenuBarController: NSObject, NSPopoverDelegate {
    static let shared = MenuBarController()

    /// Collapsed quick-actions layout (Move row closed).
    static let popoverHeightCollapsed: CGFloat = 360
    /// Move grid unfolded — room for 3×3 slots + thirds row.
    static let popoverHeightExpanded: CGFloat = 540
    static let popoverWidth: CGFloat = 380

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?

    var isPopoverShown: Bool {
        popover?.isShown == true
    }

    private override init() {
        super.init()
    }

    func start() {
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = Self.menuBarIcon
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        contextMenu = buildContextMenu()
    }

    func warmUpPopover() {
        let popover = makePopover()
        _ = popover.contentViewController?.view
    }

    func dismissPopover() {
        popover?.performClose(nil)
    }

    /// Resize the menu-bar popover when inline sections expand (e.g. Move grid).
    func setPopoverContentHeight(_ height: CGFloat) {
        guard let popover else { return }
        let size = NSSize(width: Self.popoverWidth, height: height)
        guard popover.contentSize != size else { return }
        popover.contentSize = size
    }

    private func showProjectsPopover() {
        guard let button = statusItem?.button else { return }
        let popover = makePopover()
        // Always open collapsed; Move expands on demand.
        popover.contentSize = NSSize(
            width: Self.popoverWidth,
            height: Self.popoverHeightCollapsed
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.sharingType = .readOnly
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent,
              let button = statusItem?.button else { return }

        if event.type == .rightMouseUp {
            contextMenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else if let shown = popover, shown.isShown {
            shown.performClose(sender)
        } else {
            showProjectsPopover()
        }
    }

    private func makePopover() -> NSPopover {
        if let popover { return popover }
        let timed = DiagnosticLog.shared.startTimed("makePopover")
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: MainView(scanner: ProjectScanner.shared))
        popover.behavior = .transient
        // Keep resize of contentSize (Move expand/collapse) non-animated —
        // animating NSPopover + SwiftUI layout has crashed with nested material
        // resolve (EXC_BAD_ACCESS / stack guard) on recent macOS builds.
        popover.animates = false
        popover.contentSize = NSSize(
            width: Self.popoverWidth,
            height: Self.popoverHeightCollapsed
        )
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        self.popover = popover
        DiagnosticLog.shared.finish(timed)
        return popover
    }

    func popoverWillShow(_ notification: Notification) {
        AppActivationCoordinator.shared.refresh()
        NotificationCenter.default.post(name: .latticesPopoverWillShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        AppActivationCoordinator.shared.refresh()
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let actions: [(String, String, Selector)] = [
            ("Assistant", "⌘⇧A", #selector(menuAssistant)),
            ("Home", "", #selector(menuWorkspace)),
            ("Studio", "", #selector(menuLayout)),
            ("Command Bar", "", #selector(menuSearch)),
        ]
        for (title, shortcut, action) in actions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if !shortcut.isEmpty {
                // Display-only; the actual hotkey is global.
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        FrontWindowPlacementMenu.attach(to: menu)

        menu.addItem(.separator())

        let cliActions: [(String, Selector)] = [
            ("Projects…", #selector(menuProjects)),
            ("Initialize Project in Terminal…", #selector(menuInitializeProject)),
            ("Launch Project in Terminal…", #selector(menuLaunchProject)),
        ]
        for (title, action) in cliActions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let runs = NSMenuItem(title: "Runs…", action: #selector(menuRuns), keyEquivalent: "")
        runs.target = self
        menu.addItem(runs)

        let activityLog = NSMenuItem(title: "Activity Log…", action: #selector(menuActivityLog), keyEquivalent: "")
        activityLog.target = self
        menu.addItem(activityLog)

        let update = NSMenuItem(title: "Update Lattices…", action: #selector(menuUpdate), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Help & Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Lattices", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func menuAssistant() { AssistantAccess.show() }
    @objc private func menuWorkspace() { ScreenMapWindowController.shared.showPage(.home) }
    @objc private func menuLayout() { ScreenMapWindowController.shared.showPage(.screenMap) }
    @objc private func menuSearch() { UnifiedCommandBarWindow.shared.toggle(mode: .search) }
    @objc private func menuProjects() { DispatchQueue.main.async { self.showProjectsPopover() } }
    @objc private func menuInitializeProject() { CliActionLauncher.initializeProjectInTerminal() }
    @objc private func menuLaunchProject() { CliActionLauncher.launchProjectInTerminal() }
    @objc private func menuRuns() { ScreenMapWindowController.shared.showPage(.runs) }
    @objc private func menuActivityLog() { ScreenMapWindowController.shared.showPage(.activity) }
    @MainActor @objc private func menuUpdate() { AppUpdater.shared.promptForUpdate() }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private static let menuBarIcon: NSImage = {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let pad: CGFloat = 2
            let gap: CGFloat = 1.5
            let cellSize = (size - 2 * pad - 2 * gap) / 3
            let solidCells: Set<Int> = [0, 3, 6, 7, 8]

            for row in 0..<3 {
                for column in 0..<3 {
                    let index = row * 3 + column
                    let x = pad + CGFloat(column) * (cellSize + gap)
                    let y = pad + CGFloat(row) * (cellSize + gap)
                    let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

                    if solidCells.contains(index) {
                        NSColor.black.setFill()
                    } else {
                        NSColor.black.withAlphaComponent(0.25).setFill()
                    }
                    let path = NSBezierPath(roundedRect: rect, xRadius: 0.8, yRadius: 0.8)
                    path.fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
