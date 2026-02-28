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
        HotkeyManager.shared.register {
            CommandPaletteWindow.shared.toggle()
        }

        // Register command mode hotkey (Hyper+1) → opens standalone screen map
        HotkeyManager.shared.registerCommandMode {
            ScreenMapWindowController.shared.toggle()
        }

        // Register layer-switching hotkeys (Cmd+Option+1/2/3...)
        let workspace = WorkspaceManager.shared
        if let config = workspace.config {
            HotkeyManager.shared.registerLayerHotkeys(count: (config.layers ?? []).count) { index in
                workspace.tileLayer(index: index)
            }
        }

        // Register window tiling hotkeys (Ctrl+Option+arrows/letters)
        HotkeyManager.shared.registerTileHotkeys()

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
        DesktopModel.shared.start()
        TmuxModel.shared.start()
        DaemonServer.shared.start()

        // --diagnostics flag: auto-open diagnostics panel on launch
        if CommandLine.arguments.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DiagnosticWindow.shared.show()
            }
        }
    }

    private static func stylePanel(_ panel: NSPanel) {
        let bg = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        panel.backgroundColor = bg
        panel.isOpaque = false
        panel.hasShadow = true
        panel.invalidateShadow()
    }
}
