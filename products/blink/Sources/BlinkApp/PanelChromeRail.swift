import AppKit
import HudsonObservability
import SwiftUI

/// The note's title bar, lifted out of the note's own rectangle: ✕, title,
/// focus ring, and mode toggle in a strip sitting flush on top of the page.
///
/// Why a separate window rather than a band inside the panel: the note's frame
/// is load-bearing twice over. It is autosaved per note and has to restore
/// exactly, and the webview's content rect is what decides where the prose
/// wraps. Growing the panel to make room for chrome would drift the remembered
/// geometry; insetting the webview would reflow the note every time the rail
/// appeared. A child window leaves the panel's frame untouched, so the chrome
/// is genuinely off the page instead of merely looking like it.
///
/// It should not *read* as a separate window, though. The rail sits flush
/// against the note and rounds only its outer corners, while the note squares
/// the corners along the shared seam — together they form one silhouette.
///
/// AppKit moves child windows with their parent, so dragging, flinging, and
/// shading need no bookkeeping here — only width changes and screen edges do.
@MainActor
final class PanelChromeRail {
    /// Slim enough to read as a title bar, tall enough for a 24pt hit target —
    /// the point of moving these controls off the page is that they stop being
    /// fiddly.
    static let height: CGFloat = 26
    /// Minimum tab width — title + controls. Wider notes keep a centered tab
    /// rather than a second full-width story.
    static let minTabWidth: CGFloat = 220
    /// Gap from the note's sides so the page corners stay the silhouette.
    static let sideGutter: CGFloat = 14
    /// How far the tab sits on the page. Locks onto the existing top edge
    /// without covering the first line of prose.
    static let seat: CGFloat = 6

    /// Where the rail ended up relative to the note. Normally above; a note
    /// parked against the top of the screen gets it tucked underneath instead.
    enum Placement { case above, below }

    private weak var panel: NotePanel?
    private let window: RailPanel
    private let host: NSHostingView<PanelChromeRailView>
    private let glass: NSVisualEffectView
    private let backdrop: NSView
    private let drag: DragHandle
    private var observers: [NSObjectProtocol] = []
    private var isVisible = false
    private var cornerRadius: CGFloat
    private(set) var placement: Placement = .above
    private let log = HudLogger(category: "blink.chrome")

    /// Screen frame of the rail window. Used by the note to treat the strip as
    /// part of the hover target when crossing the seam.
    var frame: NSRect { window.frame }
    var isShowing: Bool { isVisible }

    /// Fired when the pointer enters or leaves the rail, so the note can keep
    /// the strip up while you reach for it.
    var onHoverChanged: ((Bool) -> Void)?

    /// Fired when the rail flips sides, so the note can move its squared corners
    /// to whichever edge now carries the seam.
    var onPlacementChanged: ((Placement) -> Void)?

    init(
        panel: NotePanel,
        state: PanelModeState,
        title: String,
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material,
        tint: CGFloat,
        accent: NSColor,
        onClose: @escaping () -> Void,
        onSelectMode: @escaping (String) -> Void,
        onToggleFocus: @escaping () -> Void
    ) {
        self.panel = panel
        self.cornerRadius = cornerRadius

        let rail = RailPanel(
            contentRect: NSRect(x: 0, y: 0, width: panel.frame.width, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        rail.isFloatingPanel = true
        rail.hidesOnDeactivate = false
        rail.isOpaque = false
        rail.backgroundColor = .clear
        rail.hasShadow = false
        rail.appearance = panel.appearance
        rail.alphaValue = 0
        // The strip has to see mouse-moved or crossing the seam never marks
        // railPointerInside, and the linger expires before you can click it.
        rail.acceptsMouseMovedEvents = true
        // Invisible chrome must not swallow clicks meant for whatever is behind
        // it; `setVisible` re-arms this in step with the fade.
        rail.ignoresMouseEvents = true

        let glass = NSVisualEffectView()
        // Match the note's glass so the rail is a continuation of the page,
        // not a separate hud pill parked above it. Material comes from the
        // panel's resolved theme — never a second global lookup.
        glass.material = material
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        // No surrounding hairline — the rail is selected chrome, not a framed
        // box. Silhouette comes from the shared glass + outer corner radii.
        glass.layer?.borderWidth = 0


        // Same contrast job the note's tint layer performs: deepen/lift the
        // glass so glyphs stay legible over the desktop. Kept light enough that
        // the strip still reads as one material with the page.
        let backdrop = NSView()
        backdrop.wantsLayer = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: glass.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])


        // The whole strip is the grab surface — the one job a title bar has
        // always had. The controls live *inside* the handle rather than beside
        // it, so AppKit offers them the click first and anything they decline
        // (title, padding, empty space) falls through to the drag.
        let drag = DragHandle()
        drag.showsGrip = false
        drag.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(drag)
        NSLayoutConstraint.activate([
            drag.topAnchor.constraint(equalTo: glass.topAnchor),
            drag.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            drag.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])

        let host = NSHostingView(
            rootView: PanelChromeRailView(
                state: state,
                title: title,
                onClose: onClose,
                onSelectMode: onSelectMode,
                onToggleFocus: onToggleFocus
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        drag.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: drag.topAnchor),
            host.leadingAnchor.constraint(equalTo: drag.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: drag.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: drag.bottomAnchor),
        ])

