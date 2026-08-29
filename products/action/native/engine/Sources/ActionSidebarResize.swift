import AppKit
import SwiftUI

/// Pure resize math for the launcher rail's label column.
///
/// Kept separate from the gesture so every width decision can be reasoned about
/// without simulating a drag. Two clamps matter and they are deliberately
/// different:
///
/// - **Preview** width may fall below the minimum, all the way to zero, so the
///   edge can visually travel toward the collapse threshold while dragging.
/// - **Committed** width always lands inside `min...max`, so whatever is stored
///   is a width the rail can actually re-expand to.
///
/// Ported from Hudson's `HudSidebarResizeGeometry` (`~/dev/hudson`), which Linea
/// uses; the contract is theirs, the numbers are tuned to Action's rail.
struct ActionSidebarResizeGeometry: Equatable {
    let minLabelWidth: CGFloat
    let maxLabelWidth: CGFloat
    /// Dragging left past this preview width collapses the rail.
    let collapseLabelWidth: CGFloat
    /// The width the drag magnets toward: the one the rail shipped at, so it can
    /// be put back exactly without aiming.
    let defaultLabelWidth: CGFloat
    /// Total travel below which a press counts as a click rather than a resize.
    ///
    /// This decides the *outcome* of a press, not when the edge starts moving —
    /// the edge tracks the pointer from the first pixel either way. A press that
    /// ends inside this radius rewinds its own width change and toggles instead,
    /// so a click never leaves the rail two points narrower than it found it.
    let activationDistance: CGFloat
    /// Magnet radius around `defaultLabelWidth`. Hold Option to suppress it.
    let snapDistance: CGFloat

    static let `default` = ActionSidebarResizeGeometry(
        minLabelWidth: 168,
        maxLabelWidth: 320,
        collapseLabelWidth: 128,
        defaultLabelWidth: 200,
        activationDistance: 3,
        snapDistance: 7
    )

    init(
        minLabelWidth: CGFloat,
        maxLabelWidth: CGFloat,
        collapseLabelWidth: CGFloat,
        defaultLabelWidth: CGFloat = 200,
        activationDistance: CGFloat,
        snapDistance: CGFloat = 7
    ) {
        let low = max(0, minLabelWidth)
        self.minLabelWidth = low
        // An inverted range would otherwise make `committedWidth` snap to the
        // maximum and strand the rail below its own minimum.
        self.maxLabelWidth = max(low, maxLabelWidth)
        self.collapseLabelWidth = max(0, collapseLabelWidth)
        self.defaultLabelWidth = min(max(low, defaultLabelWidth), max(low, maxLabelWidth))
        self.activationDistance = max(0, activationDistance)
        self.snapDistance = max(0, snapDistance)
    }

    func committedWidth(_ width: CGFloat) -> CGFloat {
        min(maxLabelWidth, max(minLabelWidth, width))
    }

    func previewWidth(_ width: CGFloat) -> CGFloat {
        min(maxLabelWidth, max(0, width))
    }

    /// A press that never travelled this far is a click, whichever direction it
    /// wandered in.
    func isClick(travel: CGFloat) -> Bool {
        abs(travel) < activationDistance
    }

    /// Pulls a live width onto the default when it passes close by.
    ///
    /// One magnet, not a grid of them: the point is that the rail can be put
    /// back exactly where it shipped without aiming, not that every width is
    /// quantised. Above the collapse threshold only — near the threshold the
    /// gesture is about collapsing, and a magnet there fights it.
    func snapped(_ width: CGFloat, magnetsEnabled: Bool) -> CGFloat {
        guard magnetsEnabled, width > collapseLabelWidth else { return width }
        guard abs(width - defaultLabelWidth) <= snapDistance else { return width }
        return defaultLabelWidth
    }

    /// Compact drags start at zero so the labels grow out of the rail instead of
    /// snapping to their stored width the instant the drag activates.
    func dragStartWidth(isCompact: Bool, currentWidth: CGFloat) -> CGFloat {
        isCompact ? 0 : committedWidth(currentWidth)
    }

