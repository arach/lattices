import SwiftUI

struct MainView: View {
    @ObservedObject var scanner: ProjectScanner
    @StateObject private var prefs = Preferences.shared
    @StateObject private var permChecker = PermissionChecker.shared
    @ObservedObject private var workspace = WorkspaceManager.shared
    @StateObject private var inventory = InventoryManager.shared
    @State private var searchText = ""
    @State private var hasCheckedSetup = false
    @State private var bannerDismissed = false
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
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 600, minHeight: 460, idealHeight: 460, maxHeight: .infinity)
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .onAppear {
            if needsSetup && !hasCheckedSetup {
                hasCheckedSetup = true
                SettingsWindow.open(prefs: prefs, scanner: scanner)
            }
            scanner.updateRoot(prefs.scanRoot)
            scanner.scan()
            inventory.refresh()
            permChecker.check()
            bannerDismissed = false
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("lattice")
                    .font(Typo.title())
                    .foregroundColor(Palette.text)

                if runningCount > 0 || !inventory.orphans.isEmpty {
                    let total = runningCount + inventory.orphans.count
                    Text("\(total) session\(total == 1 ? "" : "s")")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.running)
                        .padding(.leading, 4)
                } else {
                    Text("None")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .padding(.leading, 4)
                }

                Spacer()

                headerButton(icon: "arrow.up.left.and.arrow.down.right") {
                    // Dismiss the MenuBarExtra panel immediately
                    for window in NSApp.windows {
                        if window is NSPanel, window.isVisible,
                           !CommandPaletteWindow.shared.isVisible || window.frame.width < 500 {
                            // MenuBarExtra panels are small (~380px); command palette is 540px
                            if window.frame.width <= 400 {
                                window.orderOut(nil)
                            }
                        }
                    }
                    MainWindow.shared.show()
                }
                headerButton(icon: "arrow.clockwise") { scanner.scan(); inventory.refresh() }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

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

            // Status bar
            statusBar
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

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            // Settings button
            Button { SettingsWindow.open(prefs: prefs, scanner: scanner) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Diagnostics toggle
            Button { DiagnosticWindow.shared.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DiagnosticWindow.shared.isVisible ? Palette.running : Palette.textMuted)
                    if !permChecker.allGranted {
                        Circle()
                            .fill(Palette.detach)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(!permChecker.allGranted ? "Permissions missing — open diagnostics" : "Toggle diagnostics")

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5, height: 12)
                .padding(.horizontal, 8)

            // Config summary — keys dim, values white
            statusLine

            Spacer()

            // Palette hint
            Text("\u{2318}\u{21E7}M")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
                .help("Command palette (Cmd+Shift+M)")

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5, height: 12)
                .padding(.horizontal, 6)

            // Quit
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Quit lattice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.surface.opacity(0.4))
    }

    private var statusLine: some View {
        HStack(spacing: 3) {
            statusPair("terminal", prefs.terminal.rawValue.lowercased())
            statusDot
            statusPair("mode", prefs.mode.rawValue)
            statusDot
            statusPair("home", "~/\((prefs.scanRoot as NSString).lastPathComponent)")
        }
    }

    private func statusPair(_ key: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(key + ":")
                .font(Typo.mono(9))
                .foregroundColor(Palette.textMuted)
            Text(value)
                .font(Typo.mono(9))
                .foregroundColor(Palette.text)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(Palette.textMuted)
            .frame(width: 2, height: 2)
            .padding(.horizontal, 4)
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

            Text("Run  lattice init  in a project\nto add it here")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
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
            permissionRow("Screen Recording", granted: permChecker.screenRecording) {
                permChecker.requestScreenRecording()
            }

            Text("Click a row to request access.")
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
                    workspace.focusLayer(index: i)
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
