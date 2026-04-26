import SwiftUI

// MARK: - Navigation Pages

enum AppPage: String, CaseIterable {
    case home
    case screenMap
    case desktopInventory
    case pi
    case settings
    case docs

    var label: String {
        switch self {
        case .home:             return "Home"
        case .screenMap:        return "Screen Map"
        case .desktopInventory: return "Desktop Inventory"
        case .pi:               return "Pi"
        case .settings:         return "Settings"
        case .docs:             return "Docs"
        }
    }

    var icon: String {
        switch self {
        case .home:             return "house"
        case .screenMap:        return "rectangle.3.group"
        case .desktopInventory: return "macwindow.on.rectangle"
        case .pi:               return "terminal"
        case .settings:         return "gearshape"
        case .docs:             return "book"
        }
    }

    /// Pages shown as primary tabs in the unified window
    static var primaryTabs: [AppPage] { [.home, .screenMap, .desktopInventory, .pi] }
}

// MARK: - App Shell View

struct AppShellView: View {
    @ObservedObject var controller: ScreenMapController
    @ObservedObject var windowController = ScreenMapWindowController.shared
    @StateObject private var commandState = CommandModeState()

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar (only on primary pages)
            if AppPage.primaryTabs.contains(windowController.activePage) {
                tabBar
                Rectangle().fill(Palette.border).frame(height: 0.5)
            }

            contentArea
        }
        .background(Palette.bg)
        .onAppear {
            commandState.onDismiss = { windowController.activePage = .home }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppPage.primaryTabs, id: \.rawValue) { tab in
                tabButton(tab)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppPage) -> some View {
        let isActive = windowController.activePage == tab

        return Button {
            windowController.activePage = tab
            if tab == .screenMap { controller.enter() }
            if tab == .desktopInventory { commandState.enter() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10))
                Text(tab.label)
                    .font(Typo.monoBold(11))
            }
            .foregroundColor(isActive ? Palette.text : Palette.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Palette.surfaceHov : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch windowController.activePage {
        case .home:
            HomeDashboardView(onNavigate: { page in
                windowController.activePage = page
                if page == .screenMap { controller.enter() }
                if page == .desktopInventory { commandState.enter() }
            })
        case .screenMap:
            ScreenMapView(controller: controller, onNavigate: { page in
                windowController.activePage = page
            })
        case .desktopInventory:
            CommandModeView(state: commandState)
        case .pi:
            PiWorkspaceView()
        case .settings:
            SettingsContentView(
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { windowController.activePage = .screenMap; controller.enter() }
            )
        case .docs:
            SettingsContentView(
                page: .docs,
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { windowController.activePage = .screenMap; controller.enter() }
            )
        }
    }
}
