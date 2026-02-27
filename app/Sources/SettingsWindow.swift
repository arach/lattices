import AppKit
import SwiftUI

/// Opens Settings as a standalone window with proper chrome.
enum SettingsWindow {
    private static var window: NSWindow?

    static func open(prefs: Preferences, scanner: ProjectScanner) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(prefs: prefs, scanner: scanner) {
            close()
        }
        .preferredColorScheme(.dark)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "lattice settings"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        w.appearance = NSAppearance(named: .darkAqua)
        w.minSize = NSSize(width: 460, height: 320)
        w.maxSize = NSSize(width: 700, height: 600)
        w.center()
        w.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    static func close() {
        window?.close()
        window = nil
    }
}
