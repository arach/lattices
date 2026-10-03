import AppKit
import SwiftUI

/// A second, own-process representation on the membership drag's one provider.
/// Physical relocation is deliberately single-window; membership remains plural.
struct OverviewWindowDragPayload: Codable, Equatable {
    static let type = "com.lattices.overview-window"
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
        guard let wid = OverviewWindowDrop.window(from: payloads, session: membershipDragSession,
                to: destination, projection: projection, moving: moving) else {
            rejectMove("Window or destination changed, or a move is in progress; refresh and retry")
            return false
        }
        return move(wid, to: destination)
    }
}
