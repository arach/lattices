import AppKit
import HudsonObservability
import SwiftUI
import HudsonShell
import HudsonUI

// MARK: - Navigation Pages

enum AppPage: String, CaseIterable {
    case home
    case screenMap
    case desktopInventory
    case activity
    case runs
    case assistant
    case settings
    case companionSettings
    case docs

    var label: String {
        switch self {
        case .home:             return "Home"
        case .screenMap:        return "Studio"
        case .desktopInventory: return "Windows"
        case .activity:         return "Activity"
        case .runs:             return "Runs"
        case .assistant:        return "Assistant"
        case .settings:         return "Settings"
        case .companionSettings:return "Settings"
        case .docs:             return "Docs"
        }
    }

    var icon: String {
        switch self {
        case .home:             return "house"
        case .screenMap:        return "rectangle.3.group"
        case .desktopInventory: return "macwindow.on.rectangle"
        case .activity:         return "list.bullet.rectangle"
        case .runs:             return "record.circle"
        case .assistant:        return "bubble.left.and.bubble.right"
        case .settings:         return "gearshape"
        case .companionSettings:return "ipad.and.iphone"
        case .docs:             return "book"
        }
    }

    /// The rail's groups, in order. They answer "what kind of thing is this":
    /// places you work, agent surfaces, system state — so Runs and Activity stop
    /// reading as peers of Home.
    static let navigationGroups: [(title: String, pages: [AppPage])] = [
        ("Workspace", [.home, .screenMap, .desktopInventory]),
        ("Agents",    [.assistant, .runs]),
        ("System",    [.activity]),
    ]

    /// Pages shown as primary tabs in the unified window
    static var primaryTabs: [AppPage] { navigationGroups.flatMap(\.pages) }
}

// MARK: - App Shell View

struct AppShellView: View {
    @ObservedObject var controller: ScreenMapController
    @ObservedObject var windowController = ScreenMapWindowController.shared
    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var ocr = OcrModel.shared
    @StateObject private var commandState = CommandModeState()
    @State private var selectedStudioLayerId: String?

    /// Labels are on by default. Collapsing to the icon rail stays available
    /// through the brand mark, but as a preference the user sets and keeps —
    /// not the state the app boots into.
    @AppStorage("sidebar.compact") private var sidebarCompact = false
    /// Expanded label-column width. The rail's trailing edge is a drag handle
    /// (same `HudNavigationSidebar.resizable` behavior Scout ships); the width
    /// persists, and dragging below `collapseLabelWidth` folds into the icon
    /// rail. Both bindings are caller-owned — the host previews during the drag
    /// and commits through these on release.
    @AppStorage("sidebar.labelWidth") private var sidebarLabelWidth = 120.0
    /// Actions the visible page published with `.pageActions(_:)`.
    @State private var pageActions: [PageAction] = []
    @ObservedObject private var activityLog = HudLogStore.shared
    @ObservedObject private var daemon = DaemonServer.shared
    @ObservedObject private var desktop = DesktopModel.shared

    private var manifest: HudAppManifest {
        HudAppManifest(name: "Lattices", accent: Palette.running, targetLabel: "Machine")
    }

    /// Hudson rail ↔ our `activePage`. Selecting a rail item routes through the
    /// same `showPage` path the old tabs used; non-primary pages (Settings, Docs)
    /// leave the rail with no selection.
    private var selection: Binding<AppPage?> {
        Binding(
            get: { AppPage.primaryTabs.contains(windowController.activePage) ? windowController.activePage : nil },
            set: { if let page = $0 { windowController.showPage(page) } }
        )
    }

    private var entries: [HudSidebarEntry<AppPage>] {
        AppPage.navigationGroups.flatMap { group -> [HudSidebarEntry<AppPage>] in
            [.section(id: group.title, title: group.title)]
                + group.pages.map { .item(HudSidebarItem(id: $0, title: $0.label, icon: $0.icon)) }
        }
    }

