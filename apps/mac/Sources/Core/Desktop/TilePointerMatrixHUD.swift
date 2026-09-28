import AppKit

/// Lattices matrix picker: a tight 3×3 of mark-cells at the cursor. No
/// letters — the grid is the map. The centre cell holds the mark's pointer,
/// turned toward the cell you aim at; over the centre, where a release
/// maximizes, it becomes the knob. Destination preview stays on
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
        view.aim(at: position, animated: panel.isVisible)
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
            self?.matrixView?.aim(at: nil, animated: false)
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

/// The centre glyph: which way the pointer points, and how far it has become
/// the knob.
private struct Centre {
    /// Radians, counterclockwise from +x.
    var heading: CGFloat
    /// 0 is the pointer, 1 the knob.
    var knob: CGFloat

    /// The mark's own pose: pointing into the crook of the L, bottom left.
    static let rest = Centre(heading: .pi * 5 / 4, knob: 0)

    func mixed(with other: Centre, by t: CGFloat) -> Centre {
        Centre(heading: heading + (other.heading - heading) * t, knob: knob + (other.knob - knob) * t)
    }
}

private final class TilePointerMatrixView: NSView {
    /// #ef6a47, the family coral: the mark's accent, and the HUD's only hue.
    static let coral = NSColor(srgbRed: 239 / 255, green: 106 / 255, blue: 71 / 255, alpha: 1)
    /// #f2f2f2, the mark's ink on dark, lights the aimed cell.
    static let ink = NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 0.94)
    /// The pointer's square, as a share of the centre cell.
    static let pointerScale: CGFloat = 0.64
    static let turnDuration: CFTimeInterval = 0.16

    private(set) var position: TilePosition?
    /// The centre as drawn, and the tween that carries it toward `position`.
    private var shown = Centre.rest
    private var from = Centre.rest
    private var to = Centre.rest
    private var start: CFTimeInterval = 0
    private var link: CADisplayLink?

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

    /// Lights `position`'s cell and turns the centre toward it: eased when
    /// `animated`, at once otherwise.
    func aim(at position: TilePosition?, animated: Bool) {
        if position != self.position {
            self.position = position
            from = shown
            to = Self.target(for: position, turningFrom: shown.heading)
            start = CACurrentMediaTime()
            needsDisplay = true
            if animated { run() }
        }
        if !animated { settle() }
    }

    /// Moves the centre along its tween to `now`.
    func advance(to now: CFTimeInterval) {
        let t = min(1, max(0, (now - start) / Self.turnDuration))
        shown = from.mixed(with: to, by: 1 - pow(1 - t, 3))
        needsDisplay = true
        if t == 1 { settle() }
    }

    private func run() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp)
    }

    private func settle() {
        link?.invalidate()
        link = nil
        shown = to
        needsDisplay = true
    }

    /// Toward an outer cell by the shorter way round, back to rest, or, over
    /// the centre, into the knob on the pointer's heading.
    private static func target(for position: TilePosition?, turningFrom heading: CGFloat) -> Centre {
        if position == .maximize { return Centre(heading: heading, knob: 1) }
        var bearing = Centre.rest.heading
        if let cell = TilePointerMatrixHUD.cells.first(where: { $0.position == position }) {
            bearing = atan2(CGFloat(1 - cell.row), CGFloat(cell.col - 1))
        }
        return Centre(heading: heading + (bearing - heading).remainder(dividingBy: 2 * .pi), knob: 0)
    }

    override func draw(_ dirtyRect: NSRect) {
        for cell in TilePointerMatrixHUD.cells {
            let rect = TilePointerMatrixHUD.cellRect(col: cell.col, row: cell.row, in: bounds)
            drawCell(rect, selected: cell.position == position)
        }
        drawCentre(in: TilePointerMatrixHUD.cellRect(col: 1, row: 1, in: bounds))
    }

    private func drawCell(_ rect: CGRect, selected: Bool) {
        let inset: CGFloat = selected ? 0 : 1.2
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = max(1.6, min(box.width, box.height) * 0.22)
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = selected ? 12 : 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(selected ? 0.36 : 0.22)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        if selected {
            Self.ink.setFill()
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

        // A dark hairline keeps the lit cell's edge over light windows.
        path.lineWidth = selected ? 1.0 : 0.6
        (selected ? NSColor.black.withAlphaComponent(0.2) : NSColor.white.withAlphaComponent(0.08)).setStroke()
        path.stroke()
    }

    /// The pointer on `shown.heading`, drawn `shown.knob` of the way into the
    /// knob. Both outlines have one point per step, tip first, so each point
    /// slides straight to its partner.
    private func drawCentre(in cell: CGRect) {
        let side = cell.width * Self.pointerScale
        let centre = CGPoint(x: cell.midX, y: cell.midY)
        let pointer = Self.pointer(heading: shown.heading, side: side, centre: centre)
        let knob = Self.knob(radius: side * 0.29, centre: centre, from: shown.heading, count: pointer.count)
        let path = NSBezierPath()
        for (index, (a, b)) in zip(pointer, knob).enumerated() {
            let point = CGPoint(x: a.x + (b.x - a.x) * shown.knob, y: a.y + (b.y - a.y) * shown.knob)
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        path.close()
        Self.coral.setFill()
        path.fill()
    }

    /// The cursor in a `side` square about `centre`, pointing along `heading`.
    /// Its tip sits where the heading leaves the square: a corner on a
    /// diagonal, an edge's midpoint straight on. In the mark's pose, tip in
    /// the bottom-left corner, the tail reaches the top and right edges.
    private static func pointer(heading: CGFloat, side: CGFloat, centre: CGPoint) -> [CGPoint] {
        let (dx, dy) = (cos(heading), sin(heading))
        let reach = side / 2 / max(abs(dx), abs(dy))
        let tip = CGPoint(x: centre.x + dx * reach, y: centre.y + dy * reach)
        let scale = side / cursorSpan
        return cursor.map { p in
            CGPoint(x: tip.x + scale * (p.y * dy - p.x * dx), y: tip.y - scale * (p.x * dy + p.y * dx))
        }
    }

    /// `count` points round a circle, counterclockwise from `angle`.
    private static func knob(radius: CGFloat, centre: CGPoint, from angle: CGFloat, count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let a = angle + 2 * .pi * CGFloat(index) / CGFloat(count)
            return CGPoint(x: centre.x + radius * cos(a), y: centre.y + radius * sin(a))
        }
    }

    /// Action's cursor, the site's `actionCursor`, as points spaced evenly
    /// round its outline, counterclockwise from the tip. The tip sits at the
    /// origin and the tail runs along +x.
    private static let cursor: [CGPoint] = {
        let path = NSBezierPath()
        path.move(to: .zero)
        path.curve(to: NSPoint(x: 8, y: -3.730461265239989), controlPoint1: NSPoint(x: 0, y: -2), controlPoint2: NSPoint(x: 3, y: -3))
        path.line(to: NSPoint(x: 170, y: -79.27230188634977))
        path.curve(to: NSPoint(x: 175, y: -73.93537846789975), controlPoint: NSPoint(x: 180, y: -83.93537846789975))
        path.line(to: NSPoint(x: 140, y: -26))
        path.curve(to: NSPoint(x: 140, y: 26), controlPoint: NSPoint(x: 124, y: 0))
        path.line(to: NSPoint(x: 175, y: 73.93537846789975))
        path.curve(to: NSPoint(x: 170, y: 79.27230188634977), controlPoint: NSPoint(x: 180, y: 83.93537846789975))
        path.line(to: NSPoint(x: 8, y: 3.730461265239989))
        path.curve(to: .zero, controlPoint1: NSPoint(x: 3, y: 3), controlPoint2: NSPoint(x: 0, y: 2))
        path.close()
        return resample(path, count: 160)
    }()

    /// How far the cursor reaches turned 45°, where it spans a square.
    private static let cursorSpan: CGFloat = 530 - 348.61256823541

    /// `count` points spaced evenly round a closed path, from its first point.
    private static func resample(_ path: NSBezierPath, count: Int) -> [CGPoint] {
        path.flatness = 0.05
        let flat = path.flattened
        var ring: [CGPoint] = []
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<flat.elementCount {
            let kind = flat.element(at: index, associatedPoints: &points)
            if kind == .moveTo || kind == .lineTo { ring.append(points[0]) }
        }
        ring.append(ring[0])
        var lengths: [CGFloat] = [0]
        for (a, b) in zip(ring, ring.dropFirst()) {
            lengths.append(lengths[lengths.count - 1] + hypot(b.x - a.x, b.y - a.y))
        }
        var segment = 0
        return (0..<count).map { index in
            let at = lengths[lengths.count - 1] * CGFloat(index) / CGFloat(count)
            while lengths[segment + 1] < at { segment += 1 }
            let (a, b) = (ring[segment], ring[segment + 1])
            let t = (at - lengths[segment]) / max(lengths[segment + 1] - lengths[segment], .ulpOfOne)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }
}
