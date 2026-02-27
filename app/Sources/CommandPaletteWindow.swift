import AppKit
import SwiftUI

/// NSPanel subclass that accepts key events even without a titlebar
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CommandPaletteWindow {
    static let shared = CommandPaletteWindow()

    private var panel: NSPanel?
    private var scanner: ProjectScanner?

    func configure(scanner: ProjectScanner) {
        self.scanner = scanner
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let p = panel, p.isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Always rebuild for fresh command state
        dismiss()

        guard let scanner = scanner else { return }

        // Ensure projects are up to date (full scan if list is empty,
        // e.g. palette opened via hotkey before main popover appeared)
        if scanner.projects.isEmpty {
            scanner.scan()
        } else {
            scanner.refreshStatus()
        }

        let commands = CommandBuilder.build(scanner: scanner)
        let view = CommandPaletteView(commands: commands) { [weak self] in
            self?.dismiss()
        }
        .preferredColorScheme(.dark)

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        // Use NSVisualEffectView as contentView with a maskImage to communicate
        // the rounded shape to the window server (layer.cornerRadius only clips
        // at the view level — the window backing store stays rectangular)
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

        // Center horizontally, slightly above vertical center (Spotlight-style)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 270
            let y = screenFrame.midY - 220 + (screenFrame.height * 0.1)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Stretchable mask image for rounded corners — capInsets preserve the
    /// corner arcs while the center stretches to any window size
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
