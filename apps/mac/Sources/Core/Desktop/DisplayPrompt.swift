import AppKit

/// A question asked on one or more screens at once, drawn like the layer
/// pad: a title, a line of detail, a lit button and a dark one. Clicking the
/// lit button on a screen answers with that screen; the dark one, or the
/// wait running out, answers nil. Answering on one screen closes them all.
final class DisplayPrompt {
    static let shared = DisplayPrompt()

    /// How long it waits before leaving things be.
    static let wait: TimeInterval = 30

    private var panels: [NSPanel] = []
    private var answer: ((DisplayGather.Screen?) -> Void)?
    private var timeout: DispatchWorkItem?

    private init() {}

    var isAsking: Bool { answer != nil }

    func ask(
        on screens: [DisplayGather.Screen],
        title: String,
        detail: String,
        go: String,
        stay: String,
        answer: @escaping (DisplayGather.Screen?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        close(with: nil)
        self.answer = answer
        let started = CACurrentMediaTime()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for screen in screens {
            let view = DisplayPromptView(
                title: title, detail: detail, go: go, stay: stay,
                started: started, limit: Self.wait
            ) { [weak self] picked in self?.close(with: picked ? screen : nil) }
            let size = view.frame.size
            // Top-left visible frame back to AppKit's bottom-left.
            let visible = DisplayGeometryMapper.topLeftFrame(screen.visible, primaryHeight: primaryHeight)
            let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 24)
            let panel = NSPanel(
                contentRect: CGRect(origin: origin, size: size),
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
            panel.animationBehavior = .none
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        let leave = DispatchWorkItem { [weak self] in self?.close(with: nil) }
        timeout = leave
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wait, execute: leave)
    }

    /// Closes every screen's prompt, answering with `picked`.
    func close(with picked: DisplayGather.Screen?) {
        timeout?.cancel()
        timeout = nil
        for panel in panels {
            (panel.contentView as? DisplayPromptView)?.stop()
            panel.orderOut(nil)
        }
        panels = []
        let answer = self.answer
        self.answer = nil
        answer?(picked)
    }
}

final class DisplayPromptView: NSView {
    private enum Choice { case go, stay }

    private let title: String
    private let detail: String
    private let go: String
    private let stay: String
    private let started: CFTimeInterval
    private let limit: TimeInterval
    private let choose: (Bool) -> Void
    private var hovered: Choice?
    private var tracking: NSTrackingArea?
    private var clock: Timer?

    static let margin: CGFloat = 14
    static let inset: CGFloat = 14
    static let width: CGFloat = 440
    static let buttonHeight: CGFloat = 40
    static let titleFont = rounded(14, .semibold)
    static let detailFont = rounded(12, .medium)
    static let choiceFont = rounded(13, .semibold)

    init(title: String, detail: String, go: String, stay: String, started: CFTimeInterval, limit: TimeInterval, choose: @escaping (Bool) -> Void) {
        self.title = title
        self.detail = detail
        self.go = go
        self.stay = stay
        self.started = started
        self.limit = limit
        self.choose = choose
        let height = Self.margin * 2 + Self.inset * 2 + 20 + 18 + 12 + Self.buttonHeight
        super.init(frame: CGRect(x: 0, y: 0, width: Self.width + Self.margin * 2, height: height))
        clock = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func stop() {
        clock?.invalidate()
        clock = nil
    }

    private var box: CGRect { bounds.insetBy(dx: Self.margin, dy: Self.margin) }

    private var buttons: (go: CGRect, stay: CGRect) {
        let row = CGRect(x: box.minX + Self.inset, y: box.minY + Self.inset, width: box.width - Self.inset * 2, height: Self.buttonHeight)
        let half = (row.width - 8) / 2
        return (CGRect(x: row.minX, y: row.minY, width: half, height: row.height),
                CGRect(x: row.minX + half + 8, y: row.minY, width: half, height: row.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        LayerBezelView.darkInk.withAlphaComponent(0.94).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.lineWidth = 0.6
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.stroke()

        let text = box.insetBy(dx: Self.inset + 2, dy: 0)
        drawText(title, font: Self.titleFont, colour: LayerBezelView.ink,
                 in: CGRect(x: text.minX, y: box.maxY - Self.inset - 20, width: text.width, height: 20))
        drawText(detail, font: Self.detailFont, colour: NSColor.white.withAlphaComponent(0.55),
                 in: CGRect(x: text.minX, y: box.maxY - Self.inset - 38, width: text.width, height: 18))

        let (goRect, stayRect) = buttons
        let goPath = NSBezierPath(roundedRect: goRect, xRadius: 9, yRadius: 9)
        LayerBezelView.ink.setFill()
        goPath.fill()
        if hovered == .go {
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: goRect.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        }
        drawText(go, font: Self.choiceFont, colour: LayerBezelView.darkInk, in: goRect, alignment: .center)

        let stayPath = NSBezierPath(roundedRect: stayRect, xRadius: 9, yRadius: 9)
        NSColor.white.withAlphaComponent(hovered == .stay ? 0.12 : 0.06).setFill()
        stayPath.fill()
        stayPath.lineWidth = 0.6
        NSColor.white.withAlphaComponent(0.14).setStroke()
        stayPath.stroke()
        drawText(stay, font: Self.choiceFont, colour: NSColor.white.withAlphaComponent(0.9), in: stayRect, alignment: .center)

        // The wait drains along the foot of the button that leaves things be.
        let left = max(0, 1 - (CACurrentMediaTime() - started) / limit)
        let track = CGRect(x: stayRect.minX + 10, y: stayRect.minY + 5, width: stayRect.width - 20, height: 2)
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()
        LatticesPointer.coral.setFill()
        NSBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: track.width * left, height: 2), xRadius: 1, yRadius: 1).fill()
    }

    private func choice(at point: CGPoint) -> Choice? {
        let (goRect, stayRect) = buttons
        if goRect.contains(point) { return .go }
        if stayRect.contains(point) { return .stay }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let picked = choice(at: convert(event.locationInWindow, from: nil)) else { return }
        choose(picked == .go)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let now = choice(at: convert(event.locationInWindow, from: nil))
        if now != hovered {
            hovered = now
            (now == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        NSCursor.arrow.set()
    }

    private func drawText(_ text: String, font: NSFont, colour: NSColor, in rect: CGRect, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
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
