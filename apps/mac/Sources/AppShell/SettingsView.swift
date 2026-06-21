import DeckKit
import AVFoundation
import SwiftUI
import HudsonUI
#if canImport(HudsonVoice)
import HudsonVoice
#endif

/// Settings content with internal General / Shortcuts tabs.
/// Can also render the Docs page when `page == .docs`.
struct SettingsContentView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case shortcuts
        case keyboard
        case mouse
        case hyperspace
        case voice
        case ai
        case search
        case companion

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .shortcuts: return "Shortcuts"
            case .keyboard: return "Keyboard"
            case .mouse: return "Mouse"
            case .hyperspace: return "Hyperspace"
            case .voice: return "Voice"
            case .ai: return "AI"
            case .search: return "Search & OCR"
            case .companion: return "Companion"
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .shortcuts: return "command"
            case .keyboard: return "keyboard"
            case .mouse: return "computermouse"
            case .hyperspace: return "square.grid.3x3.fill"
            case .voice: return "waveform.badge.mic"
            case .ai: return "sparkles"
            case .search: return "text.viewfinder"
            case .companion: return "ipad.and.iphone"
            }
        }

        var eyebrow: String {
            switch self {
            case .general: return "Workspace"
            case .shortcuts: return "Controls"
            case .keyboard: return "Keys"
            case .mouse: return "Input"
            case .hyperspace: return "Survey"
            case .voice: return "Capture"
            case .ai: return "Agents"
            case .search: return "Indexing"
            case .companion: return "LATS iOS Bridge"
            }
        }

        var summary: String {
            switch self {
            case .general:
                return "App updates, permissions, terminal defaults, project discovery, and interaction behavior."
            case .shortcuts:
                return "A full map of global hotkeys for workspace movement and tmux flow."
            case .keyboard:
                return "Caps Lock to Hyper, tap-for-Escape, and key-state recovery."
            case .mouse:
                return "Cursor marker defaults, middle-click gestures, HUD confirmation, and rule configuration."
            case .hyperspace:
                return "Per-display window surveys, lighting, zoom, and layout for Hyperspace."
            case .voice:
                return "Lattices hosts the embedded voice runtime, microphone access, command shortcuts, and the provider-backed voice model."
            case .ai:
                return "Provider auth, chat readiness, and assistant runtime state."
            case .search:
                return "OCR cadence, quality, and recent capture visibility."
            case .companion:
                return "Local-network pairing, trusted iPad devices, and bridge security."
            }
        }

        var group: String {
            switch self {
            case .general, .shortcuts:
                return "Workspace"
            case .keyboard, .mouse, .hyperspace, .voice:
                return "Control"
            case .ai, .search:
                return "Intelligence"
            case .companion:
                return "Devices"
            }
        }

        static var groupedCases: [(String, [SettingsSection])] {
            ["Workspace", "Control", "Intelligence", "Devices"].compactMap { group in
                let sections = allCases.filter { $0.group == group }
                return sections.isEmpty ? nil : (group, sections)
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
    @ObservedObject var assistantSession: PiChatSession = .shared
    @ObservedObject var audioLayer: AudioLayer = .shared
    @ObservedObject var handsOffSession: HandsOffSession = .shared
    @ObservedObject var desktopModel: DesktopModel = .shared
    var onBack: (() -> Void)? = nil

    @State private var selectedTab: SettingsSection = .general
    @State private var keyboardRecoveryStatus: String?
    @FocusState private var assistantAuthFieldFocused: Bool

    // Hyperspace survey dials — same UserDefaults keys (and defaults) the in-survey
    // rig writes, so the two stay in lockstep. See ExposeView in WindowMotionMode.
    @AppStorage("hyperspace.ambient")    private var hsAmbient: Double = 0.5
    @AppStorage("hyperspace.keyLight")   private var hsKeyLight: Double = 0.4
    @AppStorage("hyperspace.keyAngle")   private var hsKeyAngle: Int = 0
    @AppStorage("hyperspace.spotlight")  private var hsSpotlight: Double = 0.3
    @AppStorage("hyperspace.temp")       private var hsTemp: Double = 0.5
    @AppStorage("hyperspace.sizeAuto")   private var hsSizeAuto: Bool = true
    @AppStorage("hyperspace.tileScale")  private var hsTileScale: Double = 1.0
    @AppStorage("hyperspace.layoutTall") private var hsLayoutTall: Bool = false
    @AppStorage("hyperspace.handKeys")   private var hsHandKeys: Bool = false

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
        .onReceive(NotificationCenter.default.publisher(for: .latticesShowGeneralSettings)) { _ in
            selectedTab = .general
        }
        .onReceive(NotificationCenter.default.publisher(for: .latticesShowAssistantSettings)) { _ in
            selectedTab = .ai
        }
        .onReceive(NotificationCenter.default.publisher(for: .latticesShowSettingsSection)) { note in
            if let raw = note.userInfo?["section"] as? String,
               let section = SettingsSection(rawValue: raw) {
                selectedTab = section
            }
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

    private var companionTrackpadBinding: Binding<Bool> {
        Binding(
            get: { prefs.companionTrackpadEnabled },
            set: { enabled in
                prefs.companionTrackpadEnabled = enabled
                if enabled && !permChecker.accessibility {
                    permChecker.requestAccessibility()
                }
            }
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
                            .font(.system(size: HudTextSize.xs, weight: .semibold))
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

            HudDivider(color: HudHairline.standard)
        }
    }

    // MARK: - Settings Body

    private var settingsBody: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 196, alignment: .top)
                .background(Palette.bg)

            HudDivider(color: HudHairline.standard, axis: .vertical)
                .frame(maxHeight: .infinity)

            VStack(spacing: 0) {
                settingsSectionHero(selectedTab)

                HudDivider(color: HudHairline.standard)

                selectedSectionContent
                    .background(Palette.bg)
            }
        }
        .background(Palette.bg)
    }

    private var settingsSidebar: some View {
        // Scrollable so the section list never imposes a tall minimum height. The
        // unified window is user-resizable; without this, the non-scrolling list
        // (~480pt) overflows short windows and pushes the shell's status bar off
        // the bottom — every section pane already scrolls, so the rail must too.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Palette.running.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Palette.running.opacity(0.24), lineWidth: 0.5)
                            )
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Palette.running)
                    }
                    .frame(width: 28, height: 28)

                    Text("Settings")
                        .font(Typo.heading(14))
                        .foregroundColor(Palette.text)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SettingsSection.groupedCases, id: \.0) { group, sections in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(group.uppercased())
                                    .font(Typo.pixel(10))
                                    .foregroundColor(Palette.textDim.opacity(0.82))
                                    .tracking(1.15)

                                Rectangle()
                                    .fill(Palette.border.opacity(0.65))
                                    .frame(height: 0.5)
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 5) {
                                ForEach(sections) { section in
                                    settingsTab(section)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.bg.opacity(0.55))
    }

    private func settingsTab(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(
            icon: section.icon,
            title: section.title,
            eyebrow: section.eyebrow,
            isActive: selectedTab == section,
            accent: Palette.running
        ) {
            selectedTab = section
        }
    }

    private func settingsSectionHero(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.textMuted.opacity(0.82))

            Text(section.title)
                .font(Typo.heading(14))
                .foregroundColor(Palette.text)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Palette.bg)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedTab {
        case .general:
            generalContent
        case .shortcuts:
            shortcutsContent
        case .keyboard:
            keyboardContent
        case .mouse:
            mouseGesturesContent
        case .hyperspace:
            hyperspaceContent
        case .voice:
            voiceContent
        case .ai:
            aiContent
        case .search:
            searchOcrContent
        case .companion:
            companionContent
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permissions")
                            .font(Typo.monoBold(12))
                            .foregroundColor(Palette.text)
                        Text(missing.isEmpty ? "Ready for window control, OCR, and voice" : "\(missing.count) permission \(missing.count == 1 ? "needs" : "need") attention")
                            .font(Typo.mono(9.5))
                            .foregroundColor(Palette.textMuted)
                    }

                    Spacer()

                    statusToken(missing.isEmpty ? "All on" : "\(missing.count) off", color: missing.isEmpty ? Palette.running : Palette.detach)
                }

                Text("Lattices uses these macOS grants for window control, OCR, gestures, shortcuts, and local voice capture.")
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)

                HStack(spacing: 12) {
                    ForEach(Capability.allCases) { cap in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cap.isGranted ? Palette.running : Palette.detach)
                                .frame(width: 5, height: 5)
                            Text(cap.title)
                                .font(Typo.mono(9))
                                .foregroundColor(Palette.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        PermissionsAssistantWindowController.shared.show(focus: missing.first)
                    } label: {
                        Text(missing.isEmpty ? "Open Assistant" : "Set Up")
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

                    Spacer()

                    Button {
                        permChecker.openAutomationSettings()
                    } label: {
                        Text("Automation")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Button {
                        permChecker.openInputMonitoringSettings()
                    } label: {
                        Text("Input Monitoring")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var permissionsDetailCard: some View {
        let allCapabilitiesGranted = Capability.allCases.allSatisfy(\.isGranted)
        return settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: allCapabilitiesGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(allCapabilitiesGranted ? Palette.running : Palette.detach)
                    Text("macOS permissions")
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

                Text("Window discovery, gestures, remaps, OCR, voice capture, and synthetic shortcuts all depend on these macOS grants.")
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

                    permissionSettingsRow(
                        "Microphone",
                        granted: permChecker.microphoneGranted,
                        detail: "Required for local dictation and voice commands hosted by Lattices."
                    ) {
                        permChecker.requestMicrophone()
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
    }

    private var appUpdateCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Lattices app")
                                .font(Typo.monoBold(12))
                                .foregroundColor(Palette.text)
                            buildChannelBadge
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(appUpdater.currentDisplayVersion)
                                .font(Typo.monoBold(13))
                                .foregroundColor(Palette.text)
                            Text(LatticesRuntime.buildStatusLabel)
                                .font(Typo.monoBold(9.5))
                                .foregroundColor(Palette.textMuted)
                        }
                    }

                    Spacer()

                    Toggle("Auto", isOn: $appUpdater.autoCheckEnabled)
                        .font(Typo.caption(9))
                        .toggleStyle(.checkbox)
                        .foregroundColor(Palette.textMuted.opacity(0.9))
                }

                if let update = appUpdater.availableUpdate {
                    Text("New version v\(update.version) is ready")
                        .font(Typo.monoBold(10))
                        .foregroundColor(Palette.detach)
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

                HStack(spacing: 10) {
                    Button {
                        appUpdater.promptForUpdate()
                    } label: {
                        Text(appUpdater.isUpdating ? "Preparing..." : (appUpdater.availableUpdate == nil ? "Check for Updates" : "Update to v\(appUpdater.availableUpdate?.version ?? "")"))
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

                    Spacer()
                }
            }
        }
    }

    private var interactionBehaviorCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session behavior")
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)

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
                    ? "Shows keybinding hints when you detach from a tmux session."
                    : "Detaches sessions quietly once Lattices has done the workspace handoff.")
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.75))
            }
        }
    }

    private var terminalSettingsCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Terminal")
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)

                Picker("", selection: $prefs.terminal) {
                    ForEach(Terminal.installed) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text("Used when Lattices attaches to tmux sessions.")
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.75))
            }
        }
    }

    private var projectDiscoveryCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Project discovery")
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)

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
                                .fill(HudSurface.control)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudHairline.standard, lineWidth: 0.5))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Palette.textDim)
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(HudSurface.control)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(HudHairline.standard, lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Choose scan root")
                }

                HStack {
                    Text("Scans for .lattices.json project configs.")
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
    }

    private var inputControlsCard: some View {
        shortcutSectionCard(
            title: "Input Controls",
            eyebrow: "Gestures",
            summary: "Mouse gestures and drag snapping live alongside the shortcuts they trigger."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Drag-to-snap")
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.text)
                        Text("Hold a modifier while dragging a window to reveal snap targets.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                    }

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

                cardDivider

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Middle-click gestures")
                            .font(Typo.monoBold(11))
                            .foregroundColor(Palette.text)
                        Text("Directional mouse gestures can switch Spaces, open the Screen Map, or trigger dictation.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                    }

                    Spacer()

                    Toggle("", isOn: $prefs.mouseGesturesEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                cardDivider

                mouseGestureHUDSettingsControls

                breakerStatusRow(
                    state: mouseGestureController.breakerState,
                    label: "Mouse gestures"
                ) {
                    mouseGestureController.reArmAfterBreakerTrip()
                }
            }
        }
    }

    private var keyboardContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Caps Lock as Hyper")
                                    .font(Typo.monoBold(12))
                                    .foregroundColor(Palette.text)
                                Text("Hold Caps Lock for Hyper. Tap Caps Lock for Escape.")
                                    .font(Typo.caption(10))
                                    .foregroundColor(Palette.textMuted)
                            }

                            Spacer()

                            Toggle("", isOn: $prefs.keyboardRemapsEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        HStack(spacing: 10) {
                            statusToken(
                                prefs.keyboardRemapsEnabled ? "Enabled" : "Off",
                                color: prefs.keyboardRemapsEnabled ? Palette.running : Palette.textDim
                            )
                            statusToken(
                                keyboardRemapController.capsLockTransportActive ? "Transport active" : "Transport idle",
                                color: keyboardRemapController.capsLockTransportActive ? Palette.running : Palette.textDim
                            )
                            if !permChecker.accessibility {
                                statusToken("Accessibility needed", color: Palette.detach)
                            }
                            Spacer(minLength: 0)
                        }

                        cardDivider

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active remap")
                                .font(Typo.mono(10))
                                .foregroundColor(Palette.textDim)

                            if keyboardRemapStore.summaryLines.isEmpty {
                                Text("No active keyboard remaps")
                                    .font(Typo.caption(9.5))
                                    .foregroundColor(Palette.textMuted.opacity(0.7))
                            } else {
                                ForEach(keyboardRemapStore.summaryLines.prefix(3), id: \.self) { line in
                                    Text(line)
                                        .font(Typo.caption(9.5))
                                        .foregroundColor(Palette.textMuted.opacity(0.82))
                                }
                            }
                        }

                        breakerStatusRow(
                            state: keyboardRemapController.breakerState,
                            label: "Keyboard remaps"
                        ) {
                            keyboardRemapController.reArmAfterBreakerTrip()
                        }

                        if let keyboardRecoveryStatus {
                            Text(keyboardRecoveryStatus)
                                .font(Typo.caption(9.5))
                                .foregroundColor(Palette.textMuted.opacity(0.8))
                        }

                        HStack(spacing: 8) {
                            Button {
                                let didClear = keyboardRemapController.clearStuckCapsLockState()
                                keyboardRecoveryStatus = didClear
                                    ? "Caps Lock state cleared."
                                    : "Could not clear Caps Lock state; check Accessibility/Input Monitoring."
                            } label: {
                                settingsActionLabel("Clear Stuck State", icon: "escape", emphasized: true)
                            }
                            .buttonStyle(.plain)

                            Button {
                                keyboardRemapStore.restoreDefaults()
                                keyboardRecoveryStatus = "Keyboard remaps restored to defaults."
                            } label: {
                                settingsActionLabel("Restore Defaults", icon: "arrow.counterclockwise")
                            }
                            .buttonStyle(.plain)

                            Button {
                                keyboardRemapStore.openConfiguration()
                            } label: {
                                settingsActionLabel("Open Config", icon: "doc.text")
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        if !permChecker.accessibility {
                            cardDivider

                            permissionSettingsRow(
                                "Accessibility",
                                granted: permChecker.accessibility,
                                detail: "Required for Caps Lock as Hyper and tap-for-Escape handling."
                            ) {
                                permChecker.requestAccessibility()
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mouseGestureHUDSettingsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Gesture confirmation HUD")
                .font(Typo.monoBold(10.5))
                .foregroundColor(Palette.text)

            HStack(spacing: 12) {
                HStack {
                    Text("Visual")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                    Spacer()
                    Toggle("", isOn: $prefs.mouseGestureHUDVisualEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                HStack {
                    Text("Audio")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)
                    Spacer()
                    Toggle("", isOn: $prefs.mouseGestureHUDAudioEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }

            HStack {
                Text("Style")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                Spacer()
                Picker("", selection: $prefs.mouseGestureHUDStyle) {
                    ForEach(MouseGestureHUDStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
        }
        .padding(10)
        .background(shortcutsInsetPanel)
    }

    private var cursorMarkerSettingsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent cursor marker")
                    .font(Typo.monoBold(10.5))
                    .foregroundColor(Palette.text)
                Text("Default resting marker for computer-use cursor actions. Individual actions can still override these values.")
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Shape")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                Spacer()
                Picker("", selection: $prefs.cursorMarkerShape) {
                    ForEach(CursorMarkerShape.settingsOptions) { shape in
                        Text(shape.label).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }

            HStack {
                Text("Rotation")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                Spacer()
                Picker("", selection: $prefs.cursorMarkerAngleDeg) {
                    ForEach([-8, -16], id: \.self) { angle in
                        Text("\(angle)deg").tag(angle)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("Size")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textDim)
                Spacer()
                Picker("", selection: $prefs.cursorMarkerSize) {
                    ForEach(CursorMarkerSize.settingsOptions) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
        }
        .padding(10)
        .background(shortcutsInsetPanel)
    }

    private var mouseGesturesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Middle-click gestures")
                                .font(Typo.monoBold(11))
                                .foregroundColor(Palette.text)
                            Spacer()
                            Toggle("", isOn: $prefs.mouseGesturesEnabled)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        cardDivider

                        cursorMarkerSettingsControls

                        cardDivider

                        mouseGestureHUDSettingsControls

                        cardDivider

                        mouseShortcutMappingMatrix(title: "Active mappings", limit: 8)

                        cardDivider

                        breakerStatusRow(
                            state: mouseGestureController.breakerState,
                            label: "Mouse gestures"
                        ) {
                            mouseGestureController.reArmAfterBreakerTrip()
                        }

                        mouseShortcutManagementPanel(
                            detail: "Rules live in ~/.lattices/mouse-shortcuts.json. Use Event Viewer to discover what buttons your mouse emits.",
                            showHistorySummary: true
                        )
                    }
                }
            }
            .padding(16)
        }
    }

    private func mouseShortcutMappingMatrix(title: String, limit: Int) -> some View {
        let allRules = mouseShortcutStore.enabledRules
        let rules = Array(allRules.prefix(limit))
        let hiddenCount = max(allRules.count - rules.count, 0)
        let grouped = Dictionary(grouping: rules, by: \.trigger.button)
        let sortedButtons = grouped.keys.sorted { mouseShortcutButtonSortOrder($0) < mouseShortcutButtonSortOrder($1) }

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)

            if rules.isEmpty {
                mouseShortcutEmptyMappingRow
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedButtons, id: \.self) { button in
                        if let buttonRules = grouped[button] {
                            mouseShortcutMappingButtonGroup(button: button, rules: buttonRules)
                        }
                    }
                }

                if hiddenCount > 0 {
                    Text("+\(hiddenCount) more in config")
                        .font(Typo.mono(8))
                        .foregroundColor(Palette.textMuted.opacity(0.72))
                }
            }
        }
    }

    private func mouseShortcutMappingButtonGroup(button: MouseShortcutButton, rules: [MouseShortcutRule]) -> some View {
        let sortedRules = rules.sorted { lhs, rhs in
            mouseShortcutTriggerSortOrder(lhs.trigger) < mouseShortcutTriggerSortOrder(rhs.trigger)
        }

        return VStack(alignment: .leading, spacing: 5) {
            Text(button.displayLabel)
                .font(Typo.monoBold(9))
                .foregroundColor(Palette.textMuted.opacity(0.82))

            VStack(spacing: 0) {
                ForEach(Array(sortedRules.enumerated()), id: \.element.id) { index, rule in
                    mouseShortcutMappingTableRow(rule)

                    if index < sortedRules.count - 1 {
                        Rectangle()
                            .fill(Palette.border.opacity(0.45))
                            .frame(height: 0.5)
                            .padding(.leading, 10)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surface.opacity(0.48))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border.opacity(0.65), lineWidth: 0.5))
            )
        }
    }

    private var mouseShortcutEmptyMappingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "slash.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Palette.textMuted.opacity(0.75))
            Text("No active mappings")
                .font(Typo.caption(9))
                .foregroundColor(Palette.textMuted.opacity(0.68))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surface.opacity(0.48))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border.opacity(0.65), lineWidth: 0.5))
        )
    }

    private func mouseShortcutMappingTableRow(_ rule: MouseShortcutRule) -> some View {
        HStack(spacing: 8) {
            Text(mouseShortcutGestureLabel(for: rule.trigger))
                .font(Typo.mono(9))
                .foregroundColor(Palette.text)
                .frame(width: 78, alignment: .leading)
                .lineLimit(1)

            Image(systemName: mouseShortcutTriggerIcon(for: rule.trigger))
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(Palette.textMuted.opacity(0.62))
                .frame(width: 12)

            Text(mouseShortcutActionSummary(for: rule))
                .font(Typo.caption(9))
                .foregroundColor(Palette.textMuted.opacity(0.82))
                .lineLimit(1)

            Spacer(minLength: 0)

            if rule.effectiveActions.count > 1 {
                Text("\(rule.effectiveActions.count)x")
                    .font(Typo.monoBold(8))
                    .foregroundColor(Palette.textMuted.opacity(0.72))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.surfaceHov.opacity(0.55)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func mouseShortcutManagementPanel(detail: String, showHistorySummary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                mouseShortcutControlButton(icon: "slider.horizontal.3", label: "Configure") {
                    mouseShortcutStore.openConfiguration()
                }

                mouseShortcutControlButton(icon: "scope", label: "Event Viewer") {
                    MouseInputEventViewer.shared.show()
                }

                mouseShortcutControlButton(icon: "clock.arrow.circlepath", label: "History") {
                    mouseShortcutStore.openHistory()
                }

                mouseShortcutControlButton(
                    icon: "arrow.uturn.backward",
                    label: "Undo Last",
                    isEnabled: mouseShortcutStore.hasHistory
                ) {
                    mouseShortcutStore.restoreLatestHistory()
                }

                mouseShortcutControlButton(icon: "arrow.counterclockwise", label: "Defaults") {
                    mouseShortcutStore.restoreDefaults()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Palette.textMuted.opacity(0.66))
                Text(detail)
                    .font(Typo.caption(9))
                    .foregroundColor(Palette.textMuted.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showHistorySummary, !mouseShortcutStore.historySummaryLines.isEmpty {
                HStack(spacing: 6) {
                    Text("Recent")
                        .font(Typo.monoBold(8))
                        .foregroundColor(Palette.textMuted.opacity(0.68))

                    ForEach(Array(mouseShortcutStore.historySummaryLines.prefix(3)), id: \.self) { snapshot in
                        Text(snapshot)
                            .font(Typo.mono(8))
                            .foregroundColor(Palette.textMuted.opacity(0.7))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Palette.surface.opacity(0.55))
                                    .overlay(Capsule().strokeBorder(Palette.border.opacity(0.55), lineWidth: 0.5))
                            )
                    }
                }
            }
        }
    }

    private func mouseShortcutControlButton(
        icon: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(Typo.monoBold(9))
                    .lineLimit(1)
            }
            .foregroundColor(isEnabled ? Palette.text : Palette.textMuted.opacity(0.52))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surfaceHov.opacity(isEnabled ? 0.88 : 0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.borderLit.opacity(isEnabled ? 0.75 : 0.32), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func mouseShortcutActionSummary(for rule: MouseShortcutRule) -> String {
        rule.effectiveActions.map(\.label).joined(separator: " + ")
    }

    private func mouseShortcutGestureLabel(for trigger: MouseShortcutTrigger) -> String {
        switch trigger.kind {
        case .click:
            return "click"
        case .drag:
            if let direction = trigger.direction {
                return "drag \(direction.displayLabel.lowercased())"
            }
            return "drag"
        case .shape:
            if let shape = trigger.shape {
                return shape.displayName.lowercased()
            }
            return "shape"
        }
    }

    private func mouseShortcutButtonSortOrder(_ button: MouseShortcutButton) -> Int {
        switch button {
        case .middle: return 0
        case .button4: return 1
        case .button5: return 2
        case .right: return 3
        case .number: return 4
        }
    }

    private func mouseShortcutTriggerSortOrder(_ trigger: MouseShortcutTrigger) -> Int {
        let kindOrder: Int
        switch trigger.kind {
        case .drag: kindOrder = 0
        case .shape: kindOrder = 1
        case .click: kindOrder = 2
        }

        let directionOrder: Int
        switch trigger.direction {
        case .left: directionOrder = 0
        case .right: directionOrder = 1
        case .up: directionOrder = 2
        case .down: directionOrder = 3
        case nil: directionOrder = 4
        }

        return kindOrder * 10 + directionOrder
    }

    private func mouseShortcutTriggerIcon(for trigger: MouseShortcutTrigger) -> String {
        switch trigger.kind {
        case .click:
            return "cursorarrow.click"
        case .shape:
            return "scribble.variable"
        case .drag:
            switch trigger.direction {
            case .left: return "arrow.left"
            case .right: return "arrow.right"
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case nil: return "arrow.up.and.down.and.arrow.left.and.right"
            }
        }
    }

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                appUpdateCard

                permissionsAssistantCard

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        terminalSettingsCard
                        interactionBehaviorCard
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        terminalSettingsCard
                        interactionBehaviorCard
                    }
                }

                projectDiscoveryCard
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                permissionsAssistantCard

                let allCapabilitiesGranted = Capability.allCases.allSatisfy(\.isGranted)
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Image(systemName: allCapabilitiesGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(allCapabilitiesGranted ? Palette.running : Palette.detach)
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

                        Text("Lattices uses macOS privacy permissions for window discovery, tiling, gestures, remaps, voice capture, and synthetic shortcuts.")
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

                            permissionSettingsRow(
                                "Microphone",
                                granted: permChecker.microphoneGranted,
                                detail: "Required for local dictation and voice commands hosted by Lattices."
                            ) {
                                permChecker.requestMicrophone()
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
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: LatticesRuntime.isDevBuild ? "hammer.fill" : "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(LatticesRuntime.isDevBuild ? Palette.detach : Palette.running)
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("Lattices app")
                                        .font(Typo.mono(12))
                                        .foregroundColor(Palette.text)
                                    buildChannelBadge
                                    Spacer()
                                }

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(appUpdater.currentDisplayVersion)
                                        .font(Typo.heading(20))
                                        .foregroundColor(Palette.text)
                                    Text(LatticesRuntime.buildStatusLabel)
                                        .font(Typo.monoBold(10))
                                        .foregroundColor(LatticesRuntime.isDevBuild ? Palette.detach : Palette.running)
                                }

                                if let revision = LatticesRuntime.buildRevision {
                                    Text("Build \(revision)")
                                        .font(Typo.caption(9))
                                        .foregroundColor(Palette.textMuted.opacity(0.8))
                                }
                            }
                        }

                        Text("Lattices can check for new signed releases and prepare the update here. You’ll confirm before the app quits and relaunches.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)

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
                                Text(appUpdater.isUpdating ? "Preparing..." : (appUpdater.availableUpdate == nil ? "Check for Updates" : "Update to v\(appUpdater.availableUpdate?.version ?? "")"))
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
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var behaviorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sessions")
                            .font(Typo.mono(11))
                            .foregroundColor(Palette.text)

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

                        Text("Rules live in ~/.lattices/mouse-shortcuts.json. Defaults include middle-click drag left/right for Spaces, down for Screen Map, and up for the Voice Command hotkey.")
                            .font(Typo.caption(9))
                            .foregroundColor(Palette.textMuted.opacity(0.7))

                        cardDivider

                        mouseGestureHUDSettingsControls

                        cardDivider

                        mouseShortcutMappingMatrix(title: "Active drag mappings", limit: 4)

                        breakerStatusRow(
                            state: mouseGestureController.breakerState,
                            label: "Mouse gestures"
                        ) {
                            mouseGestureController.reArmAfterBreakerTrip()
                        }

                        mouseShortcutManagementPanel(
                            detail: "Use Event Viewer to discover what your mouse emits on this machine. The config schema accepts device selectors; live gesture matching falls back to global rules when macOS does not expose the source device.",
                            showHistorySummary: false
                        )
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

                        Text("Rules live in ~/.lattices/keyboard-remaps.json. The default maps hold Caps Lock to Hyper and tap Caps Lock to Escape. While enabled, Lattices temporarily maps physical Caps Lock through a private F18 transport so the lock state does not latch.")
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
                companionCockpitCard
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

    // MARK: - Hyperspace

    private var hyperspaceContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                // ── Displays ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ocrSectionLabel("Displays")

                        Text("Hyperspace opens a separate survey on each display with windows. Nothing moves until you select and gather on that display.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8, alignment: .top)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                                hyperspaceDisplayTile(index: index, screen: screen)
                            }
                        }
                    }
                }

                // ── Lighting ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ocrSectionLabel("Lighting")
                        Text("The survey is lit like a room. These mirror the dials inside Hyperspace and apply the next time it opens.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        hsSlider("moon.stars", "Ambient", $hsAmbient) { hsPercent($0) }
                        hsKeyLightRow
                        hsSlider("flashlight.on.fill", "Spotlight", $hsSpotlight) { hsPercent($0) }
                        hsSlider("thermometer.medium", "Temperature", $hsTemp) {
                            $0 < 0.45 ? "Cool" : $0 > 0.55 ? "Warm" : "Neutral"
                        }
                    }
                }

                // ── Size & layout ──
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ocrSectionLabel("Size & Layout")

                        // Auto-fit: the panel sizes tiles from the window count, sat a
                        // little inside the fill so the lattice has room to breathe.
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Palette.textMuted)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Auto-fit to window count")
                                    .font(Typo.mono(11))
                                    .foregroundColor(Palette.text)
                                Text("Sizes tiles to fill the display, with room to breathe")
                                    .font(Typo.caption(9.5))
                                    .foregroundColor(Palette.textMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $hsSizeAuto)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }

                        // Manual zoom — active when auto is off. Lower = more room.
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Palette.textMuted)
                                .frame(width: 18)
                            Text("Zoom")
                                .font(Typo.mono(11))
                                .foregroundColor(Palette.textDim)
                                .frame(width: 96, alignment: .leading)
                            Slider(value: $hsTileScale, in: 0.55...1.7)
                                .controlSize(.small)
                                .tint(Palette.running)
                            Text(hsSizeAuto ? "auto" : String(format: "%.2f×", hsTileScale))
                                .font(Typo.monoBold(10))
                                .foregroundColor(Palette.text)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .opacity(hsSizeAuto ? 0.4 : 1)
                        .disabled(hsSizeAuto)

                        cardDivider

                        // Lattice growth: scan wide vs. grow into the vertical.
                        hsSegmentRow("rectangle.grid.2x2", "Lattice") {
                            Picker("", selection: $hsLayoutTall) {
                                Text("Scan").tag(false)
                                Text("Tall").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        // Hint keys: full keyboard vs. hand-split assignment.
                        hsSegmentRow("keyboard", "Hint keys") {
                            Picker("", selection: $hsHandKeys) {
                                Text("Standard").tag(false)
                                Text("Hand split").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 150)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func hyperspaceDisplayTile(index: Int, screen: NSScreen) -> some View {
        let windows = hyperspaceWindowCount(on: screen)
        let name = index == 0 ? "Main display" : "Display \(index + 1)"
        let size = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: index == 0 ? "display" : "rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(windows > 0 ? Palette.running : Palette.textMuted)
                    .frame(width: 16)

                Text(name)
                    .font(Typo.monoBold(10.5))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text(size)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
                Spacer(minLength: 0)
                Text("\(windows)")
                    .font(Typo.monoBold(11))
                    .foregroundColor(windows > 0 ? Palette.running : Palette.textMuted)
                Text(windows == 1 ? "window" : "windows")
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
            }
        }
        .padding(10)
        .background(shortcutsInsetPanel)
    }

    private func hyperspaceWindowCount(on screen: NSScreen) -> Int {
        desktopModel.allWindows().filter { entry in
            entry.pid != ProcessInfo.processInfo.processIdentifier &&
            entry.isOnScreen &&
            !entry.title.isEmpty &&
            hyperspaceEntry(entry, isOn: screen)
        }.count
    }

    private func hyperspaceEntry(_ entry: WindowEntry, isOn screen: NSScreen) -> Bool {
        ObjectIdentifier(WindowTiler.screenForWindowFrame(entry.frame)) == ObjectIdentifier(screen)
    }

    // A labeled lighting slider (0…1) with a right-aligned readout.
    private func hsSlider(_ icon: String, _ title: String, _ value: Binding<Double>,
                          readout: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textMuted)
                .frame(width: 18)
            Text(title)
                .font(Typo.mono(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 96, alignment: .leading)
            Slider(value: value, in: 0...1)
                .controlSize(.small)
                .tint(Palette.running)
            Text(readout(value.wrappedValue))
                .font(Typo.monoBold(10))
                .foregroundColor(Palette.text)
                .frame(width: 50, alignment: .trailing)
        }
    }

    // Key light: intensity slider plus a three-way origin picker (◤ ▲ ◥).
    private var hsKeyLightRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textMuted)
                .frame(width: 18)
            Text("Key light")
                .font(Typo.mono(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 96, alignment: .leading)
            Slider(value: $hsKeyLight, in: 0...1)
                .controlSize(.small)
                .tint(Palette.running)
            Picker("", selection: $hsKeyAngle) {
                Text("◤").tag(0)
                Text("▲").tag(1)
                Text("◥").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
        }
    }

    // A labeled row hosting a trailing control (segmented picker, etc.).
    private func hsSegmentRow<Trailing: View>(_ icon: String, _ title: String,
                                              @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.textMuted)
                .frame(width: 18)
            Text(title)
                .font(Typo.mono(11))
                .foregroundColor(Palette.textDim)
                .frame(width: 96, alignment: .leading)
            trailing()
            Spacer(minLength: 0)
        }
    }

    private func hsPercent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    // MARK: - Voice

    private var voiceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                voiceMicrophoneAccessCard

                #if canImport(HudsonVoice)
                HudsonVoiceSettingsView(
                    showsMicrophonePermission: false,
                    managesMicrophonePermission: false,
                    appName: "Lattices"
                )
                #else
                settingsCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Palette.surfaceHov)
                                .overlay(
                                    Image(systemName: "waveform.slash")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Palette.textMuted)
                                )
                                .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Voice runtime")
                                    .font(Typo.mono(12))
                                    .foregroundColor(Palette.text)
                                Text("Lattices' embedded voice runtime isn't compiled into this build.")
                                    .font(Typo.caption(9.5))
                                    .foregroundColor(Palette.textMuted)
                            }
                        }

                        Text("Build with HUDSONKIT_WITH_VOICE=1 to host the voice runtime and reveal its settings.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif

                voiceModelCard
                voiceShortcutsCard
            }
            .padding(16)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            assistantSession.prepareForDisplay()
        }
    }

    private var voiceModelCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(assistantTint.opacity(0.13))
                        .overlay(
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(assistantTint)
                        )
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Voice model")
                            .font(Typo.mono(12))
                            .foregroundColor(Palette.text)
                        Text("Local resolver first, Assistant provider when language needs interpretation.")
                            .font(Typo.caption(9.5))
                            .foregroundColor(Palette.textMuted)
                    }

                    Spacer()

                    aiStatusPill(assistantStatusLabel, tint: assistantTint)
                }

                HStack(spacing: 8) {
                    Text("Assistant provider")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)

                    Picker("", selection: $assistantSession.authProviderID) {
                        ForEach(assistantSession.providerOptions) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 190)

                    aiStatusPill(
                        assistantSession.currentProvider.authMode == .oauth ? "OAUTH" : "API KEY",
                        tint: assistantSession.currentProvider.authMode == .oauth ? Palette.detach : Palette.running
                    )

                    Spacer()
                }

                Text(assistantSession.currentProvider.helpText)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                cardDivider

                VStack(alignment: .leading, spacing: 8) {
                    voiceFactRow("Command path", value: "Local intents", detail: "Fast phrase matching handles common tiling, focus, launch, and search commands.")
                    voiceFactRow("Fallback path", value: assistantSession.currentProvider.name, detail: "Advisor, resolver, repair, and voice questions use the selected Assistant provider.")
                    voiceFactRow("Runtime", value: assistantSession.hasPiBinary ? "Pi installed" : "Pi missing", detail: assistantSession.piBinaryPath ?? "Install Pi to enable provider-backed voice.")
                }
                .padding(10)
                .background(shortcutsInsetPanel)

                HStack(spacing: 8) {
                    aiActionButton("Manage Auth", tint: Palette.running) {
                        selectedTab = .ai
                    }

                    aiActionButton("Refresh Runtime", tint: Palette.textMuted) {
                        assistantSession.refreshBinaryAvailability()
                    }

                    Spacer()
                }
            }
        }
    }

    private var voiceShortcutsCard: some View {
        shortcutSectionCard(
            title: "Voice Entry Points",
            eyebrow: "Controls",
            summary: "Voice capture, hands-off turns, and the Workspace Assistant each keep their own binding."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                compactKeyRecorder(action: .voiceCommand)
                compactKeyRecorder(action: .handsOff)
                compactKeyRecorder(action: .workspaceAssistant)
            }
        }
    }

    private func voiceFactRow(_ label: String, value: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textDim)
                .frame(width: 116, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Typo.monoBold(10.5))
                    .foregroundColor(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detail)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var voiceMicrophoneAccessCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voice access")
                            .font(Typo.monoBold(12))
                            .foregroundColor(Palette.text)
                        Text(voiceMicrophoneSummary)
                            .font(Typo.mono(9.5))
                            .foregroundColor(Palette.textMuted)
                    }

                    Spacer()

                    statusToken(voiceMicrophoneStatusLabel, color: voiceMicrophoneStatusColor)
                }

                voiceMicrophonePermissionRow

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Lattices hosts the embedded voice engine, so macOS Microphone access belongs to Lattices.")
                        .font(Typo.caption(9.5))
                        .foregroundColor(Palette.textMuted.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Button {
                        PermissionsAssistantWindowController.shared.show(focus: .voiceCapture)
                    } label: {
                        settingsActionLabel("Permissions", icon: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)

                    if voiceMicrophoneShowsSettings {
                        Button {
                            permChecker.openMicrophoneSettings()
                        } label: {
                            settingsActionLabel("System Settings", icon: "arrow.up.forward.app")
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        permChecker.check()
                    } label: {
                        settingsActionLabel("Recheck", icon: "checkmark.shield")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var voiceMicrophonePermissionRow: some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(voiceMicrophoneStatusColor.opacity(0.14))
                .overlay(
                    Image(systemName: voiceMicrophoneIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(voiceMicrophoneStatusColor)
                )
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Microphone")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.text)
                Text(voiceMicrophoneDetail)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            voiceMicrophonePrimaryAction
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.surfaceHov.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(voiceMicrophoneStatusColor.opacity(voiceMicrophoneNeedsAttention ? 0.24 : 0.12), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var voiceMicrophonePrimaryAction: some View {
        switch permChecker.microphone {
        case .notDetermined:
            Button {
                permChecker.requestMicrophone()
            } label: {
                settingsActionLabel("Request Access", icon: "mic.badge.plus", emphasized: true)
            }
            .buttonStyle(.plain)
        case .denied, .restricted:
            Button {
                permChecker.openMicrophoneSettings()
            } label: {
                settingsActionLabel("Open Settings", icon: "arrow.up.forward.app", emphasized: true)
            }
            .buttonStyle(.plain)
        case .authorized:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Ready")
                    .font(Typo.monoBold(10))
            }
            .foregroundColor(Palette.running)
        @unknown default:
            EmptyView()
        }
    }

    private var voiceMicrophoneSummary: String {
        switch permChecker.microphone {
        case .authorized:
            return "Ready for dictation and voice commands"
        case .notDetermined:
            return "Not requested yet"
        case .denied:
            return "Needs macOS approval"
        case .restricted:
            return "Blocked by device policy"
        @unknown default:
            return "Microphone status is unknown"
        }
    }

    private var voiceMicrophoneStatusLabel: String {
        switch permChecker.microphone {
        case .authorized:
            return "ready"
        case .notDetermined:
            return "not requested"
        case .denied:
            return "blocked"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    private var voiceMicrophoneStatusColor: Color {
        switch permChecker.microphone {
        case .authorized:
            return Palette.running
        case .notDetermined:
            return Palette.textMuted
        case .denied, .restricted:
            return Palette.detach
        @unknown default:
            return Palette.textDim
        }
    }

    private var voiceMicrophoneIcon: String {
        switch permChecker.microphone {
        case .authorized:
            return "checkmark.circle.fill"
        case .notDetermined:
            return "mic"
        case .denied, .restricted:
            return "exclamationmark.circle.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }

    private var voiceMicrophoneDetail: String {
        switch permChecker.microphone {
        case .authorized:
            return "Lattices can listen when you start dictation or a voice command."
        case .notDetermined:
            return "Ask macOS once before using local dictation or voice commands."
        case .denied:
            return "Open Privacy & Security > Microphone and enable Lattices, then recheck."
        case .restricted:
            return "This Mac or an administrator is blocking microphone access."
        @unknown default:
            return "Lattices could not read the current microphone permission state."
        }
    }

    private var voiceMicrophoneNeedsAttention: Bool {
        switch permChecker.microphone {
        case .authorized:
            return false
        default:
            return true
        }
    }

    private var voiceMicrophoneShowsSettings: Bool {
        switch permChecker.microphone {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    // MARK: - AI

    private var aiContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                assistantProviderCard
            }
            .padding(16)
        }
        .onAppear {
            assistantSession.prepareForDisplay()
        }
    }

    private var assistantProviderCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(assistantTint.opacity(0.13))
                        .overlay(
                            Image(systemName: assistantIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(assistantTint)
                        )
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workspace Assistant")
                            .font(Typo.mono(12))
                            .foregroundColor(Palette.text)

                        Text(assistantSession.setupStatusSummary)
                            .font(Typo.caption(9.5))
                            .foregroundColor(Palette.textMuted)
                    }

                    Spacer()

                    aiStatusPill(assistantStatusLabel, tint: assistantTint)
                }

                Text("The in-app chat and voice advisor use the selected provider once the Pi runtime is installed and authenticated.")
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text("Provider")
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textDim)

                    Picker("", selection: $assistantSession.authProviderID) {
                        ForEach(assistantSession.providerOptions) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 190)

                    aiStatusPill(
                        assistantSession.currentProvider.authMode == .oauth ? "OAUTH" : "API KEY",
                        tint: assistantSession.currentProvider.authMode == .oauth ? Palette.detach : Palette.running
                    )

                    Spacer()

                    aiActionButton("Refresh", tint: Palette.textMuted) {
                        assistantSession.refreshBinaryAvailability()
                    }
                }

                Text(assistantSession.currentProvider.helpText)
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                if let path = assistantSession.piBinaryPath {
                    Text("Runtime: \(path)")
                        .font(Typo.caption(9))
                        .foregroundColor(Palette.running.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                cardDivider

                if assistantSession.hasPiBinary {
                    assistantCredentialControls
                } else {
                    PiInstallCallout(session: assistantSession, compact: false)
                }

                assistantAuthMessage
            }
        }
    }

    @ViewBuilder
    private var assistantCredentialControls: some View {
        if assistantSession.isAuthenticating {
            if let prompt = assistantSession.pendingAuthPrompt {
                PiAuthPromptCard(
                    session: assistantSession,
                    prompt: prompt,
                    compact: false,
                    focus: $assistantAuthFieldFocused
                )
            } else {
                PiAuthNextStepCard(session: assistantSession, compact: false)
            }
        } else {
            switch assistantSession.currentProvider.authMode {
            case .apiKey:
                assistantApiKeyControls
            case .oauth:
                assistantOAuthControls
            }
        }
    }

    private var assistantApiKeyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(assistantSession.hasSelectedCredential ? Palette.running : Palette.detach)
                    .frame(width: 6, height: 6)

                Text(assistantSession.hasSelectedCredential ? "credential saved" : "credential needed")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)

                Spacer()

                if assistantSession.hasSelectedCredential && !assistantSession.isEditingStoredCredential {
                    aiActionButton("Replace", tint: Palette.detach) {
                        assistantSession.beginReplacingSelectedCredential()
                        assistantAuthFieldFocused = true
                    }

                    aiActionButton("Clear", tint: Palette.textMuted) {
                        assistantSession.removeSelectedCredential()
                    }
                }
            }

            if !assistantSession.hasSelectedCredential || assistantSession.isEditingStoredCredential {
                HStack(spacing: 8) {
                    SecureField(assistantTokenPlaceholder, text: $assistantSession.authToken)
                        .textFieldStyle(.plain)
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.text)
                        .focused($assistantAuthFieldFocused)
                        .onSubmit {
                            assistantSession.saveSelectedToken()
                        }

                    aiActionButton(
                        "Save Key",
                        tint: Palette.running,
                        disabled: assistantSession.authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        assistantSession.saveSelectedToken()
                    }

                    if assistantSession.hasSelectedCredential {
                        aiActionButton("Cancel", tint: Palette.textMuted) {
                            assistantSession.cancelReplacingSelectedCredential()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(shortcutsInsetPanel)
            }
        }
    }

    private var assistantOAuthControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(assistantSession.hasSelectedCredential ? Palette.running : Palette.detach)
                    .frame(width: 6, height: 6)

                Text(assistantSession.hasSelectedCredential ? "signed in" : "sign-in required")
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)

                Spacer()

                aiActionButton(
                    assistantSession.hasSelectedCredential ? "Reconnect" : "Sign In",
                    tint: Palette.running
                ) {
                    assistantSession.startSelectedAuthFlow()
                }

                if assistantSession.hasSelectedCredential {
                    aiActionButton("Clear", tint: Palette.textMuted) {
                        assistantSession.removeSelectedCredential()
                    }
                }
            }

            Text(assistantSession.hasSelectedCredential
                ? "\(assistantSession.currentProvider.name) is connected for provider-backed chat."
                : "Sign in once in the browser; Lattices stores the returned OAuth credential locally.")
                .font(Typo.caption(9.5))
                .foregroundColor(Palette.textMuted.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var assistantAuthMessage: some View {
        if let error = assistantSession.authErrorText {
            Text(error)
                .font(Typo.caption(9.5))
                .foregroundColor(Palette.kill.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        } else if let notice = assistantSession.authNoticeText {
            Text(notice)
                .font(Typo.caption(9.5))
                .foregroundColor(Palette.running.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var assistantTint: Color {
        if !assistantSession.hasPiBinary { return Palette.kill }
        if assistantSession.isAuthenticating || assistantSession.needsProviderSetup { return Palette.detach }
        return Palette.running
    }

    private var assistantIcon: String {
        if !assistantSession.hasPiBinary { return "exclamationmark.triangle.fill" }
        if assistantSession.isAuthenticating || assistantSession.needsProviderSetup { return "person.crop.circle.badge.questionmark" }
        return "sparkles"
    }

    private var assistantStatusLabel: String {
        if !assistantSession.hasPiBinary { return "INSTALL PI" }
        if assistantSession.isAuthenticating { return "CONNECTING" }
        if assistantSession.needsProviderSetup { return "SETUP NEEDED" }
        return "READY"
    }

    private var assistantTokenPlaceholder: String {
        let placeholder = assistantSession.currentProvider.tokenPlaceholder
        return placeholder.isEmpty ? "Paste \(assistantSession.currentProvider.tokenLabel.lowercased())" : placeholder
    }

    private func aiStatusPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Typo.monoBold(9.5))
            .foregroundColor(tint.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint.opacity(0.10))
                    .overlay(Capsule().strokeBorder(tint.opacity(0.20), lineWidth: 0.5))
            )
    }

    private func aiActionButton(
        _ label: String,
        tint: Color = Palette.text,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(Typo.monoBold(10))
                .foregroundColor(disabled ? Palette.textMuted : tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.surfaceHov)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.borderLit, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.65 : 1)
    }

    private var buildChannelBadge: some View {
        Text(LatticesRuntime.buildChannelLabel)
            .font(Typo.monoBold(9))
            .foregroundColor(Palette.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Palette.surfaceHov.opacity(0.6))
            )
    }

    private func statusToken(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(Typo.monoBold(9.5))
                .foregroundColor(Palette.textDim)
        }
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

                        if !permChecker.screenRecording {
                            cardDivider

                            PermissionAppDragCard(
                                title: "OCR needs the current Lattices app in Screen Recording",
                                permissionName: "Screen Recording",
                                detail: "If an older Lattices entry is already listed, remove it and drag this app into the list from scratch.",
                                onOpenSettings: {
                                    PermissionDragAssistantWindowController.shared.show(focus: .screenSearch, openSettings: true)
                                }
                            )
                        }
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

    private func settingsCard<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        HudCard(
            padding: 12,
            radius: HudRadius.card,
            fill: Palette.surface,
            stroke: Palette.border
        ) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardDivider: some View {
        HudDivider(color: HudHairline.subtle)
            .padding(.vertical, 3)
    }

    private func settingsActionLabel(_ title: String, icon: String, emphasized: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(Typo.monoBold(10))
        }
        .foregroundColor(emphasized ? Palette.text : Palette.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(emphasized ? Palette.surfaceHov : Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(emphasized ? Palette.borderLit : Palette.border, lineWidth: 0.5)
                )
        )
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
                            inputControlsCard

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

                    footerActionButton(icon: "list.bullet.rectangle", label: "Activity Log") {
                        ScreenMapWindowController.shared.showPage(.activity)
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

                    Toggle("", isOn: companionTrackpadBinding)
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
            title: "Pane Controls",
            eyebrow: "Reference",
            summary: "Terminal pane controls, shown here for fast recall. They are not edited by the app."
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
        @ViewBuilder content: @escaping () -> Content
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
        let badgeText = binding?.displayParts.last ?? "Unset"

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
                    Text("A developer workspace launcher. It creates pre-configured terminal layouts for your projects \u{2014} go from \u{201C}I want to work on X\u{201D} to a full environment in one click.")
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

                        Text("When local matching fails, the selected Assistant provider can advise with follow-up suggestions. Configure capture in Settings → Voice and provider auth in Settings → AI.")
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
                        footerActionButton(icon: "list.bullet.rectangle", label: "Activity Log") {
                            ScreenMapWindowController.shared.showPage(.activity)
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

private struct SettingsSidebarRow: View {
    let icon: String
    let title: String
    let eyebrow: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false

    private var iconTint: Color {
        if isActive || isHovering { return Palette.textDim }
        return Palette.textMuted
    }

    private var titleTint: Color {
        if isActive || isHovering { return Palette.text }
        return Palette.textDim
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(isActive ? accent : Color.clear)
                    .frame(width: 2, height: 22)

                HStack(alignment: .center, spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(iconTint)
                        .frame(width: 16, height: 20, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(isActive ? Typo.monoBold(11) : Typo.mono(11))
                            .foregroundColor(titleTint)

                        Text(eyebrow)
                            .font(Typo.mono(8.5))
                            .foregroundColor(Palette.textMuted.opacity(isActive ? 0.82 : 0.62))
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: HudRadius.standard))
            .background(
                RoundedRectangle(cornerRadius: HudRadius.standard)
                    .fill(isActive ? Palette.surface.opacity(0.95) : (isHovering ? Palette.surface.opacity(0.62) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HudRadius.standard)
                    .stroke(isActive ? Palette.borderLit : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
