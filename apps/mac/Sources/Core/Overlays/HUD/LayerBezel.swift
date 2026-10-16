import AppKit

// MARK: - Layer Switch HUD

/// The layer switch, laid out like the matrix picker: a 3×3 of slots numbered
/// like ⌘⌥1–9. Layers fill the eight round the middle (`LayerSlots`); the new
/// layer's slot is lit and its name sits in a bar underneath, over a list of
/// the layer's apps (`LayerRoster`). The middle holds the mark's pointer,
/// aimed at the lit slot. Slots without a layer stay dim. `acknowledge` shows
/// the bar alone, for actions that don't land on a slot: tabs, and saved
/// layers from ⌘L.
final class LayerBezel {
    static let shared = LayerBezel()

    private var panel: NSPanel?
    private var bezelView: LayerBezelView?
    private var dismissTimer: Timer?
    /// Bumped by every show, so a fade-out that ends after a newer show leaves
    /// the panel up.
    private var generation = 0
    /// While ⌘⌥ is down the bezel stays up; `release` lets it go.
    private var held = false

    private init() {}

    /// Keeps the bezel up, through any shows, until `release`.
    func hold() {
        held = true
        dismissTimer?.invalidate()
    }

    /// Lets a held bezel go `after` seconds from now.
    func release(after delay: TimeInterval) {
        guard held else { return }
        held = false
        dismissTimer?.invalidate()
        guard delay > 0 else {
            dismiss()
            return
        }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Lights the slot of layer `index` among `total`, names it `label`, and
    /// lists its `apps` underneath: here at full strength, parked, hidden,
    /// put away or on another desktop dimmed, not open dimmer, and last the
    /// other layers' windows that stayed on screen, dimmed. A layer past the
    /// eighth has no slot, so none lights. `edge` is a step off the pad's
    /// edge: the lit slot bumps that way and the bezel goes sooner.
    func show(label: String, index: Int, total: Int, apps: [LayerRoster.App] = [], edge: LayerSlots.Direction? = nil) {
        let filled = (0..<min(total, LayerSlots.ordered.count)).compactMap(LayerSlots.slot(forIndex:))
        let rows = apps.map { app -> LayerBezelView.Row in
            let presence: LayerBezelView.Row.Presence = switch app.spot {
            case _ where app.stayed: .away
            case .at(.here): .here
            case .at(.noWindow), .at(.notOpen): .absent
            default: .away
            }
            return LayerBezelView.Row(name: app.name, icon: LayerRoster.icon(for: app), note: app.note, presence: presence)
        }
        present(label: label, slots: LayerBezelView.Slots(lit: LayerSlots.slot(forIndex: index), filled: Set(filled)), rows: rows, edge: edge)
    }

    /// While ⌘⌥ aims (`LayerAim`): lights layer `index`, with a map of
    /// where its windows would sit on the main screen above the slots
    /// (`LayerForecast`), and under the name the apps a switch can't show
    /// here. `decision`, once ⌘⌥ is let go, adds two buttons under it:
    /// switch (Return) and stay (Escape), clickable.
    func showForecast(
        label: String, index: Int, total: Int, forecast: LayerForecast,
        edge: LayerSlots.Direction? = nil, decision: LayerBezelView.Decision? = nil
    ) {
        let filled = (0..<min(total, LayerSlots.ordered.count)).compactMap(LayerSlots.slot(forIndex:))
        let rows = forecast.away.map { away -> LayerBezelView.Row in
            let icon = away.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
            let absent = away.note == "Not running" || away.note == "No window open"
            return LayerBezelView.Row(name: away.app, icon: icon, note: away.note, presence: absent ? .absent : .away)
        }
        present(
            label: label,
            slots: LayerBezelView.Slots(lit: LayerSlots.slot(forIndex: index), filled: Set(filled)),
            rows: rows, edge: edge, map: forecast, decision: decision
        )
    }

    /// Shows `label` in the bar alone.
    func acknowledge(_ label: String) {
        present(label: label, slots: nil)
    }

    func dismiss(animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        // The choice is over: clicks go through again, the countdown stops.
        panel.ignoresMouseEvents = true
        bezelView?.endDecision()
        guard animated else {
            dismissTimer?.invalidate()
            generation += 1
            panel.orderOut(nil)
            return
        }
        let shown = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.generation == shown else { return }
            panel.orderOut(nil)
        })
    }

    private func present(
        label: String, slots: LayerBezelView.Slots?, rows: [LayerBezelView.Row] = [],
        edge: LayerSlots.Direction? = nil, map: LayerForecast? = nil, decision: LayerBezelView.Decision? = nil
    ) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        dismissTimer?.invalidate()
        generation += 1

        let (panel, view) = ensurePanel()

        // Centred, two thirds of the way up the screen, not counting the
        // map or the list, so the slots keep their place whatever they hold.
        let size = LayerBezelView.size(label: label, slots: slots, rows: rows, map: map, decision: decision)
        let area = screen.frame
        let top = area.minY + area.height * 2 / 3 + LayerBezelView.size(label: label, slots: slots).height / 2
            + (map.map { LayerBezelView.mapSize($0).height + LayerBezelView.gap } ?? 0)
        let frame = CGRect(
            x: round(area.midX - size.width / 2),
            y: round(top - size.height),
            width: size.width,
            height: size.height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        // On screen first, so the pointer's turn has a display to run on.
        // Only the buttons take clicks; otherwise clicks go through.
        panel.ignoresMouseEvents = decision == nil
        view.show(label: label, slots: slots, rows: rows, edge: edge, map: map, decision: decision)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        // A list takes longer to read; a bump off the edge only says where
        // you are. Held, it stays until ⌘⌥ lifts.
        guard !held else { return }
        let delay: TimeInterval = edge != nil ? 1.0 : rows.isEmpty ? 1.5 : 2.5
        dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func ensurePanel() -> (NSPanel, LayerBezelView) {
        if let panel, let bezelView { return (panel, bezelView) }

        let size = LayerBezelView.size(label: "", slots: LayerBezelView.Slots(lit: nil, filled: []))
        let view = LayerBezelView(frame: CGRect(origin: .zero, size: size))
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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view

        self.panel = panel
        self.bezelView = view
        return (panel, view)
    }
}

