import SwiftUI

// MARK: - Navigation Pages

enum AppPage: String, CaseIterable {
    case home
    case screenMap
    case desktopInventory
    case pi
    case settings
    case companionSettings
    case docs

    var label: String {
        switch self {
        case .home:             return "Home"
        case .screenMap:        return "Layout"
        case .desktopInventory: return "Desktop Inventory"
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
        case .pi:               return "bubble.left.and.bubble.right"
        case .settings:         return "gearshape"
        case .companionSettings:return "ipad.and.iphone"
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
        .onAppear {
            commandState.onDismiss = { windowController.activePage = .home }
            syncPageState(windowController.activePage)
        }
        .onChange(of: windowController.activePage) { page in
            syncPageState(page)
            windowController.applyPreferredSizing(for: page)
            clearRelevantDismissals(for: page)
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

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppPage.primaryTabs, id: \.rawValue) { tab in
                tabButton(tab)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 30)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppPage) -> some View {
        let isActive = windowController.activePage == tab

        return Button {
            windowController.showPage(tab)
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