    /// Which way the rail can still travel from a given live width.
    ///
    /// macOS says this with the pointer and Action was not saying it: a rail
    /// already at 320 that still shows a two-headed arrow is promising travel
    /// that does not exist. Finder, Xcode and Mail all switch to the one-headed
    /// cursor at the stops.
    enum Travel: Equatable {
        case both
        /// Only narrower — the rail is at its maximum.
        case leftOnly
        /// Only wider — the rail is compact or at its minimum.
        case rightOnly
    }

    func travel(isCompact: Bool, width: CGFloat) -> Travel {
        if isCompact { return .rightOnly }
        if width >= maxLabelWidth { return .leftOnly }
        // Below the minimum the rail is heading for collapse, which is still a
        // leftward destination, so both directions remain live.
        return .both
    }

    enum Outcome: Equatable {
        case expand(labelWidth: CGFloat)
        /// `restoreWidth` is kept in storage so the next expansion returns to a
        /// usable size rather than to the collapse threshold.
        case collapse(restoreWidth: CGFloat)
        case resize(labelWidth: CGFloat)
    }

    func outcome(
        isCompact: Bool,
        startWidth: CGFloat,
        finalWidth: CGFloat,
        horizontalDelta: CGFloat
    ) -> Outcome {
        if isCompact {
            // A leftward drag out of compact has nowhere to go; leave the rail
            // where it is rather than expanding it to the minimum behind the
            // operator's back.
            guard horizontalDelta > 0 else { return .collapse(restoreWidth: committedWidth(startWidth)) }
            return .expand(labelWidth: committedWidth(max(finalWidth, minLabelWidth)))
        }
        if finalWidth <= collapseLabelWidth, horizontalDelta < 0 {
            return .collapse(restoreWidth: committedWidth(startWidth))
        }
        return .resize(labelWidth: committedWidth(finalWidth))
    }
}

// MARK: - Live drag state

/// The rail's width while a drag is in flight.
///
/// A reference type on purpose, and deliberately *not* observed by the launcher
/// root. Preview width used to be `@State` up there, which meant every mouse
/// move during a resize invalidated the whole window body — the runs ledger
/// rebuilt its rows sixty times a second to answer a question about the
/// sidebar's width. Only `ActionSidebarColumn` subscribes now, so a drag
/// repaints the rail and nothing else.
final class ActionSidebarResizeState: ObservableObject {
    @Published var previewWidth: CGFloat?
}

// MARK: - The divider

/// The draggable edge of the rail.
///
/// AppKit, not `DragGesture`, and that is the whole point of the file. A SwiftUI
/// gesture cannot express the three things a Mac divider is expected to do:
///
/// - **Hold its cursor for the length of the drag.** `.onHover` reports the
///   pointer leaving the 8pt strip the moment the drag pulls past it, so the
///   resize arrows flipped back to the plain pointer mid-gesture. Tracking areas
///   and `NSCursor.set()` on each dragged event keep it.
/// - **Resize a window that is not key.** `acceptsFirstMouse` makes the first
///   click on a background window both activate it and start the drag. Without
///   it the operator clicks, nothing happens, and they click again.
/// - **Not leak a pushed cursor.** The old code called `NSCursor.push()` on
///   hover-in and `pop()` on hover-out. Any path that removed the view while the
///   pointer was over it — collapsing the rail, closing the window — skipped the
///   pop and left the resize cursor stuck app-wide until the next push/pop pair
///   happened to rebalance it. Cursor *rects* are owned by the window and
///   cannot get out of balance.
///
/// A press that does not travel toggles collapse — the same affordance as the
/// toolbar button, reachable where the hand already is. There is deliberately no
/// double-click-to-reset on top of it: the first click of a double-click would
/// have collapsed the rail before the second arrived, and deferring the toggle
/// by the double-click interval to find out would put half a second of lag on
/// the gesture people actually use. The magnet at the default width covers the
/// same need without the conflict — drag near 200 and it lands on 200 exactly.
struct ActionSidebarEdgeHandle: View {
    @Binding var isCompact: Bool
    @Binding var labelWidth: Double
    /// Written, never read: observing it here would push a fresh
    /// `updateNSView` through the representable on every mouse move.
    let resizeState: ActionSidebarResizeState

    var geometry: ActionSidebarResizeGeometry = .default
    /// Hit width. Wider than the hairline it decorates, and wider than the 8pt
    /// the SwiftUI version used: the strip straddles the rule, so 11 buys ~5pt
    /// of grab on each side, which is what the pointer needs to land first try.
    var hitWidth: CGFloat = 11

