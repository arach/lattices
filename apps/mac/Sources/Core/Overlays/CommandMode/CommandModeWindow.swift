import AppKit
import SwiftUI

/// NSPanel subclass that accepts key events and first-click mouse events.
/// Overrides sendEvent to ensure the panel is key before processing clicks,
/// which is required for SwiftUI gesture/button handling in .nonactivatingPanel panels.
private class CommandModePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsMouseMovedEvents: Bool {
        get { true }
        set { super.acceptsMouseMovedEvents = newValue }
    }

    override func sendEvent(_ event: NSEvent) {
        // Non-activating panels can silently lose key status. Re-assert key
        // and app activation before every mouse-down so SwiftUI Buttons/gestures
        // fire reliably — including the very first click after the panel appears.
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }
}

/// NSHostingView subclass that accepts first-click events in non-activating panels
private class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

final class CommandModeWindow {
    static let shared = CommandModeWindow()

    private var panel: NSPanel?
    private var isOpen = false

    /// Exposed for event monitor filtering (only handle clicks in this window)
    var panelWindow: NSWindow? { panel }

    var isVisible: Bool { isOpen }

    func toggle(launchMode: CommandModeLaunchMode = .normal) {
        if isOpen {
            if launchMode == .normal {
                dismiss()
            } else {
                show(launchMode: launchMode)
            }
        } else {
            show(launchMode: launchMode)
        }
    }

    func show(launchMode: CommandModeLaunchMode = .normal) {
        // Always rebuild for fresh state
        dismiss()
        isOpen = true

        // Dismiss palette if visible
        if CommandPaletteWindow.shared.isVisible {
            CommandPaletteWindow.shared.dismiss()
        }

        let state = CommandModeState(launchMode: launchMode)
        state.onDismiss = { [weak self] in
            self?.dismiss()
        }
        state.onPanelResize = { [weak self] width, height in
            self?.animateResize(width: width, height: height)
        }
        state.enter()

        // Compute initial size from state phase
        let initialWidth: CGFloat
        let initialHeight: CGFloat
        if state.phase == .desktopInventory {
            let displayCount = max(1, state.desktopSnapshot?.displays.count ?? 1)
            let columnWidth: CGFloat = 480
            initialWidth = CGFloat(displayCount) * columnWidth + CGFloat(displayCount - 1) + 32
            initialHeight = 640
        } else {
            initialWidth = 580; initialHeight = 360
        }

        let view = CommandModeView(state: state)
            .preferredColorScheme(.dark)

        let hosting = FirstClickHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = CommandModePanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let cornerRadius: CGFloat = 14

        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.maskImage = Self.maskImage(cornerRadius: cornerRadius)

        panel.contentView = effectView

        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])

        // Center horizontally, slightly above vertical center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let clampedWidth = min(initialWidth, screenFrame.width * 0.92)
            let clampedHeight = min(initialHeight, screenFrame.height * 0.85)
            let x = screenFrame.midX - clampedWidth / 2
            let y = screenFrame.midY - clampedHeight / 2 + (screenFrame.height * 0.08)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppDelegate.updateActivationPolicy()
    }

    private func animateResize(width: CGFloat, height: CGFloat) {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        // Clamp to screen bounds with margin
        let newWidth = min(width, screenFrame.width * 0.92)
        let newHeight = min(height, screenFrame.height * 0.85)

        let newX = screenFrame.midX - newWidth / 2
        let newY = screenFrame.midY - newHeight / 2 + (screenFrame.height * 0.08)

        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    func dismiss() {
        isOpen = false
        panel?.orderOut(nil)
        panel = nil
        AppDelegate.updateActivationPolicy()
    }

    /// Stretchable mask image for rounded corners
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
