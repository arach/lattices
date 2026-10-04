import AppKit
import SwiftUI

struct OverviewMembershipDrag: Codable, Equatable {
    static let type = "dev.lattices.overview-membership"
    let session: String
    let windows: [UInt32]
    let sourceLayer: String?
    let move: Bool

    func provider(relocation: OverviewWindowDragPayload? = nil) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = try? JSONEncoder().encode(self)
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in
            completion(data, nil); return nil
        }
        if let relocation, windows == [relocation.wid], relocation.session == session,
           let relocationData = try? JSONEncoder().encode(relocation) {
            provider.registerDataRepresentation(forTypeIdentifier: OverviewWindowDragPayload.type, visibility: .ownProcess) { completion in
                completion(relocationData, nil); return nil
            }
        }
        return provider
    }
    static func receive(_ providers: [NSItemProvider], perform: @escaping (Self) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            guard let data, data.count < 65536, let payload = try? JSONDecoder().decode(Self.self, from: data),
                  !payload.windows.isEmpty, payload.windows.count <= 512 else { return }
            DispatchQueue.main.async { perform(payload) }
        }
        return true
    }

    static func carried(clicked: UInt32, selected: Set<UInt32>) -> [UInt32] {
        selected.contains(clicked) ? selected.sorted() : [clicked]
    }
}

struct OverviewWindowMembershipMenu: View {
    @ObservedObject var model: OverviewModel
    let wid: UInt32
    var body: some View {
        Menu("Add to Layer") {
            ForEach(model.layers, id: \.id) { layer in
                Button(layer.label) { model.addComposition([wid], to: layer.id) }
            }
            Divider()
            Button("New Layer…") { model.compose([wid]) }
        }
        ForEach(model.layers.filter { model.projection.all[wid]?.layerIds.contains($0.id) == true }, id: \.id) { layer in
            if model.canRemoveComposition(wid, from: layer.id) {
                Button("Remove from \(layer.label)") { model.removeComposition(wid, from: layer.id) }
            } else {
                Button("Held by an app or project rule in \(layer.label)") {}.disabled(true)
            }
        }
        Button("New Layer…") { model.compose([wid]) }
        if model.selection.count > 1 {
            Button("New layer from \(model.selection.count) selected") { model.compose() }
        }
    }
}

struct OverviewMembershipInteractions: ViewModifier {
    @ObservedObject var model: OverviewModel
    let wid: UInt32
    func body(content: Content) -> some View {
        content
            .background(OverviewImmediateDragSource(model: model, wid: wid))
            .contextMenu { OverviewWindowMembershipMenu(model: model, wid: wid) }
    }
}

extension OverviewModel {
    func windowDragProvider(_ wid: UInt32) -> NSItemProvider {
        let membership = membershipDrag(wid)
        let relocation: OverviewWindowDragPayload? =
            membership.windows.count == 1 && moving.isEmpty && !projection.moveTargets(for: wid).isEmpty
                ? .init(session: membershipDragSession, wid: wid) : nil
        return membership.provider(relocation: relocation)
    }

    func membershipDrag(_ wid: UInt32) -> OverviewMembershipDrag {
        .init(session: membershipDragSession,
              windows: OverviewMembershipDrag.carried(clicked: wid, selected: selection),
              sourceLayer: scope.layerId,
              move: NSEvent.modifierFlags.contains(.option) && scope.layerId != nil)
    }

    func receiveMembership(_ drag: OverviewMembershipDrag, into destination: String) {
        guard drag.session == membershipDragSession else { return }
        let ids = Array(Set(drag.windows)).sorted()
        guard ids.allSatisfy({ projection.all[$0] != nil }) else {
            compositionNotice = "A dragged window is no longer available"; return
        }
        if destination == "__new_layer__" {
            compose(ids)
            composition?.moveSources = drag.sourceLayer.map { [$0] } ??
                Array(Set(ids.flatMap { projection.all[$0]?.layerIds ?? [] })).sorted()
        } else if destination == "__unassigned__" {
            var blocked = 0
            for wid in ids {
                let memberships = projection.all[wid]?.layerIds ?? []
                for id in memberships {
                    if canRemoveComposition(wid, from: id) { removeComposition(wid, from: id) }
                    else { blocked += 1 }
                }
            }
            compositionNotice = blocked == 0 ? "Removed selected windows from their layers" : "Some windows remain held by app or project rules"
        } else if drag.move, let source = drag.sourceLayer, source != destination {
            moveComposition(ids, from: source, to: destination)
        } else { addComposition(ids, to: destination) }
    }
}