        let hover = RailHoverView()
        hover.translatesAutoresizingMaskIntoConstraints = false
        hover.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: hover.topAnchor),
            glass.leadingAnchor.constraint(equalTo: hover.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: hover.trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: hover.bottomAnchor),
        ])
        rail.contentView = hover
        self.window = rail
        self.host = host
        self.glass = glass
        self.backdrop = backdrop
        self.drag = drag
        hover.onChanged = { [weak self] inside in
            self?.onHoverChanged?(inside)
        }
        applySurface(material: material, tint: tint, accent: accent)
        applyCorners()

        panel.addChildWindow(rail, ordered: .above)
        syncFrame()

        // The parent carries the rail on moves for free. Resizes change only the
        // width, and a screen change can invalidate the above/below choice.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didResizeNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncFrame() }
            },
            center.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncFrame() }
            },
        ]
    }

    /// Track the note's width and the edge the rail is attached to. Called on
    /// every parent move/resize, so it stays cheap and allocation-free.
    func syncFrame() {
        guard let panel else { return }
        let noteFrame = panel.frame
        let maxWidth = max(noteFrame.width - Self.sideGutter * 2, Self.minTabWidth)
        let width = min(max(Self.minTabWidth, noteFrame.width * 0.62), maxWidth)
        var origin = NSPoint(
            x: noteFrame.midX - width / 2,
            y: noteFrame.maxY - Self.seat
        )
        var next = Placement.above

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame,
           origin.y + Self.height > visible.maxY {
            origin.y = noteFrame.minY - Self.height + Self.seat
            next = .below
        }

        window.setFrame(
            NSRect(origin: origin, size: NSSize(width: width, height: Self.height)),
            display: true
        )

        if next != placement {
            placement = next
            applyCorners()
            onPlacementChanged?(next)
        }
    }

    func setTitle(_ title: String) {
        host.rootView.title = title
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        window.appearance = appearance
    }

    /// Paint the note's own glass material and mode tint onto the rail so the
    /// two share one surface. Callers pass the already-resolved theme values —
    /// the rail must not re-resolve config or per-note presentation drifts.
    func applySurface(material: NSVisualEffectView.Material, tint: CGFloat, accent: NSColor) {
        glass.material = material
        let scheme = AppearanceManager.shared.scheme
        let paper = NSColor(cgColor: NotePanel.tintColor(scheme))
            ?? (scheme.isDark ? .black : .white)
        let wash = scheme.isDark ? 0.10 : 0.04
        let washed = paper.blended(withFraction: wash, of: accent) ?? paper
        backdrop.layer?.backgroundColor = washed.cgColor
        backdrop.alphaValue = min(tint + (scheme.isDark ? 0.18 : 0.30), 0.84)
        glass.layer?.borderWidth = 0
        var view = host.rootView
        view.accent = Color(nsColor: accent)
        host.rootView = view
    }

    func applyCornerRadius(_ radius: CGFloat) {
        guard radius != cornerRadius else { return }
        cornerRadius = radius
        applyCorners()
    }

    /// Capsule — the rail is a tab, not a second box sharing the note's edge.
    private func applyCorners() {
        let radius = Self.height / 2
        glass.layer?.cornerRadius = radius
        glass.layer?.maskedCorners = [
            .layerMinXMinYCorner, .layerMaxXMinYCorner,
            .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
        ]
        backdrop.layer?.cornerRadius = radius
        backdrop.layer?.maskedCorners = glass.layer?.maskedCorners
            ?? [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
            ]
    }


    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            syncFrame()
            window.ignoresMouseEvents = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.completionHandler = { [weak self] in
                guard let self, !self.isVisible else { return }
                self.window.ignoresMouseEvents = true
            }
            window.animator().alphaValue = visible ? 1 : 0
        }
    }

    /// AppKit will not rehome a parent+child pair onto another display. A
    /// cross-monitor drag has to travel as a lone window; we follow by frame
    /// and reattach once the note has a new screen.
    func detachFromParent() {
        guard window.parent != nil else { return }
        panel?.removeChildWindow(window)
        window.level = panel?.level ?? .floating
        window.orderFront(nil)
    }

    func attachToParent() {
        guard let panel, window.parent == nil else { return }
        panel.addChildWindow(window, ordered: .above)
        syncFrame()
    }


    /// Detach and close. The rail is a child window, so leaving it behind would
    /// strand a floating strip with no note under it.
    func dismantle() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        panel?.removeChildWindow(window)
        window.orderOut(nil)
        window.close()
    }

}

private final class RailHoverView: NSView {
    var onChanged: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(next)
        tracking = next
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onChanged?(false)
    }
}

private final class RailPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Positioned only relative to the note. AppKit must not pin it to the
    /// origin display while the note is crossing a seam.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }


    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
             .mouseEntered, .mouseExited:
            if let note = parent as? NotePanel {
                note.setRailPointerInside(frame.contains(NSEvent.mouseLocation))
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Blinkified title bar: identity on the left, instruments on the right, and no
/// OS furniture anywhere. Deliberately not an `NSToolbar` — this belongs to the
/// note, not to a document window.
private struct PanelChromeRailView: View {
    @ObservedObject var state: PanelModeState
    var title: String
    var accent: Color = Color(
        nsColor: NSColor(srgbRed: 93 / 255, green: 158 / 255, blue: 250 / 255, alpha: 1)
    )
    var onClose: () -> Void
    var onSelectMode: (String) -> Void
    var onToggleFocus: () -> Void

    /// Adaptive rather than the in-note chrome's fixed white: the rail follows
    /// the app scheme, so its ink has to flip with it or vanish in light mode.
    private var ink: Color { .primary }

    var body: some View {
        HStack(spacing: 6) {
            CloseGlyph(ink: ink, onTap: onClose)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            FocusGlyph(state: state, ink: ink, accent: accent, onTap: onToggleFocus)
                .frame(width: 24, height: 24)
            ModeToggle(state: state, ink: ink, onSelect: onSelectMode, accent: accent)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