// MARK: - Bezel View

/// Nine slots cut like the matrix's cells, numbered in reading order, and the
/// name bar as a fourth row, over a box listing the layer's apps. The middle
/// slot shows the mark's pointer in place of its number. Unlike the matrix's
/// see-through cells these are nearly opaque, so the numbers read over any
/// window.
final class LayerBezelView: NSView {
    struct Slots {
        /// The lit slot, numbered 1–9 like its hotkey.
        var lit: Int?
        /// The slots that hold a layer.
        var filled: Set<Int>
    }

    /// One of the layer's apps, with where its windows are unless they're
    /// here.
    struct Row {
        enum Presence { case here, away, absent }
        let name: String
        let icon: NSImage?
        let note: String?
        let presence: Presence
    }

    static let cellSize: CGFloat = 44
    static let gap: CGFloat = 4
    static let barHeight: CGFloat = 30
    /// Room round the cells for their shadows.
    static let pad: CGFloat = 14
    static let gridSide = cellSize * 3 + gap * 2
    static let barInset: CGFloat = 14
    /// How wide a bar shown alone grows before its label truncates.
    static let maxBarWidth: CGFloat = 420
    static let rowHeight: CGFloat = 24
    static let listInset = CGSize(width: 10, height: 5)
    static let iconSide: CGFloat = 16
    static let iconGap: CGFloat = 7
    static let noteGap: CGFloat = 16
    /// How wide the list grows before names truncate.
    static let maxListWidth: CGFloat = 300

