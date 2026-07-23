import AppKit
import Foundation

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: Category
    let badge: String?
    let keywords: [String]
    let isHiddenByDefault: Bool
    let action: () -> Void

    enum Category: String, CaseIterable {
        case project = "Projects"
        case window  = "Window"
        case run     = "Runs"
        case app     = "App"

        var icon: String {
            switch self {
            case .project: return "terminal"
            case .window:  return "macwindow"
            case .run:     return "record.circle"
            case .app:     return "gearshape"
            }
        }
    }

    init(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        category: Category,
        badge: String? = nil,
        keywords: [String] = [],
        isHiddenByDefault: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.badge = badge
        self.keywords = keywords
        self.isHiddenByDefault = isHiddenByDefault
        self.action = action
    }

    /// Fuzzy match score — higher is better, 0 means no match
    func matchScore(query: String) -> Int {
        let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return 0 }

        let terms = words(in: q)
        let searchableText = ([title, subtitle, badge ?? ""] + keywords)
            .map(normalized)
            .joined(separator: " ")
        if terms.count > 1, terms.contains(where: { !searchableText.contains($0) }) {
            return 0
        }

        let t = normalized(title)
        let s = normalized(subtitle)
        let keywordText = keywords.map(normalized).joined(separator: " ")

        // Exact and prefix matches keep named actions above incidental text hits.
        if t == q { return 120 }
        if t.hasPrefix(q) { return 110 }
        if words(in: t).contains(where: { $0.hasPrefix(q) }) { return 95 }
        if t.contains(q) { return 80 }
        if keywordText.hasPrefix(q) { return 75 }
        if words(in: keywordText).contains(where: { $0.hasPrefix(q) }) { return 70 }
        if keywordText.contains(q) { return 60 }
        if s.hasPrefix(q) { return 55 }
        if words(in: s).contains(where: { $0.hasPrefix(q) }) { return 50 }
        if s.contains(q) { return 40 }
        if terms.count > 1 { return 35 }
        return 0
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
    }

    private func words(in value: String) -> [String] {
        value.split { ch in
            !ch.isLetter && !ch.isNumber
        }.map(String.init)
    }
}

// MARK: - Command Builder

