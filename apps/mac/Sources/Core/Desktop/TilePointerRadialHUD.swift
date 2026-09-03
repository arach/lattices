import AppKit

/// Loop-style radial picker: a 100pt ring (180pt panel) pinned to the
/// modifier origin. Destination preview stays on `TileZoneOverlay`.
final class TilePointerRadialHUD {
    static let shared = TilePointerRadialHUD()

    /// Loop: `radialMenuSize` 100, `.padding(40)` → panel `100 + 80`.
    static let ringSize: CGFloat = 100
    static let padding: CGFloat = 40
    static let panelSize: CGFloat = ringSize + padding * 2
    static let thickness: CGFloat = 20
    static let cornerRadius: CGFloat = 40

    private var panel: NSPanel?
    private var ringView: TilePointerRadialView?

    private init() {}

    func show(at origin: NSPoint, position: TilePosition?) {
        let frame = CGRect(
            x: origin.x - Self.panelSize / 2,
            y: origin.y - Self.panelSize / 2,
            width: Self.panelSize,
            height: Self.panelSize
        )
        let (panel, view) = ensurePanel()
        view.position = position
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            view.alphaValue = 0
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.00, 0.30, 1.00)
                view.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            self?.ringView?.position = nil
        })
    }

    private func ensurePanel() -> (NSPanel, TilePointerRadialView) {
        if let panel, let ringView { return (panel, ringView) }

        let view = TilePointerRadialView(frame: NSRect(origin: .zero, size: CGSize(width: Self.panelSize, height: Self.panelSize)))
        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view

        self.panel = panel
        self.ringView = view
        return (panel, view)
    }
}

private final class TilePointerRadialView: NSView {
    var position: TilePosition? {
        didSet {
            if oldValue != position {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let ringRect = bounds.insetBy(dx: TilePointerRadialHUD.padding, dy: TilePointerRadialHUD.padding)
        let radius = TilePointerRadialHUD.cornerRadius
        let thickness = TilePointerRadialHUD.thickness
        let fill = position == .maximize

        let outer = NSBezierPath(roundedRect: ringRect, xRadius: radius, yRadius: radius)
        let innerRect = ringRect.insetBy(dx: thickness, dy: thickness)
        let innerRadius = max(4, radius - thickness)
        let inner = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        let ring = NSBezierPath()
        ring.append(outer)
        ring.append(inner)
        ring.windingRule = .evenOdd
        NSColor(calibratedWhite: 0.10, alpha: 0.72).setFill()
        ring.fill()
        NSGraphicsContext.restoreGraphicsState()

        if fill {
            NSColor(calibratedWhite: 0.78, alpha: 0.28).setFill()
            inner.fill()
        } else if let position, let index = TilePointerController.wedgeIndex(for: position) {
            NSGraphicsContext.saveGraphicsState()
            ring.addClip()
            let center = CGPoint(x: ringRect.midX, y: ringRect.midY)
            let angle = 90 - CGFloat(index) * 45
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(
                withCenter: center,
                radius: ringRect.width,
                startAngle: angle - 22.5,
                endAngle: angle + 22.5,
                clockwise: false
            )
            wedge.close()
            NSColor(calibratedWhite: 0.88, alpha: 0.42).setFill()
            wedge.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        outer.lineWidth = 1.2
        NSColor.white.withAlphaComponent(position == nil ? 0.10 : 0.22).setStroke()
        outer.stroke()
        inner.lineWidth = 1
        NSColor.white.withAlphaComponent(0.12).setStroke()
        inner.stroke()

        guard let position else { return }
        let symbol = NSImage(systemSymbolName: position.icon, accessibilityDescription: position.label)
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let image = symbol?.withSymbolConfiguration(config)
        let size = image?.size ?? .zero
        let iconRect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image?.tinted(NSColor.white.withAlphaComponent(0.92)).draw(in: iconRect)
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let copy = copy() as! NSImage
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}
