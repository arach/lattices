import SwiftUI

enum MainViewLayout {
    case popover
    case embedded
}

struct MainView: View {
    @ObservedObject var scanner: ProjectScanner
    var layout: MainViewLayout = .popover
    @StateObject private var prefs = Preferences.shared
    @StateObject private var permChecker = PermissionChecker.shared
    @ObservedObject private var workspace = WorkspaceManager.shared
    @StateObject private var inventory = InventoryManager.shared
    @State private var searchText = ""
    @State private var hasCheckedSetup = false
    @State private var bannerDismissed = false
    @State private var tmuxBannerDismissed = false
    @ObservedObject private var tmuxModel = TmuxModel.shared
    @State private var orphanSectionCollapsed = true
    private let embeddedProjectColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
        count: 3
    )
    private let embeddedProjectCardHeight: CGFloat = 94
    private let embeddedProjectGridSpacing: CGFloat = 10
    private var filtered: [Project] {
        if searchText.isEmpty { return scanner.projects }
        return scanner.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredOrphans: [TmuxSession] {
        if searchText.isEmpty { return inventory.orphans }
        return inventory.orphans.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var needsSetup: Bool { prefs.scanRoot.isEmpty }
    private var runningCount: Int { scanner.projects.filter(\.isRunning).count }
    private var hasVisibleGroups: Bool {
        guard let groups = workspace.config?.groups else { return false }
        return !groups.isEmpty && searchText.isEmpty
    }
    private var embeddedProjectGridHeight: CGFloat {
        guard !filtered.isEmpty else { return 0 }
        let rowCount = min(Int(ceil(Double(filtered.count) / 3.0)), 3)
        return CGFloat(rowCount) * embeddedProjectCardHeight
            + CGFloat(max(0, rowCount - 1)) * embeddedProjectGridSpacing
    }

    var body: some View {
        VStack(spacing: 0) {
            mainContent
        }
        .frame(
            minWidth: layout == .popover ? 380 : 0,
            idealWidth: layout == .popover ? 380 : nil,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            if needsSetup && !hasCheckedSetup {
                hasCheckedSetup = true
                SettingsWindowController.shared.show()
            }
            runRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .latticesPopoverWillShow)) { _ in
            guard layout == .popover else { return }
            runRefresh()
        }
    }

    private func runRefresh() {
        let tTotal = DiagnosticLog.shared.startTimed("MainView.refresh (total)")
        scanner.updateRoot(prefs.scanRoot)

        let tScan = DiagnosticLog.shared.startTimed("ProjectScanner.scan")
        scanner.scan()
        DiagnosticLog.shared.finish(tScan)

        let tInv = DiagnosticLog.shared.startTimed("InventoryManager.refresh")
        inventory.refresh()
        DiagnosticLog.shared.finish(tInv)

        let tPerm = DiagnosticLog.shared.startTimed("PermissionChecker.check")
        permChecker.check()
        DiagnosticLog.shared.finish(tPerm)

        bannerDismissed = false
        DiagnosticLog.shared.finish(tTotal)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if layout == .popover {
                HStack {
                    Text("Lattices")
                        .font(Typo.mono(14))
                        .foregroundColor(Palette.text)

                    Spacer()

                    headerButton(icon: "house") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        ScreenMapWindowController.shared.showPage(.home)
                    }
                    headerButton(icon: "rectangle.3.group") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        ScreenMapWindowController.shared.showPage(.screenMap)
                    }
                    headerButton(icon: "magnifyingglass") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        ScreenMapWindowController.shared.showPage(.desktopInventory)
                    }
                    headerButton(icon: "command") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        CommandPaletteWindow.shared.toggle()
                    }
                    headerButton(icon: "arrow.clockwise") { scanner.scan(); inventory.refresh() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
            } else {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Palette.textMuted)
                        .font(.system(size: 11))
                    TextField("Search projects...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Typo.body(13))
                        .foregroundColor(Palette.text)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Palette.textMuted)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.surface)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            // Permission banner
            if !permChecker.allGranted && !bannerDismissed {
                permissionBanner
            }

            // tmux not-found banner
            if !tmuxModel.isAvailable && !tmuxBannerDismissed {
                tmuxBanner
            }

            if layout == .popover {
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                actionsSection

                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                bottomBar
            } else {
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                if filtered.isEmpty && !hasVisibleGroups {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    embeddedProjectsSection
                }

                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                // Actions footer
                actionsSection

                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 0.5)

                // Bottom bar
                bottomBar
            }
        }
    }

    private var embeddedProjectsSection: some View {
        VStack(spacing: 0) {
            if hasVisibleGroups, let groups = workspace.config?.groups {
                LazyVStack(spacing: 4) {
                    ForEach(groups) { group in
                        TabGroupRow(group: group, workspace: workspace)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, filtered.isEmpty ? 8 : 6)
            }

            if !filtered.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(searchText.isEmpty ? "Projects" : "Matches")
                            .font(Typo.monoBold(10))
                            .foregroundColor(Palette.textMuted)

                        if searchText.isEmpty {
                            Text("\(runningCount) live")
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.running.opacity(0.8))
                        }

                        Spacer()

                        Text("\(filtered.count)")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    ScrollView(.vertical, showsIndicators: filtered.count > 9) {
                        LazyVGrid(columns: embeddedProjectColumns, spacing: embeddedProjectGridSpacing) {
                            ForEach(filtered) { project in
                                HomeProjectCard(
                                    project: project,
                                    onLaunch: { launchProject(project) },
                                    onDetach: { detachProject(project) },
                                    onKill: { killProject(project) },
                                    onSync: { syncProject(project) },
                                    onRestart: { paneName in restartProject(project, paneName: paneName) }
                                )
                                .frame(height: embeddedProjectCardHeight)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                    .frame(maxHeight: embeddedProjectGridHeight)
                }
            }

            if !filteredOrphans.isEmpty {
                orphanSection
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Orphan section

    private var orphanSection: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
                .padding(.vertical, 4)

            // Section header
            Button {
                withAnimation(.easeOut(duration: 0.15)) { orphanSectionCollapsed.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: orphanSectionCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Palette.textMuted)

                    Text("Unmanaged Sessions")
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.textMuted)

                    Text("\(filteredOrphans.count)")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.detach)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.detach.opacity(0.12))
                        )

                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            if !orphanSectionCollapsed {
                ForEach(filteredOrphans) { session in
                    OrphanRow(
                        session: session,
                        onAttach: {
                            let terminal = Preferences.shared.terminal
                            terminal.focusOrAttach(session: session.name)
                        },
                        onKill: {
                            SessionManager.killByName(session.name)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                inventory.refresh()
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Actions footer

    private var actionsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Quick Actions")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.textMuted)

                Spacer()

                Button("Help & shortcuts") {
                    SettingsWindowController.shared.show()
                }
                .buttonStyle(.plain)
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ActionRow(
                label: "Home",
                detail: "Workspace overview and project launcher",
                hotkeyTokens: hotkeyTokens(.unifiedWindow),
                icon: "house",
                accentColor: Palette.text
            ) {
                ScreenMapWindowController.shared.showPage(.home)
            }
            ActionRow(
                label: "Layout",
                detail: "Arrange windows and layers",
                hotkeyTokens: [],
                icon: "rectangle.3.group",
                accentColor: Palette.running
            ) {
                ScreenMapWindowController.shared.showPage(.screenMap)
            }
            ActionRow(
                label: "Search",
                detail: "Windows, projects, sessions, processes, and OCR",
                hotkeyTokens: hotkeyTokens(.omniSearch),
                icon: "magnifyingglass",
                accentColor: AudioLayer.shared.isListening ? Palette.running : Palette.textDim
            ) {
                ScreenMapWindowController.shared.showPage(.desktopInventory)
            }
            ActionRow(
                label: "Command Palette",
                detail: "Launch, attach, and control projects",
                hotkeyTokens: hotkeyTokens(.palette),
                icon: "command",
                accentColor: Palette.running
            ) {
                CommandPaletteWindow.shared.toggle()
            }
        }
        .padding(.vertical, 4)
        .background(Palette.surface.opacity(0.4))
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            bottomBarButton(icon: "gearshape", label: "Settings") {
                SettingsWindowController.shared.show()
            }

            HStack(spacing: 4) {
                if !permChecker.allGranted {
                    Circle()
                        .fill(Palette.detach)
                        .frame(width: 5, height: 5)
                }
            }

            Spacer()

            bottomBarButton(icon: "power", label: "Quit", color: Palette.kill) {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.bg)
    }

    private func bottomBarButton(icon: String, label: String, color: Color = Palette.textMuted, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(Typo.mono(9))
            }
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

    private func hotkeyTokens(_ action: HotkeyAction) -> [String] {
        guard let binding = HotkeyStore.shared.bindings[action],
              let key = binding.displayParts.last else { return [] }

        let modifiers = Set(binding.displayParts.dropLast())
        if modifiers == Set(["Ctrl", "Option", "Shift", "Cmd"]) {
            return ["Hyper", shortenHotkeyToken(key)]
        }

        return binding.displayParts.map(shortenHotkeyToken)
    }

    private func shortenHotkeyToken(_ token: String) -> String {
        switch token {
        case "Cmd": return "⌘"
        case "Shift": return "⇧"
        case "Option": return "⌥"
        case "Ctrl": return "⌃"
        case "Return": return "↩"
        case "Escape": return "Esc"
        case "Space": return "Space"
        default: return token
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Palette.textMuted)

            Text("No projects yet")
                .font(Typo.heading(14))
                .foregroundColor(Palette.textDim)

            Text("Choose a repo and we’ll hand off to the CLI\nin your terminal.")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 10) {
                Button(action: CliActionLauncher.initializeProjectInTerminal) {
                    Text("Initialize Project")
                        .angularButton(Palette.running)
                }
                .buttonStyle(.plain)

                Button(action: CliActionLauncher.launchProjectInTerminal) {
                    Text("Launch Project")
                        .angularButton(.white, filled: false)
                }
                .buttonStyle(.plain)
            }

            Text("Initialize runs  lattices init && lattices  in the folder you choose.")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Permission banner

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.detach)
                Text("PERMISSIONS NEEDED")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.detach)
                Spacer()
                Button { bannerDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }

            permissionRow("Accessibility", granted: permChecker.accessibility) {
                permChecker.requestAccessibility()
            }
            permissionRow("Screen Capture", granted: permChecker.screenRecording) {
                permChecker.requestScreenRecording()
            }

            Text("Click a row to continue the permission flow in macOS.")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.detach.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Palette.detach.opacity(0.20), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - tmux banner

    private var tmuxBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundColor(Palette.detach)
                Text("TMUX NOT FOUND")
                    .font(Typo.monoBold(10))
                    .foregroundColor(Palette.detach)
                Spacer()
                Button { tmuxBannerDismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Palette.textMuted)
                }
                .buttonStyle(.plain)
            }

            Text("Session management requires tmux. Install it with Homebrew:")
                .font(Typo.mono(10))
                .foregroundColor(Palette.text)

            Button {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/zsh")
                task.arguments = ["-lc", "brew install tmux"]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("brew install tmux")
                        .font(Typo.monoBold(10))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.detach.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            Text("Window tiling, search, and OCR work without tmux.")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.detach.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Palette.detach.opacity(0.20), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func permissionRow(_ name: String, granted: Bool, open: @escaping () -> Void) -> some View {
        Button(action: { if !granted { open() } }) {
            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundColor(granted ? Palette.running : Palette.detach)
                Text(name)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.text)
                Spacer()
                if granted {
                    Text("granted")
                        .font(Typo.mono(9))
                        .foregroundColor(Palette.running)
                } else {
                    HStack(spacing: 4) {
                        Text("not set")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.detach)
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                            .foregroundColor(Palette.detach)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(granted ? Color.clear : Palette.detach.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(granted)
    }

    // MARK: - Helpers

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textDim)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func launchProject(_ project: Project) {
        SessionManager.launch(project: project)
    }

    private func detachProject(_ project: Project) {
        SessionManager.detach(project: project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            scanner.refreshStatus()
        }
    }

    private func killProject(_ project: Project) {
        SessionManager.kill(project: project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            scanner.refreshStatus()
        }
    }

    private func syncProject(_ project: Project) {
        SessionManager.sync(project: project)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            scanner.refreshStatus()
        }
    }

    private func restartProject(_ project: Project, paneName: String?) {
        SessionManager.restart(project: project, paneName: paneName)
    }
}