/// The payload, not changing keyboard state, owns the promised operation.
enum OverviewDragLabel {
    static func layer(_ label: String, id: String, drag: OverviewMembershipDrag?) -> String {
        if id == "__new_layer__" { return "New layer with \(drag?.windows.count ?? 1) windows" }
        if id == "__unassigned__" { return "Remove from layers" }
        return (drag?.move == true && drag?.sourceLayer != id ? "Move to " : "Add to ") + label
    }
    static func desktop(_ number: Int) -> String { "Move to Desktop \(number)" }
}

/// Observe the existing hit surface without replacing its click/context-menu handlers.
/// Native dragging begins after 4 points, with no long-press recognizer.
struct OverviewImmediateDragSource: NSViewRepresentable {
    let model: OverviewModel
    let wid: UInt32
    func makeNSView(context: Context) -> Source { Source() }
    func updateNSView(_ view: Source, context: Context) { view.model = model; view.wid = wid }
    static func dismantleNSView(_ view: Source, coordinator: ()) { view.uninstall() }

    final class Source: NSView, NSDraggingSource {
        weak var model: OverviewModel?
        var wid: UInt32 = 0
        var monitor: Any?
        var down: NSEvent?
        var payload: OverviewMembershipDrag?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            uninstall()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                return self.observe(event)
            }
        }
        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil; down = nil; payload = nil
        }
        func observe(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, let model else { return event }
            switch event.type {
            case .leftMouseDown:
                let point = convert(event.locationInWindow, from: nil)
                if visibleRect.contains(point), !isHiddenOrHasHiddenAncestor,
                   let hit = window?.contentView?.hitTest(window!.contentView!.convert(event.locationInWindow, from: nil)),
                   let parent = superview, hit === parent || hit.isDescendant(of: parent) {
                    down = event; payload = model.membershipDrag(wid)
                }
            case .leftMouseUp: down = nil; payload = nil
            case .leftMouseDragged:
                guard let down, let payload,
                      hypot(event.locationInWindow.x - down.locationInWindow.x,
                            event.locationInWindow.y - down.locationInWindow.y) >= 4 else { return event }
                self.down = nil; self.payload = nil
                let item = NSPasteboardItem()
                guard let data = try? JSONEncoder().encode(payload) else { return event }
                item.setData(data, forType: .init(OverviewMembershipDrag.type))
                if payload.windows.count == 1,
                   let relocation = try? JSONEncoder().encode(OverviewWindowDragPayload(session: payload.session, wid: wid)) {
                    item.setData(relocation, forType: .init(OverviewWindowDragPayload.type))
                }
                let title = model.projection.all[wid]?.title ?? "Window"
                let text = payload.windows.count > 1 ? "\(payload.windows.count) windows · \(title)" : title
                let image = NSImage(size: NSSize(width: 300, height: 38))
                image.lockFocus()
                NSColor.windowBackgroundColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 300, height: 38), xRadius: 6, yRadius: 6).fill()
                (text as NSString).draw(in: NSRect(x: 10, y: 9, width: 280, height: 22), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
                image.unlockFocus()
                let dragging = NSDraggingItem(pasteboardWriter: item)
                dragging.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: image.size), contents: image)
                model.activeDrag = payload
                beginDraggingSession(with: [dragging], event: event, source: self)
                return nil
            default: break
            }
            return event
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? [.copy, .move] : []
        }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            model?.activeDrag = nil
        }
    }
}