    var body: some View {
        // The safe-area probe must wrap the shell: `HudAppShell`'s content
        // respects the top safe area, so only a GeometryReader *outside* it
        // sees the real titlebar inset we need for the sidebar headers.
        GeometryReader { proxy in
            HudAppShell(statusBarSpan: .besideLeading) {
                navigationSidebar(titleBarInset: proxy.safeAreaInsets.top)
                    .ignoresSafeArea(.container, edges: .top)
            } trailing: {
                EmptyView()
            } content: {
                VStack(spacing: 0) {
                    titleBar
                    contentArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea(.container, edges: .top)
                .onPreferenceChange(PageActionsKey.self) { pageActions = $0 }
            } statusBar: {
                statusBar
            }
        }
        .background(HudWindowChrome(colorScheme: .dark))
        .hudsonAppManifest(manifest)
        .onAppear {
            commandState.onDismiss = { windowController.activePage = .home }
            syncPageState(windowController.activePage)
        }
        .onChange(of: windowController.activePage) { page in
            syncPageState(page)
            clearRelevantDismissals(for: page)
        }
    }

    // MARK: - Navigation Rail

    /// AppStorage stores Double; the sidebar's resize host wants CGFloat.
    private var sidebarLabelWidthBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(sidebarLabelWidth) },
            set: { sidebarLabelWidth = Double($0) }
        )
    }

    private func navigationSidebar(titleBarInset: CGFloat) -> some View {
        HudNavigationSidebar(
            selection: selection,
            entries: entries,
            isCompact: sidebarCompact,
            accent: Palette.running,
            labelWidth: CGFloat(sidebarLabelWidth),
            onHeaderTap: {
                withAnimation(HudMotion.chromeSpring) { sidebarCompact.toggle() }
            }
        ) {
            // railHeader — the brand mark is the top slot. The sidebar surface
            // runs to the window's top edge (floating chrome), so the headers
            // pad themselves down past the traffic lights by titleBarInset.
            // Tapping the mark (onHeaderTap) toggles the rail open/closed.
            LatticesMarkAvatar(size: 24, tint: Palette.running)
                .padding(.top, titleBarInset)
        } labelHeader: {
            Text("Lattices")
                .font(Typo.heading(14))
                .foregroundColor(Palette.text)
                .padding(.top, titleBarInset)
        } footer: {
            // The footer holds the two ambient things: whether the daemon is
            // reachable, and Settings — a non-primary page, so it routes through
            // showPage directly rather than the selection binding.
            VStack(spacing: 0) {
                SidebarDaemonStatus(
                    isListening: daemon.isListening,
                    port: LatticesLocalEndpoints.agentAPIPort,
                    isCompact: sidebarCompact,
                    labelWidth: CGFloat(sidebarLabelWidth)
                )

                SidebarFooterButton(
                    icon: "gearshape",
                    label: "Settings",
                    isActive: windowController.activePage == .settings,
                    isCompact: sidebarCompact,
                    labelWidth: CGFloat(sidebarLabelWidth),
                    accent: Palette.running
                ) {
                    windowController.showPage(.settings)
                }
            }
        }
        .resizable(
            isCompact: $sidebarCompact,
            labelWidth: sidebarLabelWidthBinding,
            minLabelWidth: 76,
            maxLabelWidth: 260,
            collapseLabelWidth: 44
        )
    }

    // MARK: - Title Bar

    /// Every page gets the same header: the page name at the leading edge, the
    /// actions that belong to that page at the trailing edge. Pages publish
    /// their own set with `.pageActions(_:)`; Search is the chrome's, because
    /// ⌘K works everywhere.
    private var titleBar: some View {
        HStack(spacing: 8) {
            Text(windowController.activePage.label)
                .font(Typo.heading(15))
                .foregroundColor(Palette.text)
                .lineLimit(1)

            Spacer(minLength: 12)

            ForEach(pageActions) { action in
                PageActionButton(action: action)
            }
            PageActionButton(action: searchAction)
        }
        .padding(.horizontal, Chrome.inset)
        .frame(height: Chrome.titleBarHeight)
        .background(Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Chrome.hairline)
        }
    }

    private var searchAction: PageAction {
        PageAction(id: "chrome.search", title: "Search", icon: "magnifyingglass", shortcut: "⌘K") {
            UnifiedCommandBarWindow.shared.show(mode: .search)
        }
    }

    // MARK: - Status Bar

    /// Three slots with the same meaning on every page — session health, desktop
    /// shape, last scan — so the strip never changes shape under you. Anything
    /// page-specific lives next to the thing it counts. The one variable region
    /// is the error line, and it sits between the fixed slots so they hold.
    private var statusBar: some View {
        HStack(spacing: 18) {
            statusSlot(width: 132) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(runningSessionCount > 0 ? Palette.running : Palette.textMuted)
                        .frame(width: 6, height: 6)
                    Text(sessionHealthText)
                }
            }

            statusSlot(width: 260) {
                Text(desktopShapeText)
            }

            if let error = activityPreviewMessage {
                Button {
                    windowController.showPage(.activity)
                } label: {
                    Text(error)
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.kill)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help("Open Activity")
            }

            Spacer(minLength: 12)

            statusSlot(width: 150, alignment: .trailing) {
                Text(lastScanText)
            }
        }
        .padding(.horizontal, Chrome.inset)
        .frame(height: Chrome.statusBarHeight)
        .background(Palette.bg)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Chrome.hairline)
        }
    }

    /// A reserved column. Fixed width is the whole point: the numbers inside
    /// change every few seconds and the slot must not move when they do.
    private func statusSlot<Content: View>(
        width: CGFloat,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .font(Typo.mono(11))
            .foregroundColor(Palette.textMuted)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private var runningSessionCount: Int {
        scanner.projects.filter(\.isRunning).count
    }

    private var sessionHealthText: String {
        let running = runningSessionCount
        return "\(running) session\(running == 1 ? "" : "s") running"
    }

    /// Windows come from the live desktop model so the slot reads the same before
    /// the Windows page has ever been opened; spaces are only known once a
    /// snapshot exists, and hold an em dash until then rather than lying with 0.
    private var desktopShapeText: String {
        let windows = desktop.windows.count
        let displays = commandState.desktopSnapshot?.displays.count ?? NSScreen.screens.count
        let spaces = commandState.desktopSnapshot?.displays.reduce(0) { $0 + $1.spaceCount }
        let spacesText = spaces.map { "\($0)" } ?? "—"
        return "\(windows) windows · \(displays) displays · \(spacesText) spaces"
    }

    private var lastScanText: String {
        if ocr.isScanning { return "Scanning screen" }
        guard ocr.enabled else { return "Screen text off" }
        guard let last = ocr.lastReviewedAt ?? ocr.results.values.map(\.timestamp).max() else {
            return "No scan yet"
        }
        return "Scanned \(relativeStatusTime(last))"
    }

    /// Warnings stay in the log. Only errors belong in the status strip.
    private var activityPreviewMessage: String? {
        guard let entry = activityLog.summary.lastEntry else { return nil }
        guard entry.level == .error || entry.level == .fault else { return nil }
        let trimmed = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func relativeStatusTime(_ date: Date) -> String {
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 10 { return "now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Entering a feature page clears its capability snooze — the user is
    /// telling us they want this to work, so the banner can resurface.
    private func clearRelevantDismissals(for page: AppPage) {
        let prefs = Preferences.shared
        switch page {
        case .screenMap:
            prefs.clearDismissal(Capability.windowControl.rawValue)
        case .desktopInventory:
            prefs.clearDismissal(Capability.screenSearch.rawValue)
        default:
            break
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch windowController.activePage {
        case .home:
            HomeDashboardView(onNavigate: { page in
                windowController.showPage(page)
                if page == .screenMap { controller.enter() }
                if page == .desktopInventory { commandState.enter() }
            })
        case .screenMap:
            ScreenMapView(
                controller: controller,
                studioLayerScopeId: $selectedStudioLayerId,
                onNavigate: { page in
                    windowController.activePage = page
                }
            )
        case .desktopInventory:
            CommandModeView(state: commandState, presentation: .embedded)
        case .activity:
            ActivityPageView()
        case .runs:
            RunsReviewView()
        case .assistant:
            WorkspaceAssistantView()
        case .settings:
            SettingsContentView(
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { windowController.showPage(.screenMap); controller.enter() }
            )
        case .companionSettings:
            SettingsContentView(
                page: .companionSettings,
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { windowController.showPage(.screenMap); controller.enter() }
            )
        case .docs:
            SettingsContentView(
                page: .docs,
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { windowController.showPage(.screenMap); controller.enter() }
            )
        }
    }

    private func syncPageState(_ page: AppPage) {
        if page == .screenMap { controller.enter() }
        if page == .desktopInventory { commandState.enter() }
    }
}

// MARK: - Sidebar Daemon Status

/// Daemon reachability, drawn on the rail's geometry so it lines up with the
/// footer button under it: the dot centers in the fixed rail column, the name
/// and port ride the collapsing label column. Not a button — it reports, it
/// doesn't navigate.
private struct SidebarDaemonStatus: View {
    let isListening: Bool
    let port: UInt16
    let isCompact: Bool
    var labelWidth: CGFloat = HudSidebarLayout.labelWidth

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(isListening ? Palette.running : Palette.kill)
                .frame(width: 6, height: 6)
                .frame(width: HudSidebarLayout.railWidth, height: HudSidebarLayout.rowHeight)

            HStack(spacing: 6) {
                Text("Daemon")
                    .font(Typo.body(12))
                    .foregroundColor(Palette.textDim)
                Text(verbatim: ":\(port)")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.textMuted)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, HudSidebarLayout.labelLeading)
            .frame(width: isCompact ? 0 : labelWidth, alignment: .leading)
            .clipped()
            .opacity(isCompact ? 0 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isListening ? "Daemon listening on port \(port)" : "Daemon offline")
        .help(isListening ? "Daemon listening on :\(port)" : "Daemon offline")
    }
}

// MARK: - Sidebar Footer Button

/// A rail-aligned button for `HudNavigationSidebar`'s footer slot. Matches the
/// geometry and color states of the nav rail icons: the glyph centers in the
/// fixed rail column, and the label rides a width-collapsing column so it
/// animates in lockstep with the rail's compact toggle (and is clipped to the
/// rail when compact, never spilling into content).
private struct SidebarFooterButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let isCompact: Bool
    var labelWidth: CGFloat = HudSidebarLayout.labelWidth
    let accent: Color
    let action: () -> Void

    @State private var isHovering = false

    private var tint: Color {
        if isActive   { return accent }
        if isHovering { return HudPalette.ink }
        return HudPalette.muted
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: HudSidebarLayout.iconSize))
                .foregroundStyle(tint)
                .frame(width: HudSidebarLayout.railWidth, height: HudSidebarLayout.rowHeight)

            Text(label)
                .font(HudFont.ui(HudTextSize.base, weight: isActive ? .semibold : .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, HudSidebarLayout.labelLeading)
                .frame(width: isCompact ? 0 : labelWidth, alignment: .leading)
                .clipped()
                .opacity(isCompact ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { isHovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}
