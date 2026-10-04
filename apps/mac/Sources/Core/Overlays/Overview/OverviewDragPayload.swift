import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A second, own-process representation on the membership drag's one provider.
/// Physical relocation is deliberately single-window; membership remains plural.
struct OverviewWindowDragPayload: Codable, Equatable {
    static let type = UTType(exportedAs: "com.lattices.overview-window", conformingTo: .data).identifier
    let session: String
    let wid: UInt32

    static func decode(_ data: Data, session: String) -> Self? {
        guard data.count < 4096,
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              payload.session == session, payload.wid != 0 else { return nil }
        return payload
    }
}

enum OverviewWindowDrop {
    static func destination(on display: OverviewDisplay, spaceId: Int) -> OverviewMoveDestination? {
        guard let desktop = display.desktopNumber(of: spaceId) else { return nil }
        return .init(displayIndex: display.index, displayId: display.displayId,
                     displayName: display.name, spaceId: spaceId, desktop: desktop)
    }

    static func window(from items: [OverviewWindowDragPayload], session: String,
                       to destination: OverviewMoveDestination,
                       projection: OverviewProjection, moving: Set<UInt32>) -> UInt32? {
        guard items.count == 1, let item = items.first, item.wid != 0,
              item.session == session, moving.isEmpty,
              projection.moveTargets(for: item.wid).contains(destination) else { return nil }
        return item.wid
    }
}

struct OverviewWindowDropTarget: ViewModifier {
    @ObservedObject var model: OverviewModel
    let display: OverviewDisplay
    let spaceId: Int
    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let destination = OverviewWindowDrop.destination(on: display, spaceId: spaceId) {
            content
                .overlay {
                    if isTargeted && model.moving.isEmpty {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Palette.text, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .onDrop(of: [OverviewWindowDragPayload.type], isTargeted: $isTargeted) { providers in
                    OverviewDragProbe.log("legacy-drop display=\(destination.displayId) target=\(destination.spaceId) providers=\(providers.count)")
                    guard providers.count == 1, let provider = providers.first,
                          model.moving.isEmpty else { return false }
                    provider.loadDataRepresentation(forTypeIdentifier: OverviewWindowDragPayload.type) { data, _ in
                        DispatchQueue.main.async {
                            guard let data,
                                  let payload = OverviewWindowDragPayload.decode(data, session: model.membershipDragSession) else {
                                model.rejectMove("This window drag is no longer available; start a new drag")
                                return
                            }
                            _ = model.receiveWindowDrop([payload], to: destination)
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

extension OverviewModel {
    @discardableResult
    func receiveWindowDrop(_ payloads: [OverviewWindowDragPayload], to destination: OverviewMoveDestination) -> Bool {
        DiagnosticLog.shared.info("OverviewMove: source=legacy-drop windows=\(payloads.map(\.wid)) target=\(destination.spaceId) attempt")
        guard let wid = OverviewWindowDrop.window(from: payloads, session: membershipDragSession,
                to: destination, projection: projection, moving: moving) else {
            rejectMove("Window or destination changed, or a move is in progress; refresh and retry")
            return false
        }
        return move(wid, to: destination)
    }
}

/// Desktop numbering is per display; keep the display name alongside every group.
struct OverviewDesktopStrip: View {
    @ObservedObject var model: OverviewModel
    var previewSpace: Int? = nil
    @State private var targeted: Int?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.projection.displays, id: \.displayId) { display in
                    Text(display.name).font(.caption).foregroundStyle(Palette.textMuted)
                    ForEach(display.desktops, id: \.self) { space in
                        if let destination = OverviewWindowDrop.destination(on: display, spaceId: space) {
                            let hovered = (targeted ?? previewSpace) == space
                            let count = model.projection.all.values.filter {
                                $0.spaceId == space && $0.layerIds.contains(model.scope.layerId ?? "")
                            }.count
                            Text(hovered ? OverviewDragLabel.desktop(destination.desktop) : "Desktop \(destination.desktop) · \(count)")
                                .font(.system(size: 12)).foregroundStyle(Palette.text)
                                .frame(minWidth: 140, minHeight: 44)
                                .background(hovered ? Palette.borderLit : Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .background(OverviewPointerDrop(id: "desktop-strip:\(display.displayId):\(space)", hover: { point in
                                    targeted = point == nil ? nil : space
                                }) { payload, _ in
                                    guard model.moving.isEmpty else { OverviewDragProbe.log("pointer-reject reason=move-in-progress"); return }
                                    model.moveDragged(payload, to: destination)
                                })
                                .onDrop(of: [OverviewMembershipDrag.type], isTargeted: Binding(
                                    get: { targeted == space }, set: { targeted = $0 ? space : nil }
                                )) { providers in
                                    guard model.moving.isEmpty else { return false }
                                    return OverviewMembershipDrag.receive(providers) { model.moveDragged($0, to: destination) }
                                }
                        }
                    }
                }
            }.padding(8)
        }.background(Palette.bg)
    }
}