    var body: some View {
        ActionSidebarDividerRegion(
            isCompact: $isCompact,
            labelWidth: $labelWidth,
            resizeState: resizeState,
            geometry: geometry
        )
        .frame(width: hitWidth)
        .accessibilityElement()
        .accessibilityLabel("Resize sidebar")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ActionSidebarDividerRegion: NSViewRepresentable {
    @Binding var isCompact: Bool
    @Binding var labelWidth: Double
    let resizeState: ActionSidebarResizeState
    let geometry: ActionSidebarResizeGeometry

    func makeNSView(context: Context) -> DividerView {
        let view = DividerView()
        view.apply(context.coordinator)
        return view
    }

    func updateNSView(_ view: DividerView, context: Context) {
        context.coordinator.isCompact = $isCompact
        context.coordinator.labelWidth = $labelWidth
        context.coordinator.resizeState = resizeState
        context.coordinator.geometry = geometry
        view.apply(context.coordinator)
        // The stop the rail sits at decides which cursor the strip advertises,
        // and that stop changes without the pointer moving.
        view.window?.invalidateCursorRects(for: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isCompact: $isCompact,
            labelWidth: $labelWidth,
            resizeState: resizeState,
            geometry: geometry
        )
    }

    final class Coordinator {
        var isCompact: Binding<Bool>
        var labelWidth: Binding<Double>
        var resizeState: ActionSidebarResizeState
        var geometry: ActionSidebarResizeGeometry

        init(
            isCompact: Binding<Bool>,
            labelWidth: Binding<Double>,
            resizeState: ActionSidebarResizeState,
            geometry: ActionSidebarResizeGeometry
        ) {
            self.isCompact = isCompact
            self.labelWidth = labelWidth
            self.resizeState = resizeState
            self.geometry = geometry
        }
    }
}

private final class DividerView: NSView {
    private var coordinator: ActionSidebarDividerRegion.Coordinator?
    private var trackingArea: NSTrackingArea?

    /// Width at the instant the mouse went down, in label-column points.
    private var dragStartWidth: CGFloat?
    /// Pointer x at the instant the mouse went down, in window coordinates.
    /// Absolute positions, not accumulated deltas: a dropped or coalesced event
    /// then costs nothing, where a delta sum would drift for the rest of the
    /// drag.
    private var dragStartX: CGFloat = 0
    private var liveWidth: CGFloat = 0
    private var isDragging = false

    private var geometry: ActionSidebarResizeGeometry {
        coordinator?.geometry ?? .default
    }

    private var isCompact: Bool {
        coordinator?.isCompact.wrappedValue ?? false
    }

    func apply(_ coordinator: ActionSidebarDividerRegion.Coordinator) {
        self.coordinator = coordinator
    }

    // A click on a background window resizes it instead of being spent on
    // activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .cursorUpdate, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    // MARK: Cursor

    private var currentCursor: NSCursor {
        // Mid-drag, `isCompact` is still whatever it was when the press started
        // — it is only committed on mouse-up — so asking it would advertise
        // "you can only widen" for the whole of a drag that has already widened
        // past the minimum and can go back.
        let travel = isDragging
            ? geometry.travel(isCompact: false, width: liveWidth)
            : geometry.travel(isCompact: isCompact, width: liveWidthOrStored)
        switch travel {
        case .both: return .resizeLeftRight
        case .leftOnly: return .resizeLeft
        case .rightOnly: return .resizeRight
        }
    }

    private var liveWidthOrStored: CGFloat {
        if isDragging { return liveWidth }
        return CGFloat(coordinator?.labelWidth.wrappedValue ?? 0)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        currentCursor.set()
    }

    override func mouseExited(with event: NSEvent) {
        // Nothing to do: the cursor rect is the window's, and AppKit restores
        // whatever belongs to wherever the pointer went. Forcing the arrow here
        // would stamp on a neighbour that has a cursor of its own — and during a
        // drag the pointer is routinely outside the strip, which is exactly the
        // flicker this view exists to remove.
    }

    // MARK: Drag

    override func mouseDown(with event: NSEvent) {
        guard let coordinator else { return }
        isDragging = true
        dragStartX = event.locationInWindow.x
        dragStartWidth = geometry.dragStartWidth(
            isCompact: isCompact,
            currentWidth: CGFloat(coordinator.labelWidth.wrappedValue)
        )
        liveWidth = dragStartWidth ?? 0
        currentCursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let start = dragStartWidth, let coordinator else { return }

        let delta = event.locationInWindow.x - dragStartX
        // Tracked from the first pixel. The old gesture waited for 6pt of travel
        // and then jumped the edge to where the pointer already was, which is
        // the single most visible tell that a divider is not a real one.
        let raw = geometry.previewWidth(start + delta)
        let magnetsEnabled = !event.modifierFlags.contains(.option)
        liveWidth = geometry.snapped(raw, magnetsEnabled: magnetsEnabled)

        coordinator.resizeState.previewWidth = liveWidth
        currentCursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, let start = dragStartWidth, let coordinator else { return }
        defer {
            isDragging = false
            dragStartWidth = nil
            coordinator.resizeState.previewWidth = nil
            window?.invalidateCursorRects(for: self)
            // The drag set the cursor directly, bypassing the cursor rects, so
            // a drag that ended away from the strip has to hand the pointer back.
            if !bounds.contains(convert(event.locationInWindow, from: nil)) {
                NSCursor.arrow.set()
            }
        }

        let delta = event.locationInWindow.x - dragStartX

        if geometry.isClick(travel: delta) {
            // The rail moved by at most a couple of points while the operator
            // was, as far as they are concerned, clicking. Put it back and
            // treat the press as the toggle it was.
            withAnimation(.easeInOut(duration: 0.16)) {
                coordinator.isCompact.wrappedValue.toggle()
            }
            return
        }

        switch geometry.outcome(
            isCompact: isCompact,
            startWidth: start,
            finalWidth: liveWidth,
            horizontalDelta: delta
        ) {
        case let .expand(width):
            coordinator.labelWidth.wrappedValue = Double(width)
            withAnimation(.easeInOut(duration: 0.16)) {
                coordinator.isCompact.wrappedValue = false
            }
        case let .collapse(restoreWidth):
            coordinator.labelWidth.wrappedValue = Double(restoreWidth)
            withAnimation(.easeInOut(duration: 0.16)) {
                coordinator.isCompact.wrappedValue = true
            }
        case let .resize(width):
            coordinator.labelWidth.wrappedValue = Double(width)
        }
    }
}

// MARK: - The rail's column

/// The rail's width slot, and the only thing in the window that watches a drag.
///
/// The launcher root hands it the *committed* state — the stored width and
/// whether the rail is collapsed — plus a builder for the rail's contents. The
/// live width is read here and nowhere else, so sixty width changes a second
/// cost sixty evaluations of this view instead of sixty evaluations of a window
/// that also contains a 260-row ledger.
///
/// `content` is called with `showsIconsOnly` rather than reading it from the
/// parent for the same reason: mid-drag, labels have to drop out as the edge
/// crosses the collapse threshold, and that decision belongs to whoever is
/// watching the drag.
struct ActionSidebarColumn<Content: View>: View {
    @ObservedObject var resizeState: ActionSidebarResizeState
    let isCompact: Bool
    let committedLabelWidth: CGFloat
    let compactWidth: CGFloat
    var geometry: ActionSidebarResizeGeometry = .default
    @ViewBuilder var content: (Bool) -> Content

    /// Mid-drag the preview wins outright: dragging left from an expanded rail
    /// has to be able to travel below the minimum toward the collapse
    /// threshold, which is the whole feel of the gesture.
    private var width: CGFloat {
        if let preview = resizeState.previewWidth {
            return max(compactWidth, preview)
        }
        return isCompact ? compactWidth : geometry.committedWidth(committedLabelWidth)
    }

    /// True while the rail is narrow enough that labels no longer fit. During a
    /// drag this follows the preview, so labels drop out as the edge crosses the
    /// threshold rather than snapping at the end.
    private var showsIconsOnly: Bool {
        if let preview = resizeState.previewWidth {
            return preview <= geometry.collapseLabelWidth
        }
        return isCompact
    }

    var body: some View {
        content(showsIconsOnly)
            .frame(width: width)
    }
}
