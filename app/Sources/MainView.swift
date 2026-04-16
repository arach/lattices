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

    var body: some View {
        VStack(spacing: 0) {
            mainContent
        }
        .frame(
            minWidth: layout == .popover ? 380 : 0,
            idealWidth: layout == .popover ? 380 : nil,
            maxWidth: .infinity,
            minHeight: layout == .popover ? 520 : 0,
            idealHeight: layout == .popover ? 560 : nil,
            maxHeight: .infinity
        )
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            let tTotal = DiagnosticLog.shared.startTimed("MainView.onAppear (total)")
            if needsSetup && !hasCheckedSetup {
                hasCheckedSetup = true
                SettingsWindowController.shared.show()
            }
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
                    headerButton(icon: "terminal") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        ScreenMapWindowController.shared.showPage(.pi)
                    }
                    headerButton(icon: "arrow.up.left.and.arrow.down.right") {
                        (NSApp.delegate as? AppDelegate)?.dismissPopover()
                        ScreenMapWindowController.shared.showPage(.home)
                    }
                    headerButton(icon: "arrow.clockwise") { scanner.scan(); inventory.refresh() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }

            // Layer switcher
            if let config = workspace.config, let layers = config.layers, layers.count > 1 {
                layerBar(config: config)
            }

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

            // Permission banner
            if !permChecker.allGranted && !bannerDismissed {
                permissionBanner
            }

            // tmux not-found banner
            if !tmuxModel.isAvailable && !tmuxBannerDismissed {
                tmuxBanner
            }

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            // List
            if filtered.isEmpty && (workspace.config?.groups ?? []).isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        // Tab groups section
                        if let groups = workspace.config?.groups, !groups.isEmpty, searchText.isEmpty {
                            ForEach(groups) { group in
                                TabGroupRow(group: group, workspace: workspace)
                            }

                            if !filtered.isEmpty {
                                Rectangle()
                                    .fill(Palette.border)
                                    .frame(height: 0.5)
                                    .padding(.vertical, 4)
                            }
                        }

                        // Projects
                        ForEach(filtered) { project in
                            ProjectRow(project: project) {
                                SessionManager.launch(project: project)
                            } onDetach: {
                                SessionManager.detach(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scanner.refreshStatus()
                                }
                            } onKill: {
                                SessionManager.kill(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scanner.refreshStatus()
                                }
                            } onSync: {
                                SessionManager.sync(project: project)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    scanner.refreshStatus()
                                }
                            } onRestart: { paneName in
                                SessionManager.restart(project: project, paneName: paneName)
                            }
                        }

                        // Orphan sessions
                        if !filteredOrphans.isEmpty {
                            orphanSection
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
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
                label: "Command Palette",
                detail: "Launch, attach, and control projects",
                hotkeyTokens: hotkeyTokens(.palette),
                icon: "command",
                accentColor: Palette.running
            ) {
                CommandPaletteWindow.shared.toggle()
            }
            ActionRow(
                label: "Workspace",
                detail: "Screen map, inventory, and window context",
                hotkeyTokens: hotkeyTokens(.unifiedWindow),
                icon: "square.grid.2x2",
                accentColor: Palette.text
            ) {
                ScreenMapWindowController.shared.showPage(.home)
            }
            ActionRow(
                label: "Assistant",
                detail: "Search now, or use voice when you need it",
                hotkeyTokens: hotkeyTokens(.omniSearch),
                icon: "magnifyingglass",
                accentColor: AudioLayer.shared.isListening ? Palette.running : Palette.textDim
            ) {
                showAssistant()
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

    private func showAssistant() {
        if AudioLayer.shared.isListening || VoiceCommandWindow.shared.isVisible {
            VoiceCommandWindow.shared.toggle()
            return
        }

        OmniSearchWindow.shared.show()
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

    // MARK: - Layer Bar

    private func layerBar(config: WorkspaceConfig) -> some View {
        HStack(spacing: 6) {
            ForEach(Array((config.layers ?? []).enumerated()), id: \.element.id) { i, layer in
                let isActive = i == workspace.activeLayerIndex
                let counts = workspace.layerRunningCount(index: i)
                Button {
                    workspace.tileLayer(index: i)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isActive ? Palette.running : Palette.textMuted.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(layer.label)
                                .font(Typo.mono(11))
                                .foregroundColor(isActive ? Palette.text : Palette.textDim)
                            if counts.total > 0 {
                                Text("\(counts.running)/\(counts.total)")
                                    .font(Typo.mono(8))
                                    .foregroundColor(counts.running > 0 ? Palette.running : Palette.textMuted)
                            }
                        }
                        Text("\u{2325}\(i + 1)")
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isActive ? Palette.running.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(isActive ? Palette.running.opacity(0.3) : Palette.border, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(workspace.isSwitching)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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
}
