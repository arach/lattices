import AppKit
import SwiftUI

@MainActor
final class ActionLauncherController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = ActionLauncherController()

    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private let viewModel = ActionLauncherViewModel()
    private var appearanceMode: ActionAppearanceMode {
        get { ActionAppearanceStore.shared.mode }
        set { ActionAppearanceStore.shared.mode = newValue }
    }

    func run() {
        // The window's background colour is a resolved value AppKit holds onto,
        // so a theme swap has to hand it a new one; SwiftUI's side of the window
        // repaints itself.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ActionThemePalette.didChangeNotification,
            object: nil
        )
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = self
        applyAppearanceMode()
        configureMenu()
        ActionMenuBarController.shared.start(model: viewModel)
        showWindow()
        ActionMenuBarController.shared.warmUpPopover()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    @objc private func themeDidChange() {
        for window in [window, settingsWindow].compactMap({ $0 }) {
            window.backgroundColor = ActionWindowChrome.windowBackground
        }
        ActionMenuBarController.shared.themeDidChange()
        settingsWindow?.contentView?.needsDisplay = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.startAgent()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stopAgent()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindow()
        for url in urls {
            viewModel.handleIncomingDeepLink(url)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window {
            self.window = nil
        }
    }

    func showMainWindow() {
        showWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func reveal(_ destination: ActionLauncherDestination) {
        viewModel.revealLauncher(to: destination)
        showMainWindow()
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = ActionLauncherRootView(model: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1240, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Action"
        ActionWindowChrome.apply(to: window)
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("ActionLauncherWindow")
        window.contentView = hostingView
        window.appearance = appearanceMode.appearance
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func configureMenu() {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Action"
        let mainMenu = NSMenu(title: "MainMenu")

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "New Window",
            action: #selector(openNewWindow),
            keyEquivalent: "n"
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "Help")
        let keyboardItem = NSMenuItem(
            title: "Keyboard Shortcuts",
            action: #selector(showKeyboardShortcuts),
            keyEquivalent: "/"
        )
        keyboardItem.keyEquivalentModifierMask = [.command]
        helpMenu.addItem(keyboardItem)
        helpMenu.addItem(
            withTitle: "Action Documentation",
            action: #selector(openDocumentation),
            keyEquivalent: ""
        )
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)

        let app = NSApplication.shared
        app.mainMenu = mainMenu
        app.windowsMenu = windowMenu
        app.servicesMenu = NSMenu(title: "Services")
        app.helpMenu = helpMenu
    }

    @objc
    private func showKeyboardShortcuts() {
        NotificationCenter.default.post(name: .actionShowKeyboardCheatSheet, object: nil)
        showWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func openDocumentation() {
        NSWorkspace.shared.open(ActionDocs.siteURL)
    }

    @objc
    private func openNewWindow() {
        showWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func showAbout() {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc
    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let content = NSHostingView(
            rootView: ActionSettingsRootView(
                appearanceMode: Binding(
                    get: { self.appearanceMode },
                    set: { [weak self] mode in
                        self?.setAppearanceMode(mode)
                    }
                )
            )
        )

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.contentView = content
        window.appearance = appearanceMode.appearance
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)
        self.settingsWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setAppearanceMode(_ mode: ActionAppearanceMode) {
        appearanceMode = mode
        viewModel.appearanceMode = mode
        applyAppearanceMode()
    }

    private func applyAppearanceMode() {
        NSApplication.shared.appearance = appearanceMode.appearance
        for window in NSApplication.shared.windows {
            window.appearance = appearanceMode.appearance
        }
    }

}
