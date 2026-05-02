import AppKit
import SwiftUI

/// Dedicated window that hosts the Permissions Assistant. Singleton, opened
/// only on explicit user intent (banner button, onboarding row, Settings,
/// feature gate). Never shown automatically on app launch.
final class PermissionsAssistantWindowController: ObservableObject {
    static let shared = PermissionsAssistantWindowController()

    private var window: NSWindow?
    @Published private(set) var focusedCapability: Capability = .windowControl

    var isVisible: Bool { window?.isVisible ?? false }

    /// Open the assistant focused on the given capability. If `cap` is nil,
    /// the first missing capability is selected, falling back to `windowControl`.
    func show(focus cap: Capability? = nil) {
        let target = cap ?? Capability.missing.first ?? .windowControl
        focusedCapability = target

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = HostView(controller: self)

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Lattices Permissions",
                titleVisible: false,
                initialSize: NSSize(width: 720, height: 520),
                minSize: NSSize(width: 640, height: 460),
                maxSize: NSSize(width: 1100, height: 800)
            ),
            rootView: host
        )
        AppWindowShell.positionCentered(w)
        AppWindowShell.present(w)
        self.window = w
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        AppDelegate.updateActivationPolicy()
    }

    fileprivate func selectionBinding() -> Binding<Capability> {
        Binding(
            get: { self.focusedCapability },
            set: { self.focusedCapability = $0 }
        )
    }
}

// SwiftUI host that observes the controller so the assistant updates when
// `focusedCapability` is reassigned by an external caller (e.g. clicking a
// different feature gate while the window is already open).
private struct HostView: View {
    @ObservedObject var controller: PermissionsAssistantWindowController

    var body: some View {
        PermissionsAssistantView(
            selected: controller.selectionBinding(),
            onClose: { controller.close() }
        )
    }
}
