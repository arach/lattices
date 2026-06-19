import AppKit
import SwiftUI
import HudsonShell
import HudsonUI

// MARK: - Navigation Pages

enum AppPage: String, CaseIterable {
    case home
    case screenMap
    case desktopInventory
    case activity
    case pi
    case settings
    case companionSettings
    case docs

    var label: String {
        switch self {
        case .home:             return "Home"
        case .screenMap:        return "Studio"
        case .desktopInventory: return "Desktop Inventory"
        case .activity:         return "Activity"
        case .pi:               return "Assistant"
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
        case .pi:               return "bubble.left.and.bubble.right"
        case .settings:         return "gearshape"
        case .companionSettings:return "ipad.and.iphone"
        case .docs:             return "book"
        }
    }

    /// Pages shown as primary tabs in the unified window
    static var primaryTabs: [AppPage] { [.home, .pi, .screenMap, .desktopInventory, .activity] }
}

// MARK: - App Shell View

struct AppShellView: View {
    @ObservedObject var controller: ScreenMapController
    @ObservedObject var windowController = ScreenMapWindowController.shared
    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var ocr = OcrModel.shared
    @StateObject private var commandState = CommandModeState()
    @State private var selectedStudioLayerId: String?

    /// Sidebar starts minimized (icon-only rail); tapping the logo expands it.
    @State private var sidebarCompact = true

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
        AppPage.primaryTabs.map { page in
            .item(HudSidebarItem(id: page, title: page.label, icon: page.icon))
        }
    }

    var body: some View {
        HudAppShell {
            navigationSidebar
        } trailing: {
            EmptyView()
        } content: {
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } statusBar: {
            statusBar
        }
        // Full Hudson window chrome: transparent full-size title bar, no separator.
        // Keep the window non-draggable-by-background so content clicks aren't
        // swallowed (Lattices manages its own window placement).
        .background(HudWindowChrome(colorScheme: .dark, isMovableByWindowBackground: false))
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

    private var navigationSidebar: some View {
        HudNavigationSidebar(
            selection: selection,
            entries: entries,
            isCompact: sidebarCompact,
            accent: Palette.running,
            onHeaderTap: {
                withAnimation(HudMotion.chromeSpring) { sidebarCompact.toggle() }
            }
        ) {
            // railHeader — the brand mark is the top slot. The rail honors the
            // title-bar safe area, so it sits just below the traffic lights.
            // Tapping it (onHeaderTap) toggles the rail open/closed.
            LatticesMarkAvatar(size: 24, tint: Palette.running)
        } labelHeader: {
            Text("Lattices")
                .font(Typo.title(15))
                .foregroundColor(Palette.text)
        } footer: {
            // Settings anchors the bottom-left of the rail — below the primary
            // tabs, separated by the footer divider. Non-primary page, so it
            // routes through showPage directly rather than the selection binding.
            SidebarFooterButton(
                icon: "gearshape",
                label: "Settings",
                isActive: windowController.activePage == .settings,
                isCompact: sidebarCompact,
                accent: Palette.running
            ) {
                windowController.showPage(.settings)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 14) {
            statusBarItems
            Spacer()
            Text(statusContextLabel)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.textDim)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Palette.bg)
    }

    @ViewBuilder
    private var statusBarItems: some View {
        switch windowController.activePage {
        case .desktopInventory:
            desktopInventoryStatusItems
        case .screenMap:
            screenMapStatusItems
        default:
            workspaceStatusItems
        }
    }

    private var workspaceStatusItems: some View {
        let running = scanner.projects.filter(\.isRunning).count
        return Group {
            statusItem(icon: "circle.fill", text: "\(running) running", tint: Palette.running)
            statusItem(icon: "folder", text: "\(scanner.projects.count) projects", tint: Palette.textMuted)
        }
    }

    private var desktopInventoryStatusItems: some View {
        let snapshot = commandState.desktopSnapshot
        let windowCount = snapshot?.allWindows.count ?? 0
        let displayCount = snapshot?.displays.count ?? NSScreen.screens.count
        let spaceCount = snapshot?.displays.reduce(0) { $0 + $1.spaceCount } ?? 0
        let selectedCount = commandState.selectedWindowIds.count

        return Group {
            statusItem(icon: "macwindow", text: "\(windowCount) windows tracked", tint: Palette.running)
            statusItem(icon: "display.2", text: "\(displayCount) monitors", tint: Palette.textMuted)
            statusItem(icon: "rectangle.3.group", text: "\(spaceCount) spaces", tint: Palette.textMuted)
            if selectedCount > 0 {
                statusItem(icon: "checkmark.circle.fill", text: "\(selectedCount) selected", tint: Palette.running)
            }
            statusItem(icon: "text.viewfinder", text: ocrStatusText, tint: ocrStatusTint)
        }
    }

    private var screenMapStatusItems: some View {
        let windowCount = controller.editor?.windows.count ?? 0
        let displayCount = controller.editor?.displays.count ?? NSScreen.screens.count
        let pendingEdits = controller.editor?.pendingEditCount ?? 0

        return Group {
            statusItem(icon: "macwindow", text: "\(windowCount) windows mapped", tint: Palette.running)
            statusItem(icon: "display.2", text: "\(displayCount) monitors", tint: Palette.textMuted)
            if pendingEdits > 0 {
                statusItem(icon: "pencil.and.outline", text: "\(pendingEdits) pending", tint: Palette.detach)
            }
        }
    }

    private var statusContextLabel: String {
        switch windowController.activePage {
        case .desktopInventory:
            let filter = commandState.activePreset?.rawValue
            let mode: String? = {
                switch commandState.desktopMode {
                case .browsing: return nil
                case .tiling: return "Grid Region"
                case .gridPreview: return "Grid Preview"
                case .screenMap: return "Screen Map"
                }
            }()
            return [windowController.activePage.label, filter, mode]
                .compactMap { $0 }
                .joined(separator: " · ")
        default:
            return windowController.activePage.label
        }
    }

    private var ocrStatusText: String {
        if ocr.isScanning { return "OCR scanning" }
        guard ocr.enabled else { return "OCR off" }

        var parts = ["OCR armed"]
        if ocr.lastReviewedWindowCount > 0 {
            parts.append("\(ocr.lastReviewedWindowCount) reviewed")
        } else if !ocr.results.isEmpty {
            parts.append("\(ocr.results.count) cached")
        }
        if let lastReviewedAt = ocr.lastReviewedAt ?? ocr.results.values.map(\.timestamp).max() {
            parts.append("\(relativeStatusTime(lastReviewedAt)) review")
        }
        return parts.joined(separator: " · ")
    }

    private var ocrStatusTint: Color {
        if ocr.isScanning { return Palette.detach }
        return ocr.enabled ? Palette.running : Palette.textMuted
    }

    private func statusItem(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundColor(tint)
            Text(text)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .lineLimit(1)
        }
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
            HStack(spacing: 0) {
                StudioLayersView(selectedLayerId: $selectedStudioLayerId)
                    .frame(width: 320)
                ScreenMapView(controller: controller, onNavigate: { page in
                    windowController.activePage = page
                }, studioLayerScopeId: selectedStudioLayerId, onClearStudioLayerScope: {
                    selectedStudioLayerId = nil
                })
            }
        case .desktopInventory:
            CommandModeView(state: commandState, presentation: .embedded)
        case .activity:
            ActivityPageView()
        case .pi:
            PiWorkspaceView()
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
                .frame(width: isCompact ? 0 : HudSidebarLayout.labelWidth, alignment: .leading)
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
