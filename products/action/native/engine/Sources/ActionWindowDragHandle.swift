import AppKit
import SwiftUI

/// A region of the content that behaves like a title bar.
///
/// `mouseDownCanMoveWindow` gets the drag. It does not get the *other* thing
/// every Mac title bar does, which is respond to a double-click with whatever
/// the operator chose in System Settings ▸ Desktop & Dock ▸ "Double-click a
/// window's title bar to". Action's band looked like a title bar, dragged like
/// one, and then did nothing when double-clicked — the kind of gap that reads
/// as an app which reimplemented chrome instead of adopting it.
///
/// Keep this view out from over anything clickable. It is opaque to hit
/// testing, so an interactive view underneath it never sees the press.
struct ActionWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    // The window drag itself is AppKit's, started before this ever runs. Only
    // the double-click needs handling, and only after AppKit has decided the
    // press was not a drag.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let window else {
            super.mouseDown(with: event)
            return
        }
        performDoubleClickAction(on: window)
    }

    /// Mirrors AppKit's own title-bar behaviour, including "Do Nothing", which
    /// is the value the key is absent for.
    private func performDoubleClickAction(on window: NSWindow) {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize":
            window.performMiniaturize(nil)
        case "Maximize":
            window.performZoom(nil)
        default:
            break
        }
    }
}
