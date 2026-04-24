import AppKit
import SwiftUI

extension Notification.Name {
    static let latticesPopoverWillShow = Notification.Name("latticesPopoverWillShow")
}

/// Manages the NSStatusItem (menu bar icon), left-click popover, and right-click context menu.
/// Replaces the previous SwiftUI MenuBarExtra approach for full click-event control.
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static weak var shared: AppDelegate?

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
            (Self.shared?.popover?.isShown == true) ||
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
        Self.shared = self
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
        store.register(action: .unifiedWindow) { ScreenMapWindowController.shared.toggle() }
        store.register(action: .bezel) { Self.showWorkspaceInspector() }
        store.register(action: .cheatSheet) { SettingsWindowController.shared.show() }
        store.register(action: .voiceCommand) {
            DiagnosticLog.shared.info("Hotkey: voiceCommand triggered")
            VoiceCommandWindow.shared.toggle()
        }
        store.register(action: .handsOff) {
            DiagnosticLog.shared.info("Hotkey: handsOff triggered")
            HandsOffSession.shared.toggle()
            // Show voice bar when starting, hide when stopping
            if HandsOffSession.shared.state != .idle {
                HUDController.shared.showVoiceBar()
            } else {
                HUDController.shared.hideVoiceBar()
            }
        }
        store.register(action: .hud) { HUDController.shared.toggle() }
        store.register(action: .mouseFinder) { MouseFinder.shared.find() }

        // Pre-render HUD panels off-screen for instant first open
        DispatchQueue.main.async { HUDController.shared.warmUp() }
        // Pre-build the menu bar popover so the first click doesn't pay the SwiftUI mount cost.
        // Touching `.view` forces NSHostingController to materialize the SwiftUI view tree.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let p = self.makePopover()
            _ = p.contentViewController?.view
        }
        store.register(action: .omniSearch) { OmniSearchWindow.shared.toggle() }
        WindowDragSnapController.shared.start()

        // Session layer cycling
        store.register(action: .layerNext) { SessionLayerStore.shared.cycleNext() }
        store.register(action: .layerPrev) { SessionLayerStore.shared.cyclePrev() }
        store.register(action: .layerTag)  { SessionLayerStore.shared.tagFrontmostWindow() }

        // Layer-switching hotkeys (1-9): session layers take priority
        let workspace = WorkspaceManager.shared
        let configLayerCount = (workspace.config?.layers ?? []).count
        let maxLayers = max(configLayerCount, 9)
        for (i, action) in HotkeyAction.layerActions.prefix(maxLayers).enumerated() {
            let index = i
            store.register(action: action) {
                let session = SessionLayerStore.shared
                if !session.layers.isEmpty && index < session.layers.count {
                    session.switchTo(index: index)
                } else {
                    workspace.focusLayer(index: index)
                }
                EventBus.shared.post(.layerSwitched(index: index))
            }
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

        // Onboarding on first launch; otherwise just check permissions
        if !OnboardingWindowController.shared.showIfNeeded() {
            PermissionChecker.shared.check()
        }

        // Start daemon services
        let diag = DiagnosticLog.shared
        let tBoot = diag.startTimed("Daemon services boot")
        OcrStore.shared.open()
        DesktopModel.shared.start()
        OcrModel.shared.start()
        TmuxModel.shared.start()
        ProcessModel.shared.start()
        LatticesApi.setup()
        DaemonServer.shared.start()
        AgentPool.shared.start()
        diag.finish(tBoot)

        // --diagnostics flag: auto-open diagnostics panel on launch
        if CommandLine.arguments.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DiagnosticWindow.shared.show()
            }
        }

        // --screen-map flag: auto-open layout on launch
        if CommandLine.arguments.contains("--screen-map") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ScreenMapWindowController.shared.showPage(.screenMap)
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
            // Left-click → toggle the menu bar projects popover.
            if let shown = popover, shown.isShown {
                shown.performClose(sender)
            } else {
                showProjectsPopover()
            }
        }
    }

    /// Dismiss the popover programmatically (e.g. from the pop-out button).
    func dismissPopover() {
        popover?.performClose(nil)
    }

    /// Cached popover — built lazily on first click, reused on every subsequent open.
    /// Keeping the SwiftUI view tree alive avoids rebuilding on each click (slow first paint).
    /// Data refresh is driven from `popoverWillShow` + a notification MainView listens to.
    private func makePopover() -> NSPopover {
        if let p = popover { return p }
        let t = DiagnosticLog.shared.startTimed("makePopover")
        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: MainView(scanner: ProjectScanner.shared))
        p.behavior = .transient
        p.contentSize = NSSize(width: 380, height: 300)
        p.appearance = NSAppearance(named: .darkAqua)
        p.delegate = self
        popover = p
        DiagnosticLog.shared.finish(t)
        return p
    }

    private func showProjectsPopover() {
        guard let button = statusItem.button else { return }
        let p = makePopover()
        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        p.contentViewController?.view.window?.makeKey()
    }

    func popoverWillShow(_ notification: Notification) {
        Self.updateActivationPolicy()
        NotificationCenter.default.post(name: .latticesPopoverWillShow, object: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        Self.updateActivationPolicy()
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let actions: [(String, String, Selector)] = [
            ("Home", "", #selector(menuWorkspace)),
            ("Layout", "", #selector(menuLayout)),
            ("Search", "", #selector(menuSearch)),
            ("Command Palette", "⌘⇧M", #selector(menuCommandPalette)),
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

        let settings = NSMenuItem(title: "Help & Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Lattices", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func menuCommandPalette() { CommandPaletteWindow.shared.toggle() }
    @objc private func menuWorkspace() { ScreenMapWindowController.shared.showPage(.home) }
    @objc private func menuLayout() { ScreenMapWindowController.shared.showPage(.screenMap) }
    @objc private func menuSearch() { ScreenMapWindowController.shared.showPage(.desktopInventory) }
    @objc private func menuDocs() { SettingsWindowController.shared.show() }
    @objc private func menuProjects() { DispatchQueue.main.async { self.showProjectsPopover() } }
    @objc private func menuInitializeProject() { CliActionLauncher.initializeProjectInTerminal() }
    @objc private func menuLaunchProject() { CliActionLauncher.launchProjectInTerminal() }
    @objc private func menuHUD() { HUDController.shared.toggle() }
    @objc private func menuWindowBezel() { Self.showWorkspaceInspector() }
    @objc private func menuCheatSheet() { SettingsWindowController.shared.show() }
    @objc private func menuOmniSearch() { OmniSearchWindow.shared.toggle() }
    @objc private func menuSettings() { SettingsWindowController.shared.show() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private static func showWorkspaceInspector() {
        guard let entry = DesktopModel.shared.frontmostWindow(),
              entry.app != "Lattices" else {
            ScreenMapWindowController.shared.showPage(.screenMap)
            return
        }

        ScreenMapWindowController.shared.showWindow(wid: entry.wid)
    }
}
