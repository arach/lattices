import AppKit
import SwiftUI

/// In-process destinations do not depend on SwiftUI/AppKit native-drag
/// registration. Normal clicks pass through; only our explicit drag router
/// uses these bounds. Native onDrop remains for item-provider callers.
struct OverviewPointerDrop: NSViewRepresentable {
    let id: String
    var hover: (CGPoint?) -> Void = { _ in }
    let perform: (OverviewMembershipDrag, CGPoint) -> Void
    final class Target: NSView {
        var id = ""
        var hover: (CGPoint?) -> Void = { _ in }
        var perform: (OverviewMembershipDrag, CGPoint) -> Void = { _, _ in }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> Target { Target() }
    func updateNSView(_ view: Target, context: Context) {
        view.id = id; view.hover = hover; view.perform = perform
    }
}

/// Owns one pointer sequence, including cancellation and exactly one release.
/// No native drag is started, so a delayed item provider cannot also commit it.
final class OverviewPointerDrag {
    static var active: OverviewPointerDrag?
    let model: OverviewModel
    let payload: OverviewMembershipDrag
    let window: NSWindow
    private var monitor: Any?
    private var deactivation: NSObjectProtocol?
    private weak var target: OverviewPointerDrop.Target?
    private var release = OverviewPointerRelease()
    private var screenPoint = CGPoint.zero
    private let preview: NSPanel
    private let offset: CGPoint
    /// The dot board above the dragged label: which way, which desktop.
    private let board: NSPanel
    private let boardState = OverviewDotBoardState()

    init(model: OverviewModel, payload: OverviewMembershipDrag, window: NSWindow, image: NSImage, offset: CGPoint) {
        self.model = model; self.payload = payload; self.window = window; self.offset = offset
        preview = NSPanel(contentRect: CGRect(origin: .zero, size: image.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        preview.isOpaque = false; preview.backgroundColor = .clear
        preview.ignoresMouseEvents = true; preview.hasShadow = true
        preview.level = .floating; preview.isReleasedWhenClosed = false
        preview.contentView = NSImageView(image: image)
        board = NSPanel(contentRect: CGRect(origin: .zero, size: OverviewDotBoard.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        board.isOpaque = false; board.backgroundColor = .clear
        board.ignoresMouseEvents = true; board.hasShadow = true
        board.level = .floating; board.isReleasedWhenClosed = false
        board.contentView = NSHostingView(rootView: OverviewDotBoardHost(state: boardState))
    }
    func start(event: NSEvent) {
        Self.active?.finish(commit: false)
        Self.active = self
        model.activeDrag = payload
        OverviewDragProbe.log("pointer-begin windows=\(payload.windows) host=\(type(of: window)) level=\(window.level.rawValue)")
        window.addChildWindow(preview, ordered: .above)
        preview.orderFrontRegardless()
        window.addChildWindow(board, ordered: .above)
        board.orderFrontRegardless()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .leftMouseDragged: self.update(event: event); return nil
            case .leftMouseUp: self.update(event: event); self.finish(commit: true); return nil
            case .keyDown where event.keyCode == 53: self.finish(commit: false); return nil
            default: return event
            }
        }
        deactivation = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.finish(commit: false) }
        update(event: event)
    }
    static func hit(_ view: NSView, point: CGPoint) -> OverviewPointerDrop.Target? {
        guard !view.isHiddenOrHasHiddenAncestor, view.bounds.intersection(view.visibleRect).contains(view.convert(point, from: nil)) else { return nil }
        for child in view.subviews.reversed() {
            if let found = hit(child, point: point) { return found }
        }
        return view as? OverviewPointerDrop.Target
    }
    func update(event: NSEvent) {
        let screen = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        screenPoint = screen
        if OverviewDragProbe.enabled, event.type == .leftMouseUp { OverviewDragProbe.log("pointer-sample type=\(event.type.rawValue) event=\(event.locationInWindow) screen=\(screen) window=\(event.windowNumber)") }
        preview.setFrameOrigin(CGPoint(x: screen.x + offset.x, y: screen.y + offset.y))
        board.setFrameOrigin(CGPoint(x: screen.x - OverviewDotBoard.size.width / 2,
                                     y: screen.y + offset.y + preview.frame.height + 6))
        let point = window.convertPoint(fromScreen: screen)
        let next = window.isVisible ? window.contentView.flatMap { root -> OverviewPointerDrop.Target? in
            if OverviewImmediateDragSource.Source.frontmost(in: root, windowPoint: point) is OverviewDragShield.Shield { return nil }
            return Self.hit(root, point: point)
        } : nil
        if next !== target {
            if let target { OverviewDragProbe.log("pointer-exit target=\(target.id)"); target.hover(nil) }
            target = next
            if let next { OverviewDragProbe.log("pointer-enter target=\(next.id) bounds=\(next.bounds) windowRect=\(next.convert(next.bounds, to: nil)) pointer=\(point)") }
        }
        target?.hover(target!.convert(point, from: nil))
        let sign = OverviewDotSign.sign(targetId: target?.id, windows: payload.windows, projection: model.projection)
        if boardState.sign != sign { boardState.sign = sign }
    }
    func finish(commit: Bool) {
        guard release.claim() else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
        window.removeChildWindow(preview); preview.orderOut(nil)
        window.removeChildWindow(board); board.orderOut(nil)
        let destination = target
        destination?.hover(nil); target = nil
        Self.active = nil
        if commit, let destination, destination.window === window, !destination.visibleRect.isEmpty {
            let point = destination.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            OverviewDragProbe.log("pointer-perform target=\(destination.id)")
            OverviewDragProbe.log("decoded-payload windows=\(payload.windows) transport=in-process")
            destination.perform(payload, point)
        } else {
            OverviewDragProbe.log("pointer-reject reason=\(commit ? "no-visible-target" : "cancelled")")
        }
        OverviewDragProbe.log("pointer-end committed=\(commit && destination != nil)")
        model.finishDrag()
    }
}

/// Release and cancellation share one terminal transition.
struct OverviewPointerRelease {
    private(set) var finished = false
    mutating func claim() -> Bool {
        guard !finished else { return false }
        finished = true
        return true
    }
}
