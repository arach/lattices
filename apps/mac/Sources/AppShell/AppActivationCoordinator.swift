import AppKit

final class AppActivationCoordinator {
    static let shared = AppActivationCoordinator()

    private var surfaceVisibilityProviders: [(id: String, isVisible: () -> Bool)] = []

    private init() {}

    func registerSurface(id: String, isVisible: @escaping () -> Bool) {
        guard !surfaceVisibilityProviders.contains(where: { $0.id == id }) else { return }
        surfaceVisibilityProviders.append((id: id, isVisible: isVisible))
    }

    func refresh() {
        let hasVisibleWindow = surfaceVisibilityProviders.contains { provider in
            provider.isVisible()
        }
        let desired: NSApplication.ActivationPolicy = hasVisibleWindow ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            if desired == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
