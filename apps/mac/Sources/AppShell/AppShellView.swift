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
        case .screenMap:        return "Layout"
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
    @StateObject private var commandState = CommandModeState()

    /// Sidebar starts expanded (labels visible); the rail header toggles compact.
    @State private var sidebarCompact = false

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
            // railHeader — kept clear so the traffic lights float over empty space.
            Color.clear
        } labelHeader: {
            Text("Lattices")
                .font(Typo.title(15))
                .foregroundColor(Palette.text)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let running = scanner.projects.filter(\.isRunning).count
        return HStack(spacing: 14) {
            statusItem(icon: "circle.fill", text: "\(running) running", tint: Palette.running)
            statusItem(icon: "folder", text: "\(scanner.projects.count) projects", tint: Palette.textMuted)
            Spacer()
            Text(windowController.activePage.label)
                .font(Typo.geistMonoBold(9))
                .foregroundColor(Palette.textDim)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Palette.bg)
    }

    private func statusItem(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundColor(tint)
            Text(text)
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
        }
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
            ScreenMapView(controller: controller, onNavigate: { page in
                windowController.activePage = page
            })
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