enum CommandBuilder {
    static func build(scanner: ProjectScanner) -> [PaletteCommand] {
        var projectCmds: [PaletteCommand] = []
        var windowCmds: [PaletteCommand] = []
        let terminal = Preferences.shared.terminal

        for project in scanner.projects {
            if project.isRunning {
                // Project actions
                projectCmds.append(PaletteCommand(
                    id: "attach-\(project.id)",
                    title: "Attach \(project.name)",
                    subtitle: "Open terminal to running session",
                    icon: "play.fill",
                    category: .project,
                    badge: "running",
                    action: { SessionManager.launch(project: project) }
                ))
                // Window actions
                windowCmds.append(PaletteCommand(
                    id: "goto-\(project.id)",
                    title: "Go to \(project.name)",
                    subtitle: "Focus the terminal window",
                    icon: "macwindow",
                    category: .window,
                    badge: nil,
                    action: {
                        WindowTiler.navigateToWindow(
                            session: project.sessionName,
                            terminal: terminal
                        )
                    }
                ))
                windowCmds.append(PaletteCommand(
                    id: "tile-left-\(project.id)",
                    title: "Tile \(project.name) Left",
                    subtitle: "Snap window to left half",
                    icon: "rectangle.lefthalf.filled",
                    category: .window,
                    badge: nil,
                    action: {
                        WindowTiler.tile(session: project.sessionName, terminal: terminal, to: .left)
                    }
                ))
                windowCmds.append(PaletteCommand(
                    id: "tile-right-\(project.id)",
                    title: "Tile \(project.name) Right",
                    subtitle: "Snap window to right half",
                    icon: "rectangle.righthalf.filled",
                    category: .window,
                    badge: nil,
                    action: {
                        WindowTiler.tile(session: project.sessionName, terminal: terminal, to: .right)
                    }
                ))
                windowCmds.append(PaletteCommand(
                    id: "tile-max-\(project.id)",
                    title: "Maximize \(project.name)",
                    subtitle: "Expand window to fill screen",
                    icon: "rectangle.fill",
                    category: .window,
                    badge: nil,
                    action: {
                        WindowTiler.tile(session: project.sessionName, terminal: terminal, to: .maximize)
                    }
                ))
                windowCmds.append(PaletteCommand(
                    id: "detach-\(project.id)",
                    title: "Detach \(project.name)",
                    subtitle: "Disconnect clients, keep session alive",
                    icon: "eject.fill",
                    category: .window,
                    badge: nil,
                    action: { SessionManager.detach(project: project) }
                ))
                windowCmds.append(PaletteCommand(
                    id: "kill-\(project.id)",
                    title: "Kill \(project.name)",
                    subtitle: "Terminate the session",
                    icon: "xmark.circle.fill",
                    category: .window,
                    badge: nil,
                    action: { SessionManager.kill(project: project) }
                ))
                // Recovery commands
                projectCmds.append(PaletteCommand(
                    id: "sync-\(project.id)",
                    title: "Sync \(project.name)",
                    subtitle: "Reconcile session to declared config",
                    icon: "arrow.triangle.2.circlepath",
                    category: .project,
                    badge: nil,
                    action: { SessionManager.sync(project: project) }
                ))
                // Per-pane restart commands
                for paneName in project.paneNames {
                    projectCmds.append(PaletteCommand(
                        id: "restart-\(paneName)-\(project.id)",
                        title: "Restart \(paneName) in \(project.name)",
                        subtitle: "Kill and re-run the \(paneName) pane",
                        icon: "arrow.counterclockwise",
                        category: .project,
                        badge: nil,
                        action: { SessionManager.restart(project: project, paneName: paneName) }
                    ))
                }
            } else {
                projectCmds.append(PaletteCommand(
                    id: "launch-\(project.id)",
                    title: "Launch \(project.name)",
                    subtitle: project.paneSummary.isEmpty
                        ? (project.devCommand ?? project.path)
                        : project.paneSummary,
                    icon: "play.circle",
                    category: .project,
                    badge: nil,
                    action: { SessionManager.launch(project: project) }
                ))
            }
        }

        // Move-to-space commands for running projects
        let allSpaces = WindowTiler.getDisplaySpaces().flatMap(\.spaces)
        if allSpaces.count > 1 {
            for project in scanner.projects where project.isRunning {
                let tag = Terminal.windowTag(for: project.sessionName)
                var windowSpaces: [Int] = []
                if let (w, _) = WindowTiler.findWindow(tag: tag) {
                    windowSpaces = WindowTiler.getSpacesForWindow(w)
                }

                for space in allSpaces {
                    let isCurrentSpace = windowSpaces.contains(space.id)
                    windowCmds.append(PaletteCommand(
                        id: "move-space\(space.index)-\(project.id)",
                        title: "Move \(project.name) to Space \(space.index)",
                        subtitle: isCurrentSpace ? "Window is already here" : "Move window to Space \(space.index)",
                        icon: "rectangle.on.rectangle",
                        category: .window,
                        badge: isCurrentSpace ? "current" : nil,
                        action: {
                            let result = WindowTiler.moveWindowToSpace(
                                session: project.sessionName,
                                terminal: terminal,
                                spaceId: space.id
                            )
                            if case .success = result {
                                WindowTiler.switchToSpace(spaceId: space.id)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    WindowTiler.highlightWindow(session: project.sessionName)
                                }
                            }
                        }
                    ))
                }
            }
        }

        var commands = projectCmds + windowCmds

