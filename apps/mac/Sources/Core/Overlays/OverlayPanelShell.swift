import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    var activatesOnMouseDown = false
    var onKeyDown: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if activatesOnMouseDown,
           event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !isKeyWindow {
                makeKey()
            }
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if let onKeyDown {
            onKeyDown(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if let onFlagsChanged {
            onFlagsChanged(event)
        } else {
            super.flagsChanged(with: event)
        }
    }
}

private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

struct OverlayPanelShell {
    enum Background {
        case clear
        case solid(NSColor)
        case material(NSVisualEffectView.Material)
    }

    enum Placement {
        case centered(yOffsetRatio: CGFloat = 0)
        case mouseScreenCentered(yOffsetRatio: CGFloat = 0)
        case topCenter(margin: CGFloat = 40)
    }

    struct Config {
        var size: NSSize
        var styleMask: NSWindow.StyleMask = [.nonactivatingPanel]
        var title: String = ""
        var titleVisible: NSWindow.TitleVisibility = .hidden
        var titlebarAppearsTransparent = false
        var background: Background = .clear
        var cornerRadius: CGFloat? = nil
        var level: NSWindow.Level = .floating
        var hasShadow = true
        var hidesOnDeactivate = false
        var isReleasedWhenClosed = false
        var isMovableByWindowBackground = false
        var collectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        var minSize: NSSize? = nil
        var maxSize: NSSize? = nil
        var activatesOnMouseDown = false
        var onKeyDown: ((NSEvent) -> Void)? = nil
        var onFlagsChanged: ((NSEvent) -> Void)? = nil
        var appearance: NSAppearance? = NSAppearance(named: .darkAqua)
    }

    static func makePanel<Content: View>(config: Config, rootView: Content) -> OverlayPanel {
        let hosting = OverlayHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: config.size),
            styleMask: config.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = config.title
        panel.titleVisibility = config.titleVisible
        panel.titlebarAppearsTransparent = config.titlebarAppearsTransparent
        panel.isOpaque = false
        panel.backgroundColor = backgroundColor(for: config.background)
        panel.level = config.level
        panel.hasShadow = config.hasShadow
        panel.hidesOnDeactivate = config.hidesOnDeactivate
        panel.isReleasedWhenClosed = config.isReleasedWhenClosed
        panel.isMovableByWindowBackground = config.isMovableByWindowBackground
        panel.collectionBehavior = config.collectionBehavior
        panel.activatesOnMouseDown = config.activatesOnMouseDown
        panel.onKeyDown = config.onKeyDown
        panel.onFlagsChanged = config.onFlagsChanged
        if let minSize = config.minSize {
            panel.minSize = minSize
        }
        if let maxSize = config.maxSize {
            panel.maxSize = maxSize
        }
        if let appearance = config.appearance {
            panel.appearance = appearance
        }

        install(hosting: hosting, on: panel, background: config.background, cornerRadius: config.cornerRadius)
        return panel
    }

    static func position(_ window: NSWindow, placement: Placement) {
        let screen: NSScreen
        switch placement {
        case .mouseScreenCentered, .topCenter:
            screen = mouseScreen()
        case .centered:
            screen = NSScreen.main ?? mouseScreen()
        }

        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let origin: NSPoint

        switch placement {
        case .centered(let yOffsetRatio), .mouseScreenCentered(let yOffsetRatio):
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2 + (visibleFrame.height * yOffsetRatio)
            )
        case .topCenter(let margin):
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - margin
            )
        }

        window.setFrameOrigin(origin)
    }

    static func present(
        _ panel: NSPanel,
        activate: Bool = true,
        makeKey: Bool = true,
        orderFrontRegardless: Bool = false
    ) {
        if orderFrontRegardless {
            panel.orderFrontRegardless()
        } else if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }

        if makeKey {
            panel.makeKey()
        }

        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func install(
        hosting: NSView,
        on panel: NSPanel,
        background: Background,
        cornerRadius: CGFloat?
    ) {
        switch background {
        case .material(let material):
            let effectView = NSVisualEffectView()
            effectView.blendingMode = .behindWindow
            effectView.material = material
            effectView.state = .active
            effectView.wantsLayer = true
            if let cornerRadius {
                effectView.maskImage = maskImage(cornerRadius: cornerRadius)
            }
            panel.contentView = effectView
            pin(hosting: hosting, to: effectView)
        case .clear, .solid:
            panel.contentView = hosting
        }
    }

    private static func pin(hosting: NSView, to container: NSView) {
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private static func mouseScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private static func backgroundColor(for background: Background) -> NSColor {
        switch background {
        case .clear, .material:
            return .clear
        case .solid(let color):
            return color
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