    /// #f2f2f2, the mark's ink on dark, lights the active slot.
    static let ink = NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 0.94)
    /// #101518, the mark's ink on light, fills the other cells and numbers the
    /// lit one.
    static let darkInk = NSColor(srgbRed: 16 / 255, green: 21 / 255, blue: 24 / 255, alpha: 1)
    static let numberFont = rounded(17, .semibold)
    static let labelFont = rounded(13, .semibold)
    static let nameFont = rounded(12, .medium)
    static let noteFont = rounded(11, .medium)
    static let titleFont = rounded(10.5, .regular)
    static let tileFont = rounded(12, .medium)
    static let choiceFont = rounded(13, .semibold)
    static let keyFont = rounded(10.5, .semibold)
    /// The pointer's square, as a share of the middle cell, as in the matrix.
    static let pointerScale: CGFloat = 0.64
    static let turnDuration: CFTimeInterval = 0.16
    /// How far and how long the lit slot leans toward a step off the edge.
    static let bumpDistance: CGFloat = 4
    static let bumpDuration: CFTimeInterval = 0.22

    private var label = ""
    private var slots: Slots?
    private var rows: [Row] = []
    /// Where the lit layer's windows would sit, drawn above the slots.
    private var map: LayerForecast?
    /// The choice once ⌘⌥ is let go: Return switches, Escape stays.
    private var decision: Decision?
    /// The button the mouse is over.
    private var hovered: Choice?
    private var tracking: NSTrackingArea?
    /// The slot the pointer aims at, nil at rest, once it has aimed.
    private var aimed: Int?
    private var hasAimed = false
    /// The pointer as drawn, and the turn that carries it toward `aimed`.
    private var pose = LatticesPointer.Pose.rest
    private var from = LatticesPointer.Pose.rest
    private var to = LatticesPointer.Pose.rest
    private var turnStart: CFTimeInterval = 0
    /// The way the lit slot leans while a bump runs, and how far it is now.
    private var bumpDirection = CGVector.zero
    private var bumpStart: CFTimeInterval = 0
    private var lean: CGFloat = 0
    private var link: CADisplayLink?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `label`, under `slots` if given and over `rows`. When the lit
    /// slot changes, the pointer turns to it from the slot it aimed at
    /// before, so a step shows which way it went. The first aim is instant.
    /// A step off the pad's `edge` bumps the lit slot that way and back.
    func show(
        label: String, slots: Slots?, rows: [Row] = [], edge: LayerSlots.Direction? = nil,
        map: LayerForecast? = nil, decision: Decision? = nil
    ) {
        self.label = label
        self.slots = slots
        self.rows = rows
        self.map = map
        if decision == nil { hovered = nil }
        self.decision = decision
        if decision?.limit != nil { run() }
        if let slots, !hasAimed || slots.lit != aimed {
            from = pose
            if let lit = slots.lit {
                to = LatticesPointer.aim(col: (lit - 1) % 3, row: (lit - 1) / 3, turningFrom: pose.heading)
            } else {
                to = LatticesPointer.rest(turningFrom: pose.heading)
            }
            turnStart = CACurrentMediaTime()
            if hasAimed { run() } else { settle() }
            hasAimed = true
            aimed = slots.lit
        }
        if let edge, slots?.lit != nil {
            bumpDirection = switch edge {
            case .left: CGVector(dx: -1, dy: 0)
            case .right: CGVector(dx: 1, dy: 0)
            case .up: CGVector(dx: 0, dy: 1)
            case .down: CGVector(dx: 0, dy: -1)
            }
            bumpStart = CACurrentMediaTime()
            run()
        }
        needsDisplay = true
    }

    private func run() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = min(1, max(0, (link.targetTimestamp - turnStart) / Self.turnDuration))
        pose = from.mixed(with: to, by: 1 - pow(1 - t, 3))
        let b = min(1, max(0, (link.targetTimestamp - bumpStart) / Self.bumpDuration))
        lean = CGFloat(sin(Double.pi * b)) * Self.bumpDistance
        needsDisplay = true
        if t == 1, b == 1, decision?.limit == nil { settle() }
    }

    private func settle() {
        link?.invalidate()
        link = nil
        pose = to
        bumpDirection = .zero
        lean = 0
        needsDisplay = true
    }

    /// Fixed with slots, so a switch never resizes the slots and bar; fitted
    /// to `label` without. A list adds its height, and widens the panel when
    /// it's wider than the slots.
    static func size(label: String, slots: Slots?, rows: [Row] = [], map: LayerForecast? = nil, decision: Decision? = nil) -> CGSize {
        var size: CGSize
        if slots != nil {
            size = CGSize(width: gridSide + pad * 2, height: gridSide + gap + barHeight + pad * 2)
        } else {
            let text = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
            let width = min(max(gridSide, text + barInset * 2), maxBarWidth)
            size = CGSize(width: width + pad * 2, height: barHeight + pad * 2)
        }
        if !rows.isEmpty {
            size.width = max(size.width, listWidth(rows) + pad * 2)
            size.height += gap + listHeight(rows)
        }
        if let map {
            let mapped = mapSize(map)
            size.width = max(size.width, mapped.width + pad * 2)
            size.height += gap + mapped.height
        }
        if decision != nil {
            size.height += gap * 2 + choiceHeight
        }
        return size
    }

    static let mapWidth: CGFloat = 540
    static let mapInset: CGFloat = 8
    /// The line under the screen saying what the switch puts away.
    static let mapCaption: CGFloat = 20
    /// How far a window sitting on another steps down and right of it.
    static let depthStep: CGFloat = 10

    /// The screen at its shape, with room for the caption.
    static func mapSize(_ map: LayerForecast) -> CGSize {
        let inner = mapWidth - mapInset * 2
        let screen = min(max(inner / max(map.aspect, 0.5), 140), 340)
        return CGSize(width: mapWidth, height: screen + mapInset * 2 + mapCaption)
    }

    /// Fitted to the widest row, at least as wide as the slots.
    private static func listWidth(_ rows: [Row]) -> CGFloat {
        let widest = rows.map { row -> CGFloat in
            let name = (row.name as NSString).size(withAttributes: [.font: nameFont]).width
            let note = row.note.map { noteGap + ($0 as NSString).size(withAttributes: [.font: noteFont]).width } ?? 0
            return ceil(iconSide + iconGap + name + note)
        }.max() ?? 0
        return min(max(gridSide, widest + listInset.width * 2), maxListWidth)
    }

    private static func listHeight(_ rows: [Row]) -> CGFloat {
        CGFloat(rows.count) * rowHeight + listInset.height * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        // Top-down: the slots, the bar, then the list, centred.
        let content = bounds.insetBy(dx: Self.pad, dy: Self.pad)
        let blockWidth = slots == nil ? Self.size(label: label, slots: nil).width - Self.pad * 2 : Self.gridSide
        let left = bounds.midX - blockWidth / 2
        var top = content.maxY
        if let map {
            let size = Self.mapSize(map)
            drawMap(map, in: CGRect(x: bounds.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height))
            top -= size.height + Self.gap
        }
        if let slots {
            for slot in 1...9 {
                let (col, row) = ((slot - 1) % 3, (slot - 1) / 3)
                let lit = slot == slots.lit
                let cell = CGRect(
                    x: left + CGFloat(col) * (Self.cellSize + Self.gap),
                    y: top - CGFloat(row + 1) * Self.cellSize - CGFloat(row) * Self.gap,
                    width: Self.cellSize,
                    height: Self.cellSize
                ).offsetBy(dx: lit ? bumpDirection.dx * lean : 0, dy: lit ? bumpDirection.dy * lean : 0)
                drawBox(cell, lit: lit)
                if slot == LayerSlots.centre {
                    drawPointer(in: cell)
                } else {
                    let colour = lit ? Self.darkInk : NSColor.white.withAlphaComponent(slots.filled.contains(slot) ? 0.82 : 0.24)
                    drawText("\(slot)", font: Self.numberFont, colour: colour, in: cell)
                }
            }
            top -= Self.gridSide + Self.gap
        }
        let bar = CGRect(x: left, y: top - Self.barHeight, width: blockWidth, height: Self.barHeight)
        drawBox(bar, lit: false)
        drawText(label, font: Self.labelFont, colour: NSColor.white.withAlphaComponent(0.92), in: bar.insetBy(dx: Self.barInset, dy: 0))
        var bottom = bar.minY
        if !rows.isEmpty {
            let width = Self.listWidth(rows)
            let height = Self.listHeight(rows)
            drawList(in: CGRect(x: bounds.midX - width / 2, y: bar.minY - Self.gap - height, width: width, height: height))
            bottom -= Self.gap + height
        }
        if let decision {
            drawChoices(decision, in: choicesRect(below: bottom))
        }
    }

    // MARK: The choice

    /// What letting go of ⌘⌥ asks: switch to `target` or stay on `current`.
    /// With a `limit`, it stays once that runs out, and the stay button
    /// drains to show it.
    struct Decision {
        let target: String
        let current: String
        let limit: TimeInterval?
        let started: CFTimeInterval
        let choose: (Choice) -> Void
    }

    enum Choice { case go, stay }

    static let choiceHeight: CGFloat = 46

    private func choicesRect(below bottom: CGFloat) -> CGRect {
        let content = bounds.insetBy(dx: Self.pad, dy: Self.pad)
        return CGRect(x: content.minX, y: bottom - Self.gap * 2 - Self.choiceHeight, width: content.width, height: Self.choiceHeight)
    }

    /// The two buttons' rects: switch on the left, stay on the right.
    private func choiceRects() -> (go: CGRect, stay: CGRect)? {
        guard decision != nil else { return nil }
        let bar = choicesRect(below: bounds.minY + Self.pad + Self.choiceHeight + Self.gap * 2)
        let half = (bar.width - Self.gap * 2) / 2
        let go = CGRect(x: bar.minX, y: bar.minY, width: half, height: bar.height)
        return (go, CGRect(x: go.maxX + Self.gap * 2, y: bar.minY, width: half, height: bar.height))
    }

    /// Switch lit, stay dark; each names its layer and its key. The one
    /// under the mouse lifts. With a limit, a coral line drains along the
    /// stay button's foot.
    private func drawChoices(_ decision: Decision, in bar: CGRect) {
        guard let (go, stay) = choiceRects() else { return }
        drawBox(go, lit: true)
        if hovered == .go {
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: go.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        }
        drawChoice("Switch to \(decision.target)", key: "return", in: go, ink: Self.darkInk)

        drawBox(stay, lit: false)
        if hovered == .stay {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: stay.insetBy(dx: 1.2, dy: 1.2), xRadius: 9, yRadius: 9).fill()
        }
        drawChoice("Stay on \(decision.current)", key: "esc", in: stay, ink: NSColor.white.withAlphaComponent(0.9))

        if let limit = decision.limit, limit > 0 {
            let left = max(0, 1 - (CACurrentMediaTime() - decision.started) / limit)
            let track = CGRect(x: stay.minX + 10, y: stay.minY + 5, width: stay.width - 20, height: 2)
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
            LatticesPointer.coral.setFill()
            NSBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * left, height: track.height), xRadius: 1, yRadius: 1).fill()
        }
    }

    /// `title` on the left, `key` as a keycap on the right.
    private func drawChoice(_ title: String, key: String, in rect: CGRect, ink: NSColor) {
        let keyWidth = ceil((key as NSString).size(withAttributes: [.font: Self.keyFont]).width) + 12
        let cap = CGRect(x: rect.maxX - 12 - keyWidth, y: rect.midY - 10, width: keyWidth, height: 20)
        let capPath = NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5)
        ink.withAlphaComponent(0.1).setFill()
        capPath.fill()
        ink.withAlphaComponent(0.35).setStroke()
        capPath.lineWidth = 0.8
        capPath.stroke()
        drawText(key, font: Self.keyFont, colour: ink.withAlphaComponent(0.8), in: cap)
        let text = CGRect(x: rect.minX + 14, y: rect.minY, width: cap.minX - 10 - rect.minX - 14, height: rect.height)
        drawText(title, font: Self.choiceFont, colour: ink, in: text, alignment: .left)
    }

    func endDecision() {
        // Left drawn as it was while the pad fades; only the clock stops.
        guard decision != nil else { return }
        decision = nil
        hovered = nil
        link?.invalidate()
        link = nil
        pose = to
    }

    private func choice(at point: CGPoint) -> Choice? {
        guard let (go, stay) = choiceRects() else { return nil }
        if go.contains(point) { return .go }
        if stay.contains(point) { return .stay }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let decision, let picked = choice(at: convert(event.locationInWindow, from: nil)) else { return }
        decision.choose(picked)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let now = choice(at: convert(event.locationInWindow, from: nil))
        guard now != hovered else { return }
        hovered = now
        if now != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard hovered != nil else { return }
        hovered = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    /// The main screen at its shape, and on it the layer's windows where a
    /// switch would leave them, back to front. One sitting on another
    /// steps down and right of it, so a stack shows its depth. The layer's
    /// own windows are bright, what it had showing beside them dimmer, and
    /// one that comes back with the switch has a dashed edge. Under it,
    /// what the switch puts away.
    private func drawMap(_ map: LayerForecast, in box: CGRect) {
        drawBox(box, lit: false)
        let inner = box.insetBy(dx: Self.mapInset, dy: Self.mapInset)
        let screen = CGRect(x: inner.minX, y: inner.minY + Self.mapCaption, width: inner.width, height: inner.height - Self.mapCaption)
        let screenPath = NSBezierPath(roundedRect: screen, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.35).setFill()
        screenPath.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        screenPath.lineWidth = 0.8
        screenPath.stroke()

        NSGraphicsContext.saveGraphicsState()
        screenPath.addClip()
        var drawn: [CGRect] = []
        for tile in map.tiles {
            var rect = CGRect(
                x: screen.minX + tile.frame.minX * screen.width,
                y: screen.maxY - tile.frame.maxY * screen.height,
                width: tile.frame.width * screen.width,
                height: tile.frame.height * screen.height
            ).insetBy(dx: 1.5, dy: 1.5)
            // On top of another at nearly the same spot: step down and right.
            let depth = drawn.filter { abs($0.minX - rect.minX) < 6 && abs($0.maxY - rect.maxY) < 6 }.count
            rect = rect.offsetBy(dx: CGFloat(depth) * Self.depthStep, dy: -CGFloat(depth) * Self.depthStep)
            drawn.append(rect.offsetBy(dx: -CGFloat(depth) * Self.depthStep, dy: CGFloat(depth) * Self.depthStep))
            drawTile(tile, in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()

        if map.tiles.isEmpty {
            drawText("Nothing here", font: Self.noteFont, colour: NSColor.white.withAlphaComponent(0.4), in: screen)
        }
        let caption = CGRect(x: inner.minX + 2, y: inner.minY, width: inner.width - 4, height: Self.mapCaption)
        if map.putAwayCount > 0 {
            let apps = map.putAway.prefix(3).joined(separator: ", ") + (map.putAway.count > 3 ? " +\(map.putAway.count - 3)" : "")
            let count = map.putAwayCount == 1 ? "1 window" : "\(map.putAwayCount) windows"
            drawText("Puts away \(count): \(apps)", font: Self.noteFont, colour: NSColor.white.withAlphaComponent(0.55), in: caption, alignment: .left)
        } else {
            drawText("Puts nothing away", font: Self.noteFont, colour: NSColor.white.withAlphaComponent(0.4), in: caption, alignment: .left)
        }
    }

    private func drawTile(_ tile: LayerForecast.Tile, in rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(srgbRed: 0.17, green: 0.20, blue: 0.22, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = 1
        if tile.returning { path.setLineDash([3, 2], count: 2, phase: 0) }
        NSColor.white.withAlphaComponent(tile.member ? 0.55 : 0.22).setStroke()
        path.stroke()

        let alpha: CGFloat = tile.member ? 0.92 : 0.55
        let label = rect.insetBy(dx: 7, dy: 4)
        guard label.width > 18, label.height > 10 else { return }
        let lineHeight: CGFloat = 16
        let first = CGRect(x: label.minX, y: label.maxY - lineHeight, width: label.width, height: lineHeight)
        drawText(tile.app, font: Self.tileFont, colour: NSColor.white.withAlphaComponent(alpha), in: first, alignment: .left)
        if !tile.title.isEmpty, tile.title != tile.app, label.height > lineHeight * 2 + 2 {
            let second = first.offsetBy(dx: 0, dy: -lineHeight + 1)
            drawText(tile.title, font: Self.titleFont, colour: NSColor.white.withAlphaComponent(alpha * 0.6), in: second, alignment: .left)
        }
    }

    /// The layer's apps, one per row: the icon, the name, and where its
    /// windows are on the right when they aren't here. Away rows dim a
    /// little, apps with no window more.
    private func drawList(in box: CGRect) {
        drawBox(box, lit: false)
        let inner = box.insetBy(dx: Self.listInset.width, dy: Self.listInset.height)
        for (index, row) in rows.enumerated() {
            let line = CGRect(x: inner.minX, y: inner.maxY - CGFloat(index + 1) * Self.rowHeight, width: inner.width, height: Self.rowHeight)
            let alpha: CGFloat = switch row.presence {
            case .here: 1
            case .away: 0.62
            case .absent: 0.36
            }
            let icon = CGRect(x: line.minX, y: line.midY - Self.iconSide / 2, width: Self.iconSide, height: Self.iconSide)
            if let image = row.icon {
                image.draw(in: icon, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            } else {
                NSColor.white.withAlphaComponent(0.14 * alpha).setFill()
                NSBezierPath(roundedRect: icon.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5).fill()
            }
            var nameRect = CGRect(x: icon.maxX + Self.iconGap, y: line.minY, width: line.maxX - icon.maxX - Self.iconGap, height: line.height)
            if let note = row.note {
                let width = ceil((note as NSString).size(withAttributes: [.font: Self.noteFont]).width)
                let noteRect = CGRect(x: line.maxX - width, y: line.minY, width: width, height: line.height)
                let noteAlpha: CGFloat = row.presence == .absent ? 0.4 : 0.62
                drawText(note, font: Self.noteFont, colour: NSColor.white.withAlphaComponent(noteAlpha), in: noteRect, alignment: .right)
                nameRect.size.width = noteRect.minX - Self.noteGap - nameRect.minX
            }
            drawText(row.name, font: Self.nameFont, colour: NSColor.white.withAlphaComponent(0.9 * alpha), in: nameRect, alignment: .left)
        }
    }

    /// A cell in the dark ink, or lit in the light one. The corners follow the
    /// cell size, so the bar shares them.
    private func drawBox(_ rect: CGRect, lit: Bool) {
        let inset: CGFloat = lit ? 0 : 1.2
        let box = rect.insetBy(dx: inset, dy: inset)
        let radius = (Self.cellSize - inset * 2) * 0.22
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = lit ? 12 : 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(lit ? 0.36 : 0.22)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        (lit ? Self.ink : Self.darkInk.withAlphaComponent(0.92)).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let lip = CGRect(x: box.minX + 1.5, y: box.maxY - 1.8, width: box.width - 3, height: 1.1)
        NSColor.white.withAlphaComponent(lit ? 0.30 : 0.10).setFill()
        NSBezierPath(roundedRect: lip, xRadius: 0.6, yRadius: 0.6).fill()

        // A dark hairline keeps the lit cell's edge over light windows.
        path.lineWidth = lit ? 1.0 : 0.6
        (lit ? NSColor.black.withAlphaComponent(0.2) : NSColor.white.withAlphaComponent(0.14)).setStroke()
        path.stroke()
    }

    /// The mark's pointer in coral, aimed at the lit slot, or at rest when no
    /// slot is lit.
    private func drawPointer(in cell: CGRect) {
        let centre = CGPoint(x: cell.midX, y: cell.midY)
        LatticesPointer.coral.setFill()
        LatticesPointer.path(pose, side: cell.width * Self.pointerScale, centre: centre).fill()
    }

    /// One line of `text` centred in `rect` on its cap height, cut short with
    /// an ellipsis when it doesn't fit.
    private func drawText(_ text: String, font: NSFont, colour: NSColor, in rect: CGRect, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        // Lines run down from the top, so the baseline lands `ascender` below
        // it; the extra height underneath only keeps the line from clipping.
        let top = rect.midY - font.capHeight / 2 + font.ascender
        let line = CGRect(x: rect.minX, y: top - rect.height, width: rect.width, height: rect.height)
        (text as NSString).draw(in: line, withAttributes: [
            .font: font,
            .foregroundColor: colour,
            .paragraphStyle: style,
        ])
    }

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = font.fontDescriptor.withDesign(.rounded) else { return font }
        return NSFont(descriptor: descriptor, size: size) ?? font
    }
}
