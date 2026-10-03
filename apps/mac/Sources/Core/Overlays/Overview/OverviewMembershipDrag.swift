import AppKit
import SwiftUI

struct OverviewMembershipDrag: Codable, Equatable {
    static let type = "dev.lattices.overview-membership"
    let session: String
    let windows: [UInt32]
    let sourceLayer: String?
    let move: Bool

    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        let data = try? JSONEncoder().encode(self)
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in
            completion(data, nil); return nil
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
            .onDrag { model.membershipDrag(wid).provider() }
            .contextMenu { OverviewWindowMembershipMenu(model: model, wid: wid) }
    }
}

extension OverviewModel {
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
        if destination == "__unassigned__" {
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
