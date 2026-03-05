import AppKit
import SwiftUI

/// Manages the NSStatusItem (menu bar icon), left-click popover, and right-click context menu.
/// Replaces the previous SwiftUI MenuBarExtra approach for full click-event control.
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var contextMenu: NSMenu!

    /// 3×3 grid icon for the menu bar — L-shape bright, rest dim (template for auto light/dark)
    private static let menuBarIcon: NSImage = {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let pad: CGFloat = 2
            let gap: CGFloat = 1.5
            let cellSize = (size - 2 * pad - 2 * gap) / 3

            let solidCells: Set<Int> = [0, 3, 6, 7, 8]

            for row in 0..<3 {
                for col in 0..<3 {
                    let idx = row * 3 + col
                    let x = pad + CGFloat(col) * (cellSize + gap)
                    let y = pad + CGFloat(row) * (cellSize + gap)
                    let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

                    if solidCells.contains(idx) {
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
        img.isTemplate = true
        return img
    }()

    /// Toggle between .accessory (hidden from Dock/Cmd+Tab) and .regular (visible)
    /// based on whether any managed windows are open.
    static func updateActivationPolicy() {
        let hasVisibleWindow =
            CommandModeWindow.shared.isVisible ||
            CommandPaletteWindow.shared.isVisible ||
            MainWindow.shared.isVisible ||
            ScreenMapWindowController.shared.isVisible ||
            OmniSearchWindow.shared.isVisible
        let desired: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            if desired == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // --- Status item ---
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // --- Context menu (right-click) ---
        contextMenu = buildContextMenu()

        // --- Hotkey registration ---
        let scanner = ProjectScanner.shared
        CommandPaletteWindow.shared.configure(scanner: scanner)

        let store = HotkeyStore.shared
        store.register(action: .palette) { CommandPaletteWindow.shared.toggle() }
        store.register(action: .screenMap) { ScreenMapWindowController.shared.toggle() }
        store.register(action: .bezel) { WindowBezel.showBezelForFrontmostWindow() }
        store.register(action: .cheatSheet) { CheatSheetHUD.shared.toggle() }
        store.register(action: .desktopInventory) { CommandModeWindow.shared.toggle() }
        store.register(action: .omniSearch) { OmniSearchWindow.shared.toggle() }

        // Layer-switching hotkeys
        let workspace = WorkspaceManager.shared
        let layerCount = (workspace.config?.layers ?? []).count
        for (i, action) in HotkeyAction.layerActions.prefix(layerCount).enumerated() {
            let index = i
            store.register(action: action) { workspace.tileLayer(index: index) }
        }

        // Tiling hotkeys
        let tileMap: [(HotkeyAction, TilePosition)] = [
            (.tileLeft, .left), (.tileRight, .right),
            (.tileMaximize, .maximize), (.tileCenter, .center),
            (.tileTopLeft, .topLeft), (.tileTopRight, .topRight),
            (.tileBottomLeft, .bottomLeft), (.tileBottomRight, .bottomRight),
            (.tileTop, .top), (.tileBottom, .bottom),
            (.tileLeftThird, .leftThird), (.tileCenterThird, .centerThird),
            (.tileRightThird, .rightThird),
        ]
        for (action, position) in tileMap {
            store.register(action: action) { WindowTiler.tileFrontmostViaAX(to: position) }
        }
        store.register(action: .tileDistribute) { WindowTiler.distributeVisible() }

        // Check macOS permissions (Accessibility, Screen Recording)
        PermissionChecker.shared.check()

        // Start daemon services
        OcrStore.shared.open()
        DesktopModel.shared.start()
        OcrModel.shared.start()
        TmuxModel.shared.start()
        ProcessModel.shared.start()
        LatticesApi.setup()
        DaemonServer.shared.start()

        // --diagnostics flag: auto-open diagnostics panel on launch
        if CommandLine.arguments.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DiagnosticWindow.shared.show()
            }
        }

        // --screen-map flag: auto-open screen map on launch
        if CommandLine.arguments.contains("--screen-map") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ScreenMapWindowController.shared.show()
            }
        }
    }

    // MARK: - Status item click handler

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let button = statusItem.button else { return }

        if event.type == .rightMouseUp {
            // Right-click → context menu
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        } else {
            // Left-click → toggle popover
            if let shown = popover, shown.isShown {
                shown.performClose(sender)
            } else {
                let p = makePopover()
                p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                p.contentViewController?.view.window?.makeKey()
            }
        }
    }

    /// Dismiss the popover programmatically (e.g. from the pop-out button).
    func dismissPopover() {
        popover?.performClose(nil)
    }

    /// Create a fresh popover each time so the SwiftUI view tree isn't kept alive
    /// when the popover is closed — prevents continuous CPU usage from @Published updates.
    private func makePopover() -> NSPopover {
        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: MainView(scanner: ProjectScanner.shared))
        p.behavior = .transient
        p.contentSize = NSSize(width: 380, height: 520)
        p.appearance = NSAppearance(named: .darkAqua)
        p.delegate = self
        popover = p
        return p
    }

    func popoverDidClose(_ notification: Notification) {
        // Tear down the SwiftUI view tree so observed models stop driving re-renders
        popover?.contentViewController = nil
        popover = nil
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let actions: [(String, String, Selector)] = [
            ("Command Palette", "⌘⇧M", #selector(menuCommandPalette)),
            ("Screen Map", "", #selector(menuScreenMap)),
            ("Desktop Inventory", "", #selector(menuDesktopInventory)),
            ("Window Bezel", "", #selector(menuWindowBezel)),
            ("Cheat Sheet", "", #selector(menuCheatSheet)),
            ("Omni Search", "", #selector(menuOmniSearch)),
        ]
        for (title, shortcut, action) in actions {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if !shortcut.isEmpty {
                // Display-only; the actual hotkey is global
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let diag = NSMenuItem(title: "Diagnostics", action: #selector(menuDiagnostics), keyEquivalent: "")
        diag.target = self
        menu.addItem(diag)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Lattices", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func menuCommandPalette() { CommandPaletteWindow.shared.toggle() }
    @objc private func menuScreenMap() { ScreenMapWindowController.shared.toggle() }
    @objc private func menuDesktopInventory() { CommandModeWindow.shared.toggle() }
    @objc private func menuWindowBezel() { WindowBezel.showBezelForFrontmostWindow() }
    @objc private func menuCheatSheet() { CheatSheetHUD.shared.toggle() }
    @objc private func menuOmniSearch() { OmniSearchWindow.shared.toggle() }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuDiagnostics() { DiagnosticWindow.shared.toggle() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