private struct HomeProjectCard: View {
    let project: Project
    let onLaunch: () -> Void
    let onDetach: () -> Void
    let onKill: () -> Void
    let onSync: () -> Void
    let onRestart: (String?) -> Void

    @State private var isHovered = false

    private var summaryText: String {
        if !project.paneSummary.isEmpty { return project.paneSummary }
        if let cmd = project.devCommand, !cmd.isEmpty { return cmd }
        return project.hasConfig
            ? "\(project.paneCount) pane\(project.paneCount == 1 ? "" : "s")"
            : "No config"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(project.isRunning ? Palette.running : Palette.borderLit)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(Typo.heading(13))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    Text(summaryText)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if project.isRunning {
                    Text("LIVE")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.running)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Palette.running.opacity(0.10))
                        )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if project.isRunning {
                    Button(action: onDetach) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 10, weight: .medium))
                            .angularButton(Palette.detach, filled: false)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Button(action: onLaunch) {
                    Text(project.isRunning ? "Attach" : "Launch")
                        .angularButton(project.isRunning ? Palette.running : Palette.launch)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(hovered: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if project.isRunning {
                Button("Attach") { onLaunch() }
                Button("Detach") { onDetach() }
                Button {
                    WindowTiler.navigateToWindow(
                        session: project.sessionName,
                        terminal: Preferences.shared.terminal
                    )
                } label: {
                    Label("Go to Window", systemImage: "macwindow")
                }
                Divider()
                Button("Sync Session") { onSync() }
                Menu("Restart Pane") {
                    ForEach(project.paneNames, id: \.self) { name in
                        Button(name) { onRestart(name) }
                    }
                }
                Divider()
                Button("Kill Session") { onKill() }
            } else {
                Button("Launch") { onLaunch() }
            }
        }
    }
}
