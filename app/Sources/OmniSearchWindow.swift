import AppKit
import SwiftUI

private final class OmniSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !isKeyWindow {
                makeKey()
            }
        }
        super.sendEvent(event)
    }
}

private final class OmniSearchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

final class OmniSearchWindow {
    static let shared = OmniSearchWindow()

    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var state: OmniSearchState?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if let p = panel, p.isVisible {
            p.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Fresh state each time
        let searchState = OmniSearchState()
        state = searchState

        let view = OmniSearchView(state: searchState) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let hosting = OmniSearchHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let p = OmniSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Search"
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        p.hasShadow = true
        p.appearance = NSAppearance(named: .darkAqua)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 400, height: 300)
        p.maxSize = NSSize(width: 700, height: 700)
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false

        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.maskImage = Self.maskImage(cornerRadius: 14)
        p.contentView = effectView

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        // Center on screen
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.midX - 260
            let y = visibleFrame.midY + 60  // slightly above center
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p

        // Key monitor: Escape → dismiss, arrow keys → navigate, Enter → activate
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.panel?.isKeyWindow == true else { return event }

            switch event.keyCode {
            case 53: // Escape
                self?.dismiss()
                return nil
            case 125: // ↓
                self?.state?.moveSelection(1)
                return nil
            case 126: // ↑
                self?.state?.moveSelection(-1)
                return nil
            case 36: // Enter
                self?.state?.activateSelected()
                self?.dismiss()
                return nil
            default:
                return event
            }
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        state = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edgeLength = 2.0 * cornerRadius + 1.0
        let maskImage = NSImage(
            size: NSSize(width: edgeLength, height: edgeLength),
            flipped: false
        ) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.black.set()
            path.fill()
            return true
        }
        maskImage.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        maskImage.resizingMode = .stretch
        return maskImage
    }
}
