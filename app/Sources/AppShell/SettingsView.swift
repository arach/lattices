import DeckKit
import SwiftUI

/// Settings content with internal General / Shortcuts tabs.
/// Can also render the Docs page when `page == .docs`.
struct SettingsContentView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case companion
        case ai
        case search
        case shortcuts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .companion: return "Companion"
            case .ai: return "AI"
            case .search: return "Search & OCR"
            case .shortcuts: return "Shortcuts"
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .companion: return "ipad.and.iphone"
            case .ai: return "sparkles"
            case .search: return "text.viewfinder"
            case .shortcuts: return "command"
            }
        }

        var eyebrow: String {
            switch self {
            case .general: return "Workspace"
            case .companion: return "Local Bridge"
            case .ai: return "Agents"
            case .search: return "Indexing"
            case .shortcuts: return "Controls"
            }
        }

        var summary: String {
            switch self {
            case .general:
                return "Terminal defaults, scan roots, window snapping, and app updates."
            case .companion:
                return "Local-network pairing, trusted iPad devices, and bridge security."
            case .ai:
                return "Claude CLI detection plus advisor model and spending controls."
            case .search:
                return "OCR cadence, quality, and recent capture visibility."
            case .shortcuts:
                return "A full map of global hotkeys for workspace movement and tmux flow."
            }
        }
    }

    var page: AppPage = .settings
    @ObservedObject var prefs: Preferences
    @ObservedObject var scanner: ProjectScanner
    @ObservedObject var hotkeyStore: HotkeyStore = .shared
    @ObservedObject var workspaceManager: WorkspaceManager = .shared
    @ObservedObject var appUpdater: AppUpdater = .shared
    @ObservedObject var mouseShortcutStore: MouseShortcutStore = .shared
    @ObservedObject var keyboardRemapStore: KeyboardRemapStore = .shared
    @ObservedObject var permChecker: PermissionChecker = .shared
    @ObservedObject var mouseGestureController: MouseGestureController = .shared
    @ObservedObject var keyboardRemapController: KeyboardRemapController = .shared
    var onBack: (() -> Void)? = nil

    @State private var selectedTab: SettingsSection = .general

    var body: some View {
        VStack(spacing: 0) {
            // Back bar
            backBar

            if page == .docs {
                docsContent
            } else {
                settingsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background(PanelBackground())
        .onAppear {
            permChecker.check()
            if page == .companionSettings {
                selectedTab = .companion
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .latticesShowAssistantSettings)) { _ in
            selectedTab = .ai
        }
    }

    // MARK: - Back Bar

    private var currentTabLabel: String {
        page == .docs ? "Docs" : selectedTab.title
    }

    private var snapModifierBinding: Binding<SnapModifierKey> {
        Binding(
            get: { workspaceManager.snapZonesConfig.modifier ?? .command },
            set: { workspaceManager.updateSnapModifier($0) }
        )
    }

    private var backBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let onBack {
                    Button {
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }

                Text(page == .docs ? "Docs" : currentTabLabel)
                    .font(Typo.heading(13))
                    .foregroundColor(Palette.text)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle().fill(Palette.border).frame(height: 0.5)
        }
    }

    // MARK: - Settings Body

    private var settingsBody: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 220, alignment: .top)

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5)
                .frame(maxHeight: .infinity)

            VStack(spacing: 0) {
                settingsSectionHero(selectedTab)

                Rectangle().fill(Palette.border).frame(height: 0.5)

                selectedSectionContent
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS")
                    .font(Typo.pixel(14))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)
                Text("Tune how Lattices launches workspaces, listens for commands, and navigates the desktop.")
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    settingsTab(section)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func settingsTab(_ section: SettingsSection) -> some View {
        let active = selectedTab == section
        return Button {
            selectedTab = section
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(active ? Palette.text : Palette.textMuted)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(Typo.mono(11))
                        .foregroundColor(active ? Palette.text : Palette.textMuted)

                    Text(section.summary)
                        .font(Typo.caption(9.5))
                        .foregroundColor(Palette.textMuted.opacity(active ? 0.9 : 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                ZStack {
                    if active {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsSectionHero(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.eyebrow.uppercased())
                .font(Typo.pixel(14))
                .foregroundColor(Palette.textDim)
                .tracking(1)

            Text(section.title)
                .font(Typo.heading(16))
                .foregroundColor(Palette.text)

            Text(section.summary)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Palette.bg)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .companion:
            companionContent
        case .ai:
            aiContent
        case .search:
            searchOcrContent
        case .shortcuts:
            shortcutsContent
        }
    }

    // MARK: - Sticky section header

    private func stickyHeader(_ title: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(Typo.pixel(14))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Palette.bg)

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
    }

    // MARK: - General

    private var permissionsAssistantCard: some View {
        let missing = Capability.allCases.filter { !$0.isGranted }
        return settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(missing.isEmpty ? Palette.running : Palette.detach)
                    Text("Permissions")
                        .font(Typo.mono(12))
                        .foregroundColor(Palette.text)
                    Spacer()
                    Text(missing.isEmpty ? "All on" : "\(missing.count) off")
                        .font(Typo.caption(10))
                        .foregroundColor(missing.isEmpty ? Palette.running : Palette.detach)
                }

                Text("The Permissions Assistant introduces each capability before any macOS prompt. Open it any time to review status or enable something new.")
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)

                HStack(spacing: 8) {
                    ForEach(Capability.allCases) { cap in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cap.isGranted ? Palette.running : Palette.detach)
                                .frame(width: 5, height: 5)
                            Text(cap.title)
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.textMuted)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Palette.surface)
                        )
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    PermissionsAssistantWindowController.shared.show(focus: missing.first)
                } label: {
                    Text(missing.isEmpty ? "Open Permissions Assistant" : "Set up permissions")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.surfaceHov)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                permissionsAssistantCard

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Palette.running)
                            Text("Lattices app")
                                .font(Typo.mono(12))
                                .foregroundColor(Palette.text)
                            buildChannelBadge
                            Spacer()
                            Text("Current \(appUpdater.currentDisplayVersion)")
                                .font(Typo.caption(10))
                                .foregroundColor(Palette.textMuted)
                        }

                        Text("Lattices can check for new signed releases and prepare the update here. You’ll confirm before the app quits and relaunches.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)

                        HStack(spacing: 6) {
                            Image(systemName: LatticesRuntime.isDevBuild ? "hammer.fill" : "checkmark.seal.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(LatticesRuntime.isDevBuild ? Palette.running : Palette.textMuted)
                            Text(LatticesRuntime.buildStatusLabel)
                                .font(Typo.monoBold(9))
                                .foregroundColor(LatticesRuntime.isDevBuild ? Palette.running.opacity(0.9) : Palette.textMuted.opacity(0.9))
                            if let revision = LatticesRuntime.buildRevision {
                                Text(revision)
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.75))
                            }
                            Spacer()
                        }

                        if let update = appUpdater.availableUpdate {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gift.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Palette.detach)
                                    Text("New version v\(update.version) is ready")
                                        .font(Typo.monoBold(10))
                                        .foregroundColor(Palette.detach)
                                }

                                if !update.releaseNotes.isEmpty {
                                    Text(String(update.releaseNotes.prefix(180)) + (update.releaseNotes.count > 180 ? "..." : ""))
                                        .font(Typo.caption(9))
                                        .foregroundColor(Palette.textMuted)
                                        .lineLimit(3)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Palette.surfaceHov.opacity(0.65))
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.detach.opacity(0.35), lineWidth: 0.5))
                            )
                        } else if appUpdater.isChecking {
                            Text("Checking for updates...")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted)
                        } else if let error = appUpdater.lastError {
                            Text(error)
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.detach.opacity(0.9))
                        } else if let checked = appUpdater.lastChecked {
                            Text("Last checked \(checked, style: .relative)")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.8))
                        }

                        if let status = appUpdater.statusMessage {
                            Text(status)
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.running.opacity(0.85))
                        }

                        if let reason = appUpdater.unavailableReason {
                            Text(reason)
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.detach.opacity(0.9))
                        }

                        HStack(spacing: 10) {
                            Button {
                                appUpdater.promptForUpdate()
                            } label: {
                                Text(appUpdater.isUpdating ? "Preparing…" : (appUpdater.availableUpdate == nil ? "Check for Updates" : "Update to v\(appUpdater.availableUpdate?.version ?? "")"))
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(appUpdater.isUpdating)

                            Button {
                                Task { await appUpdater.check() }
                            } label: {
                                Text(appUpdater.isChecking ? "Checking..." : "Check Now")
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .disabled(appUpdater.isChecking)

                            Toggle("Auto", isOn: $appUpdater.autoCheckEnabled)
                                .font(Typo.caption(9))
                                .toggleStyle(.checkbox)
                                .foregroundColor(Palette.textMuted.opacity(0.9))

                            if appUpdater.availableUpdate != nil {
                                Button {
                                    appUpdater.viewCurrentRelease()
                                } label: {
                                    Text("Release Notes")
                                        .font(Typo.caption(9))
                                        .foregroundColor(Palette.textMuted.opacity(0.9))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    appUpdater.skipCurrentUpdate()
                                } label: {
                                    Text("Skip")
                                        .font(Typo.caption(9))
                                        .foregroundColor(Palette.textMuted.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Text("CLI: `lattices app update`")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.8))
                        }
                    }
                }

                // ── Terminal ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminal")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        Picker("", selection: $prefs.terminal) {
                            ForEach(Terminal.installed) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text("Used for attaching to tmux sessions")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                    }
                }

                // ── tmux ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("tmux")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        // Mode
                        HStack {
                            Text("Detach mode")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Picker("", selection: $prefs.mode) {
                                Text("Learning").tag(InteractionMode.learning)
                                Text("Auto").tag(InteractionMode.auto)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Text(prefs.mode == .learning
                            ? "Shows keybinding hints on detach"
                            : "Detaches sessions silently")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        // Project scan root
                        Text("Project scan root")
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textDim)

                        HStack(spacing: 6) {
                            TextField("~/dev", text: $prefs.scanRoot)
                                .textFieldStyle(.plain)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                )

                            Button {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                if !prefs.scanRoot.isEmpty {
                                    panel.directoryURL = URL(fileURLWithPath: prefs.scanRoot)
                                }
                                if panel.runModal() == .OK, let url = panel.url {
                                    prefs.scanRoot = url.path
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                                    .foregroundColor(Palette.textDim)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Color.white.opacity(0.06))
                                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Text("Scans for .lattices.json project configs")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.7))
                            Spacer()
                            Button {
                                scanner.updateRoot(prefs.scanRoot)
                                scanner.scan()
                            } label: {
                                Text("Rescan")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: permChecker.allGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(permChecker.allGranted ? Palette.running : Palette.detach)
                            Text("Permissions")
                                .font(Typo.mono(12))
                                .foregroundColor(Palette.text)
                            Spacer()
                            Button {
                                permChecker.check()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Palette.textDim)
                                    .frame(width: 24, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh permission status")
                        }

                        Text("Lattices uses macOS privacy permissions for window discovery, tiling, gestures, remaps, and synthetic shortcuts.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)

                        VStack(alignment: .leading, spacing: 6) {
                            permissionSettingsRow(
                                "Accessibility",
                                granted: permChecker.accessibility,
                                detail: "Required for mouse gestures, keyboard remaps, window movement, and focusing windows."
                            ) {
                                permChecker.requestAccessibility()
                            }

                            permissionSettingsRow(
                                "Screen Recording",
                                granted: permChecker.screenRecording,
                                detail: "Required for reliable window titles, OCR, and Space-aware window discovery."
                            ) {
                                permChecker.requestScreenRecording()
                            }

                            permissionReviewRow(
                                "Automation",
                                detail: "Needed when Lattices sends shortcuts through System Events, including gesture-triggered dictation."
                            ) {
                                permChecker.openAutomationSettings()
                            }

                            permissionReviewRow(
                                "Input Monitoring",
                                detail: "Useful to review if global input capture or synthetic shortcut behavior starts failing."
                            ) {
                                permChecker.openInputMonitoringSettings()
                            }
                        }
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Window drag snap")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack {
                            Text("Drag-to-snap")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Toggle("", isOn: $prefs.dragSnapEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        HStack {
                            Text("Snap modifier")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Picker("", selection: snapModifierBinding) {
                                ForEach(SnapModifierKey.allCases) { modifier in
                                    Text(modifier.shortLabel).tag(modifier)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        Text("Dragging stays normal until you hold \(snapModifierBinding.wrappedValue.label). While that key is down, Lattices reveals snap targets and a live preview for the window you’re moving.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        Text("Advanced landing-zone rules still live in ~/.lattices/snap-zones.json. Modifier changes here take effect on the next drag.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mouse gestures")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack {
                            Text("Middle-click gestures")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Toggle("", isOn: $prefs.mouseGesturesEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        Text("Rules live in ~/.lattices/mouse-shortcuts.json. The current defaults preserve the working setup: middle-click drag left/right switches Spaces and drag down opens the Screen Map overview.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active drag mappings")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)

                            ForEach(mouseShortcutStore.summaryLines.prefix(4), id: \.self) { line in
                                Text(line)
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.78))
                            }

                            if mouseShortcutStore.summaryLines.isEmpty {
                                Text("No active mappings")
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.6))
                            }
                        }

                        breakerStatusRow(
                            state: mouseGestureController.breakerState,
                            label: "Mouse gestures"
                        ) {
                            mouseGestureController.reArmAfterBreakerTrip()
                        }

                        HStack(spacing: 8) {
                            Button {
                                mouseShortcutStore.openConfiguration()
                            } label: {
                                Text("Configure...")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                MouseInputEventViewer.shared.show()
                            } label: {
                                Text("Open Event Viewer")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                mouseShortcutStore.restoreDefaults()
                            } label: {
                                Text("Restore Defaults")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Use Event Viewer to discover what your mouse emits on this machine. The config schema already accepts device selectors, but live gesture matching currently falls back to global rules when macOS doesn't expose the source device.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))
                    }
                }

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Keyboard remaps")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack {
                            Text("Caps Lock as Hyper")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Toggle("", isOn: $prefs.keyboardRemapsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        Text("Rules live in ~/.lattices/keyboard-remaps.json. The default maps hold Caps Lock to Hyper and tap Caps Lock to Escape, so the existing Hyper shortcuts work on the laptop keyboard.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active remaps")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)

                            ForEach(keyboardRemapStore.summaryLines.prefix(4), id: \.self) { line in
                                Text(line)
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.78))
                            }

                            if keyboardRemapStore.summaryLines.isEmpty {
                                Text("No active remaps")
                                    .font(Typo.caption(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.6))
                            }
                        }

                        breakerStatusRow(
                            state: keyboardRemapController.breakerState,
                            label: "Keyboard remaps"
                        ) {
                            keyboardRemapController.reArmAfterBreakerTrip()
                        }

                        HStack(spacing: 8) {
                            Button {
                                keyboardRemapStore.openConfiguration()
                            } label: {
                                Text("Configure...")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                keyboardRemapStore.restoreDefaults()
                            } label: {
                                Text("Restore Defaults")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Companion

    private var companionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                companionBridgeOverviewCard
                companionTrustedDevicesCard

                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Input")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trackpad proxy")
                                    .font(Typo.mono(10))
                                    .foregroundColor(Palette.textDim)
                                Text("Allow paired companions with the input.trackpad grant to move the Mac pointer through the encrypted bridge.")
                                    .font(Typo.caption(9.5))
                                    .foregroundColor(Palette.textMuted.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Toggle("", isOn: $prefs.companionTrackpadEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .disabled(!prefs.companionBridgeEnabled)
                                .opacity(prefs.companionBridgeEnabled ? 1 : 0.45)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var companionBridgeOverviewCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.running.opacity(0.14))
                        .overlay(
                            Image(systemName: "lock.shield")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Palette.running)
                        )
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(prefs.companionBridgeEnabled ? "Secure local bridge" : "Local bridge off")
                            .font(Typo.mono(12))
                            .foregroundColor(Palette.text)
                        Text(prefs.companionBridgeEnabled
                            ? "Bonjour discovery with explicit Mac approval, signed requests, encrypted payloads, and capability grants."
                            : "The companion bridge is not listening or advertising on the local network until you turn it on.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $prefs.companionBridgeEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                cardDivider

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading),
                        GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading),
                        GridItem(.flexible(minimum: 120), spacing: 10, alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    companionBridgeFact(
                        label: "Status",
                        value: prefs.companionBridgeEnabled ? "enabled" : "off"
                    )
                    companionBridgeFact(
                        label: "Port",
                        value: String(LatticesCompanionBridgeServer.defaultPort)
                    )
                    companionBridgeFact(
                        label: "Protocol",
                        value: "v\(LatticesCompanionBridgeServer.protocolVersion)"
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Enable deep link")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                    Text("lattices://companion/enable")
                        .font(Typo.monoBold(12))
                        .foregroundColor(Palette.text)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shortcutsInsetPanel)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Mac bridge fingerprint")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                    Text(LatticesCompanionSecurityCoordinator.shared.bridgeFingerprint)
                        .font(Typo.monoBold(13))
                        .foregroundColor(Palette.text)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shortcutsInsetPanel)

                HStack(spacing: 6) {
                    ForEach(DeckBridgeCapability.defaultCompanionCapabilities, id: \.self) { capability in
                        companionCapabilityBadge(capability)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var companionTrustedDevicesCard: some View {
        let trustedDevices = companionTrustedDevices(revision: companionTrustRevision)

        return settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paired devices")
                            .font(Typo.mono(12))
                            .foregroundColor(Palette.text)
                        Text("Only trusted devices can call protected deck and input routes. Pairing grants are listed per device.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            companionTrustRevision += 1
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Palette.textDim)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Palette.surfaceHov)
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)

                        if trustedDevices.isEmpty == false {
                            Button {
                                guard confirmForgetTrustedDevices() else { return }
                                LatticesCompanionSecurityCoordinator.shared.clearTrustedDevices()
                                companionTrustRevision += 1
                            } label: {
                                Text("Forget All")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.kill.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(Palette.kill.opacity(0.10))
                                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.kill.opacity(0.22), lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if trustedDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "ipad.and.iphone")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Palette.textMuted)

                        Text("No paired iPad or iPhone devices yet.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)

                        Text("Open the Lattices companion app on your iPad and select this Mac. You’ll approve the pairing prompt here.")
                            .font(Typo.caption(9.5))
                            .foregroundColor(Palette.textMuted.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(shortcutsInsetPanel)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(trustedDevices) { device in
                            companionDeviceRow(device)
                        }
                    }
                }
            }
        }
    }

    private func companionBridgeFact(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(Typo.pixel(11))
                .foregroundColor(Palette.textDim)
                .tracking(1)
            Text(value)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shortcutsInsetPanel)
    }

    private func companionDeviceRow(_ device: DeckTrustedDeviceSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surfaceHov)
                .overlay(
                    Image(systemName: companionDeviceIcon(for: device.name))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.textDim)
                )
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(device.name)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)
                        .lineLimit(1)

                    Text(device.fingerprint)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("Paired \(relativeTimestamp(device.pairedAt))")
                    Text("Last seen \(relativeTimestamp(device.lastSeenAt))")
                }
                .font(Typo.caption(9.5))
                .foregroundColor(Palette.textMuted.opacity(0.78))

                HStack(spacing: 6) {
                    ForEach(device.capabilities, id: \.self) { capability in
                        companionCapabilityBadge(capability)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                guard confirmRevokeTrustedDevice(device) else { return }
                LatticesCompanionSecurityCoordinator.shared.revokeTrustedDevice(id: device.id)
                companionTrustRevision += 1
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "xmark.shield")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Revoke")
                        .font(Typo.monoBold(9.5))
                }
                .foregroundColor(Palette.kill.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.kill.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.kill.opacity(0.22), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .help("Revoke this paired device")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shortcutsInsetPanel)
    }

    private func companionCapabilityBadge(_ capability: String) -> some View {
        Text(companionCapabilityLabel(capability))
            .font(Typo.monoBold(9))
            .foregroundColor(Palette.running.opacity(0.92))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Palette.running.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Palette.running.opacity(0.18), lineWidth: 0.5))
            )
    }

    private func companionCapabilityLabel(_ capability: String) -> String {
        switch capability {
        case DeckBridgeCapability.deckRead:
            return "Deck Read"
        case DeckBridgeCapability.deckPerform:
            return "Deck Actions"
        case DeckBridgeCapability.inputTrackpad:
            return "Trackpad"
        default:
            return capability
        }
    }

    private func companionDeviceIcon(for name: String) -> String {
        name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone"
    }

    private func confirmForgetTrustedDevices() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Forget all paired companion devices?"
        alert.informativeText = "Your iPad or iPhone will need to pair again before it can control Lattices."
        alert.addButton(withTitle: "Forget Devices")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRevokeTrustedDevice(_ device: DeckTrustedDeviceSummary) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Revoke \(device.name)?"
        alert.informativeText = """
        This removes the paired-device trust record for \(device.name).

        Fingerprint: \(device.fingerprint)

        The device will need to pair again before it can control Lattices.
        """
        alert.addButton(withTitle: "Revoke Device")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - AI

    private var aiContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Claude CLI ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Palette.running)
                            Text("Claude CLI")
                                .font(Typo.mono(12))
                                .foregroundColor(Palette.text)
                        }

                        HStack(spacing: 6) {
                            TextField("Auto-detected", text: $prefs.claudePath)
                                .textFieldStyle(.plain)
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                )

                            Button {
                                if let resolved = Preferences.resolveClaudePath() {
                                    prefs.claudePath = resolved
                                }
                            } label: {
                                Text("Detect")
                                    .font(Typo.monoBold(10))
                                    .foregroundColor(Palette.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Palette.surfaceHov)
                                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        let resolved = Preferences.resolveClaudePath()
                        if let path = resolved {
                            Text("Found: \(path)")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.running.opacity(0.8))
                        } else {
                            Text("Not found — install with: npm i -g @anthropic-ai/claude-code")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.detach)
                        }
                    }
                }

                // ── Advisor ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Voice advisor")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

                        HStack {
                            Text("Model")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            Picker("", selection: $prefs.advisorModel) {
                                Text("Haiku").tag("haiku")
                                Text("Sonnet").tag("sonnet")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        Text("Haiku is fast and cheap. Sonnet is smarter but slower.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        HStack {
                            Text("Budget per session")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("$")
                                    .font(Typo.mono(11))
                                    .foregroundColor(Palette.textDim)
                                TextField("0.50", value: $prefs.advisorBudgetUSD, formatter: {
                                    let f = NumberFormatter()
                                    f.numberStyle = .decimal
                                    f.minimumFractionDigits = 2
                                    f.maximumFractionDigits = 2
                                    return f
                                }())
                                .textFieldStyle(.plain)
                                .font(Typo.monoBold(11))
                                .foregroundColor(Palette.text)
                                .multilineTextAlignment(.center)
                                .frame(width: 50)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                                )
                            }
                        }

                        Text("Max spend per Claude CLI invocation")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        // Session stats
                        let stats = AgentPool.shared.haiku.sessionStats
                        HStack(spacing: 12) {
                            if stats.contextWindow > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(stats.contextUsage > 0.6 ? Palette.detach : Palette.running)
                                        .frame(width: 5, height: 5)
                                    Text("Context: \(Int(stats.contextUsage * 100))%")
                                        .font(Typo.mono(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                            if stats.costUSD > 0 {
                                Text("Session cost: $\(String(format: "%.3f", stats.costUSD))")
                                    .font(Typo.mono(10))
                                    .foregroundColor(Palette.textMuted)
                            }

                            Spacer()

                            let learningCount = AdvisorLearningStore.shared.entryCount
                            if learningCount > 0 {
                                Text("\(learningCount) learned")
                                    .font(Typo.mono(9))
                                    .foregroundColor(Palette.textMuted.opacity(0.6))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var buildChannelBadge: some View {
        let tint = LatticesRuntime.isDevBuild ? Palette.detach : Palette.running

        return Text(LatticesRuntime.buildChannelLabel)
            .font(Typo.monoBold(9))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    // MARK: - Search & OCR

    private func ocrNumField(_ value: Binding<Double>, width: CGFloat = 50) -> some View {
        TextField("", value: value, formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .font(Typo.monoBold(11))
            .foregroundColor(Palette.text)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }

    private func ocrIntField(_ value: Binding<Int>, width: CGFloat = 36) -> some View {
        TextField("", value: value, formatter: NumberFormatter())
            .textFieldStyle(.plain)
            .font(Typo.monoBold(11))
            .foregroundColor(Palette.text)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }

    private func ocrSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Typo.monoBold(10))
            .foregroundColor(Palette.textDim)
            .tracking(0.5)
    }

    private var searchOcrContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Screen Text Recognition Card ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        // Header row: label + toggle
                        HStack {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(prefs.ocrEnabled ? Palette.running.opacity(0.15) : Palette.surface)
                                    .overlay(
                                        Image(systemName: "text.viewfinder")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(prefs.ocrEnabled ? Palette.running : Palette.textMuted)
                                    )
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Screen text recognition")
                                        .font(Typo.mono(12))
                                        .foregroundColor(Palette.text)
                                    Text("Vision OCR on visible windows")
                                        .font(Typo.caption(10))
                                        .foregroundColor(Palette.textMuted)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { prefs.ocrEnabled },
                                set: { OcrModel.shared.setEnabled($0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }

                        // Accuracy
                        HStack(spacing: 8) {
                            Text("Accuracy")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)
                            Picker("", selection: $prefs.ocrAccuracy) {
                                Text("Accurate").tag("accurate")
                                Text("Fast").tag("fast")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 140)
                            Spacer()
                        }
                        .padding(.leading, 32)
                    }
                }

                // ── Scan Schedule Card ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ocrSectionLabel("Schedule")

                        // Quick scan sentence
                        HStack(spacing: 0) {
                            Text("Quick scan top ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrQuickLimit, width: 32)
                            Text(" windows every ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrNumField($prefs.ocrQuickInterval, width: 42)
                            Text("s")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        cardDivider

                        // Deep scan sentence
                        HStack(spacing: 0) {
                            Text("Deep scan up to ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrDeepLimit, width: 32)
                            Text(" windows every ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrNumField($prefs.ocrDeepInterval, width: 52)
                            Text("s")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        HStack(spacing: 0) {
                            Text("OCR budget: ")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            ocrIntField($prefs.ocrDeepBudget, width: 32)
                            Text(" windows per scan")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                            Spacer()
                        }

                        // Human-readable deep interval
                        let h = Int(prefs.ocrDeepInterval / 3600)
                        let m = Int(prefs.ocrDeepInterval.truncatingRemainder(dividingBy: 3600) / 60)
                        if h > 0 || m > 0 {
                            Text("≈ \(h > 0 ? "\(h)h" : "")\(m > 0 ? " \(m)m" : "")")
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.6))
                                .padding(.leading, 2)
                        }
                    }
                }

                // ── Status Card ──
                settingsCard {
                    HStack(spacing: 8) {
                        let ocrResults = OcrModel.shared.results
                        let isScanning = OcrModel.shared.isScanning

                        Circle()
                            .fill(isScanning ? Palette.detach : (prefs.ocrEnabled ? Palette.running : Palette.textMuted))
                            .frame(width: 6, height: 6)

                        Text(isScanning ? "Scanning..." : (prefs.ocrEnabled ? "\(ocrResults.count) windows cached" : "Disabled"))
                            .font(Typo.mono(10))
                            .foregroundColor(Palette.textMuted)

                        Spacer()

                        Button {
                            OcrModel.shared.scan()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Scan Now")
                                    .font(Typo.monoBold(10))
                            }
                            .foregroundColor(prefs.ocrEnabled ? Palette.text : Palette.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(prefs.ocrEnabled ? Palette.surfaceHov : Palette.surface)
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!prefs.ocrEnabled)
                    }
                }

                // ── Recent Captures ──
                recentCapturesSection
            }
            .padding(16)
        }
    }

    // MARK: - Recent Captures Browser

    private var recentCapturesSection: some View {
        let ocrResults = OcrModel.shared.results
        let grouped = Dictionary(grouping: ocrResults.values, by: \.app)
            .sorted { $0.value.count > $1.value.count }

        return Group {
            if !grouped.isEmpty {
                settingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ocrSectionLabel("Recent Captures")

                        ForEach(grouped, id: \.key) { app, windows in
                            ocrAppGroup(app: app, windows: windows.sorted { $0.timestamp > $1.timestamp })
                        }
                    }
                }
            }
        }
    }

    private func ocrAppGroup(app: String, windows: [OcrWindowResult]) -> some View {
        let isCollapsed = collapsedOcrApps.contains(app)

        return VStack(alignment: .leading, spacing: 0) {
            // App header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isCollapsed {
                        collapsedOcrApps.remove(app)
                    } else {
                        collapsedOcrApps.insert(app)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 10)

                    Text(app)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)

                    Text("(\(windows.count))")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)

                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(windows, id: \.wid) { win in
                        ocrWindowRow(win)
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private func ocrWindowRow(_ win: OcrWindowResult) -> some View {
        let isExpanded = expandedOcrWindow == win.wid
        let preview = String(win.fullText.prefix(80)).replacingOccurrences(of: "\n", with: " ")

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedOcrWindow = isExpanded ? nil : win.wid
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                        .frame(width: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(win.title.isEmpty ? "Untitled" : win.title)
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.text)
                                .lineLimit(1)

                            Spacer()

                            Text(ocrRelativeTime(win.timestamp))
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted)
                        }

                        if !isExpanded && !preview.isEmpty {
                            Text(preview)
                                .font(Typo.caption(9))
                                .foregroundColor(Palette.textMuted.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ocrExpandedDetail(win)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
            }
        }
    }

    private func ocrExpandedDetail(_ win: OcrWindowResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Metadata row
            HStack(spacing: 10) {
                let avgConfidence = win.texts.isEmpty ? 0 : win.texts.map(\.confidence).reduce(0, +) / Float(win.texts.count)
                Text("\(win.texts.count) blocks")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Text("confidence: \(String(format: "%.0f%%", avgConfidence * 100))")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }

            // Full text in scrollable monospaced area
            ScrollView {
                Text(win.fullText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Palette.textDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 150)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
    }

    private func ocrRelativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    // MARK: - Settings Card

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass()
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.03), Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .padding(.vertical, 3)
    }

    private func permissionSettingsRow(
        _ title: String,
        granted: Bool,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if granted {
                permChecker.check()
            } else {
                action()
            }
        } label: {
            permissionRowContent(
                title,
                status: granted ? "granted" : "not set",
                statusColor: granted ? Palette.running : Palette.detach,
                icon: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                iconColor: granted ? Palette.running : Palette.detach,
                detail: detail,
                showsExternalLink: !granted
            )
        }
        .buttonStyle(.plain)
        .help(granted ? "Refresh permission status" : "Open macOS permission flow")
    }

    private func permissionReviewRow(
        _ title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            permissionRowContent(
                title,
                status: "review",
                statusColor: Palette.textDim,
                icon: "gearshape.2.fill",
                iconColor: Palette.textDim,
                detail: detail,
                showsExternalLink: true
            )
        }
        .buttonStyle(.plain)
        .help("Open macOS Privacy & Security settings")
    }

    private func permissionRowContent(
        _ title: String,
        status: String,
        statusColor: Color,
        icon: String,
        iconColor: Color,
        detail: String,
        showsExternalLink: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 12, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.text)
                    Text(status)
                        .font(Typo.mono(9))
                        .foregroundColor(statusColor)
                    Spacer()
                    if showsExternalLink {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 9))
                            .foregroundColor(Palette.textMuted)
                    }
                }

                Text(detail)
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Palette.surfaceHov.opacity(status == "not set" ? 0.75 : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(status == "not set" ? Palette.detach.opacity(0.22) : Palette.borderLit.opacity(0.6), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func breakerStatusRow(
        state: EventTapBreaker.State,
        label: String,
        onReArm: @escaping () -> Void
    ) -> some View {
        switch state {
        case .armed:
            EmptyView()
        case .paused(let cooldownSec):
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("\(label) paused — \(cooldownSec)s cooldown")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Spacer()
            }
        case .disabled:
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("\(label) disabled — tap callback exceeded OS budget repeatedly")
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted)
                Spacer()
                Button {
                    onReArm()
                } label: {
                    Text("Re-enable")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.surfaceHov)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Shortcuts

    private var shortcutsContent: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let contentWidth = max(geo.size.width - 40, 320)
                let sectionColumns = [
                    GridItem(.adaptive(minimum: min(320, contentWidth), maximum: 440), spacing: 16, alignment: .top)
                ]
                let tilingColumns = contentWidth > 860
                    ? [
                        GridItem(.flexible(minimum: 280, maximum: 360), spacing: 16, alignment: .top),
                        GridItem(.flexible(minimum: 320, maximum: 640), spacing: 16, alignment: .top)
                    ]
                    : [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16, alignment: .top)]

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 16) {
                            companionCockpitCard

                            shortcutsOverviewCard

                            LazyVGrid(columns: sectionColumns, alignment: .leading, spacing: 16) {
                                shortcutsAppCard
                                shortcutsLayersCard
                            }

                            shortcutSectionCard(
                                title: "Window Tiling",
                                eyebrow: "Desktop Layout",
                                summary: "See the directional map first, then edit the matching global shortcuts below."
                            ) {
                                LazyVGrid(columns: tilingColumns, alignment: .leading, spacing: 16) {
                                    shortcutsTilingVisualizer
                                    shortcutsTilingEditors
                                }
                            }

                            shortcutsTmuxCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }

            Spacer(minLength: 0)

            separator

            HStack {
                HStack(spacing: 8) {
                    footerActionButton(icon: "book", label: "Docs") {
                        ScreenMapWindowController.shared.showPage(.docs)
                    }

                    footerActionButton(icon: "stethoscope", label: "Diagnostics") {
                        DiagnosticWindow.shared.show()
                    }
                }

                Spacer()

                Button {
                    hotkeyStore.resetAll()
                } label: {
                    Text("Reset All to Defaults")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.textDim)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Shortcuts: Overview

    private var companionCockpitCard: some View {
        let layout = LatticesCompanionCockpitCatalog.normalized(prefs.companionCockpitLayout)
        let selectedPage = layout.pages.first(where: { $0.id == selectedCompanionCockpitPageID }) ?? layout.pages.first
        let categories = LatticesCompanionShortcutCategory.allCases
        let trustedDeviceCount = companionTrustedDevices(revision: companionTrustRevision).count

        return shortcutSectionCard(
            title: "Companion Cockpit",
            eyebrow: "iPad & iPhone",
            summary: "Define the Mac-authored command deck here, then let the companion app render it. Trackpad proxy runs through the same bridge."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Trackpad Proxy")
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.text)
                        Text("Enable remote pointer control for the iPad trackpad surface. Accessibility permission is still required on the Mac.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $prefs.companionTrackpadEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!prefs.companionBridgeEnabled)
                        .opacity(prefs.companionBridgeEnabled ? 1 : 0.45)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pairing and trust")
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.text)
                        Text("\(trustedDeviceCount) paired \(trustedDeviceCount == 1 ? "device" : "devices"). Revoke devices and review bridge grants in Companion settings.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        selectedTab = .companion
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "ipad.and.iphone")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Manage")
                                .font(Typo.monoBold(10))
                        }
                        .foregroundColor(Palette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Palette.surfaceHov)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(shortcutsInsetPanel)

                if let selectedPage {
                    Picker("Companion page", selection: $selectedCompanionCockpitPageID) {
                        ForEach(layout.pages) { page in
                            Text(page.title).tag(page.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        if let subtitle = selectedPage.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(Typo.caption(10.5))
                                .foregroundColor(Palette.textMuted)
                        }

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(minimum: 120, maximum: 220), spacing: 8, alignment: .top),
                                count: max(2, selectedPage.columns)
                            ),
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(Array(selectedPage.slotIDs.enumerated()), id: \.offset) { index, shortcutID in
                                companionCockpitSlotMenu(
                                    pageID: selectedPage.id,
                                    index: index,
                                    shortcutID: shortcutID,
                                    categories: categories
                                )
                            }
                        }
                    }
                    .padding(12)
                    .background(shortcutsInsetPanel)
                }

                HStack(spacing: 10) {
                    Text("Changes appear in the iPad companion on the next snapshot refresh.")
                        .font(Typo.caption(10.5))
                        .foregroundColor(Palette.textMuted)

                    Spacer()

                    Button("Reset Companion Layout") {
                        prefs.resetCompanionCockpitLayout()
                    }
                    .buttonStyle(.plain)
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textDim)
                }
            }
        }
    }

    private var shortcutsOverviewCard: some View {
        shortcutSectionCard(
            title: "Shortcut Map",
            eyebrow: "Quick Reference",
            summary: "Global hotkeys are editable here. tmux shortcuts stay as a built-in reference so you can keep your workspace flow in one place."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 10, alignment: .top)],
                alignment: .leading,
                spacing: 10
            ) {
                shortcutFactCard(
                    icon: "command",
                    title: "Global Hotkeys",
                    detail: "Edit palette, search, voice, and workspace actions without leaving settings."
                )
                shortcutFactCard(
                    icon: "rectangle.split.3x3",
                    title: "Spatial Tiling",
                    detail: "The layout grid mirrors the screen positions used by the menu bar app."
                )
                shortcutFactCard(
                    icon: "terminal",
                    title: "tmux Muscle Memory",
                    detail: "Keep the core pane controls visible here while you tune the app-level shortcuts."
                )
            }
        }
    }

    // MARK: - Shortcuts: App

    private var shortcutsAppCard: some View {
        shortcutSectionCard(
            title: "App & Workspace",
            eyebrow: "Global",
            summary: "Commands for opening primary surfaces and navigating the desktop companion."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(HotkeyAction.allCases.filter { $0.group == .app }, id: \.rawValue) { action in
                    compactKeyRecorder(action: action)
                }
            }
        }
    }

    // MARK: - Shortcuts: Layers

    private var shortcutsLayersCard: some View {
        shortcutSectionCard(
            title: "Layers",
            eyebrow: "Workspace Stack",
            summary: "Direct jumps stay grouped separately from layer cycling so the numeric map is easier to scan."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                shortcutSubsectionLabel("Jump to a Layer")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(HotkeyAction.layerActions, id: \.rawValue) { action in
                        compactKeyRecorder(action: action)
                    }
                }

                cardDivider

                shortcutSubsectionLabel("Cycle & Tag")

                VStack(alignment: .leading, spacing: 8) {
                    ForEach([HotkeyAction.layerPrev, .layerNext, .layerTag], id: \.rawValue) { action in
                        compactKeyRecorder(action: action)
                    }
                }
            }
        }
    }

    // MARK: - Shortcuts: Tiling

    private var shortcutsTilingVisualizer: some View {
        VStack(alignment: .leading, spacing: 12) {
            shortcutSubsectionLabel("Screen Regions")

            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tileCell(action: .tileTopLeft, label: "TL")
                        tileCell(action: .tileTop, label: "Top")
                        tileCell(action: .tileTopRight, label: "TR")
                    }
                    HStack(spacing: 2) {
                        tileCell(action: .tileLeft, label: "Left")
                        tileCell(action: .tileMaximize, label: "Max")
                        tileCell(action: .tileRight, label: "Right")
                    }
                    HStack(spacing: 2) {
                        tileCell(action: .tileBottomLeft, label: "BL")
                        tileCell(action: .tileBottom, label: "Bottom")
                        tileCell(action: .tileBottomRight, label: "BR")
                    }
                }
                .padding(8)
                .background(shortcutsInsetPanel)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thirds")
                        .font(Typo.caption(10.5))
                        .foregroundColor(Palette.textMuted)

                    HStack(spacing: 2) {
                        tileCell(action: .tileLeftThird, label: "\u{2153}L")
                        tileCell(action: .tileCenterThird, label: "\u{2153}C")
                        tileCell(action: .tileRightThird, label: "\u{2153}R")
                    }
                }
                .padding(8)
                .background(shortcutsInsetPanel)

                Text("Use the grid as a visual legend for where each shortcut will place the focused window.")
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortcutsTilingEditors: some View {
        VStack(alignment: .leading, spacing: 12) {
            shortcutSubsectionLabel("Editable Bindings")

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    HotkeyAction.tileLeft, .tileRight, .tileTop, .tileBottom,
                    .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight
                ], id: \.rawValue) { action in
                    compactKeyRecorder(action: action)
                }
            }

            cardDivider

            shortcutSubsectionLabel("Layout Helpers")

            VStack(alignment: .leading, spacing: 8) {
                ForEach([
                    HotkeyAction.tileLeftThird, .tileCenterThird, .tileRightThird,
                    .tileCenter, .tileMaximize, .tileDistribute, .tileTypeGrid
                ], id: \.rawValue) { action in
                    compactKeyRecorder(action: action)
                }
            }
        }
    }

    // MARK: - Shortcuts: tmux

    private var shortcutsTmuxCard: some View {
        shortcutSectionCard(
            title: "Inside tmux",
            eyebrow: "Reference",
            summary: "These are tmux-native controls. They are shown here for fast recall and are not edited by the app."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow("Detach", keys: ["Ctrl+B", "D"])
                    shortcutRow("Kill pane", keys: ["Ctrl+B", "X"])
                    shortcutRow("Pane left", keys: ["Ctrl+B", "\u{2190}"])
                    shortcutRow("Pane right", keys: ["Ctrl+B", "\u{2192}"])
                    shortcutRow("Zoom toggle", keys: ["Ctrl+B", "Z"])
                    shortcutRow("Scroll mode", keys: ["Ctrl+B", "["])
                }
                .padding(12)
                .background(shortcutsInsetPanel)

                Text("Tip: use this as your quick memory jogger while editing the global shortcuts above.")
                    .font(Typo.caption(10.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            compactKeyRecorder(action: .tileOrganize)
        }
    }

    // MARK: - Shortcut section UI

    private func shortcutSectionCard<Content: View>(
        title: String,
        eyebrow: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(eyebrow.uppercased())
                        .font(Typo.pixel(12))
                        .foregroundColor(Palette.textDim)
                        .tracking(1)

                    Text(title)
                        .font(Typo.monoBold(12))
                        .foregroundColor(Palette.text)

                    Text(summary)
                        .font(Typo.caption(10.5))
                        .foregroundColor(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
        }
    }

    private func shortcutFactCard(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textDim)

            Text(title)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)

            Text(detail)
                .font(Typo.caption(10))
                .foregroundColor(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(shortcutsInsetPanel)
    }

    private func shortcutSubsectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Typo.pixel(11))
            .foregroundColor(Palette.textDim)
            .tracking(1)
    }

    private var shortcutsInsetPanel: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
    }

    private func relativeTimestamp(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func companionTrustedDevices(revision: Int) -> [DeckTrustedDeviceSummary] {
        _ = revision
        return LatticesCompanionSecurityCoordinator.shared.trustedDeviceSummaries()
    }

    // MARK: - Tile cell (spatial grid item)

    private func tileCell(action: HotkeyAction, label: String) -> some View {
        let binding = hotkeyStore.bindings[action]
        let badgeText = binding?.displayParts.last ?? ""

        return Button {
            // Open inline key recorder for this action
        } label: {
            VStack(spacing: 3) {
                Text(label)
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textDim)
                Text(badgeText)
                    .font(Typo.geistMonoBold(9))
                    .foregroundColor(Palette.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: tileCellPopoverBinding(for: action)) {
            KeyRecorderView(action: action, store: hotkeyStore)
                .padding(12)
                .frame(width: 300)
        }
    }

    @State private var expandedOcrWindow: UInt32?
    @State private var collapsedOcrApps: Set<String> = []

    @State private var activeTilePopover: HotkeyAction?
    @State private var selectedCompanionCockpitPageID = "main"
    @State private var companionTrustRevision = 0

    private func tileCellPopoverBinding(for action: HotkeyAction) -> Binding<Bool> {
        Binding(
            get: { activeTilePopover == action },
            set: { if !$0 { activeTilePopover = nil } }
        )
    }

    // MARK: - Compact key recorder

    private func compactKeyRecorder(action: HotkeyAction) -> some View {
        KeyRecorderView(action: action, store: hotkeyStore)
    }

    private func companionCockpitSlotMenu(
        pageID: String,
        index: Int,
        shortcutID: String,
        categories: [LatticesCompanionShortcutCategory]
    ) -> some View {
        let definition = LatticesCompanionCockpitCatalog.definition(for: shortcutID)
        let label = definition?.title ?? "Empty"
        let subtitle = definition?.subtitle ?? "Choose a shortcut"
        let icon = definition?.iconSystemName ?? "square.dashed"

        return Menu {
            Button("Empty Slot") {
                prefs.updateCompanionCockpitSlot(pageID: pageID, index: index, shortcutID: "")
            }

            ForEach(categories) { category in
                let shortcuts = LatticesCompanionCockpitCatalog.shortcuts.filter {
                    $0.category == category && !$0.id.isEmpty
                }
                if !shortcuts.isEmpty {
                    Section(category.title) {
                        ForEach(shortcuts) { shortcut in
                            Button {
                                prefs.updateCompanionCockpitSlot(
                                    pageID: pageID,
                                    index: index,
                                    shortcutID: shortcut.id
                                )
                            } label: {
                                Label(shortcut.title, systemImage: shortcut.iconSystemName)
                            }
                        }
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("Slot \(index + 1)")
                        .font(Typo.pixel(10))
                        .foregroundColor(Palette.textDim)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.textMuted)
                }

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textDim)

                Text(label)
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                    .lineLimit(2)

                Text(subtitle)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shortcut row (read-only, for tmux)

    private func shortcutRow(_ label: String, keys: [String]) -> some View {
        HStack {
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    keyBadge(key)
                }
            }
            .padding(.leading, 8)

            Spacer()
        }
    }

    // MARK: - Docs

    private var docsContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                Section(header: stickyHeader("What is lattices?")) {
                    Text("A developer workspace launcher. It creates pre-configured terminal layouts for your projects using tmux \u{2014} go from \u{201C}I want to work on X\u{201D} to a full environment in one click.")
                        .font(Typo.caption(11))
                        .foregroundColor(Palette.textDim)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Glossary")) {
                    VStack(alignment: .leading, spacing: 12) {
                        glossaryItem("Session",
                            "A persistent workspace that lives in the background. Survives terminal crashes, disconnects, even closing your laptop.")
                        glossaryItem("Pane",
                            "A single terminal view inside a session. A typical setup has two panes \u{2014} Claude Code on the left, dev server on the right.")
                        glossaryItem("Attach",
                            "Connect your terminal window to an existing session. The session was already running \u{2014} you\u{2019}re just viewing it.")
                        glossaryItem("Detach",
                            "Disconnect your terminal but keep the session alive. Your dev server keeps running, Claude keeps thinking.")
                        glossaryItem("tmux",
                            "Terminal multiplexer \u{2014} the engine behind lattices. It manages sessions, panes, and layouts. lattices configures it so you don\u{2019}t have to.")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("How it works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStep("1", "Create a .lattices.json in your project root")
                        flowStep("2", "lattices reads the config and builds a tmux session")
                        flowStep("3", "Each pane gets its command (claude, dev server, etc.)")
                        flowStep("4", "Session persists in the background until you kill it")
                        flowStep("5", "Attach and detach from any terminal, any time")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Voice commands")) {
                    VStack(alignment: .leading, spacing: 8) {
                        flowStep("⌥", "Hold Option key to speak, release to stop")
                        flowStep("⇥", "Tab to arm/disarm the mic")
                        flowStep("⎋", "Escape to dismiss")

                        Text("Built-in commands: find, show, open, tile, kill, scan")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .padding(.top, 4)

                        Text("When local matching fails, Claude Haiku advises with follow-up suggestions. Configure the AI model and budget in Settings → AI.")
                            .font(Typo.caption(10.5))
                            .foregroundColor(Palette.textMuted)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Section(header: stickyHeader("Reference")) {
                    HStack(spacing: 8) {
                        docsLinkButton(icon: "doc.text", label: "Config format", file: "config.md")
                        docsLinkButton(icon: "book", label: "Full concepts", file: "concepts.md")
                        footerActionButton(icon: "stethoscope", label: "Diagnostics") {
                            DiagnosticWindow.shared.show()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - Docs helpers

    private func glossaryItem(_ term: String, _ definition: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(term)
                .font(Typo.monoBold(11))
                .foregroundColor(Palette.text)
            Text(definition)
                .font(Typo.caption(10.5))
                .foregroundColor(Palette.textMuted)
                .lineSpacing(2)
        }
    }

    private func flowStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.running)
                .frame(width: 14)
            Text(text)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
        }
    }

    private func docsLinkButton(icon: String, label: String, file: String) -> some View {
        Button {
            let path = resolveDocsFile(file)
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            footerActionLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func footerActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerActionLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    private func footerActionLabel(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(Typo.caption(11))
        }
        .foregroundColor(Palette.textDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        )
    }

    private func resolveDocsFile(_ file: String) -> String {
        let bundle = Bundle.main.bundlePath
        let appDir = (bundle as NSString).deletingLastPathComponent
        let docsPath = ((appDir as NSString).appendingPathComponent("../docs/\(file)") as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
        // Fallback: look relative to the repo root (dev builds)
        let repoGuess = ((appDir as NSString).appendingPathComponent("../../docs/\(file)") as NSString).standardizingPath
        return FileManager.default.fileExists(atPath: repoGuess) ? repoGuess : docsPath
    }

    // MARK: - Shared helpers

    private var separator: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(Typo.caption(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 100, alignment: .trailing)
                .padding(.top, 2)

            content()
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func keyBadge(_ key: String) -> some View {
        Text(key)
            .font(Typo.geistMonoBold(10))
            .foregroundColor(Palette.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )
    }
}
