import AppKit
import Carbon

extension Notification.Name {
    static let latticesPopoverWillShow = Notification.Name("latticesPopoverWillShow")
    static let latticesShowGeneralSettings = Notification.Name("latticesShowGeneralSettings")
    static let latticesShowAssistantSettings = Notification.Name("latticesShowAssistantSettings")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var notificationObservers: [NSObjectProtocol] = []

    static func updateActivationPolicy() {
        AppActivationCoordinator.shared.refresh()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        registerDeepLinkHandler()
        installSystemInputBoundaryObservers()

        MenuBarController.shared.start()
        registerVisibleSurfaces()
        HotkeyBootstrap.registerHotkeys()

        DispatchQueue.main.async { HUDController.shared.warmUp() }
        DispatchQueue.main.async { MenuBarController.shared.warmUpPopover() }
        DispatchQueue.main.async { ScreenOverlayCanvasController.shared.warmUp() }

        WindowDragSnapController.shared.start()
        MouseGestureController.shared.start()
        KeyboardRemapController.shared.start()

        if !OnboardingWindowController.shared.showIfNeeded() {
            PermissionChecker.shared.check()
        }

        AppServicesBootstrap.start()

        Task {
            await AppUpdater.shared.checkIfNeeded()
        }

        // --diagnostics flag: auto-open diagnostics panel on launch
        if CommandLine.arguments.contains("--diagnostics") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                DiagnosticWindow.shared.show()
            }
        }

        // --screen-map flag: auto-open layout on launch
        if CommandLine.arguments.contains("--screen-map") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ScreenMapWindowController.shared.showPage(.screenMap)
            }
        }

        // Explicit preview entry point for development/demo flows. This still
        // requires a launch argument; the assistant never opens automatically.
        if CommandLine.arguments.contains("--permissions-assistant") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                PermissionsAssistantWindowController.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeSystemInputBoundaryObservers()
        KeyboardRemapController.shared.stop()
        AppServicesBootstrap.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        resetInputCapture(reason: "app became active")
    }

    func applicationWillResignActive(_ notification: Notification) {
        resetInputCapture(reason: "app resigned active")
    }

    private func registerVisibleSurfaces() {
        let coordinator = AppActivationCoordinator.shared
        coordinator.registerSurface(id: "menuBarPopover") { MenuBarController.shared.isPopoverShown }
        coordinator.registerSurface(id: "commandMode") { CommandModeWindow.shared.isVisible }
        coordinator.registerSurface(id: "commandPalette") { CommandPaletteWindow.shared.isVisible }
        coordinator.registerSurface(id: "mainWindow") { MainWindow.shared.isVisible }
        coordinator.registerSurface(id: "screenMap") { ScreenMapWindowController.shared.isVisible }
        coordinator.registerSurface(id: "omniSearch") { OmniSearchWindow.shared.isVisible }
    }

    private func installSystemInputBoundaryObservers() {
        let center = NSWorkspace.shared.notificationCenter
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetInputCapture(reason: "system will sleep")
        })
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetInputCapture(reason: "system did wake")
        })
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetInputCapture(reason: "screens did wake")
        })
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetInputCapture(reason: "screens did sleep")
        })
    }

    private func removeSystemInputBoundaryObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func resetInputCapture(reason: String) {
        InputCaptureResetCenter.reset(reason: reason)
    }

    // MARK: - Deep Links

    private func registerDeepLinkHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: value)
        else {
            return
        }
        handleDeepLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.localizedCaseInsensitiveCompare("lattices") == .orderedSame else {
            return
        }

        let host = url.host?.lowercased()
        let action = url.pathComponents
            .first { $0 != "/" }?
            .lowercased()

        guard host == "companion" else {
            SettingsWindowController.shared.show()
            return
        }

        switch action {
        case "enable", "start":
            Preferences.shared.companionBridgeEnabled = true
            SettingsWindowController.shared.showCompanion()
        case "disable", "stop":
            Preferences.shared.companionBridgeEnabled = false
            SettingsWindowController.shared.showCompanion()
        default:
            SettingsWindowController.shared.showCompanion()
        }
    }

}