        // Layer commands (focus + launch)
        let workspace = WorkspaceManager.shared
        if let wsConfig = workspace.config {
            for (i, layer) in (wsConfig.layers ?? []).enumerated() {
                let layerIndex = i
                let isActive = i == workspace.activeLayerIndex
                let counts = workspace.layerRunningCount(index: i)
                commands.append(PaletteCommand(
                    id: "layer-focus-\(layer.id)",
                    title: "Focus Layer: \(layer.label)",
                    subtitle: "\(counts.running)/\(counts.total) running \u{2014} \u{2325}\(i + 1)",
                    icon: "square.stack.3d.up",
                    category: .app,
                    badge: isActive ? "active" : nil,
                    action: { workspace.tileLayer(index: layerIndex) }
                ))
                commands.append(PaletteCommand(
                    id: "layer-launch-\(layer.id)",
                    title: "Launch Layer: \(layer.label)",
                    subtitle: "Start all \(layer.projects.count) project\(layer.projects.count == 1 ? "" : "s")",
                    icon: "play.circle",
                    category: .app,
                    badge: isActive ? "active" : nil,
                    action: { workspace.tileLayer(index: layerIndex, launch: true) }
                ))
            }

            // Tab group commands
            for group in wsConfig.groups ?? [] {
                let isRunning = workspace.isGroupRunning(group)

                if isRunning {
                    commands.append(PaletteCommand(
                        id: "group-attach-\(group.id)",
                        title: "Attach \(group.label)",
                        subtitle: "\(group.tabs.count) tabs",
                        icon: "rectangle.stack",
                        category: .project,
                        badge: "group",
                        action: {
                            workspace.focusTab(
                                group: group,
                                tabIndex: workspace.selectedTabIndex(in: group)
                            )
                        }
                    ))

                    // Per-tab focus commands
                    for (idx, tab) in group.tabs.enumerated() {
                        let tabLabel = tab.displayLabel
                        let tabIndex = idx
                        commands.append(PaletteCommand(
                            id: "group-tab-\(group.id)-\(idx)",
                            title: "\(group.label): \(tabLabel)",
                            subtitle: "Focus tab \(idx + 1) in group",
                            icon: "rectangle.topthird.inset.filled",
                            category: .project,
                            badge: nil,
                            action: {
                                workspace.focusTab(group: group, tabIndex: tabIndex)
                            }
                        ))
                    }

                    commands.append(PaletteCommand(
                        id: "group-kill-\(group.id)",
                        title: "Kill \(group.label) Group",
                        subtitle: "Terminate the group session",
                        icon: "xmark.circle.fill",
                        category: .window,
                        badge: nil,
                        action: {
                            workspace.killGroup(group)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                scanner.refreshStatus()
                            }
                        }
                    ))
                } else {
                    commands.append(PaletteCommand(
                        id: "group-launch-\(group.id)",
                        title: "Launch \(group.label)",
                        subtitle: "\(group.tabs.count) tabs \u{2014} \(group.tabs.map(\.displayLabel).joined(separator: ", "))",
                        icon: "rectangle.stack",
                        category: .project,
                        badge: "group",
                        action: { workspace.launchGroup(group) }
                    ))
                }
            }
        }

        // Orphan session commands
        let inventory = InventoryManager.shared
        for orphan in inventory.orphans {
            let orphanKeywords = [
                "orphan",
                "unmanaged",
                "tmux",
                "session",
                orphan.name,
            ]
            commands.append(PaletteCommand(
                id: "orphan-attach-\(orphan.name)",
                title: "Attach \(orphan.name)",
                subtitle: "\(orphan.panes.count) pane\(orphan.panes.count == 1 ? "" : "s") \u{2014} \(orphan.panes.prefix(3).map(\.currentCommand).joined(separator: ", "))",
                icon: "play.fill",
                category: .project,
                badge: "orphan",
                keywords: orphanKeywords,
                isHiddenByDefault: true,
                action: {
                    let terminal = Preferences.shared.terminal
                    terminal.focusOrAttach(session: orphan.name)
                }
            ))
            commands.append(PaletteCommand(
                id: "orphan-kill-\(orphan.name)",
                title: "Kill \(orphan.name)",
                subtitle: "Terminate unmanaged session",
                icon: "xmark.circle.fill",
                category: .window,
                badge: "orphan",
                keywords: orphanKeywords + ["remove"],
                isHiddenByDefault: true,
                action: {
                    SessionManager.killByName(orphan.name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        inventory.refresh()
                    }
                }
            ))
        }

        // App actions
        commands.append(PaletteCommand(
            id: "run-screenshot-current-window",
            title: "Screenshot Current Window",
            subtitle: "Save a run artifact from the frontmost window",
            icon: "camera.viewfinder",
            category: .run,
            badge: nil,
            action: {
                Task.detached(priority: .userInitiated) {
                    do {
                        let result = try CaptureController.shared.screenshotWindow(params: .object([
                            "source": .string("palette"),
                        ]))
                        if let path = result["artifact"]?["path"]?.stringValue {
                            DiagnosticLog.shared.success("Capture: saved screenshot artifact \(path)")
                        }
                    } catch {
                        DiagnosticLog.shared.warn("Capture: screenshot failed — \(error.localizedDescription)")
                    }
                }
            }
        ))

        commands.append(PaletteCommand(
            id: "runs-review-last",
            title: "Review Runs",
            subtitle: "Inspect run traces and artifacts",
            icon: "folder",
            category: .run,
            badge: nil,
            action: {
                guard let run = RunStore.shared.list(limit: 1).first else {
                    DiagnosticLog.shared.info("Runs: no runs available to review")
                    return
                }
                DiagnosticLog.shared.info("Runs: reviewing \(run.id)")
                ScreenMapWindowController.shared.showPage(.runs)
            }
        ))

        commands.append(PaletteCommand(
            id: "app-workspace-chat",
            title: "Workspace Assistant",
            subtitle: "Open AI chat (⌘⇧A)",
            icon: "bubble.left.and.bubble.right",
            category: .app,
            badge: nil,
            keywords: ["assistant", "ai", "chat", "help"],
            action: { AssistantAccess.show() }
        ))

        commands.append(PaletteCommand(
            id: "app-settings",
            title: "Settings",
            subtitle: "Terminal, scan root, keyboard, shortcuts, voice, and OCR",
            icon: "gearshape",
            category: .app,
            badge: nil,
            keywords: ["preferences", "configuration", "general", "keyboard"],
            action: {
                SettingsWindowController.shared.show()
            }
        ))

        commands.append(PaletteCommand(
            id: "app-keyboard-settings",
            title: "Keyboard Settings",
            subtitle: "Caps Lock as Hyper and tap-for-Escape",
            icon: "keyboard",
            category: .app,
            badge: nil,
            keywords: ["caps", "caps lock", "hyper", "escape", "remap", "keyboard remaps"],
            action: { SettingsWindowController.shared.show(section: "keyboard") }
        ))

        commands.append(PaletteCommand(
            id: "app-shortcuts-settings",
            title: "Shortcuts",
            subtitle: "Review or change global keyboard shortcuts",
            icon: "command",
            category: .app,
            badge: nil,
            keywords: ["hotkeys", "key bindings", "keyboard", "controls"],
            action: { SettingsWindowController.shared.show(section: "shortcuts") }
        ))

        commands.append(PaletteCommand(
            id: "app-voice-settings",
            title: "Voice Capture",
            subtitle: "Microphone, dictation, and voice command settings",
            icon: "waveform.badge.mic",
            category: .app,
            badge: nil,
            keywords: ["voice", "dictation", "mic", "microphone", "capture", "talk"],
            action: { SettingsWindowController.shared.show(section: "voice") }
        ))

        commands.append(PaletteCommand(
            id: "app-voice-command",
            title: "Voice Command",
            subtitle: "Open the voice capture bar",
            icon: "mic",
            category: .app,
            badge: nil,
            keywords: ["voice", "dictation", "speak", "command box", "universal box"],
            action: { UnifiedCommandBarWindow.shared.toggle(mode: .voice) }
        ))

        commands.append(PaletteCommand(
            id: "app-command-bar",
            title: "Command Bar",
            subtitle: "Type slash commands and workspace actions",
            icon: "text.cursor",
            category: .app,
            badge: nil,
            keywords: ["universal box", "command box", "slash commands", "actions"],
            action: { UnifiedCommandBarWindow.shared.toggle(mode: .command) }
        ))

        commands.append(PaletteCommand(
            id: "app-search-bar",
            title: "Search Bar",
            subtitle: "Search windows, projects, sessions, processes, and OCR",
            icon: "magnifyingglass",
            category: .app,
            badge: nil,
            keywords: ["universal search", "omni search", "find"],
            action: { UnifiedCommandBarWindow.shared.toggle(mode: .search) }
        ))

        commands.append(PaletteCommand(
            id: "app-home",
            title: "Home",
            subtitle: "Open the workspace home view",
            icon: "house",
            category: .app,
            badge: nil,
            action: { ScreenMapWindowController.shared.showPage(.home) }
        ))

        commands.append(PaletteCommand(
            id: "app-windows-list",
            title: "Desktop Inventory",
            subtitle: "Browse windows, displays, spaces, and screen text",
            icon: "magnifyingglass",
            category: .app,
            badge: nil,
            keywords: ["search", "windows", "ocr", "desktop", "inventory"],
            action: { ScreenMapWindowController.shared.showPage(.desktopInventory) }
        ))

        commands.append(PaletteCommand(
            id: "app-search-settings",
            title: "Search & OCR Settings",
            subtitle: "OCR cadence, quality, and recent capture visibility",
            icon: "text.viewfinder",
            category: .app,
            badge: nil,
            keywords: ["search", "ocr", "indexing", "screen text"],
            action: { SettingsWindowController.shared.show(section: "search") }
        ))

        commands.append(PaletteCommand(
            id: "app-screen-map",
            title: "Studio",
            subtitle: "Arrange windows & layers",
            icon: "rectangle.3.group",
            category: .app,
            badge: nil,
            action: { ScreenMapWindowController.shared.showPage(.screenMap) }
        ))

        commands.append(PaletteCommand(
            id: "app-diagnostics",
            title: "Activity Log",
            subtitle: "View logs, events, and diagnostics",
            icon: "list.bullet.rectangle",
            category: .app,
            badge: nil,
            action: { ScreenMapWindowController.shared.showPage(.activity) }
        ))

        commands.append(PaletteCommand(
            id: "app-refresh",
            title: "Refresh Projects",
            subtitle: "Re-scan for .lattices.json configs",
            icon: "arrow.clockwise",
            category: .app,
            badge: nil,
            action: { scanner.scan() }
        ))

        commands.append(PaletteCommand(
            id: "app-quit",
            title: "Quit Lattices",
            subtitle: "Exit the menu bar app",
            icon: "power",
            category: .app,
            badge: nil,
            action: { NSApp.terminate(nil) }
        ))

        return commands
    }
}
