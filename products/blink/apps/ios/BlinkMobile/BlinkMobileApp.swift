import HudsonUI
import SwiftUI

@main
struct BlinkMobileApp: App {
    @StateObject private var model = BlinkMobileModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(BlinkThemeChoice.storageKey) private var themeRaw = BlinkThemeChoice.default.rawValue
    @AppStorage(BlinkAppearance.storageKey) private var appearanceRaw = BlinkAppearance.default.rawValue

    private var appearance: BlinkAppearance {
        BlinkAppearance(rawValue: appearanceRaw) ?? .default
    }

    private var currentHudTheme: HudTheme {
        _ = themeRaw
        return BlinkMobileTheme.hudTheme
    }

    private var currentTint: Color {
        _ = themeRaw
        return BlinkMobileTheme.signal
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(currentTint)
                .hudTheme(currentHudTheme)
                .preferredColorScheme(appearance.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.activate()
            case .background: model.deactivate()
            case .inactive: break
            @unknown default: break
            }
        }
    }
}
