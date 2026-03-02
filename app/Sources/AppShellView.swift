import SwiftUI

// MARK: - Navigation Pages

enum AppPage: String, CaseIterable {
    case screenMap
    case settings
    case docs

    var label: String {
        switch self {
        case .screenMap: return "Screen Map"
        case .settings:  return "Settings"
        case .docs:      return "Docs"
        }
    }

    var icon: String {
        switch self {
        case .screenMap: return "rectangle.3.group"
        case .settings:  return "gearshape"
        case .docs:      return "book"
        }
    }
}

// MARK: - App Shell View

struct AppShellView: View {
    @ObservedObject var controller: ScreenMapController
    @ObservedObject var windowController = ScreenMapWindowController.shared

    var body: some View {
        contentArea
            .background(Palette.bg)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch windowController.activePage {
        case .screenMap:
            ScreenMapView(controller: controller, onNavigate: { page in
                windowController.activePage = page
            })
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
