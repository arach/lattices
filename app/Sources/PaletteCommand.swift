import AppKit
import Foundation

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let category: Category
    let badge: String?
    let action: () -> Void

    enum Category: String, CaseIterable {
        case project = "Projects"
        case window  = "Window"
        case app     = "App"

        var icon: String {
            switch self {
            case .project: return "terminal"
            case .window:  return "macwindow"
            case .app:     return "gearshape"
            }
        }
    }

    /// Fuzzy match score — higher is better, 0 means no match
    func matchScore(query: String) -> Int {
        let q = query.lowercased()
        let t = title.lowercased()
        let s = subtitle.lowercased()

        // Exact prefix match on title — best
        if t.hasPrefix(q) { return 100 }
        // Word-boundary prefix (e.g. "set" matches "Open Settings")
        let words = t.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 80 }
        // Contains in title
        if t.contains(q) { return 60 }
        // Subtitle prefix
        if s.hasPrefix(q) { return 50 }
        // Subtitle contains
        if s.contains(q) { return 40 }
        // Subsequence match on title
        if isSubsequence(q, of: t) { return 20 }
        return 0
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        for ch in needle {
            while let next = it.next() {
                if next == ch { break }
            }
            // If iterator is exhausted before matching all chars, not a subsequence
            // (handled by the while loop returning nil)
        }
        // Verify: re-check properly
        var hi = haystack.startIndex
        for ch in needle {
            guard let found = haystack[hi...].firstIndex(of: ch) else { return false }
            hi = haystack.index(after: found)
        }
        return true
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
                    subtitle: "Terminate the tmux session",
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
                            if let firstTab = group.tabs.first {
                                let session = WorkspaceManager.sessionName(for: firstTab.path)
                                let terminal = Preferences.shared.terminal
                                terminal.focusOrAttach(session: session)
                            }
                        }
                    ))

                    // Per-tab focus commands
                    for (idx, tab) in group.tabs.enumerated() {
                        let tabLabel = tab.label ?? (tab.path as NSString).lastPathComponent
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
                        subtitle: "\(group.tabs.count) tabs \u{2014} \(group.tabs.map { $0.label ?? ($0.path as NSString).lastPathComponent }.joined(separator: ", "))",
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
            commands.append(PaletteCommand(
                id: "orphan-attach-\(orphan.name)",
                title: "Attach \(orphan.name)",
                subtitle: "\(orphan.panes.count) pane\(orphan.panes.count == 1 ? "" : "s") \u{2014} \(orphan.panes.prefix(3).map(\.currentCommand).joined(separator: ", "))",
                icon: "play.fill",
                category: .project,
                badge: "orphan",
                action: {
                    let terminal = Preferences.shared.terminal
                    terminal.focusOrAttach(session: orphan.name)
                }
            ))
            commands.append(PaletteCommand(
                id: "orphan-kill-\(orphan.name)",
                title: "Kill \(orphan.name)",
                subtitle: "Terminate unmanaged tmux session",
                icon: "xmark.circle.fill",
                category: .window,
                badge: "orphan",
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
            id: "app-settings",
            title: "Settings",
            subtitle: "Terminal, scan root, mode",
            icon: "gearshape",
            category: .app,
            badge: nil,
            action: {
                SettingsWindowController.shared.show()
            }
        ))

        commands.append(PaletteCommand(
            id: "app-screen-map",
            title: "Screen Map",
            subtitle: "Visual window editor",
            icon: "rectangle.3.group",
            category: .app,
            badge: nil,
            action: { ScreenMapWindowController.shared.show() }
        ))

        commands.append(PaletteCommand(
            id: "app-diagnostics",
            title: "Diagnostics",
            subtitle: "View logs and debug info",
            icon: "stethoscope",
            category: .app,
            badge: nil,
            action: { DiagnosticWindow.shared.show() }
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
