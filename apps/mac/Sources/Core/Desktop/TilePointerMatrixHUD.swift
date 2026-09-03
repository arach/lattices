import AppKit

/// Lattices matrix picker: a tight 3×3 of mark-cells at the cursor. No
/// letters — the grid is the map. Destination preview stays on
/// `TileZoneOverlay`.
final class TilePointerMatrixHUD {
    static let shared = TilePointerMatrixHUD()

    static let panelSize: CGFloat = 116
    static let pad: CGFloat = 8
    static let gap: CGFloat = 3
    static var cellSize: CGFloat {
        (panelSize - pad * 2 - gap * 2) / 3
    }

    static let cells: [(col: Int, row: Int, position: TilePosition)] = [
        (0, 0, .topLeft), (1, 0, .top), (2, 0, .topRight),
        (0, 1, .left), (1, 1, .maximize), (2, 1, .right),
        (0, 2, .bottomLeft), (1, 2, .bottom), (2, 2, .bottomRight),
    ]

    private var panel: NSPanel?
    private var matrixView: TilePointerMatrixView?

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
                ctx.duration = 0.08
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.00, 0.30, 1.00)
                view.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            self?.matrixView?.position = nil
        })
    }

    static func cellRect(col: Int, row: Int, in bounds: CGRect = CGRect(origin: .zero, size: CGSize(width: panelSize, height: panelSize))) -> CGRect {
        let size = cellSize
        return CGRect(
            x: bounds.minX + pad + CGFloat(col) * (size + gap),
            y: bounds.maxY - pad - CGFloat(row + 1) * size - CGFloat(row) * gap,
            width: size,
            height: size
        )
    }

    private func ensurePanel() -> (NSPanel, TilePointerMatrixView) {
        if let panel, let matrixView { return (panel, matrixView) }

        let view = TilePointerMatrixView(frame: NSRect(
            origin: .zero,
            size: CGSize(width: Self.panelSize, height: Self.panelSize)
        ))
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
        self.matrixView = view
        return (panel, view)
    }
}

private final class TilePointerMatrixView: NSView {
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
        for cell in TilePointerMatrixHUD.cells {
            let rect = TilePointerMatrixHUD.cellRect(col: cell.col, row: cell.row, in: bounds)
            let selected = cell.position == position
            drawCell(rect, selected: selected, isMark: cell.position == .maximize)
        }
    }

    private func drawCell(_ rect: CGRect, selected: Bool, isMark: Bool) {
        let inset: CGFloat = selected ? 0 : 1.2
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = max(1.6, min(box.width, box.height) * 0.22)
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = selected ? 12 : 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = selected
            ? NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.45, alpha: 0.42)
            : NSColor.black.withAlphaComponent(0.22)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        if selected {
            NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.45, alpha: 0.94).setFill()
        } else {
            NSColor(calibratedWhite: 0.12, alpha: 0.72).setFill()
        }
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let lip = CGRect(x: box.minX + 1.5, y: box.maxY - 1.8, width: box.width - 3, height: 1.1)
        if lip.width > 0 {
            let lipPath = NSBezierPath(roundedRect: lip, xRadius: 0.6, yRadius: 0.6)
            NSColor.white.withAlphaComponent(selected ? 0.30 : 0.10).setFill()
            lipPath.fill()
        }

        path.lineWidth = selected ? 1.0 : 0.6
        NSColor.white.withAlphaComponent(selected ? 0.22 : 0.08).setStroke()
        path.stroke()

        guard isMark else { return }
        let ink = selected
            ? NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.09, alpha: 0.94)
            : NSColor.white.withAlphaComponent(0.72)
        drawMark(in: box.insetBy(dx: box.width * 0.22, dy: box.height * 0.22), tint: ink, dim: selected ? 0.28 : 0.16)
    }

    /// Same 3×3 L as `LatticesMark`: left column + bottom row.
    private func drawMark(in rect: CGRect, tint: NSColor, dim: CGFloat) {
        let on: [Bool] = [true, false, false, true, false, false, true, true, true]
        let gap = max(0.6, min(rect.width, rect.height) * 0.08)
        let cell = (min(rect.width, rect.height) - 2 * gap) / 3
        let origin = CGPoint(
            x: rect.midX - (cell * 3 + gap * 2) / 2,
            y: rect.midY - (cell * 3 + gap * 2) / 2
        )
        let radius = max(0.45, cell * 0.22)
        for (index, bright) in on.enumerated() {
            let col = index % 3
            let row = 2 - index / 3
            let box = CGRect(
                x: origin.x + CGFloat(col) * (cell + gap),
                y: origin.y + CGFloat(row) * (cell + gap),
                width: cell,
                height: cell
            )
            let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
            (bright ? tint : tint.withAlphaComponent(dim)).setFill()
            path.fill()
        }
    }
}
