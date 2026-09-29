import AppKit

// MARK: - Layer Switch HUD

/// The layer switch, laid out like the matrix picker: nine numbered slots, one
/// per ⌘⌥1–9, with the new layer's slot lit and its name in a bar underneath.
/// Slots without a layer stay dim. `acknowledge` shows the bar alone, for
/// actions that don't land on a slot: tabs, and saved Studio layers.
final class LayerBezel {
    static let shared = LayerBezel()

    private var panel: NSPanel?
    private var bezelView: LayerBezelView?
    private var dismissTimer: Timer?
    /// Bumped by every show, so a fade-out that ends after a newer show leaves
    /// the panel up.
    private var generation = 0

    private init() {}

    /// Lights slot `index` of the `total` that hold a layer, and names it
    /// `label`. A layer past the ninth has no slot, so none lights.
    func show(label: String, index: Int, total: Int) {
        present(label: label, slots: LayerBezelView.Slots(lit: index, filled: total))
    }

    /// Shows `label` in the bar alone.
    func acknowledge(_ label: String) {
        present(label: label, slots: nil)
    }

    func dismiss() {
        guard let panel, panel.isVisible else { return }
        let shown = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard self?.generation == shown else { return }
            panel.orderOut(nil)
        })
    }

    private func present(label: String, slots: LayerBezelView.Slots?) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        dismissTimer?.invalidate()
        generation += 1

        let (panel, view) = ensurePanel()
        view.show(label: label, slots: slots)

        // Centred, two thirds of the way up the screen.
        let size = LayerBezelView.size(label: label, slots: slots)
        let area = screen.frame
        let frame = CGRect(
            x: round(area.midX - size.width / 2),
            y: round(area.minY + area.height * 2 / 3 - size.height / 2),
            width: size.width,
            height: size.height
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func ensurePanel() -> (NSPanel, LayerBezelView) {
        if let panel, let bezelView { return (panel, bezelView) }

        let size = LayerBezelView.size(label: "", slots: LayerBezelView.Slots(lit: 0, filled: 0))
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
/// name bar as a fourth row. Unlike the matrix's see-through cells these are
/// nearly opaque, so the numbers read over any window.
final class LayerBezelView: NSView {
    struct Slots {
        /// The lit slot, counted from 0.
        var lit: Int
        /// How many slots hold a layer.
        var filled: Int
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

    /// #f2f2f2, the mark's ink on dark, lights the active slot.
    static let ink = NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 0.94)
    /// #101518, the mark's ink on light, fills the other cells and numbers the
    /// lit one.
    static let darkInk = NSColor(srgbRed: 16 / 255, green: 21 / 255, blue: 24 / 255, alpha: 1)
    static let numberFont = rounded(17, .semibold)
    static let labelFont = rounded(13, .semibold)

    private var label = ""
    private var slots: Slots?

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(label: String, slots: Slots?) {
        self.label = label
        self.slots = slots
        needsDisplay = true
    }

    /// Fixed with slots, so a switch never resizes the panel; fitted to
    /// `label` without.
    static func size(label: String, slots: Slots?) -> CGSize {
        if slots != nil {
            return CGSize(width: gridSide + pad * 2, height: gridSide + gap + barHeight + pad * 2)
        }
        let text = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
        let width = min(max(gridSide, text + barInset * 2), maxBarWidth)
        return CGSize(width: width + pad * 2, height: barHeight + pad * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let content = bounds.insetBy(dx: Self.pad, dy: Self.pad)
        if let slots {
            for slot in 0..<9 {
                let (col, row) = (slot % 3, slot / 3)
                let cell = CGRect(
                    x: content.minX + CGFloat(col) * (Self.cellSize + Self.gap),
                    y: content.maxY - CGFloat(row + 1) * Self.cellSize - CGFloat(row) * Self.gap,
                    width: Self.cellSize,
                    height: Self.cellSize
                )
                let lit = slot == slots.lit
                drawBox(cell, lit: lit)
                let colour = lit ? Self.darkInk : NSColor.white.withAlphaComponent(slot < slots.filled ? 0.82 : 0.24)
                drawText("\(slot + 1)", font: Self.numberFont, colour: colour, in: cell)
            }
        }
        let bar = CGRect(x: content.minX, y: content.minY, width: content.width, height: Self.barHeight)
        drawBox(bar, lit: false)
        drawText(label, font: Self.labelFont, colour: NSColor.white.withAlphaComponent(0.92), in: bar.insetBy(dx: Self.barInset, dy: 0))
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

    /// One line of `text` centred in `rect` on its cap height, cut short with
    /// an ellipsis when it doesn't fit.
    private func drawText(_ text: String, font: NSFont, colour: NSColor, in rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
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
