import AppKit

/// Registers the global hotkey (Cmd+Shift+D) on launch.
/// The menu bar itself is handled by SwiftUI's MenuBarExtra.
class AppDelegate: NSObject, NSApplicationDelegate {

    /// Toggle between .accessory (hidden from Dock/Cmd+Tab) and .regular (visible)
    /// based on whether any managed windows are open.
    /// Call this after showing or dismissing a window.
    static func updateActivationPolicy() {
        let hasVisibleWindow =
            CommandModeWindow.shared.isVisible ||
            CommandPaletteWindow.shared.isVisible ||
            MainWindow.shared.isVisible ||
            ScreenMapWindowController.shared.isVisible
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

        CommandPaletteWindow.shared.configure(scanner: ProjectScanner.shared)

        // Register all hotkeys via HotkeyStore (user-configurable bindings)
        let store = HotkeyStore.shared
        store.register(action: .palette) { CommandPaletteWindow.shared.toggle() }
        store.register(action: .screenMap) { ScreenMapWindowController.shared.toggle() }
        store.register(action: .bezel) { WindowBezel.showBezelForFrontmostWindow() }
        store.register(action: .cheatSheet) { CheatSheetHUD.shared.toggle() }
        store.register(action: .desktopInventory) { CommandModeWindow.shared.toggle() }

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

        // Style the MenuBarExtra panel when it appears
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let panel = note.object as? NSPanel else { return }
            Self.stylePanel(panel)
        }

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

    private static func stylePanel(_ panel: NSPanel) {
        let bg = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        panel.backgroundColor = bg
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.invalidateShadow()
    }
}
