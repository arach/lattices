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
    @State private var pageOrigins: [AppPage: AppPage] = [:]
    @State private var previousPage: AppPage = .home
    @State private var originCaptureBypassPage: AppPage?

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
            syncPageState(windowController.activePage)
            captureOriginIfNeeded(for: windowController.activePage, from: previousPage)
            previousPage = windowController.activePage
        }
        .onChange(of: windowController.activePage) { page in
            if originCaptureBypassPage == page {
                originCaptureBypassPage = nil
            } else {
                captureOriginIfNeeded(for: page, from: previousPage)
            }
            syncPageState(page)
            previousPage = page
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
                navigate(to: page)
            })
        case .screenMap:
            ScreenMapView(controller: controller, onNavigate: { page in
                navigate(to: page)
            })
        case .desktopInventory:
            CommandModeView(state: commandState, presentation: .embedded)
        case .pi:
            PiWorkspaceView()
        case .settings:
            SettingsContentView(
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { navigateBack(from: .settings) }
            )
        case .docs:
            SettingsContentView(
                page: .docs,
                prefs: Preferences.shared,
                scanner: ProjectScanner.shared,
                onBack: { navigateBack(from: .docs) }
            )
        }
    }

    private func navigate(to page: AppPage) {
        windowController.activePage = page
    }

    private func navigateBack(from page: AppPage) {
        let destination = pageOrigins[page] ?? .home
        originCaptureBypassPage = destination
        windowController.activePage = destination
    }

    private func captureOriginIfNeeded(for page: AppPage, from origin: AppPage) {
        guard page == .settings || page == .docs else { return }
        pageOrigins[page] = origin
    }

    private func syncPageState(_ page: AppPage) {
        if page == .screenMap { controller.enter() }
        if page == .desktopInventory { commandState.enter() }
    }
}
